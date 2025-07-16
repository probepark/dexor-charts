variable "frontend_domains" {
  description = "List of domains for the frontend application"
  type        = list(string)
  validation {
    condition     = length(var.frontend_domains) > 0
    error_message = "At least one frontend domain must be specified."
  }
}

variable "allowed_origins" {
  description = "Allowed CORS origins for the storage bucket"
  type        = list(string)
  default     = ["*"]
}

variable "static_content_retention_days" {
  description = "Number of days to retain static content in the bucket"
  type        = number
  default     = 365
}

variable "enable_versioning" {
  description = "Enable versioning for the storage bucket"
  type        = bool
  default     = true
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

variable "cdn_query_string_blacklist" {
  description = "Query string parameters to exclude from cache key"
  type        = list(string)
  default     = ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "fbclid", "gclid"]
}

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

variable "api_backend_service_id" {
  description = "Backend service ID for API routes"
  type        = string
  default     = ""
}

variable "custom_path_rules" {
  description = "Custom path rules for URL map"
  type = list(object({
    paths   = list(string)
    service = string
  }))
  default = []
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

variable "enable_cdn_logging" {
  description = "Enable CDN access logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

variable "enable_monitoring" {
  description = "Enable monitoring alerts and dashboards"
  type        = bool
  default     = true
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

variable "iap_client_id" {
  description = "OAuth2 client ID for IAP"
  type        = string
  default     = ""
  sensitive   = true
}

variable "iap_client_secret" {
  description = "OAuth2 client secret for IAP"
  type        = string
  default     = ""
  sensitive   = true
}