# ==============================================================================
# GOOGLE ARTIFACT REGISTRY ACCESS OUTPUTS
# ==============================================================================

output "artifact_registry_service_account_email" {
  description = "Email of the service account for Artifact Registry access"
  value       = var.enable_secret_manager ? google_service_account.artifact_registry_reader[0].email : ""
}