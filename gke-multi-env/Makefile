# GKE Multi-Environment Infrastructure Makefile
# Usage: make [target] ENV=[dev|prod]

.PHONY: help setup init-dev init-prod plan-dev plan-prod apply-dev apply-prod destroy-dev destroy-prod
.PHONY: status-dev status-prod kubectl-dev kubectl-prod
.PHONY: db-status-dev db-status-prod redis-status-dev redis-status-prod
.PHONY: argocd-password-dev argocd-password-prod argocd-port-forward-dev argocd-port-forward-prod
.PHONY: dns-records-dev dns-records-prod ingress-ip-dev ingress-ip-prod
.PHONY: logs-dev logs-prod clean-dev clean-prod dev-workflow prod-workflow
.PHONY: validate-dev validate-prod check-requirements
.PHONY: secrets-list-dev secrets-list-prod secrets-get-dev secrets-get-prod app-config-dev app-config-prod
.PHONY: k8s-db-proxy-dev k8s-db-proxy-prod k8s-db-deploy-dev k8s-db-deploy-prod k8s-db-delete-dev k8s-db-delete-prod

# Default environment
ENV ?= dev

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
BLUE := \033[0;34m
NC := \033[0m

# Helper function to print colored output
define log_info
	echo "$(BLUE)[INFO]$(NC) $(1)"
endef

define log_success
	echo "$(GREEN)[SUCCESS]$(NC) $(1)"
endef

define log_warning
	echo "$(YELLOW)[WARNING]$(NC) $(1)"
endef

define log_error
	echo "$(RED)[ERROR]$(NC) $(1)"
endef

# Default target
help: ## Show this help message
	echo "$(GREEN)GKE Multi-Environment Infrastructure Makefile$(NC)"
	echo ""
	echo "$(YELLOW)Usage:$(NC)"
	echo "  make [target] ENV=[dev|prod]"
	echo ""
	echo "$(YELLOW)Environment Setup:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E '(setup|init|check)' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}'
	echo ""
	echo "$(YELLOW)Development Environment:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E 'dev' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}'
	echo ""
	echo "$(YELLOW)Production Environment:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -E 'prod' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}'
	echo ""
	echo "$(YELLOW)Management Commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -vE '(dev|prod|setup|init|check)' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}'
	echo ""
	echo "$(YELLOW)Examples:$(NC)"
	echo "  make setup                    # Install dependencies and check requirements"
	echo "  make dev-workflow            # Complete dev environment setup"
	echo "  make init-dev                # Initialize dev environment"
	echo "  make apply-dev               # Deploy dev environment"
	echo "  make status-dev              # Check dev environment status"
	echo "  make argocd-password-dev     # Get ArgoCD admin password for dev"
	echo ""

# Requirements and Setup
check-requirements: ## Check if all required tools are installed
	$(call log_info,"Checking requirements...")
	@command -v terraform >/dev/null 2>&1 || ($(call log_error,"Terraform not found. Please install Terraform.") && exit 1)
	@command -v gcloud >/dev/null 2>&1 || ($(call log_error,"gcloud CLI not found. Please install Google Cloud SDK.") && exit 1)
	@command -v kubectl >/dev/null 2>&1 || ($(call log_error,"kubectl not found. Please install kubectl.") && exit 1)
	@command -v helm >/dev/null 2>&1 || ($(call log_error,"helm not found. Please install Helm.") && exit 1)
	@command -v jq >/dev/null 2>&1 || ($(call log_error,"jq not found. Please install jq.") && exit 1)
	$(call log_success,"All required tools are installed")

setup: check-requirements ## Install dependencies and setup environment
	$(call log_info,"Setting up environment...")
	@gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "." || ($(call log_error,"No active gcloud authentication. Run 'gcloud auth login'") && exit 1)
	$(call log_success,"Environment setup completed")

# Environment-specific initialization
init-dev: check-requirements ## Initialize Terraform for dev environment
	$(call log_info,"Initializing dev environment...")
	@./scripts/deploy.sh dev init
	$(call log_success,"Dev environment initialized")

init-prod: check-requirements ## Initialize Terraform for prod environment
	$(call log_info,"Initializing prod environment...")
	@./scripts/deploy.sh prod init
	$(call log_success,"Prod environment initialized")

# Planning
plan-dev: ## Plan Terraform changes for dev environment
	$(call log_info,"Planning dev environment changes...")
	@./scripts/deploy.sh dev plan

plan-prod: ## Plan Terraform changes for prod environment
	$(call log_info,"Planning prod environment changes...")
	@./scripts/deploy.sh prod plan

# Validation
validate-dev: ## Validate Terraform configuration for dev environment
	$(call log_info,"Validating dev environment configuration...")
	@cd terraform && terraform workspace select dev && terraform validate
	$(call log_success,"Dev environment configuration is valid")

validate-prod: ## Validate Terraform configuration for prod environment
	$(call log_info,"Validating prod environment configuration...")
	@cd terraform && terraform workspace select prod && terraform validate
	$(call log_success,"Prod environment configuration is valid")

# Deployment
apply-dev: ## Deploy dev environment
	$(call log_info,"Deploying dev environment...")
	@./scripts/deploy.sh dev apply
	$(call log_success,"Dev environment deployed")

apply-prod: ## Deploy prod environment
	$(call log_warning,"Deploying PRODUCTION environment...")
	@./scripts/deploy.sh prod apply
	$(call log_success,"Prod environment deployed")

# Destruction
destroy-dev: ## Destroy dev environment
	$(call log_warning,"Destroying dev environment...")
	@./scripts/deploy.sh dev destroy

destroy-prod: ## Destroy prod environment
	$(call log_error,"Destroying PRODUCTION environment...")
	@./scripts/deploy.sh prod destroy

# Status and Information
status-dev: ## Show dev environment status
	@./scripts/deploy.sh dev status

status-prod: ## Show prod environment status
	@./scripts/deploy.sh prod status

# Kubectl configuration
kubectl-dev: ## Configure kubectl for dev environment
	$(call log_info,"Configuring kubectl for dev environment...")
	@cd terraform && terraform workspace select dev && eval "$$(terraform output -raw kubectl_config_command)"
	$(call log_success,"kubectl configured for dev environment")

kubectl-prod: ## Configure kubectl for prod environment
	$(call log_info,"Configuring kubectl for prod environment...")
	@cd terraform && terraform workspace select prod && eval "$$(terraform output -raw kubectl_config_command)"
	$(call log_success,"kubectl configured for prod environment")

# Database management
db-status-dev: ## Check database status for dev environment
	$(call log_info,"Checking dev database status...")
	@cd terraform && terraform workspace select dev && \
	DB_IP=$$(terraform output -raw database_private_ip 2>/dev/null || echo "Not deployed") && \
	echo "Database IP: $$DB_IP" && \
	if [ "$$DB_IP" != "Not deployed" ]; then \
		echo "Database Connection Name: $$(terraform output -raw database_connection_name)"; \
		kubectl get secret mysql-credentials -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"' 2>/dev/null || echo "Database secret not found"; \
	fi

db-status-prod: ## Check database status for prod environment
	$(call log_info,"Checking prod database status...")
	@cd terraform && terraform workspace select prod && \
	DB_IP=$$(terraform output -raw database_private_ip 2>/dev/null || echo "Not deployed") && \
	echo "Database IP: $$DB_IP" && \
	if [ "$$DB_IP" != "Not deployed" ]; then \
		echo "Database Connection Name: $$(terraform output -raw database_connection_name)"; \
		kubectl get secret mysql-credentials -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"' 2>/dev/null || echo "Database secret not found"; \
	fi

# Redis management
redis-status-dev: ## Check Redis status for dev environment
	$(call log_info,"Checking dev Redis status...")
	@cd terraform && terraform workspace select dev && \
	REDIS_HOST=$$(terraform output -raw redis_host 2>/dev/null || echo "Not deployed") && \
	echo "Redis Host: $$REDIS_HOST" && \
	if [ "$$REDIS_HOST" != "Not deployed" ]; then \
		echo "Redis Port: $$(terraform output -raw redis_port)"; \
		kubectl get secret redis-credentials -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"' 2>/dev/null || echo "Redis secret not found"; \
	fi

redis-status-prod: ## Check Redis status for prod environment
	$(call log_info,"Checking prod Redis status...")
	@cd terraform && terraform workspace select prod && \
	REDIS_HOST=$$(terraform output -raw redis_host 2>/dev/null || echo "Not deployed") && \
	echo "Redis Host: $$REDIS_HOST" && \
	if [ "$$REDIS_HOST" != "Not deployed" ]; then \
		echo "Redis Port: $$(terraform output -raw redis_port)"; \
		kubectl get secret redis-credentials -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"' 2>/dev/null || echo "Redis secret not found"; \
	fi

# ArgoCD management
argocd-password-dev: kubectl-dev ## Get ArgoCD admin password for dev environment
	$(call log_info,"Getting ArgoCD admin password for dev...")
	@kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo ""
	echo "ArgoCD URL: $$(cd terraform && terraform workspace select dev && terraform output -raw argocd_url)"

argocd-password-prod: kubectl-prod ## Get ArgoCD admin password for prod environment
	$(call log_info,"Getting ArgoCD admin password for prod...")
	@kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo ""
	echo "ArgoCD URL: $$(cd terraform && terraform workspace select prod && terraform output -raw argocd_url)"

argocd-port-forward-dev: kubectl-dev ## Port forward to ArgoCD server for dev environment
	$(call log_info,"Starting port forward to ArgoCD server (dev)...")
	echo "ArgoCD will be available at: http://localhost:8080"
	echo "Username: admin"
	echo "Password: $$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)"
	@kubectl port-forward svc/argocd-server -n argocd 8080:443

argocd-port-forward-prod: kubectl-prod ## Port forward to ArgoCD server for prod environment
	$(call log_info,"Starting port forward to ArgoCD server (prod)...")
	echo "ArgoCD will be available at: http://localhost:8080"
	echo "Username: admin"
	echo "Password: $$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)"
	@kubectl port-forward svc/argocd-server -n argocd 8080:443

# DNS and Ingress management
dns-records-dev: ## Show DNS records for dev environment
	$(call log_info,"Checking DNS records for dev environment...")
	@cd terraform && terraform workspace select dev && \
	DOMAIN=$$(terraform output -raw argocd_url | sed 's|https://||') && \
	echo "Checking DNS for: $$DOMAIN" && \
	nslookup $$DOMAIN || echo "DNS record not found"

dns-records-prod: ## Show DNS records for prod environment
	$(call log_info,"Checking DNS records for prod environment...")
	@cd terraform && terraform workspace select prod && \
	DOMAIN=$$(terraform output -raw argocd_url | sed 's|https://||') && \
	echo "Checking DNS for: $$DOMAIN" && \
	nslookup $$DOMAIN || echo "DNS record not found"

ingress-ip-dev: ## Get NGINX Ingress IP for dev environment
	$(call log_info,"Getting NGINX Ingress IP for dev...")
	@cd terraform && terraform workspace select dev && \
	terraform output -raw nginx_ingress_ip 2>/dev/null || echo "Ingress not deployed"

ingress-ip-prod: ## Get NGINX Ingress IP for prod environment
	$(call log_info,"Getting NGINX Ingress IP for prod...")
	@cd terraform && terraform workspace select prod && \
	terraform output -raw nginx_ingress_ip 2>/dev/null || echo "Ingress not deployed"

# Logging and debugging
logs-dev: kubectl-dev ## View logs for dev environment services
	$(call log_info,"Available namespaces:")
	@kubectl get namespaces
	echo ""
	$(call log_info,"ArgoCD pods:")
	@kubectl get pods -n argocd
	echo ""
	$(call log_info,"NGINX Ingress pods:")
	@kubectl get pods -n nginx-ingress

logs-prod: kubectl-prod ## View logs for prod environment services
	$(call log_info,"Available namespaces:")
	@kubectl get namespaces
	echo ""
	$(call log_info,"ArgoCD pods:")
	@kubectl get pods -n argocd
	echo ""
	$(call log_info,"NGINX Ingress pods:")
	@kubectl get pods -n nginx-ingress

# Cleanup
clean-dev: ## Clean up dev environment temporary files
	$(call log_info,"Cleaning up dev environment temporary files...")
	@rm -f terraform/dev.tfplan
	@rm -f terraform/.terraform.lock.hcl
	$(call log_success,"Dev environment cleaned up")

clean-prod: ## Clean up prod environment temporary files
	$(call log_info,"Cleaning up prod environment temporary files...")
	@rm -f terraform/prod.tfplan
	@rm -f terraform/.terraform.lock.hcl
	$(call log_success,"Prod environment cleaned up")

# Workflow targets
dev-workflow: setup init-dev plan-dev ## Complete dev environment workflow (setup, init, plan)
	$(call log_info,"Dev environment workflow completed")
	$(call log_info,"Next steps:")
	echo "  1. Review the plan output above"
	echo "  2. Run 'make apply-dev' to deploy"
	echo "  3. Run 'make argocd-password-dev' to get ArgoCD credentials"

prod-workflow: setup init-prod plan-prod ## Complete prod environment workflow (setup, init, plan)
	$(call log_info,"Prod environment workflow completed")
	$(call log_warning,"Next steps:")
	echo "  1. Review the plan output above carefully"
	echo "  2. Run 'make apply-prod' to deploy to PRODUCTION"
	echo "  3. Run 'make argocd-password-prod' to get ArgoCD credentials"

# Generic targets that use ENV variable
init: check-requirements ## Initialize Terraform for specified environment (ENV=dev|prod)
	@if [ "$(ENV)" = "dev" ]; then $(MAKE) init-dev; elif [ "$(ENV)" = "prod" ]; then $(MAKE) init-prod; else $(call log_error,"Invalid ENV value. Use ENV=dev or ENV=prod"); exit 1; fi

plan: ## Plan Terraform changes for specified environment (ENV=dev|prod)
	@if [ "$(ENV)" = "dev" ]; then $(MAKE) plan-dev; elif [ "$(ENV)" = "prod" ]; then $(MAKE) plan-prod; else $(call log_error,"Invalid ENV value. Use ENV=dev or ENV=prod"); exit 1; fi

apply: ## Deploy specified environment (ENV=dev|prod)
	@if [ "$(ENV)" = "dev" ]; then $(MAKE) apply-dev; elif [ "$(ENV)" = "prod" ]; then $(MAKE) apply-prod; else $(call log_error,"Invalid ENV value. Use ENV=dev or ENV=prod"); exit 1; fi

destroy: ## Destroy specified environment (ENV=dev|prod)
	@if [ "$(ENV)" = "dev" ]; then $(MAKE) destroy-dev; elif [ "$(ENV)" = "prod" ]; then $(MAKE) destroy-prod; else $(call log_error,"Invalid ENV value. Use ENV=dev or ENV=prod"); exit 1; fi

status: ## Show status for specified environment (ENV=dev|prod)
	@if [ "$(ENV)" = "dev" ]; then $(MAKE) status-dev; elif [ "$(ENV)" = "prod" ]; then $(MAKE) status-prod; else $(call log_error,"Invalid ENV value. Use ENV=dev or ENV=prod"); exit 1; fi

# Secret Manager commands
secrets-list-dev: ## List all secrets in Secret Manager for dev environment
	$(call log_info,"Listing Secret Manager secrets for dev environment...")
	@cd terraform && terraform workspace select dev && \
	PROJECT_ID=$$(terraform output -raw cluster_name | sed 's/-gke-cluster//') && \
	gcloud secrets list --project=$$PROJECT_ID --filter="labels.environment=dev" --format="table(name,labels.type:label=TYPE,createTime:label=CREATED)"

secrets-list-prod: ## List all secrets in Secret Manager for prod environment
	$(call log_info,"Listing Secret Manager secrets for prod environment...")
	@cd terraform && terraform workspace select prod && \
	PROJECT_ID=$$(terraform output -raw cluster_name | sed 's/-gke-cluster//') && \
	gcloud secrets list --project=$$PROJECT_ID --filter="labels.environment=prod" --format="table(name,labels.type:label=TYPE,createTime:label=CREATED)"

secrets-get-dev: ## Get a secret value from Secret Manager for dev (usage: make secrets-get-dev SECRET=secret-name)
	@if [ -z "$(SECRET)" ]; then \
		$(call log_error,"SECRET parameter is required. Usage: make secrets-get-dev SECRET=secret-name"); \
		exit 1; \
	fi
	$(call log_info,"Getting secret '$(SECRET)' from dev environment...")
	@cd terraform && terraform workspace select dev && \
	PROJECT_ID=$$(terraform output -raw cluster_name | sed 's/-gke-cluster//') && \
	gcloud secrets versions access latest --secret="dev-$(SECRET)" --project=$$PROJECT_ID

secrets-get-prod: ## Get a secret value from Secret Manager for prod (usage: make secrets-get-prod SECRET=secret-name)
	@if [ -z "$(SECRET)" ]; then \
		$(call log_error,"SECRET parameter is required. Usage: make secrets-get-prod SECRET=secret-name"); \
		exit 1; \
	fi
	$(call log_info,"Getting secret '$(SECRET)' from prod environment...")
	@cd terraform && terraform workspace select prod && \
	PROJECT_ID=$$(terraform output -raw cluster_name | sed 's/-gke-cluster//') && \
	gcloud secrets versions access latest --secret="prod-$(SECRET)" --project=$$PROJECT_ID

app-config-dev: ## Get application configuration JSON from Secret Manager for dev environment
	$(call log_info,"Getting application configuration for dev environment...")
	@cd terraform && terraform workspace select dev && \
	terraform output -raw app_config_secret_command | bash

app-config-prod: ## Get application configuration JSON from Secret Manager for prod environment
	$(call log_info,"Getting application configuration for prod environment...")
	@cd terraform && terraform workspace select prod && \
	terraform output -raw app_config_secret_command | bash

# Kubernetes Cloud SQL Proxy commands
k8s-db-proxy-dev: kubectl-dev ## Connect to dev database via Kubernetes Cloud SQL Proxy (port 3306)
	$(call log_info,"Connecting to dev database via Kubernetes...")
	@./scripts/k8s-cloud-sql-proxy.sh dev 3306 connect

k8s-db-proxy-prod: kubectl-prod ## Connect to prod database via Kubernetes Cloud SQL Proxy (port 3307)
	$(call log_info,"Connecting to prod database via Kubernetes...")
	@./scripts/k8s-cloud-sql-proxy.sh prod 3307 connect

k8s-db-deploy-dev: kubectl-dev ## Deploy Cloud SQL Proxy to dev Kubernetes cluster
	$(call log_info,"Deploying Cloud SQL Proxy to dev cluster...")
	@./scripts/k8s-cloud-sql-proxy.sh dev 3306 deploy

k8s-db-deploy-prod: kubectl-prod ## Deploy Cloud SQL Proxy to prod Kubernetes cluster
	$(call log_info,"Deploying Cloud SQL Proxy to prod cluster...")
	@./scripts/k8s-cloud-sql-proxy.sh prod 3307 deploy

k8s-db-delete-dev: kubectl-dev ## Delete Cloud SQL Proxy from dev Kubernetes cluster
	$(call log_info,"Deleting Cloud SQL Proxy from dev cluster...")
	@./scripts/k8s-cloud-sql-proxy.sh dev 3306 delete

k8s-db-delete-prod: kubectl-prod ## Delete Cloud SQL Proxy from prod Kubernetes cluster
	$(call log_info,"Deleting Cloud SQL Proxy from prod cluster...")
	@./scripts/k8s-cloud-sql-proxy.sh prod 3307 delete
