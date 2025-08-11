# ArgoCD Applications

This directory contains ArgoCD application manifests for deploying Kaia DEX services.

## Structure

```
argocd-applications/
├── dev/                          # Development environment applications
│   ├── repository-secret.yaml    # Git repository secret with deploy key
│   ├── dev-kaia-orderbook-dex-backend.yaml
│   ├── dev-kaia-orderbook-dex-frontend.yaml
│   ├── dev-kaia-orderbook-dex-core.yaml
│   └── deploy.sh                 # Deployment script
├── staging/                      # Staging environment (future)
└── prod/                         # Production environment (future)
```

## Setup Deploy Key

1. Generate SSH deploy key:
```bash
ssh-keygen -t rsa -b 4096 -C "argocd@dexor" -f deploy_key -N ""
```

2. Add public key to GitHub:
   - Go to https://github.com/probepark/dexor-charts/settings/keys
   - Click "Add deploy key"
   - Title: "ArgoCD Dev Cluster"
   - Key: Contents of `deploy_key.pub`
   - Check "Allow write access" if needed

3. Update `repository-secret.yaml`:
   - Replace the placeholder with contents of `deploy_key` (private key)

## Deployment

### Prerequisites

1. kubectl configured to connect to dev cluster
2. ArgoCD installed in the cluster
3. Deploy key configured in GitHub

### Deploy Applications

```bash
cd argocd-applications/dev
./deploy.sh
```

This will:
- Create `kaia-dex` namespace
- Deploy repository secret
- Deploy all three applications with `dev-` prefix

### Manual Deployment

```bash
# Create namespace
kubectl create namespace kaia-dex

# Deploy repository secret
kubectl apply -f repository-secret.yaml

# Deploy applications
kubectl apply -f dev-kaia-orderbook-dex-backend.yaml
kubectl apply -f dev-kaia-orderbook-dex-frontend.yaml
kubectl apply -f dev-kaia-orderbook-dex-core.yaml
```

## Application Management

### Check application status
```bash
kubectl get applications -n argocd
argocd app list
```

### Sync applications
```bash
argocd app sync dev-kaia-orderbook-dex-backend
argocd app sync dev-kaia-orderbook-dex-frontend
argocd app sync dev-kaia-orderbook-dex-core
```

### View application details
```bash
argocd app get dev-kaia-orderbook-dex-backend
```

## Configuration

Each application:
- Uses `dev-` prefix for the name
- Deploys to `kaia-dex` namespace
- Sources from `https://github.com/kaiachain/kaia-orderbook-dex-devops`
- Uses respective `values-dev.yaml` file
- Has automated sync with prune and self-heal enabled

## Troubleshooting

### Repository access issues
- Verify deploy key is correctly added to GitHub
- Check repository secret: `kubectl get secret dexor-charts-repo -n argocd -o yaml`
- Test SSH connection: `ssh -T git@github.com`

### Sync failures
- Check application logs: `argocd app logs dev-kaia-orderbook-dex-backend`
- Verify Helm values file exists in the repository
- Check namespace permissions
