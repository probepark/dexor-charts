# ==============================================================================
# GOOGLE ARTIFACT REGISTRY ACCESS FOR ARGOCD IMAGE UPDATER
# ==============================================================================

# Service Account for Artifact Registry access
resource "google_service_account" "artifact_registry_reader" {
  count        = var.enable_secret_manager ? 1 : 0
  account_id   = "${var.environment}-artifact-registry-reader"
  display_name = "${var.environment} Artifact Registry Reader for ArgoCD"
  description  = "Service account for ArgoCD Image Updater to access Google Artifact Registry"
}

# Grant Artifact Registry Reader role
resource "google_project_iam_member" "artifact_registry_reader" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.artifact_registry_reader[0].email}"
}

# Workload Identity binding for ArgoCD Image Updater
resource "google_service_account_iam_member" "artifact_registry_workload_identity" {
  count              = var.enable_secret_manager ? 1 : 0
  service_account_id = google_service_account.artifact_registry_reader[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-image-updater]"
}

# ConfigMap for ArgoCD Image Updater authentication script
resource "kubernetes_config_map" "argocd_image_updater_auth" {
  count = var.enable_secret_manager ? 1 : 0

  metadata {
    name      = "argocd-image-updater-auth"
    namespace = "argocd"
    labels = {
      "app.kubernetes.io/name"       = "argocd-image-updater"
      "app.kubernetes.io/part-of"    = "argocd-image-updater"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "auth.sh" = <<-EOT
#!/bin/sh
# Script to get GCP access token for ArgoCD Image Updater
# This script is called by ArgoCD Image Updater to authenticate with Google Artifact Registry

ACCESS_TOKEN=$(wget --header 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token -q -O - | grep -Eo '"access_token":.*?[^\\]",' | cut -d '"' -f 4)
echo "oauth2accesstoken:$ACCESS_TOKEN"
    EOT
  }

  depends_on = [
    kubernetes_namespace.argocd
  ]
}