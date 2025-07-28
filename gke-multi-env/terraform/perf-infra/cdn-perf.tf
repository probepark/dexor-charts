# Simplified CDN configuration for Performance environment

# Only create CDN resources if cdn_sites is configured
locals {
  enable_cdn = length(var.cdn_sites) > 0
}

# Storage buckets for CDN sites
resource "google_storage_bucket" "cdn_sites" {
  for_each = var.cdn_sites
  
  name                        = "${var.project_id}-${var.environment}-${each.key}-static"
  location                    = var.region
  force_destroy               = true  # Allow destruction in perf environment
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"
  
  website {
    main_page_suffix = each.value.index_page != null ? each.value.index_page : "index.html"
    not_found_page   = each.value.error_page != null ? each.value.error_page : "404.html"
  }
  
  cors {
    origin          = each.value.cors_origins != null ? each.value.cors_origins : ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Lifecycle rule for retention
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
  
  # Versioning
  versioning {
    enabled = each.value.enable_versioning != null ? each.value.enable_versioning : false
  }
  
  labels = {
    environment = var.environment
    site        = each.key
    managed_by  = "terraform"
  }
}

# Make buckets publicly readable
resource "google_storage_bucket_iam_member" "cdn_bucket_public_read" {
  for_each = var.cdn_sites
  
  bucket = google_storage_bucket.cdn_sites[each.key].name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Backend buckets for Load Balancer
resource "google_compute_backend_bucket" "cdn_backends" {
  for_each = var.cdn_sites
  
  name        = "${var.environment}-${each.key}-backend"
  bucket_name = google_storage_bucket.cdn_sites[each.key].name
  enable_cdn  = true
  
  cdn_policy {
    cache_mode                   = each.value.cache_mode != null ? each.value.cache_mode : "CACHE_ALL_STATIC"
    client_ttl                   = each.value.client_ttl != null ? each.value.client_ttl : var.cdn_client_ttl
    default_ttl                  = each.value.default_ttl != null ? each.value.default_ttl : var.cdn_default_ttl
    max_ttl                      = each.value.max_ttl != null ? each.value.max_ttl : var.cdn_max_ttl
    negative_caching             = true
    serve_while_stale            = var.cdn_serve_while_stale
  }
  
  custom_response_headers = concat(
    var.custom_response_headers,
    each.value.custom_headers != null ? each.value.custom_headers : []
  )
}

# URL map disabled - using dev environment's ALB
# resource "google_compute_url_map" "cdn_url_map" {
#   count = local.enable_cdn ? 1 : 0
#   
#   name            = "${var.environment}-cdn-url-map"
#   default_service = google_compute_backend_bucket.cdn_backends[var.default_site].id
#   
#   dynamic "host_rule" {
#     for_each = local.enable_cdn ? var.cdn_sites : {}
#     content {
#       hosts        = host_rule.value.domains
#       path_matcher = "path-matcher-${host_rule.key}"
#     }
#   }
#   
#   dynamic "path_matcher" {
#     for_each = local.enable_cdn ? var.cdn_sites : {}
#     content {
#       name            = "path-matcher-${path_matcher.key}"
#       default_service = google_compute_backend_bucket.cdn_backends[path_matcher.key].id
#     }
#   }
# }

# Target HTTPS proxy disabled - using dev environment's ALB
# resource "google_compute_target_https_proxy" "cdn_https_proxy" {
#   count = local.enable_cdn ? 1 : 0
#   
#   name    = "${var.environment}-cdn-https-proxy"
#   url_map = google_compute_url_map.cdn_url_map[0].id
#   
#   ssl_certificates = var.use_managed_certificate ? [
#     google_compute_managed_ssl_certificate.cdn_cert[0].id
#   ] : []
# }

# Managed SSL Certificate disabled - using dev environment's certificate
# resource "google_compute_managed_ssl_certificate" "cdn_cert" {
#   count = local.enable_cdn && var.use_managed_certificate ? 1 : 0
#   
#   name = "${var.environment}-cdn-ssl-cert"
#   
#   managed {
#     domains = local.enable_cdn ? flatten([
#       for site_key, site in var.cdn_sites : site.domains
#     ]) : []
#   }
#   
#   lifecycle {
#     create_before_destroy = true
#   }
# }

# Global forwarding rule for HTTPS disabled - using dev environment's ALB
# resource "google_compute_global_forwarding_rule" "cdn_https" {
#   count = local.enable_cdn ? 1 : 0
#   
#   name                  = "${var.environment}-cdn-https-forwarding-rule"
#   target                = google_compute_target_https_proxy.cdn_https_proxy[0].id
#   port_range            = "443"
#   load_balancing_scheme = "EXTERNAL"
# }

# Global forwarding rule for HTTP disabled - using dev environment's ALB
# resource "google_compute_global_forwarding_rule" "cdn_http" {
#   count = local.enable_cdn && var.enable_http_redirect ? 1 : 0
#   
#   name                  = "${var.environment}-cdn-http-forwarding-rule"
#   target                = google_compute_target_http_proxy.cdn_http_proxy[0].id
#   port_range            = "80"
#   load_balancing_scheme = "EXTERNAL"
# }

# Target HTTP proxy for redirect disabled - using dev environment's ALB
# resource "google_compute_target_http_proxy" "cdn_http_proxy" {
#   count = local.enable_cdn && var.enable_http_redirect ? 1 : 0
#   
#   name    = "${var.environment}-cdn-http-proxy"
#   url_map = google_compute_url_map.cdn_http_redirect[0].id
# }

# URL map for HTTP redirect disabled - using dev environment's ALB
# resource "google_compute_url_map" "cdn_http_redirect" {
#   count = local.enable_cdn && var.enable_http_redirect ? 1 : 0
#   
#   name = "${var.environment}-cdn-http-redirect"
#   
#   default_url_redirect {
#     https_redirect         = true
#     redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
#     strip_query            = false
#   }
# }