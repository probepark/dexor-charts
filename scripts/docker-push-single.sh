#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GCP_PROJECT="orderbook-dex-dev"
GCP_REGION="asia-northeast3"
REGISTRY_URL="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/dev-docker-registry"
DEFAULT_TAG="dev"
BRANCH_NAME="feature/deploy"

# Print usage
usage() {
    echo "Usage: $0 <repository-name> [tag]"
    echo "  repository-name: One of: frontend, backend, core"
    echo "  tag: Docker image tag (default: ${DEFAULT_TAG})"
    echo ""
    echo "Examples:"
    echo "  $0 frontend"
    echo "  $0 backend v1.0.0"
    echo "  $0 core latest"
    exit 1
}

# Check arguments
if [ $# -lt 1 ]; then
    usage
fi

# Parse arguments
REPO_SHORT=$1
TAG=${2:-$DEFAULT_TAG}

# Map short names to full repository names
case "$REPO_SHORT" in
    "frontend")
        REPO_NAME="kaia-orderbook-dex-frontend"
        ;;
    "backend")
        REPO_NAME="kaia-orderbook-dex-backend"
        ;;
    "core")
        REPO_NAME="kaia-orderbook-dex-core"
        ;;
    *)
        echo "Error: Unknown repository: $REPO_SHORT"
        usage
        ;;
esac

# Parent directory
PARENT_DIR="../.."
REPO_DIR="${PARENT_DIR}/${REPO_NAME}"

# Print colored message
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if directory exists
check_directory() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        print_message $RED "Error: Directory $dir does not exist"
        print_message $YELLOW "Please ensure the repository is cloned at: $dir"
        exit 1
    fi
}

# Main execution
main() {
    print_message $GREEN "=== Docker Build and Push for ${REPO_NAME} ==="
    print_message $BLUE "Registry: ${REGISTRY_URL}"
    print_message $BLUE "Tag: ${TAG}"
    echo
    
    # Check directory
    check_directory "$REPO_DIR"
    
    # Change to repository directory
    cd "$REPO_DIR"
    
    # Check current branch
    current_branch=$(git branch --show-current)
    if [ "$current_branch" != "$BRANCH_NAME" ]; then
        print_message $YELLOW "Warning: Current branch is '$current_branch', not '$BRANCH_NAME'"
        read -p "Do you want to continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message $RED "Aborted by user"
            exit 1
        fi
    fi
    
    # Authenticate Docker
    print_message $BLUE "Authenticating Docker with Artifact Registry..."
    gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev --quiet
    
    # Build image
    local image_name="${REGISTRY_URL}/${REPO_NAME}:${TAG}"
    print_message $BLUE "Building Docker image: ${image_name}"
    
    docker build -t "${image_name}" .
    
    if [ $? -eq 0 ]; then
        print_message $GREEN "✓ Docker image built successfully"
        
        # Push image
        print_message $BLUE "Pushing image to Artifact Registry..."
        docker push "${image_name}"
        
        if [ $? -eq 0 ]; then
            print_message $GREEN "✓ Image pushed successfully!"
            echo
            print_message $GREEN "Image URL: ${image_name}"
            echo
            print_message $BLUE "To use this image in Kubernetes:"
            echo "  image: ${image_name}"
        else
            print_message $RED "✗ Failed to push image"
            exit 1
        fi
    else
        print_message $RED "✗ Failed to build Docker image"
        exit 1
    fi
}

# Run main function
main