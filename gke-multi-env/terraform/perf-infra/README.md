# Performance Infrastructure for Kaia Orderbook DEX

This Terraform module creates the performance testing infrastructure for the Kaia Orderbook DEX project, including MySQL and Redis instances with the same specifications as QA environment.

## Architecture

The performance infrastructure uses the same tier configuration as QA environment for consistency:

### Database Configuration
- **MySQL**: `db-g1-small` tier with 20GB SSD storage (same as QA)
- **Redis**: `BASIC` tier with 2GB memory (same as QA)
- **Network**: Uses private IPs within the existing dev VPC
- **Security**: Kubernetes secrets and Google Secret Manager integration

### Resource Specifications

| Component | Specification | Purpose |
|-----------|---------------|---------|
| MySQL | db-g1-small, 20GB SSD | Basic tier same as QA |
| Redis | BASIC, 2GB | Basic tier same as QA |
| Connections | 1000 max MySQL connections | Standard connection limit |

## Prerequisites

1. **Existing Dev Environment**: The dev GKE cluster and VPC must exist
2. **Private Service Access**: VPC peering for Cloud SQL private IPs
3. **Terraform State**: GCS bucket `dexor-terraform-state` configured
4. **GCP APIs**: Secret Manager, Cloud SQL, Memorystore APIs enabled

## Usage

### 1. Configuration

Copy the example variables file:
```bash
cd environments/perf/
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your project details:
```hcl
project_id = "your-gcp-project-id"
region     = "asia-northeast3"
dev_network_name = "dev-vpc"
dev_cluster_name = "dev-gke-cluster"
perf_namespace = "kaia-dex-perf"
```

### 2. Deploy Infrastructure

From the repository root:
```bash
cd gke-multi-env/terraform/perf-infra/
terraform init
terraform plan -var-file="../../environments/perf/terraform.tfvars"
terraform apply -var-file="../../environments/perf/terraform.tfvars"
```

### 3. Verify Deployment

Check created resources:
```bash
# Database status
terraform output mysql_private_ip
terraform output redis_host

# Kubernetes resources
kubectl get namespace kaia-dex-perf
kubectl get secrets -n kaia-dex-perf
```

## Resources Created

### Google Cloud Resources
- Cloud SQL MySQL instance (`perf-mysql-instance`)
- Cloud Memorystore Redis instance (`perf-redis`)
- Secret Manager secrets (mysql password, redis auth, app config)
- Service accounts and IAM bindings

### Kubernetes Resources
- Namespace: `kaia-dex-perf`
- Secrets: `mysql-perf-secret`, `redis-perf-secret`
- ConfigMap: `database-connection-perf`
- Service Account: `perf-secret-manager-sa`

## Performance Optimizations

### MySQL Optimizations
- `max_connections`: 1000 for concurrent connections (same as QA)
- `long_query_time`: 2 seconds for performance monitoring (same as QA)
- SSD storage for reduced I/O latency

### Redis Optimizations
- Basic tier with standard configuration (same as QA)
- 2GB memory for caching scenarios

## Security

### Access Control
- Private IP addresses only (no public access)
- Workload Identity for secure pod-to-GCP authentication
- Secret Manager integration for credential management
- Dev backend service account reused for consistency

### Secret Management
All sensitive data stored in:
1. **Google Secret Manager**: Encrypted at rest and in transit
2. **Kubernetes Secrets**: Base64 encoded within cluster
3. **ConfigMaps**: Non-sensitive connection information only

## Monitoring and Troubleshooting

### Connection Testing
```bash
# Test MySQL connectivity
kubectl run mysql-client --rm -it --image=mysql:8.0 --restart=Never -- \
  mysql -h <mysql-private-ip> -u kaia_perf -p

# Test Redis connectivity  
kubectl run redis-client --rm -it --image=redis:7.0 --restart=Never -- \
  redis-cli -h <redis-host> -a <redis-password>
```

### Performance Metrics
- Monitor slow queries with `slow_query_log = on`
- Redis memory usage and hit rates
- Connection pool utilization
- Database transaction rates

## Cleanup

To destroy the performance infrastructure:
```bash
terraform destroy -var-file="../../environments/perf/terraform.tfvars"
```

**Warning**: This will permanently delete all performance databases and cached data.

## Integration with Applications

### Backend Configuration
The backend service uses these connection details automatically when deployed to the `kaia-dex-perf` namespace:

```yaml
env:
  - name: DB_HOST
    valueFrom:
      configMapKeyRef:
        name: database-connection-perf
        key: mysql-host
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: mysql-perf-secret
        key: mysql-password
```

### Load Testing Scenarios
This infrastructure supports:
- **Concurrent Users**: Up to 1000 simultaneous database connections (same as QA)
- **Data Volume**: 20GB MySQL storage (same as QA)  
- **Cache Performance**: 2GB Redis for caching scenarios (same as QA)
- **Environment Consistency**: Same tier configuration as QA for fair comparison