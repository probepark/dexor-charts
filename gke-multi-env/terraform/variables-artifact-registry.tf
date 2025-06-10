# ==============================================================================
# ARTIFACT REGISTRY VARIABLES
# ==============================================================================

variable "enable_github_gke_access" {
  description = "Enable GitHub Actions access to GKE cluster"
  type        = bool
  default     = false
}

variable "create_github_sa_key" {
  description = "Create service account key for GitHub Actions (not recommended for production)"
  type        = bool
  default     = false
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity Federation for GitHub Actions (recommended)"
  type        = bool
  default     = true
}

variable "github_repositories" {
  description = "List of GitHub repository names (e.g., ['kaiachain/dexor-charts', 'kaiachain/other-repo'])"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.github_repositories) > 0
    error_message = "At least one GitHub repository must be specified."
  }
  
  validation {
    condition     = alltrue([for repo in var.github_repositories : can(regex("^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", repo))])
    error_message = "All GitHub repositories must be in format 'owner/repo'."
  }
}

variable "enable_artifact_registry_cleanup" {
  description = "Enable automatic cleanup policies for Artifact Registry"
  type        = bool
  default     = true
}

variable "docker_retention_days" {
  description = "Number of days to retain Docker images"
  type        = number
  default     = 30
}

variable "helm_retention_days" {
  description = "Number of days to retain Helm charts"
  type        = number
  default     = 30
}