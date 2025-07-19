# Workload Identity Federation for GitHub Actions (shared across all sites)
resource "google_iam_workload_identity_pool" "cdn_deploy_pool" {
  count                     = var.enable_cdn_workload_identity ? 1 : 0
  workload_identity_pool_id = "${var.environment}-cdn-deploy-pool"
  display_name              = "CDN deployment pool"
  description               = "Workload Identity Pool for CDN GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "cdn_github" {
  count                              = var.enable_cdn_workload_identity ? 1 : 0
  workload_identity_pool_id          = google_iam_workload_identity_pool.cdn_deploy_pool[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github-cdn"
  display_name                       = "GitHub CDN Provider"
  
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  
  attribute_condition = "assertion.repository in [${join(",", formatlist("'%s'", var.cdn_github_repositories))}]"
}

resource "google_service_account_iam_member" "cdn_workload_identity" {
  for_each = var.enable_cdn_workload_identity ? toset(var.cdn_github_repositories) : []
  
  service_account_id = google_service_account.cdn_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.cdn_deploy_pool[0].name}/attribute.repository/${each.value}"
}