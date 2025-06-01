#!/bin/bash

# GKE Multi-Environment Deployment Script
# Usage: ./scripts/deploy.sh [dev|prod] [init|plan|apply|destroy|status]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 [ENVIRONMENT] [ACTION]"
    echo ""
    echo "ENVIRONMENT:"
    echo "  dev     - Development environment"
    echo "  prod    - Production environment"
    echo ""
    echo "ACTION:"
    echo "  init    - Initialize Terraform"
    echo "  plan    - Plan Terraform changes"
    echo "  apply   - Apply Terraform changes"
    echo "  destroy - Destroy infrastructure"
    echo "  status  - Show infrastructure status"
    echo ""
    echo "Examples:"
    echo "  $0 dev init"
    echo "  $0 prod plan"
    echo "  $0 dev apply"
}

check_requirements() {
    local missing_tools=()

    # Check for required tools
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v gcloud >/dev/null 2>&1 || missing_tools+=("gcloud")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "No active gcloud authentication found."
        log_info "Please run 'gcloud auth login' to authenticate."
        exit 1
    fi
}

validate_environment() {
    local env=$1
    if [[ "$env" != "dev" && "$env" != "prod" ]]; then
        log_error "Invalid environment: $env"
        log_info "Environment must be either 'dev' or 'prod'"
        exit 1
    fi
}

setup_workspace() {
    local env=$1
    
    cd "$TERRAFORM_DIR"
    
    # Create workspace if it doesn't exist
    if ! terraform workspace list | grep -q "$env"; then
        log_info "Creating Terraform workspace: $env"
        terraform workspace new "$env"
    else
        log_info "Switching to Terraform workspace: $env"
        terraform workspace select "$env"
    fi
}

terraform_init() {
    local env=$1
    
    log_info "Initializing Terraform for $env environment..."
    
    cd "$TERRAFORM_DIR"
    terraform init
    
    setup_workspace "$env"
    
    log_success "Terraform initialized successfully for $env environment"
}

terraform_plan() {
    local env=$1
    local tfvars_file="$PROJECT_DIR/environments/$env/terraform.tfvars"
    
    if [[ ! -f "$tfvars_file" ]]; then
        log_error "Terraform variables file not found: $tfvars_file"
        exit 1
    fi
    
    log_info "Planning Terraform changes for $env environment..."
    
    cd "$TERRAFORM_DIR"
    setup_workspace "$env"
    
    terraform plan \
        -var-file="$tfvars_file" \
        -out="$env.tfplan"
    
    log_success "Terraform plan completed for $env environment"
    log_info "Plan saved to: $env.tfplan"
}

terraform_apply() {
    local env=$1
    local tfvars_file="$PROJECT_DIR/environments/$env/terraform.tfvars"
    local plan_file="$TERRAFORM_DIR/$env.tfplan"
    
    if [[ ! -f "$tfvars_file" ]]; then
        log_error "Terraform variables file not found: $tfvars_file"
        exit 1
    fi
    
    cd "$TERRAFORM_DIR"
    setup_workspace "$env"
    
    # Ask for confirmation
    if [[ "$env" == "prod" ]]; then
        log_warning "You are about to apply changes to the PRODUCTION environment!"
        echo -n "Are you sure you want to continue? (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            log_info "Deployment cancelled."
            exit 0
        fi
    fi
    
    log_info "Applying Terraform changes for $env environment..."
    
    # Use plan file if it exists, otherwise apply directly
    if [[ -f "$plan_file" ]]; then
        terraform apply "$plan_file"
        rm -f "$plan_file"
    else
        terraform apply \
            -var-file="$tfvars_file" \
            -auto-approve
    fi
    
    log_success "Terraform apply completed for $env environment"
    
    # Configure kubectl
    configure_kubectl "$env"
    
    # Show important outputs
    show_outputs "$env"
}

terraform_destroy() {
    local env=$1
    local tfvars_file="$PROJECT_DIR/environments/$env/terraform.tfvars"
    
    if [[ ! -f "$tfvars_file" ]]; then
        log_error "Terraform variables file not found: $tfvars_file"
        exit 1
    fi
    
    # Multiple confirmations for production
    if [[ "$env" == "prod" ]]; then
        log_warning "You are about to DESTROY the PRODUCTION environment!"
        log_warning "This action is IRREVERSIBLE and will delete all infrastructure!"
        echo -n "Type 'destroy-prod' to confirm: "
        read -r confirmation
        if [[ "$confirmation" != "destroy-prod" ]]; then
            log_info "Destruction cancelled."
            exit 0
        fi
        
        echo -n "Are you absolutely sure? (yes/no): "
        read -r final_confirmation
        if [[ "$final_confirmation" != "yes" ]]; then
            log_info "Destruction cancelled."
            exit 0
        fi
    else
        log_warning "You are about to destroy the $env environment!"
        echo -n "Are you sure you want to continue? (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            log_info "Destruction cancelled."
            exit 0
        fi
    fi
    
    log_info "Destroying Terraform infrastructure for $env environment..."
    
    cd "$TERRAFORM_DIR"
    setup_workspace "$env"
    
    terraform destroy \
        -var-file="$tfvars_file" \
        -auto-approve
    
    log_success "Terraform destroy completed for $env environment"
}

