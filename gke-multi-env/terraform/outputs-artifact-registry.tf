# ==============================================================================
# ARTIFACT REGISTRY OUTPUTS
# ==============================================================================

output "docker_registry_url" {
  description = "Artifact Registry Docker repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_registry.repository_id}"
}

output "helm_registry_url" {
  description = "Artifact Registry Helm repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.helm_registry.repository_id}"
}

output "github_actions_service_account_email" {
  description = "GitHub Actions service account email"
  value       = google_service_account.github_actions_sa.email
}

output "github_actions_service_account_key" {
  description = "GitHub Actions service account key (base64 encoded)"
  value       = var.create_github_sa_key ? google_service_account_key.github_actions_key[0].private_key : null
  sensitive   = true
}

output "workload_identity_provider" {
  description = "Workload Identity Provider resource name"
  value       = var.enable_workload_identity ? google_iam_workload_identity_pool_provider.github_provider[0].name : null
}

output "workload_identity_provider_audience" {
  description = "Workload Identity Provider audience for GitHub Actions"
  value       = var.enable_workload_identity ? google_iam_workload_identity_pool.github_pool[0].name : null
}

output "github_actions_docker_login_command" {
  description = "Docker login command for GitHub Actions"
  value       = "gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet"
}

output "github_actions_push_example" {
  description = "Example Docker push commands for GitHub Actions"
  value = {
    tag  = "docker tag my-app:latest ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_registry.repository_id}/my-app:latest"
    push = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_registry.repository_id}/my-app:latest"
  }
}