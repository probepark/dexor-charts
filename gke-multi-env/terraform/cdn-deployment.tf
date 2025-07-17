resource "google_service_account" "frontend_deploy" {
  account_id   = "${var.environment}-frontend-deploy-sa"
  display_name = "Frontend Deployment Service Account"
  description  = "Service account for deploying frontend assets to CDN"
}

resource "google_storage_bucket_iam_member" "frontend_deploy_admin" {
  bucket = google_storage_bucket.frontend_static.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.frontend_deploy.email}"
}

resource "google_compute_url_maps_iam_member" "frontend_deploy_cdn_invalidator" {
  project = var.project_id
  name    = google_compute_url_map.frontend_url_map.name
  role    = "roles/compute.urlMapAdmin"
  member  = "serviceAccount:${google_service_account.frontend_deploy.email}"
}

resource "google_iam_workload_identity_pool" "frontend_deploy_pool" {
  count                     = var.enable_cdn_workload_identity ? 1 : 0
  workload_identity_pool_id = "${var.environment}-frontend-deploy-pool"
  display_name              = "Frontend deployment pool"
  description               = "Workload Identity Pool for frontend GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "frontend_github" {
  count                              = var.enable_cdn_workload_identity ? 1 : 0
  workload_identity_pool_id          = google_iam_workload_identity_pool.frontend_deploy_pool[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github-frontend"
  display_name                       = "GitHub Frontend Provider"
  
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  
  attribute_condition = "assertion.repository == '${var.github_repository}'"
}

resource "google_service_account_iam_member" "frontend_workload_identity" {
  count              = var.enable_cdn_workload_identity ? 1 : 0
  service_account_id = google_service_account.frontend_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.frontend_deploy_pool[0].name}/attribute.repository/${var.github_repository}"
}

