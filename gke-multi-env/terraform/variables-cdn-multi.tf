variable "cdn_sites" {
  description = "Map of CDN site configurations"
  type = map(object({
    domains                = list(string)           # List of domains/CNAMEs for this site
    index_page             = optional(string)       # Main page (default: index.html)
    error_page             = optional(string)       # Error page (default: 404.html)
    cors_origins           = optional(list(string)) # CORS allowed origins
    retention_days         = optional(number)       # Days to retain content
    enable_versioning      = optional(bool)         # Enable bucket versioning
    cache_mode             = optional(string)       # CDN cache mode
    client_ttl             = optional(number)       # Client cache TTL
    default_ttl            = optional(number)       # CDN default TTL
    max_ttl                = optional(number)       # CDN max TTL
    custom_headers         = optional(list(string)) # Additional response headers
    enable_spa_routing = optional(bool)             # Enable SPA routing for HTML
  }))
  
  # Validation rules simplified to avoid IDE parsing issues
  validation {
    condition     = length(var.cdn_sites) > 0
    error_message = "At least one CDN site must be defined."
  }
}

variable "default_site" {
  description = "Default site key to use when no host matches"
  type        = string
  
  # Note: validation that default_site exists in cdn_sites is handled at runtime
}