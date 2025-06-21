#!/bin/bash

# Script to create repository-secret.yaml for ArgoCD
# This secret is used for Git repository authentication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="argocd"
SECRET_NAME="dexor-charts-repo"
REPO_URL="git@github.com:probepark/dexor-charts.git"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --namespace <namespace>    Kubernetes namespace (default: argocd)"
    echo "  -s, --secret-name <name>       Secret name (default: dexor-charts-repo)"
    echo "  -r, --repo-url <url>          Repository URL (default: git@github.com:probepark/dexor-charts.git)"
    echo "  -k, --ssh-key <path>          Path to SSH private key file (required)"
    echo "  -h, --help                    Display this help message"
    echo ""
    echo "Example:"
    echo "  $0 --ssh-key ~/.ssh/id_rsa"
    echo "  $0 -k ./deploy_key -n argocd -s my-repo-secret"
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
        -r|--repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY_PATH="$2"
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

# Check if SSH key path is provided
if [ -z "$SSH_KEY_PATH" ]; then
    echo -e "${RED}Error: SSH private key path is required${NC}"
    usage
fi

# Check if SSH key file exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}Error: SSH private key file not found: $SSH_KEY_PATH${NC}"
    exit 1
fi

# Read SSH private key
SSH_PRIVATE_KEY=$(cat "$SSH_KEY_PATH" | base64 | tr -d '\n')

# Output directory
OUTPUT_DIR="argocd-applications/dev"
OUTPUT_FILE="$OUTPUT_DIR/repository-secret.yaml"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Generate repository-secret.yaml
cat > "$OUTPUT_FILE" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: ${REPO_URL}
  sshPrivateKey: |
$(cat "$SSH_KEY_PATH" | sed 's/^/    /')
---
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}-image-updater
  namespace: ${NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
data:
  sshPrivateKey: ${SSH_PRIVATE_KEY}
EOF

echo -e "${GREEN}Successfully created repository secret: $OUTPUT_FILE${NC}"
echo ""
echo "Secret details:"
echo "  Namespace: $NAMESPACE"
echo "  Secret name: $SECRET_NAME"
echo "  Repository URL: $REPO_URL"
echo "  SSH key: $SSH_KEY_PATH"
echo ""
echo -e "${YELLOW}Note: This file contains sensitive data and is gitignored.${NC}"
echo -e "${YELLOW}Apply it manually to your cluster:${NC}"
echo ""
echo "  kubectl apply -f $OUTPUT_FILE"
echo ""
echo -e "${YELLOW}For ArgoCD Image Updater, make sure to configure the git credentials:${NC}"
echo "  argocd-image-updater.argoproj.io/git-credentials: ${SECRET_NAME}-image-updater"