# Google Artifact Registry Access Setup for ArgoCD Image Updater

This guide explains how to configure ArgoCD Image Updater to access Google Artifact Registry (GAR) using Terraform.

## Overview

The setup creates:
1. A Google Service Account with Artifact Registry Reader permissions
2. Workload Identity bindings for secure pod-to-GCP authentication
3. Kubernetes secrets for docker registry authentication
4. ArgoCD Image Updater configuration

## Architecture

```
ArgoCD Image Updater (Pod)
    ↓
Kubernetes Service Account (argocd-image-updater)
    ↓
Workload Identity Binding
    ↓
Google Service Account (artifact-registry-reader)
    ↓
Google Artifact Registry
```

## Prerequisites

- GKE cluster with Workload Identity enabled
- ArgoCD installed in the cluster
- ArgoCD Image Updater installed
- Terraform initialized with the GKE module

## Configuration

### 1. Enable in Terraform

The GCR access is automatically configured when `enable_secret_manager` is set to `true` in your terraform.tfvars:

```hcl
# environments/dev/terraform.tfvars
enable_secret_manager = true
create_gcr_key = false  # Use Workload Identity (recommended)
```

### 2. Apply Terraform Changes

```bash
# For development environment
make apply-dev

# For production environment
make apply-prod
```

### 3. Verify the Setup

Check that resources were created:

```bash
# Check service account
gcloud iam service-accounts describe dev-artifact-registry-reader@${PROJECT_ID}.iam.gserviceaccount.com

# Check Kubernetes secret
kubectl get secret gcr-secret -n kaia-dex

# Check ArgoCD Image Updater config
kubectl get configmap argocd-image-updater-config -n argocd
```

## Usage in ArgoCD Applications

### Application Annotation

Add the following annotation to your ArgoCD Application:

```yaml
metadata:
  annotations:
    # Image list configuration
    argocd-image-updater.argoproj.io/image-list: |
      myapp=asia-northeast3-docker.pkg.dev/project/repo/image:tag
    
    # Pull secret reference
    argocd-image-updater.argoproj.io/pull-secret: pullsecret:kaia-dex/gcr-secret
```

### Example Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-kaia-orderbook-dex-core
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: |
      nitro=asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core:dev
    argocd-image-updater.argoproj.io/nitro.update-strategy: latest
    argocd-image-updater.argoproj.io/nitro.helm.image-name: nitroNode.image.repository
    argocd-image-updater.argoproj.io/nitro.helm.image-tag: nitroNode.image.tag
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: image-updater-{{.SHA256}}
    argocd-image-updater.argoproj.io/pull-secret: pullsecret:kaia-dex/gcr-secret
spec:
  # ... rest of application spec
```

## Workload Identity vs Service Account Key

### Workload Identity (Recommended)

By default, the setup uses Workload Identity for authentication:

```hcl
create_gcr_key = false  # Default
```

Benefits:
- No key rotation needed
- More secure (no keys stored)
- Automatic credential management

### Service Account Key (Alternative)

If Workload Identity is not available, use a service account key:

```hcl
create_gcr_key = true
```

The key will be stored in Google Secret Manager and included in the docker config secret.

## Troubleshooting

### Check ArgoCD Image Updater Logs

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater
```

### Verify Registry Access

```bash
# Test pulling an image using the secret
kubectl run test-gcr-access \
  --image=asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core:dev \
  --namespace=kaia-dex \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"gcr-secret"}]}}' \
  --rm -it --restart=Never -- echo "Success"
```

### Common Issues

1. **403 Forbidden errors**
   - Check IAM permissions: Service account needs `roles/artifactregistry.reader`
   - Verify project ID in the image path

2. **Image not found**
   - Ensure the image exists in the registry
   - Check the registry URL format

3. **Authentication failures**
   - Verify Workload Identity binding
   - Check secret is properly formatted
   - Ensure ArgoCD Image Updater can access the secret

## Security Considerations

1. **Least Privilege**: Service account only has read access to Artifact Registry
2. **Namespace Isolation**: Secrets are created in specific namespaces
3. **Workload Identity**: Preferred over service account keys
4. **Audit Logging**: All registry access is logged in Cloud Audit Logs

## Cleanup

To remove GCR access configuration:

```bash
# Remove from Terraform state
terraform destroy -target=google_service_account.artifact_registry_reader
terraform destroy -target=kubernetes_secret.gcr_docker_config

# Or disable in tfvars and apply
enable_secret_manager = false
make apply-dev
```