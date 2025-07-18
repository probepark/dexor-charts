# ==============================================================================
# GOOGLE ARTIFACT REGISTRY ACCESS FOR ARGOCD IMAGE UPDATER
# ==============================================================================

# Note: kaia-dex namespace is expected to exist already (created by ArgoCD or manually)

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
resource "kubernetes_config_map" "argocd_image_updater_config" {
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
# This script generates docker credentials for Google Artifact Registry using Workload Identity

# Use IP address instead of metadata.google.internal to avoid DNS issues
TOKEN=$(wget -qO- --header="Metadata-Flavor: Google" \
  "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token" \
  | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "Failed to get access token" >&2
  exit 1
fi

# Return in the format expected by ArgoCD Image Updater
echo "oauth2accesstoken:$TOKEN"
    EOT
  }

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

# Note: The ArgoCD Image Updater registries ConfigMap is managed by Helm
# The registry configuration is set in the Helm values in main.tf

# Create a dummy secret for ArgoCD applications to reference (dev namespace)
resource "kubernetes_secret" "gcr_secret" {
  count = var.enable_secret_manager ? 1 : 0

  metadata {
    name      = "gcr-secret"
    namespace = "kaia-dex"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "asia-northeast3-docker.pkg.dev" = {
          username = "oauth2accesstoken"
          password = "dummy"
          auth     = base64encode("oauth2accesstoken:dummy")
        }
      }
    })
  }

  # No depends_on needed as the namespace should already exist
}

# Create a dummy secret for ArgoCD applications to reference (qa namespace)
resource "kubernetes_secret" "gcr_secret_qa" {
  count = var.enable_secret_manager ? 1 : 0

  metadata {
    name      = "gcr-secret"
    namespace = "kaia-dex-qa"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "asia-northeast3-docker.pkg.dev" = {
          username = "oauth2accesstoken"
          password = "dummy"
          auth     = base64encode("oauth2accesstoken:dummy")
        }
      }
    })
  }

  # No depends_on needed as the namespace should already exist
}

# Role for ArgoCD Image Updater to read secrets in kaia-dex namespace
resource "kubernetes_role" "argocd_image_updater_secrets" {
  count = var.enable_secret_manager ? 1 : 0

  metadata {
    name      = "argocd-image-updater-secrets"
    namespace = "kaia-dex"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }
}

# RoleBinding for ArgoCD Image Updater in kaia-dex namespace
resource "kubernetes_role_binding" "argocd_image_updater_secrets" {
  count = var.enable_secret_manager ? 1 : 0

  metadata {
    name      = "argocd-image-updater-secrets"
    namespace = "kaia-dex"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.argocd_image_updater_secrets[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-image-updater"
    namespace = "argocd"
  }
}

# Role for ArgoCD Image Updater to read secrets in kaia-dex-qa namespace
resource "kubernetes_role" "argocd_image_updater_secrets_qa" {
  count = var.enable_secret_manager ? 1 : 0

  metadata {
    name      = "argocd-image-updater-secrets"
    namespace = "kaia-dex-qa"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }
}

# RoleBinding for ArgoCD Image Updater in kaia-dex-qa namespace
resource "kubernetes_role_binding" "argocd_image_updater_secrets_qa" {
  count = var.enable_secret_manager ? 1 : 0

  metadata {
    name      = "argocd-image-updater-secrets"
    namespace = "kaia-dex-qa"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.argocd_image_updater_secrets_qa[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-image-updater"
    namespace = "argocd"
  }
}