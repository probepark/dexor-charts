variable "enable_workload_identity_federation" {
  description = "Enable Workload Identity Federation for GitHub Actions"
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo'"
  type        = string
  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "GitHub repository must be in format 'owner/repo'."
  }
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = ""
}

variable "github_repo_name" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "deployment_branch" {
  description = "Git branch to trigger deployments"
  type        = string
  default     = "main"
}

variable "enable_cache_invalidation" {
  description = "Enable automatic CDN cache invalidation after deployment"
  type        = bool
  default     = true
}


variable "iap_allowed_domain" {
  description = "Domain allowed for IAP access"
  type        = string
  default     = ""
}

variable "iap_allowed_members" {
  description = "List of members allowed for IAP access"
  type        = list(string)
  default     = []
}