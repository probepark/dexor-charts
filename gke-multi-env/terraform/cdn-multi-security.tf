# Shared security policy for all CDN sites
resource "google_compute_security_policy" "cdn_security_policy" {
  count       = var.enable_cloud_armor ? 1 : 0
  name        = "${var.environment}-cdn-security-policy"
  description = "Security policy for CDN"
  
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

# Per-site IAP configuration (optional)
# IAP configuration disabled - not supported with backend buckets
# resource "google_iap_web_backend_service_iam_binding" "cdn_sites_iap" {
#   for_each = { 
#     for site_key, site in var.cdn_sites : site_key => site 
#     if var.enable_iap && lookup(site, "iap_members", null) != null 
#   }
#   
#   web_backend_service = google_compute_backend_bucket.cdn_backends[each.key].name
#   role                = "roles/iap.httpsResourceAccessor"
#   members             = each.value.iap_members
# }