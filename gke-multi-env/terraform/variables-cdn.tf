# Deprecated variables - use cdn_sites configuration instead
# variable "frontend_domains" - use cdn_sites
# variable "allowed_origins" - use cdn_sites.cors_origins  
# variable "static_content_retention_days" - use cdn_sites.retention_days

variable "enable_versioning" {
  description = "Enable versioning for the storage bucket"
  type        = bool
  default     = false
}

variable "cdn_client_ttl" {
  description = "Client TTL for CDN cache in seconds"
  type        = number
  default     = 3600
}

variable "cdn_default_ttl" {
  description = "Default TTL for CDN cache in seconds"
  type        = number
  default     = 3600
}

variable "cdn_max_ttl" {
  description = "Maximum TTL for CDN cache in seconds"
  type        = number
  default     = 86400
}

variable "cdn_serve_while_stale" {
  description = "Serve stale content while revalidating in seconds"
  type        = number
  default     = 86400
}

# Deprecated variable - not used in current backend bucket configuration
# variable "cdn_query_string_blacklist" - cache key policy not supported for backend buckets

variable "custom_response_headers" {
  description = "Custom response headers to add"
  type        = list(string)
  default     = [
    "X-Frame-Options: SAMEORIGIN",
    "X-Content-Type-Options: nosniff",
    "X-XSS-Protection: 1; mode=block",
    "Referrer-Policy: strict-origin-when-cross-origin"
  ]
}

variable "use_managed_certificate" {
  description = "Use Google-managed SSL certificate"
  type        = bool
  default     = true
}

variable "ssl_private_key" {
  description = "SSL private key for custom certificate"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssl_certificate" {
  description = "SSL certificate for custom certificate"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssl_policy_id" {
  description = "SSL policy to use for HTTPS proxy"
  type        = string
  default     = null
}


variable "enable_http_redirect" {
  description = "Enable HTTP to HTTPS redirect"
  type        = bool
  default     = true
}

variable "create_dns_records" {
  description = "Create DNS records for the frontend domains"
  type        = bool
  default     = false
}

variable "dns_managed_zone_name" {
  description = "Name of the Cloud DNS managed zone"
  type        = string
  default     = ""
}

# Logging variables - not currently implemented in multi-site CDN
# variable "enable_cdn_logging" - CDN logging not configured
# variable "log_retention_days" - CDN logging not configured

variable "enable_monitoring" {
  description = "Enable monitoring alerts and dashboards"
  type        = bool
  default     = false
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor security policy"
  type        = bool
  default     = false
}

variable "cloud_armor_rules" {
  description = "Cloud Armor security rules"
  type = list(object({
    action      = string
    priority    = number
    description = string
    expression  = string
  }))
  default = []
}

variable "enable_iap" {
  description = "Enable Identity-Aware Proxy"
  type        = bool
  default     = false
}

# IAP variables - not supported with backend buckets
# variable "iap_client_id" - IAP not supported for backend buckets  
# variable "iap_client_secret" - IAP not supported for backend buckets
