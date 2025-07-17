# GCP CDN with Cloud Storage Static Site Hosting

This Terraform configuration sets up a complete CDN-backed static website hosting solution on Google Cloud Platform.

## Architecture Overview

```
User → Cloud CDN → Load Balancer → Backend Bucket → Cloud Storage
         ↓
    SSL Certificate
         ↓
    Cloud Armor (optional)
```

## Features

### Core Features
- ✅ Cloud Storage bucket for static file hosting
- ✅ Cloud CDN for global content delivery
- ✅ HTTPS Load Balancer with managed SSL certificates
- ✅ Custom domain support
- ✅ Automatic HTTP to HTTPS redirect
- ✅ CORS configuration for API access

### Security Features
- 🔒 Cloud Armor DDoS protection and WAF rules
- 🔒 Identity-Aware Proxy (IAP) for access control
- 🔒 Security headers (HSTS, CSP, X-Frame-Options, etc.)
- 🔒 Rate limiting and geo-blocking

### Deployment Features
- 🚀 Workload Identity Federation for GitHub Actions
- 🚀 GitHub Actions automated deployment
- 🚀 Automatic cache invalidation
- 🚀 Deployment scripts with proper cache headers

### Monitoring & Logging
- 📊 CDN access logs to Cloud Storage
- 📊 Monitoring dashboards
- 📊 Alerting policies for availability

## Usage

### 1. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project"
environment = "production"
region = "us-central1"
frontend_domains = ["app.example.com", "www.example.com"]

# Optional: Enable security features
enable_cloud_armor = true
enable_iap = false

# Optional: GitHub Actions deployment
enable_cdn_workload_identity = true
github_repository = "your-org/your-repo"
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 3. Deploy Frontend Assets

#### Manual Deployment
```bash
# Build your frontend
npm run build

# Upload to bucket
gsutil -m rsync -r -d ./dist gs://your-bucket-name/

# Invalidate CDN cache
gcloud compute url-maps invalidate-cdn-cache your-url-map-name --path "/*"
```

#### Automated Deployment
Use the provided GitHub Actions workflow in `examples/github-actions-deploy.yml`.

## Configuration Options

### CDN Cache Settings
- `cdn_client_ttl`: Browser cache duration (default: 1 hour)
- `cdn_default_ttl`: CDN edge cache duration (default: 1 hour)
- `cdn_max_ttl`: Maximum cache duration (default: 24 hours)
- `cdn_serve_while_stale`: Serve stale content while revalidating

### Security Options
- `enable_cloud_armor`: Enable Cloud Armor WAF
- `enable_iap`: Enable Identity-Aware Proxy
- `custom_response_headers`: Add security headers

### Deployment Options
- `enable_cdn_workload_identity`: Enable Workload Identity Federation for CDN deployment via GitHub Actions
- `enable_cache_invalidation`: Auto-invalidate CDN after deploy

## File Structure

```
terraform/
├── cdn-static-site.tf          # Main CDN and storage resources
├── cdn-security.tf             # Security configurations
├── cdn-deployment.tf           # Deployment automation
├── variables-cdn.tf            # CDN-specific variables
├── variables-cdn-deployment.tf # Deployment variables
├── outputs-cdn.tf              # Output values
├── templates/
│   └── deploy-frontend.sh.tpl  # Deployment script template
└── examples/
    ├── terraform.tfvars.example
    └── github-actions-deploy.yml
```

## Best Practices

1. **Cache Strategy**
   - Static assets (JS, CSS): Long cache with immutable flag
   - HTML files: Short cache for updates
   - Use versioned filenames for cache busting

2. **Security**
   - Always use HTTPS
   - Enable Cloud Armor for DDoS protection
   - Set proper CORS headers
   - Use security headers (CSP, HSTS, etc.)

3. **Performance**
   - Enable gzip compression
   - Use appropriate cache headers
   - Consider image optimization
   - Monitor cache hit ratio

4. **Deployment**
   - Always invalidate CDN cache after deployment
   - Use atomic deployments (all or nothing)
   - Test in staging environment first
   - Monitor deployment success

## Troubleshooting

### SSL Certificate Issues
- Managed certificates require DNS to point to the load balancer IP
- Certificate provisioning can take up to 15 minutes
- Ensure all domains in `frontend_domains` are valid

### Cache Issues
- Use cache invalidation after deployments
- Check cache headers with: `curl -I https://your-domain.com`
- Monitor cache hit ratio in Cloud Console

### CORS Issues
- Verify `allowed_origins` includes all necessary domains
- Check browser console for CORS errors
- Test with: `curl -H "Origin: https://example.com" -I https://your-cdn.com`

## Cost Optimization

1. **Storage**: Enable lifecycle rules to delete old content
2. **CDN**: Monitor egress traffic and optimize cache headers
3. **Logging**: Set appropriate retention periods
4. **Monitoring**: Use sampling for high-traffic sites

## Outputs

After deployment, Terraform will output:
- `frontend_bucket_name`: Storage bucket name
- `frontend_cdn_ip`: Load balancer IP address
- `deployment_instructions`: Step-by-step deployment guide
- `github_actions_deployment`: Example GitHub Actions config