# QA Environment Infrastructure

This directory contains Terraform configuration for QA-specific resources (MySQL and Redis) that use the existing dev VPC and GKE cluster.

## Overview

The QA environment:
- Uses the existing dev VPC network
- Uses the existing dev GKE cluster
- Has its own dedicated namespace (`kaia-dex-qa`)
- Has its own dedicated database instances:
  - **MySQL**: Basic tier instance with 20GB storage
  - **Redis**: Basic tier instance with 2GB memory
- Automatically creates Kubernetes secrets for database credentials

## Prerequisites

1. The dev environment must be deployed first (creates VPC and GKE cluster)
2. GCP authentication configured
3. Terraform >= 1.0
4. kubectl access to the dev cluster

## Configuration

1. Configuration file is located in the environments directory:
```bash
cd ../../environments/qa/
cp terraform.tfvars.example terraform.tfvars
```

2. Edit `environments/qa/terraform.tfvars` with your actual values:
```hcl
project_id       = "orderbook-dex-dev"
region           = "asia-northeast3"
dev_network_name = "dev-vpc"
dev_cluster_name = "dev-gke-cluster"
qa_namespace     = "kaia-dex-qa"
```

## Deployment

Use the main Makefile from the gke-multi-env directory:

```bash
# From gke-multi-env directory
make qa-init    # Initialize Terraform
make qa-plan    # Review the plan
make qa-apply   # Apply the configuration

# Or use terraform directly from this directory
terraform init
terraform plan -var-file="../../environments/qa/terraform.tfvars"
terraform apply -var-file="../../environments/qa/terraform.tfvars"
```

## Outputs

After deployment, retrieve connection information:

```bash
# Get all outputs
terraform output

# Get specific outputs
terraform output mysql_private_ip
terraform output mysql_password
terraform output redis_host
terraform output redis_auth_string
```

## Connecting to Resources

### MySQL Connection
```bash
# From within the GKE cluster (in kaia-dex-qa namespace)
mysql -h <mysql_private_ip> -u kaia_qa -p<password> kaia_orderbook_qa

# Using kubectl port-forward from local machine
kubectl port-forward -n kaia-dex-qa deployment/cloud-sql-proxy 3306:3306
mysql -h 127.0.0.1 -u kaia_qa -p<password> kaia_orderbook_qa
```

### Redis Connection
```bash
# From within the GKE cluster (in kaia-dex-qa namespace)
redis-cli -h <redis_host> -p 6379 -a <auth_string>
```

### Kubernetes Secrets

The following secrets are automatically created in the `kaia-dex-qa` namespace:

1. **mysql-qa-secret**:
   - `mysql-host`: Private IP of MySQL instance
   - `mysql-port`: 3306
   - `mysql-database`: kaia_orderbook_qa
   - `mysql-user`: kaia_qa
   - `mysql-password`: Generated password

2. **redis-qa-secret**:
   - `redis-host`: Redis instance host
   - `redis-port`: 6379
   - `redis-password`: Redis auth string

3. **database-connection-qa** (ConfigMap):
   - Contains non-sensitive connection information

## Resource Specifications

### MySQL (Cloud SQL)
- **Instance**: db-g1-small (1 vCPU, 1.7 GB RAM)
- **Storage**: 20GB SSD with autoresize
- **Backup**: Daily backups retained for 7 days
- **High Availability**: Disabled (single zone)
- **SSL**: Not required

### Redis (Cloud Memorystore)
- **Tier**: Basic (no replication)
- **Memory**: 2GB
- **Version**: Redis 7.0
- **Auth**: Enabled
- **TLS**: Disabled
- **Persistence**: Disabled (memory only)

## Cost Estimation

Approximate monthly costs (as of 2024):
- MySQL db-g1-small: ~$20-30/month
- Redis Basic 2GB: ~$40-50/month
- **Total**: ~$60-80/month

## Cleanup

To destroy the QA resources:

```bash
# From gke-multi-env directory
make qa-destroy

# Or from this directory
terraform destroy -var-file="../../environments/qa/terraform.tfvars"
```

**Warning**: This will delete all data in the QA databases!