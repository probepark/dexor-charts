# GKE Multi-Environment Deployment Guide

This comprehensive guide will walk you through deploying a production-ready GKE multi-environment infrastructure with ArgoCD, monitoring, and supporting services.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Environment Configuration](#environment-configuration)
4. [Development Environment Deployment](#development-environment-deployment)
5. [Production Environment Deployment](#production-environment-deployment)
6. [Post-Deployment Configuration](#post-deployment-configuration)
7. [Database Management](#database-management)
8. [DNS and Certificate Management](#dns-and-certificate-management)
9. [ArgoCD Setup and Usage](#argocd-setup-and-usage)
10. [Monitoring and Maintenance](#monitoring-and-maintenance)
11. [Troubleshooting](#troubleshooting)
12. [Security Considerations](#security-considerations)

## 📚 Prerequisites

### Required Tools

Ensure the following tools are installed and configured:

```bash
# Terraform (>= 1.0)
terraform version

# Google Cloud SDK
gcloud version

# kubectl
kubectl version --client

# Helm (>= 3.0)
helm version

# jq (for JSON processing)
jq --version
```

### Google Cloud Setup

1. **Create or Select GCP Project**
   ```bash
   # Create new project
   gcloud projects create YOUR_PROJECT_ID --name="GKE Multi-Environment"
   
   # Or list existing projects
   gcloud projects list
   
   # Set active project
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Enable Required APIs**
   ```bash
   gcloud services enable \
     container.googleapis.com \
     compute.googleapis.com \
     dns.googleapis.com \
     sqladmin.googleapis.com \
     redis.googleapis.com \
     servicenetworking.googleapis.com \
     cloudresourcemanager.googleapis.com \
     iam.googleapis.com
   ```

3. **Set Up Authentication**
   ```bash
   # Interactive login
   gcloud auth login
   
   # Application Default Credentials for Terraform
   gcloud auth application-default login
   
   # Verify authentication
   gcloud auth list
   ```

4. **Configure Default Region/Zone**
   ```bash
   gcloud config set compute/region asia-northeast3
   gcloud config set compute/zone asia-northeast3-a
   ```

### DNS Zone Setup

Create Cloud DNS zones for your domains:

```bash
# Development zone
gcloud dns managed-zones create dev-example-com \
  --description="Development environment DNS zone" \
  --dns-name="dev.example.com"

# Production zone  
gcloud dns managed-zones create prod-example-com \
  --description="Production environment DNS zone" \
  --dns-name="prod.example.com"

# Get name servers for domain delegation
gcloud dns managed-zones describe dev-example-com --format="value(nameServers[].join(' '))"
gcloud dns managed-zones describe prod-example-com --format="value(nameServers[].join(' '))"
```

### IAM Permissions

Ensure your account has the following roles:

- `roles/editor` or specific roles:
  - `roles/container.admin`
  - `roles/compute.admin` 
  - `roles/dns.admin`
  - `roles/cloudsql.admin`
  - `roles/redis.admin`
  - `roles/iam.serviceAccountAdmin`

## 🛠️ Initial Setup

### 1. Clone and Setup Project

```bash
# Navigate to your project directory
cd /path/to/your/projects

# The project should already be created, navigate to it
cd gke-multi-env

# Verify project structure
tree -L 3
```

### 2. Check Prerequisites

```bash
# Run the setup check
make setup
```

This command will:
- Verify all required tools are installed
- Check GCP authentication
- Validate project configuration

## ⚙️ Environment Configuration

### Development Environment

Edit `environments/dev/terraform.tfvars`:

```hcl
# Dev Environment Configuration
environment = "dev"

# GCP Configuration - REQUIRED CHANGES
project_id = "your-actual-project-id"        # Change this!
region     = "asia-northeast3"

# Domain Configuration - REQUIRED CHANGES  
domain_suffix   = "dev.yourdomain.com"       # Change this!
dns_zone_name   = "dev-yourdomain-com"       # Change this!

# Service Enablement
enable_external_dns = true
enable_cloud_sql    = true
enable_redis        = true

# Database Configuration
db_name = "dev_app_database"
db_user = "dev_app_user"

# Cert-Manager Configuration - REQUIRED CHANGES
cert_manager_email = "your-email@yourdomain.com"  # Change this!
```

### Production Environment

Edit `environments/prod/terraform.tfvars`:

```hcl
# Production Environment Configuration
environment = "prod"

# GCP Configuration - REQUIRED CHANGES
project_id = "your-actual-project-id"        # Change this!
region     = "asia-northeast3"

# Domain Configuration - REQUIRED CHANGES
domain_suffix   = "prod.yourdomain.com"      # Change this!
dns_zone_name   = "prod-yourdomain-com"      # Change this!

# Service Enablement
enable_external_dns = true
enable_cloud_sql    = true
enable_redis        = true

# Database Configuration
db_name = "prod_app_database"
db_user = "prod_app_user"

# Cert-Manager Configuration - REQUIRED CHANGES
cert_manager_email = "your-email@yourdomain.com"  # Change this!
```

### Configuration Validation

```bash
# Validate development configuration
make validate-dev

# Validate production configuration
make validate-prod
```

## 🚀 Development Environment Deployment

### Step 1: Initialize Development Environment

```bash
# Run complete dev workflow (recommended)
make dev-workflow
```

This command will:
1. Check prerequisites
2. Initialize Terraform
3. Create/select dev workspace
4. Generate deployment plan

### Step 2: Review the Plan

Carefully review the Terraform plan output. It should show:
- GKE cluster creation
- VPC and networking setup
- Cloud SQL MySQL instance
- Redis instance
- Service accounts and IAM bindings
- Kubernetes namespaces and services

### Step 3: Deploy Development Environment

```bash
# Apply the development environment
make apply-dev
```

This process takes approximately 10-15 minutes and includes:
1. Creating GCP resources
2. Deploying GKE cluster
3. Installing ArgoCD
4. Setting up NGINX Ingress
5. Configuring Cert-Manager
6. Deploying External DNS

### Step 4: Verify Development Deployment

```bash
# Check overall status
make status-dev

# Verify kubectl access
kubectl get nodes

# Check all pods are running
kubectl get pods --all-namespaces

# Verify ingress
make ingress-ip-dev
```

### Step 5: Access ArgoCD (Development)

```bash
# Get ArgoCD credentials
make argocd-password-dev

# The output will show:
# - ArgoCD admin password
# - ArgoCD URL (https://argocd-dev.yourdomain.com)
```

Access ArgoCD via:
- **URL**: https://argocd-dev.yourdomain.com
- **Username**: admin
- **Password**: (from command output)

## 🏭 Production Environment Deployment

### Step 1: Initialize Production Environment

```bash
# Run complete prod workflow
make prod-workflow
```

**⚠️ Important**: Review the plan output very carefully for production!

### Step 2: Production Pre-Deployment Checklist

Before deploying to production, verify:

- [ ] DNS zones are properly configured
- [ ] Domain delegation is set up
- [ ] Terraform plan shows expected resources
- [ ] No unexpected deletions or changes
- [ ] Email address for certificates is correct
- [ ] Project ID and region are correct

### Step 3: Deploy Production Environment

```bash
# Deploy production (requires confirmation)
make apply-prod
```

**Production deployment includes additional safety measures:**
- Deletion protection on critical resources
- Manual upgrade settings
- High availability configurations
- Enhanced security settings

### Step 4: Verify Production Deployment

```bash
# Check production status
make status-prod

# Verify all services
kubectl get pods --all-namespaces

# Check ingress and certificates
kubectl get ingress --all-namespaces
kubectl get certificates --all-namespaces
```

### Step 5: Access ArgoCD (Production)

```bash
# Get ArgoCD credentials
make argocd-password-prod
```

Access ArgoCD via:
- **URL**: https://argocd-prod.yourdomain.com
- **Username**: admin
- **Password**: (from command output)

## 🔧 Post-Deployment Configuration

### Kubernetes Context Management

```bash
# Switch between environments
make kubectl-dev     # Configure kubectl for dev
make kubectl-prod    # Configure kubectl for prod

# Verify current context
kubectl config current-context
```

### ArgoCD Initial Setup

1. **Login to ArgoCD**
   - Access the ArgoCD URL
   - Use admin credentials from the setup

2. **Change Default Password**
   ```bash
   # Port forward for local access (if needed)
   make argocd-port-forward-dev   # or prod
   
   # Change password via CLI
   argocd account update-password --account admin
   ```

3. **Add Git Repositories**
   - Navigate to Settings > Repositories
   - Add your application repositories
   - Configure SSH keys or HTTPS access

### SSL Certificate Verification

```bash
# Check certificate status
kubectl get certificates --all-namespaces

# Check certificate details
kubectl describe certificate argocd-server-tls -n argocd

# Verify HTTPS access
curl -I https://argocd-dev.yourdomain.com
```

## 🗄️ Database Management

### Development Database Access

```bash
# Get database connection information
make db-status-dev

# Connect via Cloud SQL Proxy
gcloud sql connect dev-mysql-instance --user=dev_app_user --database=dev_app_database
```

### Production Database Access

```bash
# Get database connection information
make db-status-prod

# Connect via Cloud SQL Proxy (requires authentication)
gcloud sql connect prod-mysql-instance --user=prod_app_user --database=prod_app_database
```

### Database Credentials in Kubernetes

```bash
# View database secret
kubectl get secret mysql-credentials -o yaml

# Decode credentials
kubectl get secret mysql-credentials -o jsonpath='{.data.password}' | base64 -d
```

### Database Backup Verification

```bash
# List backups
gcloud sql backups list --instance=dev-mysql-instance   # or prod-mysql-instance

# Create manual backup
gcloud sql backups create --instance=prod-mysql-instance --description="Manual backup"
```

## 🌐 DNS and Certificate Management

### External DNS Status

```bash
# Check External DNS logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Verify DNS records
make dns-records-dev
make dns-records-prod
```

### Manual DNS Record Management

```bash
# List current records
gcloud dns record-sets list --zone=dev-yourdomain-com

# Add custom record (if needed)
gcloud dns record-sets transaction start --zone=dev-yourdomain-com
gcloud dns record-sets transaction add "1.2.3.4" --name=app-dev.yourdomain.com --type=A --zone=dev-yourdomain-com
gcloud dns record-sets transaction execute --zone=dev-yourdomain-com
```

### Certificate Troubleshooting

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate requests
kubectl get certificaterequests --all-namespaces

# Manual certificate creation (if needed)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-cert
  namespace: default
spec:
  secretName: example-cert-tls
  issuerRef:
    name: letsencrypt-dev
    kind: ClusterIssuer
  dnsNames:
  - example-dev.yourdomain.com
EOF
```

## 🎯 ArgoCD Setup and Usage

### Initial Application Setup

1. **Create Your First Application**
   ```yaml
   # example-app.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: example-app
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://github.com/your-org/your-app
       targetRevision: HEAD
       path: k8s
     destination:
       server: https://kubernetes.default.svc
       namespace: default
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

2. **Apply the Application**
   ```bash
   kubectl apply -f example-app.yaml
   ```

### ArgoCD Image Updater Configuration

The Image Updater is automatically installed. Configure it for your applications:

```yaml
# Add annotations to your application
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: myapp=myregistry/myapp
    argocd-image-updater.argoproj.io/write-back-method: git
```

### ArgoCD Best Practices

1. **Use Projects for Organization**
   ```bash
   # Create development project
   argocd proj create development \
     --src https://github.com/your-org/* \
     --dest https://kubernetes.default.svc,dev-namespace
   ```

2. **Set Up RBAC**
   ```yaml
   # argocd-rbac-cm
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: argocd-rbac-cm
     namespace: argocd
   data:
     policy.default: role:readonly
     policy.csv: |
       p, role:admin, applications, *, */*, allow
       p, role:admin, clusters, *, *, allow
       g, your-team@company.com, role:admin
   ```

## 📊 Monitoring and Maintenance

### Health Checks

```bash
# Overall environment health
make status-dev    # or status-prod

# Specific service health
kubectl get pods --all-namespaces
kubectl top nodes
kubectl top pods --all-namespaces
```

### Log Management

```bash
# View environment logs
make logs-dev     # or logs-prod

# Specific service logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
kubectl logs -n nginx-ingress -l app.kubernetes.io/name=ingress-nginx
kubectl logs -n cert-manager -l app=cert-manager
```

### Resource Monitoring

```bash
# Cluster resource usage
kubectl top nodes
kubectl describe nodes

# Pod resource usage
kubectl top pods --all-namespaces --sort-by=cpu
kubectl top pods --all-namespaces --sort-by=memory
```

### Backup Strategies

1. **Database Backups** (Automatic)
   - Dev: 7-day retention
   - Prod: 30-day retention

2. **ArgoCD Configuration Backup**
   ```bash
   # Export ArgoCD applications
   kubectl get applications -n argocd -o yaml > argocd-apps-backup.yaml
   
   # Export ArgoCD projects
   kubectl get appprojects -n argocd -o yaml > argocd-projects-backup.yaml
   ```

3. **Terraform State Backup**
   ```bash
   # Download state files
   cd terraform
   terraform state pull > state-backup-$(date +%Y%m%d).json
   ```

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 1. Terraform State Lock

```bash
# List locks
terraform force-unlock <LOCK_ID>

# If state is corrupted
terraform import google_container_cluster.primary projects/PROJECT_ID/locations/REGION/clusters/CLUSTER_NAME
```

#### 2. ArgoCD Not Accessible

```bash
# Check ingress status
kubectl get ingress -n argocd
kubectl describe ingress argocd-server-ingress -n argocd

# Check certificate status
kubectl get certificate -n argocd
kubectl describe certificate argocd-server-tls -n argocd

# Check External DNS
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

#### 3. Database Connection Issues

```bash
# Check Cloud SQL status
gcloud sql instances describe INSTANCE_NAME

# Test connectivity from pod
kubectl run mysql-client --image=mysql:8.0 --restart=Never -it --rm -- mysql -h DATABASE_IP -u USERNAME -p
```

#### 4. DNS Resolution Problems

```bash
# Check External DNS configuration
kubectl get configmap external-dns -n external-dns -o yaml

# Test DNS resolution
nslookup argocd-dev.yourdomain.com
dig argocd-dev.yourdomain.com

# Check Cloud DNS records
gcloud dns record-sets list --zone=ZONE_NAME
```

#### 5. Certificate Issues

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate request details
kubectl describe certificaterequest -n NAMESPACE

# Manual certificate debugging
kubectl get events --sort-by=.metadata.creationTimestamp -n cert-manager
```

### Performance Troubleshooting

#### High Resource Usage

```bash
# Identify resource-heavy pods
kubectl top pods --all-namespaces --sort-by=cpu
kubectl top pods --all-namespaces --sort-by=memory

# Check node capacity
kubectl describe nodes

# Scale down if needed
kubectl scale deployment DEPLOYMENT_NAME --replicas=1 -n NAMESPACE
```

#### Slow Application Deployment

```bash
# Check ArgoCD sync status
kubectl get applications -n argocd
kubectl describe application APP_NAME -n argocd

# Check image pull times
kubectl describe pod POD_NAME -n NAMESPACE | grep -A 10 Events
```

### Emergency Procedures

#### 1. Emergency Database Backup

```bash
# Create immediate backup
gcloud sql backups create --instance=INSTANCE_NAME --description="Emergency backup $(date)"

# Export data
gcloud sql export sql INSTANCE_NAME gs://BUCKET_NAME/emergency-backup-$(date +%Y%m%d).sql --database=DATABASE_NAME
```

#### 2. ArgoCD Recovery

```bash
# Reset ArgoCD admin password
kubectl patch secret argocd-initial-admin-secret -n argocd -p '{"data":{"password":"'$(echo -n 'newpassword' | base64)'"}}'

# Restart ArgoCD server
kubectl rollout restart deployment argocd-server -n argocd
```

#### 3. Complete Environment Recovery

```bash
# Re-apply Terraform configuration
make apply-dev  # or apply-prod

# Verify all services
make status-dev  # or status-prod
```

## 🔒 Security Considerations

### Network Security

1. **Private Clusters**: All node IPs are private
2. **VPC Isolation**: Separate VPCs for dev/prod
3. **Firewall Rules**: Minimal required access
4. **Private Service Access**: Database connections via private IP

### Identity and Access Management

1. **Workload Identity**: Secure pod-to-GCP authentication
2. **Service Account Separation**: Minimal permissions per service
3. **RBAC**: Kubernetes role-based access control
4. **Secret Management**: Kubernetes secrets for sensitive data

### Data Security

1. **Encryption in Transit**: TLS for all communications
2. **Encryption at Rest**: Google Cloud default encryption
3. **Database Security**: Private IP, SSL enforcement (prod)
4. **Redis Security**: AUTH and TLS enabled (prod)

### Compliance and Auditing

```bash
# Review IAM policies
gcloud projects get-iam-policy PROJECT_ID

# Check service account usage
gcloud iam service-accounts list

# Review firewall rules
gcloud compute firewall-rules list

# Check encryption status
gcloud sql instances describe INSTANCE_NAME --format="value(settings.ipConfiguration.requireSsl)"
```

### Security Maintenance

1. **Regular Updates**
   ```bash
   # Check for cluster updates
   gcloud container get-server-config --region=REGION
   
   # Update cluster (dev environment)
   gcloud container clusters upgrade CLUSTER_NAME --region=REGION
   ```

2. **Security Scanning**
   ```bash
   # Enable vulnerability scanning
   gcloud container images scan IMAGE_URL
   
   # Check for security updates
   kubectl get nodes -o wide
   ```

3. **Access Review**
   - Regularly review ArgoCD user access
   - Audit Kubernetes RBAC permissions
   - Review GCP IAM bindings

## 📈 Scaling and Optimization

### Cluster Scaling

```bash
# Manual node pool scaling
gcloud container clusters resize CLUSTER_NAME --num-nodes=5 --region=REGION

# Enable vertical pod autoscaling
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/latest/download/vpa-release.yaml
```

### Cost Optimization

1. **Development Environment**
   - Use preemptible nodes
   - Scale down during off-hours
   - Use smaller database tiers

2. **Production Environment**
   - Right-size resources based on monitoring
   - Use committed use discounts
   - Enable cluster autoscaling

### Performance Optimization

1. **Database Performance**
   ```bash
   # Monitor database performance
   gcloud sql operations list --instance=INSTANCE_NAME
   
   # Adjust database flags if needed
   gcloud sql instances patch INSTANCE_NAME --database-flags=slow_query_log=on
   ```

2. **Redis Performance**
   ```bash
   # Monitor Redis metrics in Cloud Console
   # Adjust memory size if needed
   gcloud redis instances update INSTANCE_NAME --size=10
   ```

---

This comprehensive deployment guide provides everything needed to successfully deploy and manage your GKE multi-environment infrastructure. Always test changes in the development environment first, and maintain regular backups of critical data and configurations.