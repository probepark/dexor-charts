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

variable "github_repository" {
  description = "GitHub repository name (e.g., 'kaiachain/dexor-charts')"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", var.github_repository)) || var.github_repository == ""
    error_message = "GitHub repository must be in format 'owner/repo' or empty string."
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