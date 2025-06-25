#!/bin/bash

# Script to create Google Container Registry (GCR) secret for ArgoCD Image Updater
# This secret is used for authenticating with Google Artifact Registry

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="kaia-dex"
SECRET_NAME="gcr-secret"
REGISTRY_URL="asia-northeast3-docker.pkg.dev"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --namespace <namespace>       Kubernetes namespace (default: kaia-dex)"
    echo "  -s, --secret-name <name>          Secret name (default: gcr-secret)"
    echo "  -k, --key-file <path>             Path to Google service account JSON key file (required)"
    echo "  -r, --registry <url>              Registry URL (default: asia-northeast3-docker.pkg.dev)"
    echo "  -h, --help                        Display this help message"
    echo ""
    echo "Example:"
    echo "  $0 --key-file ~/gcp-key.json"
    echo "  $0 -k ./service-account.json -n kaia-dex -s gcr-auth"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -s|--secret-name)
            SECRET_NAME="$2"
            shift 2
            ;;
        -k|--key-file)
            KEY_FILE_PATH="$2"
            shift 2
            ;;
        -r|--registry)
            REGISTRY_URL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Check if key file path is provided
if [ -z "$KEY_FILE_PATH" ]; then
    echo -e "${RED}Error: Google service account key file path is required${NC}"
    usage
fi

# Check if key file exists
if [ ! -f "$KEY_FILE_PATH" ]; then
    echo -e "${RED}Error: Service account key file not found: $KEY_FILE_PATH${NC}"
    exit 1
fi

# Validate JSON file
if ! jq empty "$KEY_FILE_PATH" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON file: $KEY_FILE_PATH${NC}"
    exit 1
fi

# Extract email from service account key
SERVICE_ACCOUNT_EMAIL=$(jq -r '.client_email' "$KEY_FILE_PATH")
if [ -z "$SERVICE_ACCOUNT_EMAIL" ] || [ "$SERVICE_ACCOUNT_EMAIL" == "null" ]; then
    echo -e "${RED}Error: Could not extract client_email from service account key${NC}"
    exit 1
fi

echo -e "${GREEN}Creating Google Artifact Registry secret...${NC}"
echo "  Namespace: $NAMESPACE"
echo "  Secret name: $SECRET_NAME"
echo "  Registry: $REGISTRY_URL"
echo "  Service account: $SERVICE_ACCOUNT_EMAIL"

# Create the secret using kubectl
kubectl create secret docker-registry "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    --docker-server="$REGISTRY_URL" \
    --docker-username="_json_key" \
    --docker-password="$(cat "$KEY_FILE_PATH")" \
    --dry-run=client -o yaml > gcr-secret.yaml

# Add labels for ArgoCD Image Updater
cat >> gcr-secret.yaml << EOF

---
# Additional configuration for ArgoCD Image Updater
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
    - name: gcr
      prefix: asia-northeast3-docker.pkg.dev
      api_url: https://asia-northeast3-docker.pkg.dev
      credentials: pullsecret:${NAMESPACE}/${SECRET_NAME}
      defaultns: library
      insecure: no
EOF

echo -e "${GREEN}Successfully created GCR secret configuration${NC}"
echo ""
echo -e "${YELLOW}To apply the secret to your cluster, run:${NC}"
echo "  kubectl apply -f gcr-secret.yaml"
echo ""
echo -e "${YELLOW}Make sure to update your ArgoCD Application to reference this secret:${NC}"
echo "  argocd-image-updater.argoproj.io/pull-secret: ${NAMESPACE}/${SECRET_NAME}"
echo ""
echo -e "${YELLOW}For Workload Identity (recommended), create the secret without key file:${NC}"
echo "  kubectl create secret docker-registry ${SECRET_NAME} \\"
echo "    --namespace=${NAMESPACE} \\"
echo "    --docker-server=${REGISTRY_URL} \\"
echo "    --docker-username=_json_key \\"
echo "    --docker-password='{\"type\": \"service_account\"}'"