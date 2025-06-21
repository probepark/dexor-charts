#!/bin/bash

# Deploy ArgoCD applications for dev environment

echo "🚀 Deploying ArgoCD applications for dev environment..."

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ kubectl is not properly configured. Please configure kubectl to connect to your dev cluster."
    exit 1
fi

# Create kaia-dex namespace if it doesn't exist
echo "📦 Creating kaia-dex namespace..."
kubectl create namespace kaia-dex --dry-run=client -o yaml | kubectl apply -f -

# Deploy repository secret
echo "🔐 Deploying repository secret..."
echo "⚠️  Please ensure you have updated the SSH private key in repository-secret.yaml with your actual deploy key!"
read -p "Have you updated the deploy key? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled. Please update the deploy key first."
    echo "Generate a deploy key with: ssh-keygen -t rsa -b 4096 -C 'argocd@dexor.trade' -f deploy_key -N ''"
    echo "Then add deploy_key.pub to GitHub repository settings > Deploy keys with read access"
    exit 1
fi

kubectl apply -f repository-secret.yaml

# Deploy applications
echo "📚 Deploying ArgoCD applications..."
kubectl apply -f dev-kaia-orderbook-dex-backend.yaml
kubectl apply -f dev-kaia-orderbook-dex-frontend.yaml
kubectl apply -f dev-kaia-orderbook-dex-core.yaml

echo "✅ ArgoCD applications deployed successfully!"
echo ""
echo "📋 To check application status:"
echo "  kubectl get applications -n argocd"
echo ""
echo "🔄 To sync applications:"
echo "  argocd app sync dev-kaia-orderbook-dex-backend"
echo "  argocd app sync dev-kaia-orderbook-dex-frontend"
echo "  argocd app sync dev-kaia-orderbook-dex-core"
echo ""
echo "🌐 Or use ArgoCD UI to manage applications"