configure_kubectl() {
    local env=$1
    
    log_info "Configuring kubectl for $env environment..."
    
    cd "$TERRAFORM_DIR"
    
    # Get cluster credentials
    local project_id
    local region
    local cluster_name
    
    project_id=$(terraform output -raw project_id 2>/dev/null || echo "")
    region=$(terraform output -raw cluster_location 2>/dev/null || echo "")
    cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    
    if [[ -n "$project_id" && -n "$region" && -n "$cluster_name" ]]; then
        gcloud container clusters get-credentials "$cluster_name" \
            --region="$region" \
            --project="$project_id"
        
        log_success "kubectl configured for $env environment"
        
        # Test connection
        if kubectl cluster-info >/dev/null 2>&1; then
            log_success "Successfully connected to GKE cluster"
        else
            log_warning "Failed to connect to GKE cluster"
        fi
    else
        log_warning "Could not retrieve cluster information for kubectl configuration"
    fi
}

show_outputs() {
    local env=$1
    
    log_info "Important outputs for $env environment:"
    
    cd "$TERRAFORM_DIR"
    
    echo "----------------------------------------"
    echo "Cluster Information:"
    terraform output cluster_name 2>/dev/null || echo "  Cluster Name: Not available"
    terraform output cluster_location 2>/dev/null || echo "  Cluster Location: Not available"
    
    echo ""
    echo "Network Information:"
    terraform output vpc_name 2>/dev/null || echo "  VPC Name: Not available"
    terraform output subnet_name 2>/dev/null || echo "  Subnet Name: Not available"
    
    echo ""
    echo "Service URLs:"
    terraform output argocd_url 2>/dev/null || echo "  ArgoCD URL: Not available"
    terraform output nginx_ingress_ip 2>/dev/null || echo "  NGINX Ingress IP: Not available"
    
    echo ""
    echo "Database Information:"
    terraform output database_private_ip 2>/dev/null || echo "  Database IP: Not available"
    terraform output redis_host 2>/dev/null || echo "  Redis Host: Not available"
    
    echo ""
    echo "Kubectl Configuration:"
    terraform output kubectl_config_command 2>/dev/null || echo "  Command: Not available"
    echo "----------------------------------------"
}

show_status() {
    local env=$1
    
    log_info "Infrastructure status for $env environment:"
    
    cd "$TERRAFORM_DIR"
    setup_workspace "$env"
    
    # Check if state exists
    if ! terraform show >/dev/null 2>&1; then
        log_warning "No Terraform state found for $env environment"
        return
    fi
    
    echo "----------------------------------------"
    echo "Terraform Workspace: $(terraform workspace show)"
    echo "Terraform State:"
    terraform show -json | jq -r '.values.root_module.resources[] | select(.type | test("google_container_cluster|google_sql_database_instance|google_redis_instance")) | "\(.type): \(.values.name // .values.display_name // "unnamed")"' 2>/dev/null || echo "  Unable to parse state"
    
    # Show kubectl status if cluster exists
    if terraform output cluster_name >/dev/null 2>&1; then
        echo ""
        echo "Kubernetes Status:"
        if kubectl cluster-info >/dev/null 2>&1; then
            echo "  Cluster: Connected"
            echo "  Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
            echo "  Namespaces: $(kubectl get namespaces --no-headers 2>/dev/null | wc -l)"
        else
            echo "  Cluster: Not accessible"
        fi
    fi
    
    echo "----------------------------------------"
}

# Main script logic
main() {
    if [[ $# -ne 2 ]]; then
        show_usage
        exit 1
    fi
    
    local environment=$1
    local action=$2
    
    validate_environment "$environment"
    check_requirements
    
    case "$action" in
        init)
            terraform_init "$environment"
            ;;
        plan)
            terraform_plan "$environment"
            ;;
        apply)
            terraform_apply "$environment"
            ;;
        destroy)
            terraform_destroy "$environment"
            ;;
        status)
            show_status "$environment"
            ;;
        *)
            log_error "Invalid action: $action"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"