# Docker Build and Push Guide

This guide explains how to build and push Docker images for the Kaia Orderbook DEX services to Google Artifact Registry.

## Prerequisites

1. **Google Cloud SDK** installed and authenticated
2. **Docker** installed and running
3. **Repository Access** to the source repositories
4. **GCP Permissions** to push to Artifact Registry

## Repository Structure

The script expects the following directory structure:
```
parent-directory/
├── kaia-orderbook-dex-frontend/
├── kaia-orderbook-dex-backend/
├── kaia-orderbook-dex-core/
└── dexor-charts/ (this repository)
```

## Quick Start

### 1. Build and Push All Images

```bash
# Build and push all services with 'dev' tag
make docker-push-all

# Build and push with custom tag
TAG=v1.0.0 make docker-push-all
```

### 2. Build and Push Individual Services

```bash
# Frontend
make docker-push-frontend

# Backend
make docker-push-backend

# Core (Nitro Node)
make docker-push-core

# With custom tag
TAG=v1.0.0 make docker-push-frontend
```

### 3. Deploy Images (Build, Push, and Update Helm)

```bash
# Complete deployment workflow
make deploy-images
```

This will:
1. Build all Docker images
2. Push them to Artifact Registry
3. Update Helm charts with the new image URLs and tags

## Manual Script Usage

### Build and Push All Services

```bash
./scripts/build-and-push-docker.sh
```

This script will:
1. Authenticate with Google Cloud
2. Create or checkout `feature/deploy` branch in each repository
3. Create Dockerfiles if they don't exist
4. Build Docker images
5. Push to Artifact Registry
6. Commit any new Dockerfiles

### Build and Push Single Service

```bash
# Frontend
./scripts/docker-push-single.sh frontend [tag]

# Backend
./scripts/docker-push-single.sh backend [tag]

# Core
./scripts/docker-push-single.sh core [tag]
```

## Docker Registry Information

- **Project**: `orderbook-dex-dev`
- **Region**: `asia-northeast3`
- **Registry URL**: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry`

## Image URLs

After building and pushing, your images will be available at:

- **Frontend**: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-frontend:dev`
- **Backend API**: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-backend-api:dev`
- **Backend Event**: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-backend-event:dev`
- **Core**: `asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-core:dev`

## Dockerfile Creation

The scripts automatically create Dockerfiles if they don't exist:

### Frontend Dockerfile
- Multi-stage build with Node.js and Nginx
- Builds the React application
- Serves static files with Nginx
- Includes health check endpoint

### Backend Dockerfile
- Multi-stage Go build
- Creates minimal Alpine-based image
- Runs as non-root user
- Supports both API and Event services

### Core Dockerfile
- Uses the existing Nitro node Dockerfile
- References the `nitro-node-slim` target
- Optimized for L2 node operation

## Makefile Targets

| Target | Description |
|--------|-------------|
| `docker-auth` | Authenticate Docker with Artifact Registry |
| `docker-push-all` | Build and push all images |
| `docker-push-frontend` | Build and push frontend only |
| `docker-push-backend` | Build and push backend only |
| `docker-push-core` | Build and push core only |
| `docker-list` | List images in registry |
| `docker-clean` | Remove local images |
| `docker-pull-all` | Pull all images from registry |
| `docker-verify` | Verify images exist in registry |
| `docker-urls` | Show image URLs |
| `helm-update-images` | Update Helm charts with image info |
| `deploy-images` | Complete deployment workflow |

## Troubleshooting

### Authentication Issues
```bash
# Re-authenticate with Google Cloud
gcloud auth login
gcloud config set project orderbook-dex-dev

# Configure Docker
gcloud auth configure-docker asia-northeast3-docker.pkg.dev
```

### Build Failures
1. Ensure all dependencies are installed
2. Check Dockerfile syntax
3. Verify base images are accessible
4. Check disk space for Docker

### Push Failures
1. Verify authentication
2. Check IAM permissions
3. Ensure registry exists
4. Check network connectivity

### Branch Issues
- The script creates/uses `feature/deploy` branch
- If branch exists with conflicts, resolve manually
- Push changes after Dockerfile creation

## Best Practices

1. **Tagging Strategy**
   - Use `dev` for development
   - Use `staging` for staging environment
   - Use semantic versioning for production (e.g., `v1.0.0`)

2. **Image Optimization**
   - Use multi-stage builds
   - Minimize final image size
   - Don't include build tools in runtime image

3. **Security**
   - Run as non-root user
   - Don't include secrets in images
   - Use specific base image versions

4. **Automation**
   - Use `make deploy-images` for complete workflow
   - Set up CI/CD for automatic builds
   - Tag images with commit SHA for traceability