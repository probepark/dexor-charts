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
TAG="dev"
BRANCH_NAME="feature/deploy"

# Parent directory containing the repositories
PARENT_DIR="../.."

# Repositories to process
REPOS=(
    "kaia-orderbook-dex-frontend"
    "kaia-orderbook-dex-backend"
    "kaia-orderbook-dex-core"
)

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
        return 1
    fi
    return 0
}

# Authenticate with Google Cloud
authenticate_gcloud() {
    print_message $BLUE "=== Authenticating with Google Cloud ==="
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_message $YELLOW "No active GCP account found. Please authenticate..."
        gcloud auth login
    fi
    
    # Set project
    gcloud config set project ${GCP_PROJECT}
    
    # Configure Docker authentication
    gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev --quiet
    print_message $GREEN "✓ Google Cloud authentication configured"
}

# Create or checkout feature/deploy branch
setup_branch() {
    local repo_dir=$1
    local repo_name=$2
    
    print_message $BLUE "Setting up branch ${BRANCH_NAME} for ${repo_name}..."
    
    cd "$repo_dir"
    
    # Fetch latest changes
    git fetch origin
    
    # Check if branch exists locally
    if git show-ref --verify --quiet refs/heads/${BRANCH_NAME}; then
        print_message $YELLOW "Branch ${BRANCH_NAME} exists locally, checking out..."
        git checkout ${BRANCH_NAME}
        # Try to pull latest changes if remote branch exists
        if git ls-remote --heads origin ${BRANCH_NAME} | grep -q .; then
            git pull origin ${BRANCH_NAME} || true
        fi
    else
        # Check if branch exists on remote
        if git ls-remote --heads origin ${BRANCH_NAME} | grep -q .; then
            print_message $YELLOW "Branch ${BRANCH_NAME} exists remotely, checking out..."
            git checkout -b ${BRANCH_NAME} origin/${BRANCH_NAME}
        else
            print_message $YELLOW "Creating new branch ${BRANCH_NAME}..."
            # Get the default branch (main, master, or dev)
            local default_branch=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
            git checkout -b ${BRANCH_NAME} origin/${default_branch}
        fi
    fi
    
    cd - > /dev/null
}

# Build and push Docker image
build_and_push() {
    local repo_name=$1
    local repo_dir="${PARENT_DIR}/${repo_name}"
    
    print_message $BLUE "\n=== Processing ${repo_name} ==="
    
    # Check if directory exists
    if ! check_directory "$repo_dir"; then
        return 1
    fi
    
    # Setup branch
    setup_branch "$repo_dir" "$repo_name"
    
    # Create Dockerfile if it doesn't exist
    case "$repo_name" in
        "kaia-orderbook-dex-frontend")
            create_frontend_dockerfile "$repo_dir"
            ;;
        "kaia-orderbook-dex-backend")
            create_backend_dockerfile "$repo_dir"
            ;;
        "kaia-orderbook-dex-core")
            create_core_dockerfile "$repo_dir"
            ;;
    esac
    
    # Build Docker image
    print_message $BLUE "Building Docker image for ${repo_name}..."
    cd "$repo_dir"
    
    local image_name="${REGISTRY_URL}/${repo_name}:${TAG}"
    docker build -t "${image_name}" .
    
    if [ $? -eq 0 ]; then
        print_message $GREEN "✓ Docker image built successfully"
        
        # Push to Artifact Registry
        print_message $BLUE "Pushing image to Artifact Registry..."
        docker push "${image_name}"
        
        if [ $? -eq 0 ]; then
            print_message $GREEN "✓ Image pushed successfully: ${image_name}"
            
            # Commit Dockerfile if it was created
            if [ -n "$(git status --porcelain Dockerfile)" ]; then
                print_message $YELLOW "Committing Dockerfile..."
                git add Dockerfile
                git commit -m "Add Dockerfile for ${TAG} deployment"
                git push origin ${BRANCH_NAME}
            fi
        else
            print_message $RED "✗ Failed to push image"
            return 1
        fi
    else
        print_message $RED "✗ Failed to build Docker image"
        return 1
    fi
    
    cd - > /dev/null
}

