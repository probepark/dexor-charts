# Multi-site CDN configuration with multiple domains and storage buckets

locals {
  # Flatten domains with explicit structure to help IDE understand
  all_domains = flatten([
    for site_key, site in var.cdn_sites : [
      for domain_name in site.domains : domain_name
    ]
  ])
  
  # Create domain to site mapping
  domain_to_site = merge([
    for site_key, site in var.cdn_sites : {
      for domain_name in site.domains : domain_name => {
        site_key = site_key
        domain   = domain_name
        site     = site
      }
    }
  ]...)
}

# Storage buckets for each site
resource "google_storage_bucket" "cdn_sites" {
  for_each = var.cdn_sites
  
  name                        = "${var.project_id}-${var.environment}-${each.key}-static"
  location                    = var.region
  force_destroy               = var.environment != "prod"
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"
  
  website {
    main_page_suffix = each.value.index_page != null ? each.value.index_page : "index.html"
  }
  
  cors {
    origin          = each.value.cors_origins != null ? each.value.cors_origins : ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  dynamic "lifecycle_rule" {
    for_each = each.value.retention_days != null ? [1] : []
    content {
      condition {
        age = each.value.retention_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  versioning {
    enabled = each.value.enable_versioning != null ? each.value.enable_versioning : var.enable_versioning
  }
  
  labels = merge(
    local.common_labels,
    {
      purpose = "cdn-static-hosting"
      site    = each.key
    }
  )
}

# Note: Public access removed due to organization policy
# CDN backend bucket will access GCS internally without public permissions

# Backend buckets for CDN
resource "google_compute_backend_bucket" "cdn_backends" {
  for_each = var.cdn_sites
  
  name        = "${var.environment}-${each.key}-cdn-backend"
  bucket_name = google_storage_bucket.cdn_sites[each.key].name
  enable_cdn  = true
  
  cdn_policy {
    cache_mode                   = each.value.cache_mode != null ? each.value.cache_mode : "CACHE_ALL_STATIC"
    client_ttl                   = each.value.client_ttl != null ? each.value.client_ttl : var.cdn_client_ttl
    default_ttl                  = each.value.default_ttl != null ? each.value.default_ttl : var.cdn_default_ttl
    max_ttl                      = each.value.max_ttl != null ? each.value.max_ttl : var.cdn_max_ttl
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
    
  }
  
  custom_response_headers = concat(
    var.custom_response_headers,
    each.value.custom_headers != null ? each.value.custom_headers : []
  )
  
  compression_mode = "AUTOMATIC"
  
}

# Single global IP address for all sites
resource "google_compute_global_address" "cdn_ip" {
  name         = "${var.environment}-cdn-static-ip"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
  
  labels = merge(
    local.common_labels,
    {
      purpose = "cdn-load-balancer"
    }
  )
}

# SSL certificates for all domains
resource "google_compute_managed_ssl_certificate" "cdn_certs" {
  count = var.use_managed_certificate ? 1 : 0
  
  name = "${var.environment}-cdn-ssl-cert"
  
  managed {
    domains = flatten([for site in var.cdn_sites : site.domains])
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_ssl_certificate" "cdn_cert_custom" {
  count = var.use_managed_certificate ? 0 : 1
  
  name        = "${var.environment}-cdn-ssl-cert-custom"
  private_key = var.ssl_private_key
  certificate = var.ssl_certificate
  
  lifecycle {
    create_before_destroy = true
  }
}

# URL map with host rules for each site
resource "google_compute_url_map" "cdn_url_map" {
  name            = "${var.environment}-cdn-url-map"
  default_service = google_compute_backend_bucket.cdn_backends[var.default_site].id
  
  
  dynamic "host_rule" {
    for_each = var.cdn_sites
    content {
      hosts        = host_rule.value.domains
      path_matcher = "${host_rule.key}-paths"
    }
  }
  
  dynamic "path_matcher" {
    for_each = var.cdn_sites
    content {
      name            = "${path_matcher.key}-paths"
      default_service = google_compute_backend_bucket.cdn_backends[path_matcher.key].id
      
    }
  }
}

# Application Load Balancer - URL map with custom error response policy
resource "google_compute_url_map" "cdn_url_map_alb" {
  name            = "${var.environment}-cdn-url-map-alb"
  default_service = google_compute_backend_bucket.cdn_backends[var.default_site].id
  
  dynamic "host_rule" {
    for_each = var.cdn_sites
    content {
      hosts        = host_rule.value.domains
      path_matcher = "${host_rule.key}-paths"
    }
  }
  
  dynamic "path_matcher" {
    for_each = var.cdn_sites
    content {
      name            = "${path_matcher.key}-paths"
      default_service = google_compute_backend_bucket.cdn_backends[path_matcher.key].id
      
      # Custom error response policy for SPA routing
      dynamic "default_custom_error_response_policy" {
        for_each = path_matcher.value.enable_spa_routing != null && path_matcher.value.enable_spa_routing ? [1] : []
        content {
          error_response_rule {
            match_response_codes = ["404"]
            override_response_code = 200
            path = "/index.html"
          }
          error_service = google_compute_backend_bucket.cdn_backends[path_matcher.key].id
        }
      }
    }
  }
}

# Application Load Balancer - HTTPS proxy
resource "google_compute_target_https_proxy" "cdn_https_proxy_alb" {
  name             = "${var.environment}-cdn-https-proxy-alb"
  url_map          = google_compute_url_map.cdn_url_map_alb.id
  ssl_certificates = var.use_managed_certificate ? [google_compute_managed_ssl_certificate.cdn_certs[0].id] : [google_compute_ssl_certificate.cdn_cert_custom[0].id]
  
  ssl_policy = var.ssl_policy_id
}

# Application Load Balancer - HTTP proxy for redirect
resource "google_compute_target_http_proxy" "cdn_http_proxy_alb" {
  count   = var.enable_http_redirect ? 1 : 0
  name    = "${var.environment}-cdn-http-proxy-alb"
  url_map = google_compute_url_map.cdn_http_redirect[0].id
}

resource "google_compute_url_map" "cdn_http_redirect" {
  count = var.enable_http_redirect ? 1 : 0
  name  = "${var.environment}-cdn-http-redirect"
  
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# Application Load Balancer - Forwarding rules
resource "google_compute_global_forwarding_rule" "cdn_https_alb" {
  name                  = "${var.environment}-cdn-https-alb-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.cdn_https_proxy_alb.id
  ip_address            = google_compute_global_address.cdn_ip.id
  
  labels = local.common_labels
}

resource "google_compute_global_forwarding_rule" "cdn_http_alb" {
  count                 = var.enable_http_redirect ? 1 : 0
  name                  = "${var.environment}-cdn-http-alb-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.cdn_http_proxy_alb[0].id
  ip_address            = google_compute_global_address.cdn_ip.id
  
  labels = local.common_labels
}

# DNS records for all domains
resource "google_dns_record_set" "cdn_dns" {
  for_each = var.create_dns_records ? local.domain_to_site : {}
  
  name         = "${each.key}."
  type         = "A"
  ttl          = 300
  managed_zone = var.dns_managed_zone_name
  rrdatas      = [google_compute_global_address.cdn_ip.address]
}

# Service account for deployment (shared across all sites)
resource "google_service_account" "cdn_deploy" {
  account_id   = "${var.environment}-cdn-deploy-sa"
  display_name = "CDN Deployment Service Account"
  description  = "Service account for deploying static assets to CDN"
}

# Get the project number for CDN service account
data "google_project" "current" {}

# IAM permissions for each bucket
resource "google_storage_bucket_iam_member" "cdn_deploy_admin" {
  for_each = var.cdn_sites
  
  bucket = google_storage_bucket.cdn_sites[each.key].name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.cdn_deploy.email}"
}

# Grant Compute Engine service account access to buckets for CDN
resource "google_storage_bucket_iam_member" "cdn_compute_service_account_viewer" {
  for_each = var.cdn_sites
  
  bucket = google_storage_bucket.cdn_sites[each.key].name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com"
}

# Grant public read access to bucket objects for CDN
resource "google_storage_bucket_iam_member" "cdn_public_viewer" {
  for_each = var.cdn_sites
  
  bucket = google_storage_bucket.cdn_sites[each.key].name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# CDN cache invalidation permission
resource "google_project_iam_member" "cdn_deploy_invalidator" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${google_service_account.cdn_deploy.email}"
}

# Monitoring and logging
resource "google_monitoring_alert_policy" "cdn_site_availability" {
  for_each = var.enable_monitoring ? var.cdn_sites : {}
  
  display_name = "${var.environment} ${each.key} CDN Availability"
  combiner     = "OR"
  
  conditions {
    display_name = "${each.key} Backend Availability < 99%"
    
    condition_threshold {
      filter          = "resource.type = \"https_lb_rule\" AND resource.label.backend_name = \"${google_compute_backend_bucket.cdn_backends[each.key].name}\""
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