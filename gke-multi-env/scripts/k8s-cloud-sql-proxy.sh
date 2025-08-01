#!/bin/bash
# Deploy Cloud SQL Proxy in Kubernetes and connect via port-forward

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Store the script directory before any cd commands
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default values
ENV="${1:-dev}"
LOCAL_PORT="${2:-3306}"
ACTION="${3:-connect}" # connect, deploy, delete

# Validate environment
if [[ "$ENV" != "dev" && "$ENV" != "prod" && "$ENV" != "qa" && "$ENV" != "perf" ]]; then
    echo -e "${RED}Error: Environment must be 'dev', 'qa', 'perf', or 'prod'${NC}"
    echo "Usage: $0 [dev|qa|perf|prod] [local_port] [connect|deploy|delete]"
    exit 1
fi

echo -e "${BLUE}Kubernetes Cloud SQL Proxy for ${ENV} environment${NC}"

# Change to terraform directory to get outputs
if [ "$ENV" == "qa" ]; then
    cd "$(dirname "$0")/../terraform/qa-infra"
elif [ "$ENV" == "perf" ]; then
    cd "$(dirname "$0")/../terraform/perf-infra"
else
    cd "$(dirname "$0")/../terraform"
    terraform workspace select "$ENV" >/dev/null 2>&1
fi

# Get project ID and connection name
PROJECT_ID="orderbook-dex-dev"  # All environments use dev project
if [ "$ENV" == "qa" ] || [ "$ENV" == "perf" ]; then
    CONNECTION_NAME=$(terraform output -raw mysql_connection_name 2>/dev/null || echo "")
else
    CONNECTION_NAME=$(terraform output -raw database_connection_name 2>/dev/null || echo "")
fi

if [ -z "$CONNECTION_NAME" ] || [ "$CONNECTION_NAME" == "null" ]; then
    echo -e "${RED}Error: Could not get database connection name${NC}"
    exit 1
fi

echo -e "${GREEN}Project ID: $PROJECT_ID${NC}"
echo -e "${GREEN}Connection Name: $CONNECTION_NAME${NC}"

# Configure kubectl
echo -e "${YELLOW}Configuring kubectl...${NC}"
if [ "$ENV" == "qa" ] || [ "$ENV" == "perf" ]; then
    # QA and perf use dev cluster
    gcloud container clusters get-credentials "dev-gke-cluster" --region="asia-northeast3" --project="$PROJECT_ID"
else
    gcloud container clusters get-credentials "${ENV}-gke-cluster" --region="asia-northeast3" --project="$PROJECT_ID"
fi

# Function to create service account
create_service_account() {
    echo -e "${YELLOW}Creating Cloud SQL service account...${NC}"
    
    # Create GCP service account if it doesn't exist
    if ! gcloud iam service-accounts describe "cloud-sql-proxy-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1; then
        gcloud iam service-accounts create cloud-sql-proxy-sa \
            --display-name="Cloud SQL Proxy Service Account" \
            --project="$PROJECT_ID"
    fi
    
    # Grant Cloud SQL client role
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:cloud-sql-proxy-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudsql.client" \
        --quiet
    
    # Enable workload identity binding
    if [ "$ENV" == "qa" ]; then
        NAMESPACE="kaia-dex-qa"
    elif [ "$ENV" == "perf" ]; then
        NAMESPACE="kaia-dex-perf"
    else
        NAMESPACE="default"
    fi
    
    gcloud iam service-accounts add-iam-policy-binding \
        "cloud-sql-proxy-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/iam.workloadIdentityUser" \
        --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/cloud-sql-proxy]" \
        --project="$PROJECT_ID"
}

# Function to deploy cloud sql proxy
deploy_proxy() {
    echo -e "${YELLOW}Deploying Cloud SQL Proxy to Kubernetes...${NC}"
    
    # Create service account first
    create_service_account
    
    # Set namespace
    if [ "$ENV" == "qa" ]; then
        NAMESPACE="kaia-dex-qa"
    elif [ "$ENV" == "perf" ]; then
        NAMESPACE="kaia-dex-perf"
    else
        NAMESPACE="default"
    fi
    
    # Generate YAML with actual values
    cat "$SCRIPT_DIR/../k8s/cloud-sql-proxy.yaml" | \
        sed "s/\${PROJECT_ID}/$PROJECT_ID/g" | \
        sed "s/\${CONNECTION_NAME}/$CONNECTION_NAME/g" | \
        kubectl apply -n "$NAMESPACE" -f -
    
    # Wait for deployment
    echo -e "${YELLOW}Waiting for deployment to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=60s deployment/cloud-sql-proxy -n "$NAMESPACE"
    
    echo -e "${GREEN}Cloud SQL Proxy deployed successfully!${NC}"
}

