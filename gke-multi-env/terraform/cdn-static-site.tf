resource "google_storage_bucket" "frontend_static" {
  name                        = "${var.project_id}-${var.environment}-frontend-static"
  location                    = var.region
  force_destroy               = var.environment != "prod"
  uniform_bucket_level_access = true
  
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  
  cors {
    origin          = var.allowed_origins
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  lifecycle_rule {
    condition {
      age = var.static_content_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  versioning {
    enabled = var.enable_versioning
  }
  
  labels = merge(
    local.common_labels,
    {
      purpose = "frontend-static-hosting"
    }
  )
}

resource "google_storage_bucket_iam_member" "frontend_static_public" {
  bucket = google_storage_bucket.frontend_static.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_compute_backend_bucket" "frontend_cdn" {
  name        = "${var.environment}-frontend-cdn-backend"
  bucket_name = google_storage_bucket.frontend_static.name
  enable_cdn  = true
  
  cdn_policy {
    cache_mode                   = "CACHE_ALL_STATIC"
    client_ttl                   = var.cdn_client_ttl
    default_ttl                  = var.cdn_default_ttl
    max_ttl                      = var.cdn_max_ttl
    negative_caching             = true
    serve_while_stale            = var.cdn_serve_while_stale
    
    negative_caching_policy {
      code = 404
      ttl  = 120
    }
    
    negative_caching_policy {
      code = 410
      ttl  = 120
    }
    
    cache_key_policy {
      include_host          = true
      include_protocol      = true
      include_query_string  = false
      query_string_blacklist = var.cdn_query_string_blacklist
    }
  }
  
  custom_response_headers = var.custom_response_headers
  
  compression_mode = "AUTOMATIC"
}

resource "google_compute_global_address" "frontend_ip" {
  name         = "${var.environment}-frontend-static-ip"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
  
  labels = local.common_labels
}

resource "google_compute_managed_ssl_certificate" "frontend_cert" {
  count = var.use_managed_certificate ? 1 : 0
  
  name = "${var.environment}-frontend-ssl-cert"
  
  managed {
    domains = var.frontend_domains
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_ssl_certificate" "frontend_cert_custom" {
  count = var.use_managed_certificate ? 0 : 1
  
  name        = "${var.environment}-frontend-ssl-cert-custom"
  private_key = var.ssl_private_key
  certificate = var.ssl_certificate
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_url_map" "frontend_url_map" {
  name            = "${var.environment}-frontend-url-map"
  default_service = google_compute_backend_bucket.frontend_cdn.id
  
  host_rule {
    hosts        = var.frontend_domains
    path_matcher = "frontend-paths"
  }
  
  path_matcher {
    name            = "frontend-paths"
    default_service = google_compute_backend_bucket.frontend_cdn.id
    
    path_rule {
      paths   = ["/api/*"]
      service = var.api_backend_service_id
    }
    
    dynamic "path_rule" {
      for_each = var.custom_path_rules
      content {
        paths   = path_rule.value.paths
        service = path_rule.value.service
      }
    }
    
    route_rules {
      priority = 1
      match_rules {
        prefix_match = "/"
        header_matches {
          header_name  = "Accept"
          prefix_match = "text/html"
        }
      }
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/index.html"
        }
      }
    }
  }
}

resource "google_compute_target_https_proxy" "frontend_https_proxy" {
  name             = "${var.environment}-frontend-https-proxy"
  url_map          = google_compute_url_map.frontend_url_map.id
  ssl_certificates = var.use_managed_certificate ? [google_compute_managed_ssl_certificate.frontend_cert[0].id] : [google_compute_ssl_certificate.frontend_cert_custom[0].id]
  
  ssl_policy = var.ssl_policy_id
}

resource "google_compute_target_http_proxy" "frontend_http_proxy" {
  count   = var.enable_http_redirect ? 1 : 0
  name    = "${var.environment}-frontend-http-proxy"
  url_map = google_compute_url_map.http_redirect[0].id
}

resource "google_compute_url_map" "http_redirect" {
  count = var.enable_http_redirect ? 1 : 0
  name  = "${var.environment}-frontend-http-redirect"
  
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_global_forwarding_rule" "frontend_https" {
  name                  = "${var.environment}-frontend-https-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.frontend_https_proxy.id
  ip_address            = google_compute_global_address.frontend_ip.id
  
  labels = local.common_labels
}

resource "google_compute_global_forwarding_rule" "frontend_http" {
  count                 = var.enable_http_redirect ? 1 : 0
  name                  = "${var.environment}-frontend-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.frontend_http_proxy[0].id
  ip_address            = google_compute_global_address.frontend_ip.id
  
  labels = local.common_labels
}

resource "google_dns_record_set" "frontend_dns" {
  for_each = var.create_dns_records ? toset(var.frontend_domains) : []
  
  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  managed_zone = var.dns_managed_zone_name
  rrdatas      = [google_compute_global_address.frontend_ip.address]
}

resource "google_storage_bucket" "frontend_logs" {
  count                       = var.enable_cdn_logging ? 1 : 0
  name                        = "${var.project_id}-${var.environment}-frontend-cdn-logs"
  location                    = var.region
  force_destroy               = var.environment != "prod"
  uniform_bucket_level_access = true
  
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  labels = merge(
    local.common_labels,
    {
      purpose = "cdn-logging"
    }
  )
}

resource "google_logging_bucket" "frontend_cdn_logs" {
  count       = var.enable_cdn_logging ? 1 : 0
  name        = "${var.environment}-frontend-cdn-logs"
  location    = var.region
  bucket_id   = "${var.environment}-frontend-cdn-logs"
  
  retention_days = var.log_retention_days
}

resource "google_monitoring_alert_policy" "cdn_availability" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${var.environment} Frontend CDN Availability"
  combiner     = "OR"
  
  conditions {
    display_name = "CDN Backend Availability < 99%"
    
    condition_threshold {
      filter          = "resource.type = \"https_lb_rule\" AND metric.type = \"loadbalancing.googleapis.com/https/backend_latencies\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 0.99
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_dashboard" "cdn_dashboard" {
  count        = var.enable_monitoring ? 1 : 0
  dashboard_json = jsonencode({
    displayName = "${var.environment} Frontend CDN Dashboard"
    gridLayout = {
      widgets = [
        {
          title = "Request Rate"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"https_lb_rule\" AND resource.label.url_map_name=\"${google_compute_url_map.frontend_url_map.name}\""
                }
              }
            }]
          }
        },
        {
          title = "Cache Hit Ratio"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"https_lb_rule\" AND metric.type=\"loadbalancing.googleapis.com/https/backend_request_count\""
                }
              }
            }]
          }
        }
      ]
    }
  })
}