# ==============================================================================
# SECRET MANAGER VARIABLES
# ==============================================================================

variable "enable_secret_manager" {
  description = "Enable Google Secret Manager integration"
  type        = bool
  default     = true
}

variable "application_secrets" {
  description = "Map of application secrets to store in Secret Manager"
  type        = map(string)
  default     = {}
}

variable "enable_secret_manager_csi" {
  description = "Enable Secret Manager CSI driver for Kubernetes integration"
  type        = bool
  default     = true
}

variable "secret_replication_locations" {
  description = "List of locations for secret replication (defaults to main region)"
  type        = list(string)
  default     = []
}