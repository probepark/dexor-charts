# ==============================================================================
# SECRET MANAGER OUTPUTS
# ==============================================================================

output "secret_manager_service_account_email" {
  description = "Secret Manager service account email"
  value       = var.enable_secret_manager ? google_service_account.secret_manager_sa[0].email : null
}

output "app_config_secret_name" {
  description = "Application configuration secret name (contains all app secrets as JSON)"
  value       = var.enable_secret_manager ? google_secret_manager_secret.app_config[0].secret_id : null
}

output "app_config_secret_command" {
  description = "gcloud command to retrieve application configuration"
  value       = var.enable_secret_manager ? "gcloud secrets versions access latest --secret=${google_secret_manager_secret.app_config[0].secret_id}" : null
}

output "db_password_secret_name" {
  description = "Database password secret name (deprecated - use app_config_secret_name)"
  value       = var.enable_cloud_sql && var.enable_secret_manager ? google_secret_manager_secret.db_password[0].secret_id : null
}

output "redis_auth_secret_name" {
  description = "Redis auth secret name (deprecated - use app_config_secret_name)"
  value       = var.enable_redis && local.config.redis_auth_enabled && var.enable_secret_manager ? google_secret_manager_secret.redis_auth[0].secret_id : null
}

output "argocd_admin_password_secret_name" {
  description = "ArgoCD admin password secret name"
  value       = var.enable_secret_manager ? google_secret_manager_secret.argocd_admin_password[0].secret_id : null
}

output "secret_manager_csi_provider_class" {
  description = "Secret Manager CSI SecretProviderClass name for application config"
  value       = var.enable_secret_manager_csi ? "${var.environment}-app-config-provider" : null
}