# Function to delete proxy
delete_proxy() {
    echo -e "${YELLOW}Deleting Cloud SQL Proxy from Kubernetes...${NC}"
    
    # Set namespace
    if [ "$ENV" == "qa" ]; then
        NAMESPACE="kaia-dex-qa"
    elif [ "$ENV" == "perf" ]; then
        NAMESPACE="kaia-dex-perf"
    else
        NAMESPACE="default"
    fi
    
    cat "$SCRIPT_DIR/../k8s/cloud-sql-proxy.yaml" | \
        sed "s/\${PROJECT_ID}/$PROJECT_ID/g" | \
        sed "s/\${CONNECTION_NAME}/$CONNECTION_NAME/g" | \
        kubectl delete -n "$NAMESPACE" -f - || true
    
    echo -e "${GREEN}Cloud SQL Proxy deleted${NC}"
}

# Function to connect via port-forward
connect_proxy() {
    # Set namespace
    if [ "$ENV" == "qa" ]; then
        NAMESPACE="kaia-dex-qa"
    elif [ "$ENV" == "perf" ]; then
        NAMESPACE="kaia-dex-perf"
    else
        NAMESPACE="default"
    fi
    
    # Check if proxy is deployed
    if ! kubectl get deployment cloud-sql-proxy -n "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "${YELLOW}Cloud SQL Proxy not deployed. Deploying now...${NC}"
        deploy_proxy
    fi
    
    # Get pod name
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=cloud-sql-proxy -o jsonpath="{.items[0].metadata.name}")
    
    if [ -z "$POD_NAME" ]; then
        echo -e "${RED}Error: Cloud SQL Proxy pod not found${NC}"
        exit 1
    fi
    
    # Get database credentials
    echo -e "${YELLOW}Getting database credentials...${NC}"
    APP_CONFIG=$(gcloud secrets versions access latest --secret="${ENV}-app-config" --project="$PROJECT_ID" 2>/dev/null || echo "{}")
    
    # Parse credentials
    DB_NAME=$(echo "$APP_CONFIG" | jq -r '.rw_db_dsn' | sed -n 's/.*\/\([^?]*\).*/\1/p')
    DB_USER=$(echo "$APP_CONFIG" | jq -r '.rw_db_dsn' | sed -n 's/mysql:\/\/\([^:]*\):.*/\1/p')
    DB_PASSWORD=$(echo "$APP_CONFIG" | jq -r '.rw_db_dsn' | sed -n 's/mysql:\/\/[^:]*:\([^@]*\).*/\1/p')
    
    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${YELLOW}Using default credentials...${NC}"
        if [ "$ENV" == "qa" ]; then
            DB_NAME="kaia_orderbook_qa"
            DB_USER="kaia_qa"
            DB_PASSWORD=$(kubectl get secret mysql-qa-secret -n "$NAMESPACE" -o jsonpath="{.data.mysql-password}" 2>/dev/null | base64 -d || echo "")
        elif [ "$ENV" == "perf" ]; then
            DB_NAME="kaia_orderbook_perf"
            DB_USER="kaia_perf"
            DB_PASSWORD=$(kubectl get secret mysql-perf-secret -n "$NAMESPACE" -o jsonpath="{.data.mysql-password}" 2>/dev/null | base64 -d || echo "")
        else
            DB_NAME="dex"
            DB_USER="klaytn"
            DB_PASSWORD=$(kubectl get secret mysql-credentials -n "$NAMESPACE" -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
        fi
    fi
    
    echo -e "${GREEN}Database connection ready!${NC}"
    echo -e "${BLUE}Starting port-forward from localhost:$LOCAL_PORT to pod $POD_NAME:3306${NC}"
    echo ""
    echo -e "${YELLOW}MySQL connection command:${NC}"
    echo "mysql -h 127.0.0.1 -P $LOCAL_PORT -u $DB_USER -p'$DB_PASSWORD' $DB_NAME"
    echo ""
    echo -e "${YELLOW}Connection string:${NC}"
    echo "mysql://$DB_USER:$DB_PASSWORD@127.0.0.1:$LOCAL_PORT/$DB_NAME"
    echo ""
    echo -e "${GREEN}Press Ctrl+C to stop port-forward${NC}"
    
    # Start port-forward
    kubectl port-forward -n "$NAMESPACE" "pod/$POD_NAME" "$LOCAL_PORT:3306"
}

# Main logic
case "$ACTION" in
    deploy)
        deploy_proxy
        ;;
    delete)
        delete_proxy
        ;;
    connect|*)
        connect_proxy
        ;;
esac