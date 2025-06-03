# ==============================================================================
# ARTIFACT REGISTRY
# ==============================================================================

resource "google_project_service" "artifact_registry_api" {
  service = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Artifact Registry Repository for Docker images
resource "google_artifact_registry_repository" "docker_registry" {
  location      = var.region
  repository_id = "${var.environment}-docker-registry"
  description   = "Docker repository for ${var.environment} environment"
  format        = "DOCKER"

  labels = local.common_labels

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-tagged-versions"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
    }
  }

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }
}

# Artifact Registry Repository for Helm charts
resource "google_artifact_registry_repository" "helm_registry" {
  location      = var.region
  repository_id = "${var.environment}-helm-registry"
  description   = "Helm repository for ${var.environment} environment"
  format        = "DOCKER"

  labels = local.common_labels

  cleanup_policies {
    id     = "keep-tagged-versions"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
    }
  }

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }
}

# Service Account for GitHub Actions
resource "google_service_account" "github_actions_sa" {
  account_id   = "${var.environment}-github-actions-sa"
  display_name = "${var.environment} GitHub Actions Service Account"
  description  = "Service account for GitHub Actions to push to Artifact Registry"
}

# IAM roles for GitHub Actions Service Account
resource "google_project_iam_member" "github_actions_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

resource "google_project_iam_member" "github_actions_storage_objectViewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

# Optional: Additional roles for GitHub Actions if needed for other GCP services
resource "google_project_iam_member" "github_actions_gke_developer" {
  count   = var.enable_github_gke_access ? 1 : 0
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

# Service Account Key for GitHub Actions (use Workload Identity Federation in production)
resource "google_service_account_key" "github_actions_key" {
  count              = var.create_github_sa_key ? 1 : 0
  service_account_id = google_service_account.github_actions_sa.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Workload Identity Pool for GitHub Actions (recommended for production)
resource "google_iam_workload_identity_pool" "github_pool" {
  count                     = var.enable_workload_identity ? 1 : 0
  workload_identity_pool_id = "${var.environment}-github-pool"
  display_name              = "${var.environment} GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions"
  disabled                  = false
  project                   = var.project_id
}

# Workload Identity Pool Provider for GitHub
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  count                              = var.enable_workload_identity ? 1 : 0
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"
  description                        = "OIDC identity pool provider for GitHub Actions"
  project                            = var.project_id

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.actor"               = "assertion.actor"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_owner"    = "assertion.repository_owner"
    "attribute.repository_id"       = "assertion.repository_id"
  }

  attribute_condition = "assertion.repository_owner == '${split("/", var.github_repository)[0]}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# IAM binding for Workload Identity
resource "google_service_account_iam_binding" "github_workload_identity_binding" {
  count              = var.enable_workload_identity ? 1 : 0
  service_account_id = google_service_account.github_actions_sa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool[0].name}/attribute.repository/${var.github_repository}"
  ]
}
