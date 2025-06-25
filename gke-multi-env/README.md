# GKE Multi-Environment Infrastructure

A complete Terraform-based infrastructure solution for deploying production-ready Google Kubernetes Engine (GKE) clusters with ArgoCD, monitoring, and supporting services across development and production environments.

## 🏗️ Architecture Overview

This project creates a multi-environment GKE infrastructure with the following components:

- **GKE Clusters**: Environment-specific clusters with auto-scaling and security hardening
- **ArgoCD**: GitOps deployment platform with HA configuration for production
- **NGINX Ingress**: Load balancing and SSL termination
- **Cert-Manager**: Automated SSL certificate management with Let's Encrypt
- **External DNS**: Automatic DNS record management
- **Cloud SQL MySQL**: Managed database with regional HA for production
- **Cloud Memorystore Redis**: In-memory data store with HA for production
- **VPC Networking**: Private, secure networking with environment isolation

## 📁 Project Structure

```
gke-multi-env/
├── terraform/
│   └── main.tf                 # Complete Terraform configuration
├── environments/
│   ├── dev/
│   │   └── terraform.tfvars    # Development environment variables
│   └── prod/
│       └── terraform.tfvars    # Production environment variables
├── scripts/
│   └── deploy.sh               # Deployment automation script
├── Makefile                    # Automation commands
├── README.md                   # This file
└── docs/
    └── deployment-guide.md     # Detailed deployment instructions
```

## 🚀 Quick Start

### Prerequisites

