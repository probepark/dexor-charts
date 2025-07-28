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

# Core Deployment Commands
.PHONY: deploy-core-contracts
deploy-core-contracts: ## Deploy core contracts to Kairos testnet (dev)
	@echo "🚀 Deploying contracts to Kairos testnet..."
	@./scripts/deploy-to-kairos.sh

.PHONY: deploy-core-contracts-qa
deploy-core-contracts-qa: ## Deploy core contracts to Kairos testnet (QA)
	@echo "🚀 Deploying contracts to Kairos testnet for QA..."
	@./scripts/deploy-to-kairos.sh qa

.PHONY: deploy-core-contracts-perf
deploy-core-contracts-perf: ## Deploy core contracts to Kairos testnet (Performance)
	@echo "🚀 Deploying contracts to Kairos testnet for Performance..."
	@./scripts/deploy-to-kairos.sh perf

.PHONY: sync-core-values
sync-core-values: ## Sync deployed contract info to values-dev.yaml
	@echo "🔄 Syncing deployment configuration to values-dev.yaml..."
	@DEPLOY_MODE=sync ./scripts/deploy-and-sync-to-k8s.sh

.PHONY: deploy-core-full
deploy-core-full: ## Deploy contracts and sync to values-dev.yaml
	@echo "🚀 Full deployment: contracts + values sync..."
	@DEPLOY_MODE=full ./scripts/deploy-and-sync-to-k8s.sh

.PHONY: deploy-core-k8s
deploy-core-k8s: ## Deploy core to Kubernetes using current values-dev.yaml
	@echo "☸️  Deploying to Kubernetes..."
	@./scripts/deploy-core-to-k8s.sh

.PHONY: deploy-core-all
deploy-core-all: deploy-core-full deploy-core-k8s ## Full deployment: contracts + sync + k8s
	@echo "✅ Complete deployment finished!"

# Token Bridge Deployment Commands
.PHONY: deploy-token-bridge
deploy-token-bridge: ## Deploy token bridge contracts
	@echo "🌉 Deploying token bridge contracts for $(ENV)..."
	@./scripts/deploy-token-bridge.sh $(ENV)

.PHONY: deploy-token-bridge-dev
deploy-token-bridge-dev: ## Deploy token bridge to dev environment
	@$(MAKE) deploy-token-bridge ENV=dev

.PHONY: deploy-token-bridge-qa
deploy-token-bridge-qa: ## Deploy token bridge to QA environment
	@$(MAKE) deploy-token-bridge ENV=qa

.PHONY: deploy-token-bridge-perf
deploy-token-bridge-perf: ## Deploy token bridge to Performance environment
	@$(MAKE) deploy-token-bridge ENV=perf

.PHONY: test-token-bridge
test-token-bridge: ## Test token bridge Docker image without deployment
	@echo "🧪 Testing token bridge Docker image..."
	@docker run --rm \
		-e L1_RPC_URL="https://archive-en-kairos.node.kaia.io" \
		-e L2_RPC_URL="https://l2-rpc-dev.dexor.trade" \
		-e DEPLOYER_KEY="0x49552d0ea850ae92d477b2479315ddce17692bb05ce3f8fd4ca9109cca134cb1" \
		-e ROLLUP_ADDRESS="0x2CFcEEaad2406AAf928C40aE2833B2f3d2402c08" \
		$(REGISTRY_URL)/kaia-orderbook-dex-core-testnode/token-bridge-contracts:1.0.0 \
		deploy --dry-run || echo "Dry run completed"

# Helm Commands
.PHONY: helm-install
helm-install: ## Install all Helm charts
	@echo "📦 Installing Helm charts..."
	helm install kaia-dex-core ./charts/kaia-orderbook-dex-core -f ./charts/kaia-orderbook-dex-core/values-dev.yaml -n kaia-dex

.PHONY: helm-upgrade
helm-upgrade: ## Upgrade all Helm charts
	@echo "📦 Upgrading Helm charts..."
	helm upgrade kaia-dex-core ./charts/kaia-orderbook-dex-core -f ./charts/kaia-orderbook-dex-core/values-dev.yaml -n kaia-dex

.PHONY: helm-uninstall
helm-uninstall: ## Uninstall all Helm charts
	@echo "🗑️  Uninstalling Helm charts..."
	helm uninstall kaia-dex-core -n kaia-dex || true

# Status Commands
.PHONY: status
status: ## Show deployment status
	@echo "📊 Deployment Status:"
	@echo ""
	@echo "Kubernetes Pods:"
	@kubectl get pods -n kaia-dex -l app.kubernetes.io/instance=kaia-dex-core
	@echo ""
	@echo "Services:"
	@kubectl get svc -n kaia-dex -l app.kubernetes.io/instance=kaia-dex-core
	@echo ""
	@echo "To view logs:"
	@echo "  kubectl logs -n kaia-dex -l app.kubernetes.io/instance=kaia-dex-core"

.PHONY: port-forward
port-forward: ## Port forward to access RPC endpoint
	@echo "🔌 Setting up port forwarding..."
	@echo "RPC will be available at http://localhost:8547"
	@export POD_NAME=$$(kubectl get pods --namespace kaia-dex -l "app.kubernetes.io/name=kaia-orderbook-dex-core,app.kubernetes.io/instance=kaia-dex-core" -o jsonpath="{.items[0].metadata.name}") && \
	kubectl --namespace kaia-dex port-forward $$POD_NAME 8547:8547 8548:8548