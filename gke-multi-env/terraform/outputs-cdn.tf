output "frontend_bucket_name" {
  description = "Name of the frontend static hosting bucket"
  value       = google_storage_bucket.frontend_static.name
}

output "frontend_bucket_url" {
  description = "URL of the frontend static hosting bucket"
  value       = google_storage_bucket.frontend_static.url
}

output "frontend_cdn_ip" {
  description = "IP address of the CDN load balancer"
  value       = google_compute_global_address.frontend_ip.address
}

output "frontend_cdn_url" {
  description = "URL to access the CDN"
  value       = "https://${google_compute_global_address.frontend_ip.address}"
}

output "frontend_domains_status" {
  description = "Status of configured frontend domains"
  value = {
    domains     = var.frontend_domains
    ip_address  = google_compute_global_address.frontend_ip.address
    certificate = var.use_managed_certificate ? "Google-managed" : "Custom"
  }
}

output "cdn_backend_name" {
  description = "Name of the CDN backend bucket"
  value       = google_compute_backend_bucket.frontend_cdn.name
}

output "url_map_name" {
  description = "Name of the URL map"
  value       = google_compute_url_map.frontend_url_map.name
}

output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = var.use_managed_certificate ? google_compute_managed_ssl_certificate.frontend_cert[0].name : google_compute_ssl_certificate.frontend_cert_custom[0].name
}

output "cdn_logging_bucket" {
  description = "Name of the CDN logging bucket"
  value       = var.enable_cdn_logging ? google_storage_bucket.frontend_logs[0].name : null
}

output "deployment_instructions" {
  description = "Instructions for deploying frontend assets"
  value = <<-EOT
    To deploy your frontend assets:
    
    1. Build your frontend application:
       npm run build
    
    2. Upload to the bucket:
       gsutil -m rsync -r -d ./dist gs://${google_storage_bucket.frontend_static.name}/
    
    3. (Optional) Invalidate CDN cache:
       gcloud compute url-maps invalidate-cdn-cache ${google_compute_url_map.frontend_url_map.name} --path "/*"
    
    4. Access your site at:
       ${join(", ", formatlist("https://%s", var.frontend_domains))}
  EOT
}

output "github_actions_deployment" {
  description = "GitHub Actions deployment configuration"
  value = <<-EOT
    GitHub Actions deployment requires:
    
    1. Service Account: ${google_service_account.frontend_deploy.email}
    2. Workload Identity Provider: ${var.enable_cdn_workload_identity ? google_iam_workload_identity_pool_provider.frontend_github[0].name : "Not configured"}
    3. Bucket: gs://${google_storage_bucket.frontend_static.name}/
    4. URL Map: ${google_compute_url_map.frontend_url_map.name}
    
    Use the provided GitHub Actions workflow in examples/github-actions-deploy.yml
  EOT
}