# Create Dockerfile for frontend
create_frontend_dockerfile() {
    local repo_dir=$1
    local dockerfile="${repo_dir}/Dockerfile"
    
    if [ ! -f "$dockerfile" ]; then
        print_message $YELLOW "Creating Dockerfile for frontend..."
        cat > "$dockerfile" << 'EOF'
# Build stage
FROM node:20-alpine as builder

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Runtime stage
FROM nginx:alpine

# Copy built files
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration if exists
COPY nginx.conf /etc/nginx/conf.d/default.conf 2>/dev/null || :

# Add a simple nginx config if none exists
RUN if [ ! -f /etc/nginx/conf.d/default.conf ]; then \
    echo 'server { \
        listen 80; \
        server_name _; \
        root /usr/share/nginx/html; \
        index index.html; \
        location / { \
            try_files $uri $uri/ /index.html; \
        } \
        location /health { \
            access_log off; \
            return 200 "healthy\n"; \
            add_header Content-Type text/plain; \
        } \
    }' > /etc/nginx/conf.d/default.conf; \
    fi

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF
        print_message $GREEN "✓ Created Dockerfile for frontend"
    fi
}

# Create Dockerfile for backend
create_backend_dockerfile() {
    local repo_dir=$1
    local dockerfile="${repo_dir}/Dockerfile"
    
    if [ ! -f "$dockerfile" ]; then
        print_message $YELLOW "Creating multi-stage Dockerfile for backend..."
        
        # Check which Dockerfile.* exists to determine the structure
        if [ -f "${repo_dir}/Dockerfile.api" ] || [ -f "${repo_dir}/Dockerfile.event" ]; then
            # Use existing Dockerfile.api as base
            if [ -f "${repo_dir}/Dockerfile.api" ]; then
                cp "${repo_dir}/Dockerfile.api" "$dockerfile"
                print_message $GREEN "✓ Created Dockerfile from existing Dockerfile.api"
            else
                print_message $RED "✗ Dockerfile.api not found, please create it manually"
            fi
        else
            # Create a generic Go Dockerfile
            cat > "$dockerfile" << 'EOF'
# Build stage
FROM golang:1.23-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git make gcc musl-dev

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o api ./cmd/api

# Runtime stage
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata

# Create non-root user
RUN adduser -D -g '' appuser

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/api .

# Change ownership
RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8080

CMD ["./api"]
EOF
            print_message $GREEN "✓ Created generic Dockerfile for backend"
        fi
    fi
}

# Create Dockerfile for core (Nitro node)
create_core_dockerfile() {
    local repo_dir=$1
    local dockerfile="${repo_dir}/Dockerfile"
    
    # Check if Dockerfile already exists in the repo
    if [ -f "$dockerfile" ]; then
        print_message $YELLOW "Dockerfile already exists for core, using existing one"
    else
        print_message $YELLOW "Creating Dockerfile for core..."
        # Try to use the nitro-node-slim target from the main Dockerfile
        cat > "$dockerfile" << 'EOF'
# This Dockerfile builds the Nitro node
# The repository already has a comprehensive Dockerfile
# We'll use the slim version for deployment

# Copy from the existing Dockerfile in the repository
# and use the nitro-node-slim target
FROM nitro-node-slim

# The existing Dockerfile already sets up everything needed
# including the entrypoint and user configuration
EOF
        print_message $GREEN "✓ Created Dockerfile reference for core"
        print_message $YELLOW "Note: This references the existing Dockerfile in the repository"
    fi
}

# Main execution
main() {
    print_message $GREEN "=== Docker Build and Push Script ==="
    print_message $BLUE "Project: ${GCP_PROJECT}"
    print_message $BLUE "Region: ${GCP_REGION}"
    print_message $BLUE "Registry: ${REGISTRY_URL}"
    print_message $BLUE "Tag: ${TAG}"
    print_message $BLUE "Branch: ${BRANCH_NAME}"
    echo
    
    # Authenticate with GCP
    authenticate_gcloud
    
    # Process each repository
    local failed=0
    for repo in "${REPOS[@]}"; do
        if ! build_and_push "$repo"; then
            failed=$((failed + 1))
        fi
    done
    
    # Summary
    echo
    print_message $GREEN "=== Summary ==="
    local total=${#REPOS[@]}
    local succeeded=$((total - failed))
    print_message $GREEN "Successfully processed: ${succeeded}/${total} repositories"
    
    if [ $failed -gt 0 ]; then
        print_message $RED "Failed: ${failed} repositories"
        exit 1
    else
        print_message $GREEN "All repositories processed successfully!"
        echo
        print_message $BLUE "Images pushed:"
        for repo in "${REPOS[@]}"; do
            echo "  - ${REGISTRY_URL}/${repo}:${TAG}"
        done
    fi
}

# Run main function
main "$@"