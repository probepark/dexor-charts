# Kaia Orderbook DEX Helm Charts

This repository contains Helm charts for deploying the Kaia Orderbook DEX infrastructure on Google Kubernetes Engine (GKE).

## Quick Start - Docker Build and Deploy

```bash
# 1. Build and push all Docker images
make docker-push-all

# 2. Update Helm charts with new images and deploy
make deploy-images

# 3. Verify images in registry
make docker-verify
```

For detailed Docker operations, see [DOCKER_BUILD_GUIDE.md](DOCKER_BUILD_GUIDE.md).

## Repository Structure

```
.
├── charts/                          # Helm charts
│   ├── kaia-orderbook-dex-backend/  # Backend services chart
│   ├── kaia-orderbook-dex-frontend/ # Frontend application chart
│   ├── kaia-orderbook-dex-admin/    # Admin dashboard chart
│   └── kaia-orderbook-dex-core/     # Core Nitro node chart
├── gke-multi-env/                   # GKE infrastructure (Terraform)
├── scripts/                         # Automation scripts
│   ├── build-and-push-docker.sh     # Build and push all images
│   └── docker-push-single.sh        # Build and push single image
├── Makefile                         # Automation commands
└── DOCKER_BUILD_GUIDE.md            # Docker build documentation
```

## Components

### 1. Backend Services
- **API Service**: REST API and WebSocket endpoints
- **Event Service**: Blockchain event processing
- Minimal configuration with Secret Manager integration

### 2. Frontend Application
- React-based SPA with Vite
- Nginx serving with runtime configuration
- WebSocket support for real-time data

### 3. Admin Dashboard
- Next.js-based admin interface
- Trading pairs and user management
- Fee and analytics management

### 4. Core (Nitro Node)
- Arbitrum Nitro-based L2 solution
- Orderbook DEX functionality
- Sequencer and validator modes

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- Docker (for building images)
- Google Cloud SDK (for Artifact Registry)
- Access to source repositories

## Docker Image Management

### Building and Pushing Images

```bash
# Authenticate with Artifact Registry
make docker-auth

# Build and push all images with 'dev' tag
make docker-push-all

# Build individual services
make docker-push-frontend
make docker-push-backend
make docker-push-core

# Use custom tag
TAG=v1.0.0 make docker-push-frontend
```

### Image URLs
- Frontend: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-frontend:dev`
- Backend: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-backend:dev`
- Admin: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-admin:dev`
- Core: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core:dev`

## Helm Chart Deployment

### Install Charts

```bash
# Backend
helm install kaia-backend charts/kaia-orderbook-dex-backend/

# Frontend
helm install kaia-frontend charts/kaia-orderbook-dex-frontend/

# Admin
helm install kaia-admin charts/kaia-orderbook-dex-admin/

# Core
helm install kaia-core charts/kaia-orderbook-dex-core/
```

### Update with Registry Images

```bash
# Automatically update Helm values with registry URLs
make helm-update-images

# Then upgrade releases
helm upgrade kaia-backend charts/kaia-orderbook-dex-backend/
helm upgrade kaia-frontend charts/kaia-orderbook-dex-frontend/
helm upgrade kaia-admin charts/kaia-orderbook-dex-admin/
helm upgrade kaia-core charts/kaia-orderbook-dex-core/
```

## ArgoCD Deployment

### Prerequisites for ArgoCD

1. **Create Repository Secret**

The ArgoCD applications require Git repository access. Create the secret using the provided script:

```bash
# Generate SSH key pair (if not already exists)
ssh-keygen -t rsa -b 4096 -f ./deploy_key -N ""

# Create repository secret YAML
./scripts/create-repository-secret.sh --ssh-key ./deploy_key

# Apply the secret to your cluster
kubectl apply -f argocd-applications/dev/repository-secret.yaml
```

The script creates two secrets:
- Repository access secret for ArgoCD
- SSH key secret for ArgoCD Image Updater

2. **Deploy ArgoCD Applications**

```bash
# Deploy all ArgoCD applications
kubectl apply -f argocd-applications/dev/
```

### ArgoCD Image Updater

All ArgoCD applications are configured with Image Updater annotations to automatically deploy new images when pushed to the registry:

- **Backend**: Tracks both API and Event service images
- **Core**: Tracks Nitro node image
- **Frontend**: Tracks frontend image

When new images are pushed with the `dev` tag, ArgoCD Image Updater will:
1. Detect the new image version
2. Create a git commit in a new branch
3. Update the application automatically

## Complete Deployment Workflow

```bash
# 1. Ensure repositories are cloned in parent directory
cd ../
git clone https://github.com/kaiachain/kaia-orderbook-dex-frontend.git
git clone https://github.com/kaiachain/kaia-orderbook-dex-backend.git
git clone https://github.com/kaiachain/kaia-orderbook-dex-core.git
cd dexor-charts/

# 2. Deploy everything (build, push, update charts)
make deploy-images

# 3. Install/upgrade Helm releases
helm upgrade --install kaia-backend charts/kaia-orderbook-dex-backend/
helm upgrade --install kaia-frontend charts/kaia-orderbook-dex-frontend/
helm upgrade --install kaia-admin charts/kaia-orderbook-dex-admin/
helm upgrade --install kaia-core charts/kaia-orderbook-dex-core/
```

## Available Make Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make docker-push-all` | Build and push all Docker images |
| `make docker-push-frontend` | Build and push frontend image |
| `make docker-push-backend` | Build and push backend image |
| `make docker-push-core` | Build and push core image |
| `make docker-list` | List images in Artifact Registry |
| `make docker-verify` | Verify images exist in registry |
| `make docker-urls` | Show Docker image URLs |
| `make helm-update-images` | Update Helm charts with image info |
| `make deploy-images` | Complete build, push, and update workflow |

## Configuration

### Environment Variables
- `GCP_PROJECT`: GCP project ID (default: `orderbook-dex-dev`)
- `GCP_REGION`: GCP region (default: `asia-northeast3`)
- `TAG`: Docker image tag (default: `dev`)

### Helm Values
Each chart has its own `values.yaml` file with environment-specific configurations. Key values to update:

- Image repository and tag
- Environment phase (dev/staging/prod)
- Resource limits and requests
- Ingress configuration
- Service-specific settings

## Troubleshooting

### Docker Build Issues
1. Ensure Docker daemon is running
2. Check Dockerfile syntax
3. Verify base images are accessible

### Registry Push Issues
1. Authenticate: `gcloud auth configure-docker asia-northeast3-docker.pkg.dev`
2. Check IAM permissions for Artifact Registry
3. Verify project and region settings

### Helm Deployment Issues
1. Check image pull secrets
2. Verify image URLs in values.yaml
3. Check resource quotas and limits
4. Review pod logs: `kubectl logs -l app.kubernetes.io/name=<service>`

## License

See LICENSE file in the repository.