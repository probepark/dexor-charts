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

# Grant dev-cdn-deploy-sa permissions to upload to perf buckets
resource "google_storage_bucket_iam_member" "cdn_bucket_deploy_access" {
  for_each = var.cdn_sites

  bucket = google_storage_bucket.cdn_sites[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:dev-cdn-deploy-sa@${var.project_id}.iam.gserviceaccount.com"
}

# Backend buckets for Load Balancer
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
  }

  custom_response_headers = concat(
    var.custom_response_headers,
    each.value.custom_headers != null ? each.value.custom_headers : []
  )
}
