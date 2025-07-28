output "cdn_sites_info" {
  description = "Information about all CDN sites"
  value = {
    for site_key, site in var.cdn_sites : site_key => {
      bucket_name = google_storage_bucket.cdn_sites[site_key].name
      bucket_url  = google_storage_bucket.cdn_sites[site_key].url
      domains     = site.domains
      backend_id  = google_compute_backend_bucket.cdn_backends[site_key].id
    }
  }
}

output "cdn_load_balancer_ip" {
  description = "Single IP address serving all CDN sites"
  value       = google_compute_global_address.cdn_ip.address
}

output "cdn_url_map_name" {
  description = "Name of the Application Load Balancer URL map for cache invalidation"
  value       = google_compute_url_map.cdn_url_map_alb.name
}

output "cdn_deployment_service_account" {
  description = "Service account email for CDN deployment"
  value       = google_service_account.cdn_deploy.email
}

output "cdn_deployment_instructions" {
  description = "Deployment instructions for each site"
  value = {
    for site_key, site in var.cdn_sites : site_key => {
      deploy_command = "gsutil -m rsync -r -d ./dist gs://${google_storage_bucket.cdn_sites[site_key].name}/"
      domains        = join(", ", formatlist("https://%s", site.domains))
    }
  }
}

output "cdn_dns_configuration" {
  description = "DNS configuration for all domains"
  value = {
    ip_address = google_compute_global_address.cdn_ip.address
    domains    = flatten([for site in var.cdn_sites : site.domains])
    dns_instruction = "Point all domains to IP: ${google_compute_global_address.cdn_ip.address}"
  }
}

output "cdn_github_actions_config" {
  description = "GitHub Actions configuration for deployment"
  value = {
    service_account = google_service_account.cdn_deploy.email
    workload_identity_provider = var.enable_cdn_workload_identity ? google_iam_workload_identity_pool_provider.cdn_github[0].name : "Not configured"
    buckets = { for site_key, site in var.cdn_sites : site_key => google_storage_bucket.cdn_sites[site_key].name }
    url_map = google_compute_url_map.cdn_url_map_alb.name
  }
}