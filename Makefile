# Makefile for Kaia Orderbook DEX Docker Operations

.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Docker Registry Configuration
GCP_PROJECT := orderbook-dex-dev
GCP_REGION := asia-northeast3
REGISTRY_URL := $(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT)/dev-docker-registry
TAG ?= dev

# Docker Authentication
.PHONY: docker-auth
docker-auth: ## Authenticate Docker with Artifact Registry
	@echo "🔐 Authenticating Docker with Artifact Registry..."
	@gcloud auth configure-docker $(GCP_REGION)-docker.pkg.dev --quiet
	@echo "✅ Docker authenticated successfully"

# Build and Push All
.PHONY: docker-push-all
docker-push-all: ## Build and push all Docker images
	@echo "🚀 Building and pushing all Docker images..."
	@./scripts/build-and-push-docker.sh

# Individual Build and Push
.PHONY: docker-push-frontend
docker-push-frontend: docker-auth ## Build and push frontend Docker image
	@echo "🎨 Building and pushing frontend..."
	@./scripts/docker-push-single.sh frontend $(TAG)

.PHONY: docker-push-backend
docker-push-backend: docker-auth ## Build and push backend Docker image
	@echo "⚙️  Building and pushing backend..."
	@./scripts/docker-push-single.sh backend $(TAG)

.PHONY: docker-push-core
docker-push-core: docker-auth ## Build and push core Docker image
	@echo "🔧 Building and pushing core..."
	@./scripts/docker-push-single.sh core $(TAG)

# List Images
.PHONY: docker-list
docker-list: ## List images in Artifact Registry
	@echo "📋 Listing images in Artifact Registry..."
	@gcloud artifacts docker images list $(REGISTRY_URL) --include-tags

# Clean Local Images
.PHONY: docker-clean
docker-clean: ## Remove local Docker images
	@echo "🧹 Cleaning local Docker images..."
	@docker rmi $(REGISTRY_URL)/kaia-orderbook-dex-frontend:$(TAG) 2>/dev/null || true
	@docker rmi $(REGISTRY_URL)/kaia-orderbook-dex-backend:$(TAG) 2>/dev/null || true
	@docker rmi $(REGISTRY_URL)/kaia-orderbook-dex-core:$(TAG) 2>/dev/null || true
	@echo "✅ Local images cleaned"

# Pull Images
.PHONY: docker-pull-all
docker-pull-all: docker-auth ## Pull all images from Artifact Registry
	@echo "⬇️  Pulling all images..."
	@docker pull $(REGISTRY_URL)/kaia-orderbook-dex-frontend:$(TAG)
	@docker pull $(REGISTRY_URL)/kaia-orderbook-dex-backend:$(TAG)
	@docker pull $(REGISTRY_URL)/kaia-orderbook-dex-core:$(TAG)

# Verify Images
.PHONY: docker-verify
docker-verify: ## Verify Docker images exist in registry
	@echo "🔍 Verifying images in Artifact Registry..."
	@gcloud artifacts docker images describe \
		$(REGISTRY_URL)/kaia-orderbook-dex-frontend:$(TAG) \
		--project=$(GCP_PROJECT) >/dev/null 2>&1 && echo "✅ frontend:$(TAG) exists" || echo "❌ frontend:$(TAG) not found"
	@gcloud artifacts docker images describe \
		$(REGISTRY_URL)/kaia-orderbook-dex-backend:$(TAG) \
		--project=$(GCP_PROJECT) >/dev/null 2>&1 && echo "✅ backend:$(TAG) exists" || echo "❌ backend:$(TAG) not found"
	@gcloud artifacts docker images describe \
		$(REGISTRY_URL)/kaia-orderbook-dex-core:$(TAG) \
		--project=$(GCP_PROJECT) >/dev/null 2>&1 && echo "✅ core:$(TAG) exists" || echo "❌ core:$(TAG) not found"

# Update Helm values with image tags
.PHONY: helm-update-images
helm-update-images: ## Update Helm charts with latest image tags
	@echo "📝 Updating Helm charts with image registry and tag..."
	@echo "Registry: $(REGISTRY_URL)"
	@echo "Tag: $(TAG)"
	@# Update frontend values.yaml
	@sed -i.bak 's|repository:.*|repository: $(REGISTRY_URL)/kaia-orderbook-dex-frontend|' charts/kaia-orderbook-dex-frontend/values.yaml
	@sed -i.bak 's|tag:.*|tag: "$(TAG)"|' charts/kaia-orderbook-dex-frontend/values.yaml
	@# Update backend values.yaml
	@sed -i.bak 's|repository: kaia-orderbook-api|repository: $(REGISTRY_URL)/kaia-orderbook-dex-backend|' charts/kaia-orderbook-dex-backend/values.yaml
	@sed -i.bak 's|repository: kaia-orderbook-event|repository: $(REGISTRY_URL)/kaia-orderbook-dex-backend|' charts/kaia-orderbook-dex-backend/values.yaml
	@sed -i.bak 's|tag:.*|tag: "$(TAG)"|' charts/kaia-orderbook-dex-backend/values.yaml
	@# Update core values.yaml
	@sed -i.bak 's|repository: kaia-orderbook-nitro-node|repository: $(REGISTRY_URL)/kaia-orderbook-dex-core|' charts/kaia-orderbook-dex-core/values.yaml
	@sed -i.bak 's|tag:.*|tag: "$(TAG)"|' charts/kaia-orderbook-dex-core/values.yaml
	@# Clean up backup files
	@rm -f charts/*/values.yaml.bak
	@echo "✅ Helm charts updated"

# Show Image URLs
.PHONY: docker-urls
docker-urls: ## Show Docker image URLs
	@echo "🔗 Docker Image URLs:"
	@echo "  Frontend: $(REGISTRY_URL)/kaia-orderbook-dex-frontend:$(TAG)"
	@echo "  Backend:  $(REGISTRY_URL)/kaia-orderbook-dex-backend:$(TAG)"
	@echo "  Core:     $(REGISTRY_URL)/kaia-orderbook-dex-core:$(TAG)"

# Quick Deploy (build, push, and update helm)
.PHONY: deploy-images
deploy-images: docker-push-all helm-update-images ## Build, push all images and update Helm charts
	@echo "✅ All images deployed and Helm charts updated!"
	@echo ""
	@$(MAKE) docker-urls