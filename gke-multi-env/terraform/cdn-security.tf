resource "google_compute_security_policy" "frontend_security_policy" {
  count       = var.enable_cloud_armor ? 1 : 0
  name        = "${var.environment}-frontend-security-policy"
  description = "Security policy for frontend CDN"
  
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow all rule"
  }
  
  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      expr {
        expression = "origin.region_code == 'CN' || origin.region_code == 'RU'"
      }
    }
    description = "Block traffic from specific regions"
  }
  
  rule {
    action   = "rate_based_ban"
    priority = "2000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      
      ban_duration_sec = 600
    }
    description = "Rate limiting rule"
  }
  
  rule {
    action   = "deny(403)"
    priority = "3000"
    match {
      expr {
        expression = "request.headers['user-agent'].contains('bot') && !request.headers['user-agent'].contains('googlebot')"
      }
    }
    description = "Block suspicious bots"
  }
  
  rule {
    action   = "deny(403)"
    priority = "4000"
    match {
      expr {
        expression = <<-EOT
          evaluatePreconfiguredExpr('xss-v33-stable') || 
          evaluatePreconfiguredExpr('sqli-v33-stable') || 
          evaluatePreconfiguredExpr('lfi-v33-stable') || 
          evaluatePreconfiguredExpr('rfi-v33-stable') || 
          evaluatePreconfiguredExpr('rce-v33-stable')
        EOT
      }
    }
    description = "OWASP Top 10 protection"
  }
  
  dynamic "rule" {
    for_each = var.cloud_armor_rules
    content {
      action      = rule.value.action
      priority    = rule.value.priority
      description = rule.value.description
      match {
        expr {
          expression = rule.value.expression
        }
      }
    }
  }
  
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
      rule_visibility = "STANDARD"
    }
  }
}

resource "google_compute_backend_bucket" "frontend_cdn_with_security" {
  count       = var.enable_cloud_armor ? 1 : 0
  name        = "${var.environment}-frontend-cdn-backend-secure"
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
  
  custom_response_headers = concat(
    var.custom_response_headers,
    [
      "Strict-Transport-Security: max-age=31536000; includeSubDomains",
      "Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://www.google-analytics.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://api.${var.environment}.example.com"
    ]
  )
  
  compression_mode = "AUTOMATIC"
  
  edge_security_policy = google_compute_security_policy.frontend_security_policy[0].id
}

resource "google_compute_backend_service_iam_member" "iap" {
  count            = var.enable_iap ? 1 : 0
  backend_service  = google_compute_backend_bucket.frontend_cdn.name
  role             = "roles/iap.httpsResourceAccessor"
  member           = "domain:${var.iap_allowed_domain}"
}

resource "google_iap_web_backend_service_iam_binding" "frontend_iap" {
  count            = var.enable_iap ? 1 : 0
  web_backend_service = google_compute_backend_bucket.frontend_cdn.name
  role             = "roles/iap.httpsResourceAccessor"
  members          = var.iap_allowed_members
}

resource "google_project_service" "iap_api" {
  count   = var.enable_iap ? 1 : 0
  service = "iap.googleapis.com"
  
  disable_on_destroy = false
}