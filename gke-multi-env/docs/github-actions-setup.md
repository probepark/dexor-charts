# GitHub Actions & Artifact Registry Setup Guide

This guide explains how to configure GitHub Actions to push Docker images and Helm charts to Google Artifact Registry using the newly created Terraform resources.

## Overview

The infrastructure includes:
- **Artifact Registry repositories** for Docker images and Helm charts
- **Service Account** with appropriate permissions for GitHub Actions
- **Workload Identity Federation** (recommended for security)
- **Automatic cleanup policies** for image retention

## Prerequisites

1. Deploy the infrastructure with Artifact Registry resources:
   ```bash
   # Update terraform.tfvars with GitHub repository configuration
   github_repositories = [
     "kaiachain/dexor-charts",
     "kaiachain/another-repo",
     "kaiachain/third-repo"
   ]
   
   make apply-dev  # or make apply-prod
   ```

2. Get the outputs from Terraform:
   ```bash
   terraform output docker_registry_url
   terraform output github_actions_service_account_email
   terraform output workload_identity_provider
   ```

## Authentication Methods

### Method 1: Workload Identity Federation (Recommended)

This is the most secure method as it doesn't require storing service account keys.

#### 1. Configure GitHub Repository Secrets

Add these secrets to your GitHub repository (Settings > Secrets and variables > Actions):

```bash
# Get values from Terraform outputs
WORKLOAD_IDENTITY_PROVIDER=$(terraform output -raw workload_identity_provider)
SERVICE_ACCOUNT_EMAIL=$(terraform output -raw github_actions_service_account_email)
DOCKER_REGISTRY_URL=$(terraform output -raw docker_registry_url)
HELM_REGISTRY_URL=$(terraform output -raw helm_registry_url)
```

GitHub Secrets:
- `WORKLOAD_IDENTITY_PROVIDER`: The provider resource name
- `SERVICE_ACCOUNT_EMAIL`: GitHub Actions service account email
- `DOCKER_REGISTRY_URL`: Artifact Registry Docker repository URL
- `HELM_REGISTRY_URL`: Artifact Registry Helm repository URL

#### 2. Example GitHub Actions Workflow

```yaml
name: Build and Push to Artifact Registry

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  REGISTRY: ${{ secrets.DOCKER_REGISTRY_URL }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    
    permissions:
      contents: read
      id-token: write  # Required for Workload Identity

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ secrets.WORKLOAD_IDENTITY_PROVIDER }}
        service_account: ${{ secrets.SERVICE_ACCOUNT_EMAIL }}

    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2

    - name: Configure Docker for Artifact Registry
      run: gcloud auth configure-docker ${{ env.REGISTRY }} --quiet

    - name: Build Docker image
      run: |
        docker build -t ${{ env.REGISTRY }}/my-app:${{ github.sha }} .
        docker build -t ${{ env.REGISTRY }}/my-app:latest .

    - name: Push Docker image
      run: |
        docker push ${{ env.REGISTRY }}/my-app:${{ github.sha }}
        docker push ${{ env.REGISTRY }}/my-app:latest
```

### Method 2: Service Account Key (Not Recommended for Production)

Only use this method for testing or development environments.

#### 1. Enable Service Account Key Creation

Update your `terraform.tfvars`:
```hcl
create_github_sa_key = true
```

#### 2. Get Service Account Key

```bash
terraform apply
terraform output -raw github_actions_service_account_key | base64 -d > service-account-key.json
```

#### 3. Add GitHub Secret

Add `GOOGLE_CREDENTIALS` secret with the base64-encoded service account key:
```bash
cat service-account-key.json | base64
```

#### 4. Example Workflow with Service Account Key

```yaml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    credentials_json: ${{ secrets.GOOGLE_CREDENTIALS }}

- name: Configure Docker for Artifact Registry
  run: |
    echo '${{ secrets.GOOGLE_CREDENTIALS }}' | docker login -u _json_key --password-stdin https://${{ env.REGISTRY }}
```

## Helm Chart Publishing

### Push Helm Charts to Artifact Registry

```yaml
- name: Package and Push Helm Chart
  run: |
    helm package ./chart
    helm push my-chart-*.tgz oci://${{ secrets.HELM_REGISTRY_URL }}
```

### Use Helm Charts from Artifact Registry

```bash
# Add the registry as a repository
helm registry login $HELM_REGISTRY_URL

# Install chart
helm install my-release oci://$HELM_REGISTRY_URL/my-chart --version 1.0.0
```

## ArgoCD Integration

Configure ArgoCD to pull images from Artifact Registry:

```yaml
# argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/your-org/your-repo'
    path: k8s
    targetRevision: HEAD
    helm:
      parameters:
      - name: image.repository
        value: asia-northeast3-docker.pkg.dev/your-project/dev-docker-registry/my-app
      - name: image.tag
        value: latest
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
```

## Security Considerations

1. **Use Workload Identity Federation** instead of service account keys
2. **Limit permissions** - the service account only has Artifact Registry write access
3. **Enable cleanup policies** to manage storage costs
4. **Use specific image tags** instead of `latest` in production
5. **Scan images** for vulnerabilities before pushing

## Troubleshooting

### Authentication Issues

```bash
# Test authentication
gcloud auth list
gcloud config list

# Test Artifact Registry access
gcloud artifacts repositories list --location=asia-northeast3
```

### Permission Issues

```bash
# Check service account permissions
gcloud projects get-iam-policy PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:SERVICE_ACCOUNT_EMAIL"
```

### Docker Push Issues

```bash
# Check Docker configuration
cat ~/.docker/config.json

# Test registry connectivity
docker pull hello-world
docker tag hello-world REGISTRY_URL/hello-world:test
docker push REGISTRY_URL/hello-world:test
```

## Cleanup Policies

The Terraform configuration includes automatic cleanup policies:

- **Tagged images**: Kept for 30 days (configurable)
- **Untagged images**: Deleted after 7 days
- **Keep recent versions**: Always keep images newer than 1 day

Adjust retention periods in `terraform.tfvars`:
```hcl
docker_retention_days = 30
helm_retention_days = 30
```

## Cost Optimization

1. **Use cleanup policies** to automatically delete old images
2. **Monitor storage usage** in the GCP Console
3. **Use multi-stage Docker builds** to reduce image size
4. **Consider regional vs. multi-regional** repositories based on needs

## Outputs Reference

After applying Terraform, these outputs are available:

- `docker_registry_url`: Full URL for Docker image registry
- `helm_registry_url`: Full URL for Helm chart registry  
- `github_actions_service_account_email`: Service account for GitHub Actions
- `workload_identity_provider`: Provider name for Workload Identity
- `github_actions_docker_login_command`: Example Docker login command
- `github_actions_push_example`: Example push commands