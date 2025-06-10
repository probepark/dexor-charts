# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a production-ready GKE multi-environment infrastructure project that deploys complete cloud-native stacks across development and production environments using Terraform. The architecture emphasizes security, cost optimization, and operational excellence.

## Architecture

### Core Design Principles
- **Environment Isolation**: Separate VPCs, Terraform workspaces, and resource configurations for dev/prod
- **Configuration-Driven**: Environment differences managed through Terraform locals and tfvars files
- **Security by Default**: Private clusters, Workload Identity, minimal IAM permissions, VPC isolation
- **Cost Optimization**: Dev uses preemptible nodes and basic tiers; prod uses HA configurations
- **GitOps Ready**: ArgoCD pre-configured with ingress, SSL, and image updater

### Infrastructure Stack
- **GKE Clusters**: Private clusters with auto-scaling, environment-specific node configurations
- **Networking**: VPC-native with private service access for databases
- **ArgoCD**: GitOps platform with HA setup (prod), staging/prod SSL certificates
- **NGINX Ingress**: Load balancing with Google Cloud integration
- **Cert-Manager**: Automated Let's Encrypt certificate management
- **External DNS**: Automatic DNS record management for Cloud DNS
- **Cloud SQL MySQL**: Regional HA (prod), basic tier (dev), automated backups
- **Cloud Memorystore Redis**: HA with auth/TLS (prod), basic tier (dev)

### Key File Structure
- `terraform/main.tf`: Complete infrastructure definition (924 lines) with environment-specific logic
- `Makefile`: Comprehensive automation with 25+ targets for all operations
- `scripts/deploy.sh`: Safety-first deployment script with confirmation prompts
- `environments/{dev,prod}/terraform.tfvars`: Environment-specific configurations
- `docs/deployment-guide.md`: Detailed operational procedures and troubleshooting

## Common Commands

### Environment Setup
```bash
make setup                    # Check prerequisites and authentication
make dev-workflow            # Initialize and plan dev environment
make prod-workflow           # Initialize and plan prod environment
```

### Environment Management
```bash
make apply-dev               # Deploy development environment
make apply-prod              # Deploy production environment (requires confirmation)
make status-dev              # Show dev infrastructure status
make status-prod             # Show prod infrastructure status
make destroy-dev             # Destroy dev environment
make destroy-prod            # Destroy prod environment (multiple confirmations)
```

### Service Access
```bash
make argocd-password-dev     # Get ArgoCD admin credentials for dev
make argocd-password-prod    # Get ArgoCD admin credentials for prod
make kubectl-dev             # Configure kubectl for dev cluster
make kubectl-prod            # Configure kubectl for prod cluster
make db-status-dev           # Check database connection info
make redis-status-dev        # Check Redis connection info
```

### Troubleshooting
```bash
make logs-dev                # View service logs and pod status
make dns-records-dev         # Check DNS record propagation
make ingress-ip-dev          # Get NGINX Ingress external IP
make validate-dev            # Validate Terraform configuration
```

## Development Workflow

### Initial Setup Pattern
1. **Prerequisites**: Run `make setup` to verify tools and authentication
2. **Configuration**: Edit `environments/{env}/terraform.tfvars` with actual values
3. **Planning**: Use `make {env}-workflow` to initialize and plan
4. **Deployment**: Apply with `make apply-{env}` after reviewing plans
5. **Access**: Use service-specific commands to get credentials and URLs

### Environment Configuration Requirements
Both dev and prod terraform.tfvars files require:
- `project_id`: Actual GCP project ID
- `domain_suffix`: Your domain (e.g., "dev.example.com")
- `dns_zone_name`: Cloud DNS zone name
- `cert_manager_email`: Email for Let's Encrypt certificates

### GitHub Repository Configuration
Configure multiple repositories for GitHub Actions integration:

```hcl
github_repositories = [
  "kaiachain/dexor-charts",
  "kaiachain/another-repo",
  "kaiachain/third-repo"
]
```

**Note**: At least one repository must be specified for GitHub Actions integration to work.

### Safety Mechanisms
- **Terraform Workspaces**: Automatic workspace management per environment
- **Production Confirmations**: Multiple confirmation prompts for prod operations
- **Deletion Protection**: Enabled on critical prod resources
- **Plan Reviews**: All operations show plans before applying

### ArgoCD Integration
- Automatically deployed with SSL ingress
- Image updater pre-configured for Docker Hub
- Separate instances per environment with HA in production
- Access via `https://argocd-{env}.{domain_suffix}`

## Terraform Patterns

### Environment Configuration Logic
The `main.tf` uses a locals block with environment-specific configurations:
```hcl
locals {
  env_config = {
    dev = { gke_preemptible = true, argocd_replicas = 1, ... }
    prod = { gke_preemptible = false, argocd_replicas = 3, ... }
  }
  config = local.env_config[var.environment]
}
```

### Resource Naming Convention
Resources follow the pattern: `${var.environment}-{resource-type}`
Examples: `dev-gke-cluster`, `prod-mysql-instance`

### Service Account Strategy
- Separate service accounts per service with minimal permissions
- Workload Identity bindings for secure pod-to-GCP authentication
- Automatic secret creation for database and Redis credentials

## Operational Patterns

### Database Management
- Automatic password generation and Kubernetes secret creation
- Private IP connectivity through VPC peering
- Environment-specific backup retention (dev: 7 days, prod: 30 days)
- Connection via Cloud SQL Proxy for management access

### DNS and Certificate Management
- External DNS automatically manages A records for ingress
- Cert-Manager handles Let's Encrypt certificate lifecycle
- Environment-specific certificate issuers (staging for dev, production for prod)

### Monitoring and Troubleshooting
- Built-in GKE monitoring and logging
- Makefile targets for common debugging tasks
- Status commands show resource health and connection information
- Log viewing commands for service troubleshooting

## Security Considerations

### Network Security
- All clusters use private nodes (no public IPs)
- VPC isolation between environments
- Private service access for databases
- Firewall rules restricted to necessary traffic

### Identity and Access
- Workload Identity for pod-to-GCP authentication
- Minimal IAM permissions per service account
- Kubernetes RBAC for cluster access
- Production environment uses node taints for workload isolation

### Data Protection
- TLS encryption for all communications
- Database SSL enforcement in production
- Redis AUTH and TLS in production
- Secrets managed through Kubernetes secrets

## Common Issues and Solutions

### Terraform State Management
- Workspaces automatically managed by deployment scripts
- State locks handled with proper error messages
- Force unlock commands available if needed

### DNS Resolution Issues
- Check External DNS logs: `kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns`
- Verify Cloud DNS zone configuration
- Use `make dns-records-{env}` to check record propagation

### ArgoCD Access Problems
- Verify ingress status: `kubectl get ingress -n argocd`
- Check certificate status: `kubectl get certificates -n argocd`
- Use port-forward for local access: `make argocd-port-forward-{env}`

### Database Connectivity
- Check private IP connectivity from cluster
- Verify VPC peering for private service access
- Use Cloud SQL Proxy for direct connection testing