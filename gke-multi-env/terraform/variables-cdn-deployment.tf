variable "enable_cdn_workload_identity" {
  description = "Enable Workload Identity Federation for CDN deployment via GitHub Actions"
  type        = bool
  default     = true
}

variable "cdn_github_repositories" {
  description = "List of GitHub repositories in format 'owner/repo' allowed to deploy to CDN"
  type        = list(string)
  validation {
    condition = alltrue([
      for repo in var.cdn_github_repositories : can(regex("^[^/]+/[^/]+$", repo))
    ])
    error_message = "All GitHub repositories must be in format 'owner/repo'."
  }
  validation {
    condition     = length(var.cdn_github_repositories) > 0
    error_message = "At least one GitHub repository must be specified."
  }
}

# IAP variables - not supported with current CDN backend bucket architecture
# variable "iap_allowed_domain" - IAP disabled
# variable "iap_allowed_members" - IAP disabled
