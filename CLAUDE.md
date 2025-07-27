# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains Helm charts and infrastructure code for deploying the Kaia Orderbook DEX, a decentralized exchange platform on Kaia blockchain. The system consists of four main components deployed on Google Kubernetes Engine (GKE):

1. **Frontend**: React-based SPA with Vite
2. **Backend**: API and Event services for business logic and blockchain integration
3. **Admin**: Next.js-based admin dashboard
4. **Core**: Arbitrum Nitro-based L2 solution for orderbook functionality

## High-Level Architecture

The system follows a GitOps deployment model using ArgoCD for continuous deployment:

```
Developer → Git Push → ArgoCD → GKE Cluster → Services
                     ↓
                   Terraform → GCP Infrastructure
```

### Key Infrastructure Components
- **GKE**: Kubernetes clusters with separate node pools for different workloads
- **Cloud SQL**: MySQL database for application state
- **Memorystore**: Redis for caching and real-time data
- **Secret Manager**: Secure storage for sensitive configuration
- **Artifact Registry**: Docker image storage

## Common Development Tasks

### Building and Deploying Docker Images
```bash
# Build and push all images with 'dev' tag
make docker-push-all

# Build individual services
make docker-push-frontend
make docker-push-backend
make docker-push-core

# Deploy everything (build, push, update charts)
make deploy-images

# Verify images in registry
make docker-verify
```

### Helm Chart Operations
```bash
# Install all charts
helm install kaia-backend charts/kaia-orderbook-dex-backend/
helm install kaia-frontend charts/kaia-orderbook-dex-frontend/
helm install kaia-admin charts/kaia-orderbook-dex-admin/
helm install kaia-core charts/kaia-orderbook-dex-core/

# Upgrade with new values
helm upgrade kaia-backend charts/kaia-orderbook-dex-backend/ -f charts/kaia-orderbook-dex-backend/values-dev.yaml

# Update charts with registry URLs
make helm-update-images
```

### ArgoCD Deployment
```bash
# Create repository secret for ArgoCD
./scripts/create-repository-secret.sh --ssh-key ./deploy_key

# Deploy ArgoCD applications
kubectl apply -f argocd-applications/dev/
```

### Core Contract Deployment
```bash
# Deploy contracts to Kairos testnet
make deploy-core-contracts

# Sync deployed addresses to Helm values
make sync-core-values

# Full deployment (contracts + sync + k8s)
make deploy-core-all
```

### Monitoring and Debugging
```bash
# Check deployment status
make status

# Port forward to access services locally
make port-forward  # RPC at http://localhost:8547

# View logs
kubectl logs -n kaia-dex -l app.kubernetes.io/name=kaia-orderbook-dex-backend
```

## Code Architecture

### Repository Structure
- **charts/**: Helm charts for each component
  - Each chart has environment-specific values files (values-dev.yaml, values-qa.yaml)
  - Templates follow Kubernetes best practices with health checks, resource limits, and security contexts
- **argocd-applications/**: ArgoCD application manifests per environment
  - Configured with image updater for automatic deployments
- **scripts/**: Automation scripts for building, deployment, and operations
- **config/**: Chain configuration and deployed contract addresses
- **gke-multi-env/**: Terraform infrastructure code (has its own CLAUDE.md)

### Key Configuration Patterns

#### Environment Management
- Environment phase set via `KAIA_ORDERBOOK_PHASE` environment variable
- Each environment has separate:
  - Kubernetes namespace (kaia-dex)
  - Helm values files (values-{env}.yaml)
  - ArgoCD applications
  - GCP project resources

#### Service Discovery
- Internal services communicate via Kubernetes service names
- Backend API: `kaia-orderbook-dex-backend-api`
- Backend Event: `kaia-orderbook-dex-backend-event`
- Core RPC: `kaia-orderbook-dex-core-nitro-service:8547`

#### Security Patterns
- Google Secret Manager integration for sensitive data
- Service accounts with Workload Identity
- Network policies for service isolation
- Pod security contexts with non-root users

### Helm Chart Patterns

#### Image Management
Each service defines images with registry and tag:
```yaml
api:
  image:
    name: asia-northeast3-docker.pkg.dev/orderbook-dex-dev/dev-docker-registry/kaia-orderbook-dex-backend
    tag: "dev"
```

#### Resource Configuration
Services have configurable resources with sensible defaults:
```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

#### Health Checks
All services implement liveness and readiness probes:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
readinessProbe:
  httpGet:
    path: /ready
    port: http
```

### Deployment Workflow

1. **Code Changes**: Push to service repositories (frontend, backend, core)
2. **Build Images**: Use `make docker-push-all` to build and push to Artifact Registry
3. **Update Charts**: `make helm-update-images` updates image references
4. **Deploy**: Either:
   - Manual: `helm upgrade` commands
   - GitOps: Commit changes, ArgoCD auto-deploys
5. **Verify**: Check pod status, logs, and service endpoints

### Testing Deployments

For testing changes before production:
1. Use feature branches with custom tags: `TAG=feature-xyz make docker-push-all`
2. Deploy to dev environment first
3. Run integration tests against dev deployment
4. Promote to QA/prod after validation

## Important Notes

- Always authenticate with GCP before Docker operations: `make docker-auth`
- The core component requires deployed contracts; check config/dev/deployment.json for addresses
- Backend services expect config files mounted from ConfigMaps
- Frontend runtime configuration is injected via nginx config
- Use preemptible nodes in dev to reduce costs
- Production deployments should use proper resource limits and HA configurations