- [Terraform](https://terraform.io/downloads) >= 1.0
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.0
- [jq](https://stedolan.github.io/jq/download/)

### 1. Setup and Authentication

```bash
# Install dependencies and check requirements
make setup

# Authenticate with Google Cloud
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Configure Environment Variables

Edit the configuration files for your environments:

```bash
# Development environment
vim environments/dev/terraform.tfvars

# Production environment  
vim environments/prod/terraform.tfvars
```

### 3. Deploy Development Environment

```bash
# Complete dev workflow (setup, init, plan)
make dev-workflow

# Review the plan and deploy
make apply-dev

# Get ArgoCD credentials
make argocd-password-dev
```

### 4. Deploy Production Environment

```bash
# Complete prod workflow (setup, init, plan)
make prod-workflow

# Review the plan carefully and deploy
make apply-prod

# Get ArgoCD credentials
make argocd-password-prod
```

## 🔧 Available Commands

### Environment Management

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make setup` | Install dependencies and check requirements |
| `make dev-workflow` | Complete dev environment setup (init + plan) |
| `make prod-workflow` | Complete prod environment setup (init + plan) |

### Development Environment

| Command | Description |
|---------|-------------|
| `make init-dev` | Initialize Terraform for dev |
| `make plan-dev` | Plan Terraform changes for dev |
| `make apply-dev` | Deploy dev environment |
| `make status-dev` | Show dev environment status |
| `make destroy-dev` | Destroy dev environment |

### Production Environment

| Command | Description |
|---------|-------------|
| `make init-prod` | Initialize Terraform for prod |
| `make plan-prod` | Plan Terraform changes for prod |
| `make apply-prod` | Deploy prod environment |
| `make status-prod` | Show prod environment status |
| `make destroy-prod` | Destroy prod environment |

### Service Management

| Command | Description |
|---------|-------------|
| `make argocd-password-dev` | Get ArgoCD admin password (dev) |
| `make argocd-password-prod` | Get ArgoCD admin password (prod) |
| `make db-status-dev` | Check database status (dev) |
| `make db-status-prod` | Check database status (prod) |
| `make redis-status-dev` | Check Redis status (dev) |
| `make redis-status-prod` | Check Redis status (prod) |
| `make ingress-ip-dev` | Get NGINX Ingress IP (dev) |
| `make ingress-ip-prod` | Get NGINX Ingress IP (prod) |

## 🌍 Environment Differences

### Development Environment
- **Cost Optimized**: Preemptible nodes, smaller instances
- **Single Instance**: Single replica services
- **Auto-upgrade**: Enabled for latest features
- **SSL**: Let's Encrypt staging certificates
- **Database**: Basic tier, 7-day backups
- **Redis**: Basic tier, no authentication
- **DNS Policy**: Upsert-only (safer for testing)

### Production Environment
- **High Availability**: Multi-replica services, regional database
- **Security Hardened**: Node taints, private networking, TLS encryption
- **Manual Upgrades**: Blue-green deployments for stability
- **SSL**: Let's Encrypt production certificates
- **Database**: Standard tier, 30-day backups, regional HA
- **Redis**: Standard HA tier with authentication and TLS
- **DNS Policy**: Sync (full DNS management)
- **Deletion Protection**: Enabled for critical resources

## 🔐 Security Features

- **Private GKE Clusters**: Nodes have no public IPs
- **Workload Identity**: Secure service account authentication
- **Network Policies**: Microsegmentation between services
- **VPC Isolation**: Separate networks per environment
- **TLS Everywhere**: End-to-end encryption
- **Secret Management**: Kubernetes secrets for sensitive data
- **RBAC**: Role-based access control

## 📊 Monitoring and Observability

- **GKE Monitoring**: Built-in Google Cloud monitoring
- **ArgoCD UI**: Application deployment visibility
- **Ingress Metrics**: NGINX controller metrics
- **Resource Limits**: CPU and memory constraints
- **Health Checks**: Kubernetes probes for all services

## 🗄️ Database Access

### Development
```bash
# Get database credentials
make db-status-dev

# Connect via Cloud SQL Proxy
gcloud sql connect dev-mysql-instance --user=dev_app_user
```

### Production
```bash
# Get database credentials
make db-status-prod

# Connect via Cloud SQL Proxy
gcloud sql connect prod-mysql-instance --user=prod_app_user
```

## 🔄 GitOps with ArgoCD

### Access ArgoCD

```bash
# Development
make argocd-password-dev
# Visit: https://argocd-dev.your-domain.com

# Production  
make argocd-password-prod
# Visit: https://argocd-prod.your-domain.com
```

### Port Forward (Local Access)
```bash
# Development
make argocd-port-forward-dev
# Visit: http://localhost:8080

# Production
make argocd-port-forward-prod  
# Visit: http://localhost:8080
```

## 🌐 DNS Management

DNS records are automatically managed by External DNS:

- **Development**: `*.dev.your-domain.com`
- **Production**: `*.prod.your-domain.com`

Check DNS status:
```bash
make dns-records-dev
make dns-records-prod
```

## 🧹 Cleanup

```bash
# Clean temporary files
make clean-dev
make clean-prod

# Destroy environments (careful!)
make destroy-dev
make destroy-prod
```

## 🔍 Troubleshooting

### Common Issues

1. **Authentication Error**
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Terraform State Lock**
   
   When you see an error like "Error acquiring the state lock", follow these steps:
   
   ```bash
   # First, try to get the lock ID from the error message
   cd gke-multi-env/terraform
   terraform plan -var-file=../environments/dev/terraform.tfvars
   
   # Look for "Lock Info:" in the error output, which will show:
   # ID:        1750835415658727  <-- This is the LOCK_ID
   # Path:      gs://dexor-terraform-state/terraform/state/dev.tflock
   # Operation: OperationTypeApply
   # Who:       user@hostname
   # Created:   2025-06-25 07:10:15.213443 +0000 UTC
   
   # Force unlock using the Lock ID
   terraform force-unlock -force 1750835415658727
   
   # For production environment
   terraform workspace select prod
   terraform force-unlock -force LOCK_ID
   ```
   
   **Using Makefile commands:**
   ```bash
   # For development environment
   make unlock-dev
   
   # For production environment
   make unlock-prod
   ```
   
   **Common causes of state locks:**
   - Previous Terraform operation was interrupted
   - Multiple users running Terraform simultaneously
   - Network issues during apply/destroy operations
   - Terraform process crashed unexpectedly

3. **kubectl Not Working**
   ```bash
   make kubectl-dev    # or kubectl-prod
   ```

4. **DNS Not Resolving**
   ```bash
   # Check External DNS logs
   kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
   ```

5. **ArgoCD Not Accessible**
   ```bash
   # Check ingress status
   kubectl get ingress -n argocd
   
   # Check certificate status
   kubectl get certificate -n argocd
   ```

### Getting Help

1. Check service status: `make status-dev` or `make status-prod`
2. View logs: `make logs-dev` or `make logs-prod`
3. Validate configuration: `make validate-dev` or `make validate-prod`

## 📚 Additional Resources

- [Detailed Deployment Guide](docs/deployment-guide.md)
- [Terraform GCP Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test in development environment
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**⚠️ Important Notes:**
- Always test changes in development before applying to production
- Review Terraform plans carefully before applying
- Keep your `terraform.tfvars` files secure and don't commit sensitive values
- Production deployments require manual confirmation for safety