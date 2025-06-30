terraform {
  required_version = ">= 1.0"

  backend "gcs" {
    bucket = "dexor-terraform-state"
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# ==============================================================================
# VARIABLES
# ==============================================================================

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "asia-northeast3"
}

variable "environment" {
  description = "Environment name (dev, qa, or prod)"
  type        = string
  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "Environment must be 'dev', 'qa', or 'prod'."
  }
}

variable "domain_suffix" {
  description = "Domain suffix for services"
  type        = string
}

variable "dns_zone_name" {
  description = "Cloud DNS zone name"
  type        = string
}

variable "enable_external_dns" {
  description = "Enable External DNS"
  type        = bool
  default     = true
}

variable "enable_cloud_sql" {
  description = "Enable Cloud SQL MySQL"
  type        = bool
  default     = true
}

variable "enable_redis" {
  description = "Enable Cloud Memorystore Redis"
  type        = bool
  default     = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "app_database"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "app_user"
}

variable "cert_manager_email" {
  description = "Email for Let's Encrypt certificates"
  type        = string
}

variable "enable_sequencer_pool" {
  description = "Enable Arbitrum sequencer node pool"
  type        = bool
  default     = false
}

# ==============================================================================
# LOCAL VALUES
# ==============================================================================

locals {
  env_config = {
    dev = {
      gke_node_count         = 1
      gke_min_node_count     = 1
      gke_max_node_count     = 5
      gke_machine_type       = "e2-standard-2"
      gke_preemptible        = true
      gke_enable_autoupgrade = true
      argocd_replicas        = 1
      cert_issuer_server     = "https://acme-v02.api.letsencrypt.org/directory"
      external_dns_policy    = "upsert-only"
      db_tier                = "db-f1-micro"
      db_disk_size           = 20
      db_availability_type   = "ZONAL"
      db_backup_days         = 7
      redis_tier             = "BASIC"
      redis_memory_size      = 1
      redis_auth_enabled     = false
      redis_tls_enabled      = false
      nginx_replicas         = 1
      sequencer_min_nodes    = 1
      sequencer_max_nodes    = 2
    }
    prod = {
      gke_node_count         = 3
      gke_min_node_count     = 3
      gke_max_node_count     = 10
      gke_machine_type       = "e2-standard-4"
      gke_preemptible        = false
      gke_enable_autoupgrade = false
      argocd_replicas        = 3
      cert_issuer_server     = "https://acme-v02.api.letsencrypt.org/directory"
      external_dns_policy    = "sync"
      db_tier                = "db-n1-standard-2"
      db_disk_size           = 100
      db_availability_type   = "REGIONAL"
      db_backup_days         = 30
      redis_tier             = "STANDARD_HA"
      redis_memory_size      = 5
      redis_auth_enabled     = true
      redis_tls_enabled      = true
      nginx_replicas         = 2
      sequencer_min_nodes    = 1
      sequencer_max_nodes    = 3
    }
  }

  config = local.env_config[var.environment]
  common_labels = {
    environment = var.environment
    project     = "gke-multi-env"
    managed-by  = "terraform"
  }
}

# ==============================================================================
# PROVIDERS
# ==============================================================================

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
  }
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "google_client_config" "default" {}

# ==============================================================================
# RESOURCES
# ==============================================================================

# Random password for database
resource "random_password" "db_password" {
  count   = var.enable_cloud_sql ? 1 : 0
  length  = 16
  special = true
}

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-subnet"
  ip_cidr_range = var.environment == "dev" ? "10.0.0.0/16" : "10.1.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.environment == "dev" ? "10.4.0.0/14" : "10.8.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.environment == "dev" ? "10.12.0.0/16" : "10.13.0.0/16"
  }

  private_ip_google_access = true
}

# Private Service Access
resource "google_compute_global_address" "private_service_access" {
  count         = var.enable_cloud_sql || var.enable_redis ? 1 : 0
  name          = "${var.environment}-private-service-access"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.enable_cloud_sql || var.enable_redis ? 1 : 0
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access[0].name]
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "${var.environment}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT for egress traffic
resource "google_compute_router_nat" "nat" {
  name                               = "${var.environment}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Firewall rules
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.environment}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [
    google_compute_subnetwork.subnet.ip_cidr_range,
    google_compute_subnetwork.subnet.secondary_ip_range[0].ip_cidr_range,
    google_compute_subnetwork.subnet.secondary_ip_range[1].ip_cidr_range
  ]
}

# Service Accounts
resource "google_service_account" "gke_sa" {
  account_id   = "${var.environment}-gke-sa"
  display_name = "${var.environment} GKE Service Account"
}

resource "google_project_iam_member" "gke_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",     # Added for pulling images from Artifact Registry
    "roles/secretmanager.secretAccessor" # Added for accessing Secret Manager
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

resource "google_service_account" "external_dns_sa" {
  count        = var.enable_external_dns ? 1 : 0
  account_id   = "${var.environment}-external-dns-sa"
  display_name = "${var.environment} External DNS Service Account"
}

resource "google_project_iam_member" "external_dns_sa_dns_admin" {
  count   = var.enable_external_dns ? 1 : 0
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns_sa[0].email}"
}

resource "google_service_account_iam_member" "external_dns_workload_identity" {
  count              = var.enable_external_dns ? 1 : 0
  service_account_id = google_service_account.external_dns_sa[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-dns/external-dns]"
}

# Service Account for cert-manager DNS-01 challenge
resource "google_service_account" "cert_manager_sa" {
  account_id   = "${var.environment}-cert-manager-sa"
  display_name = "${var.environment} Cert Manager Service Account"
}

resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager_sa.email}"
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  service_account_id = google_service_account.cert_manager_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.environment}-gke-cluster"
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # VPC-native networking
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.environment == "dev" ? "172.16.0.0/28" : "172.17.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All"
    }
  }

  # Enable various addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  network_policy {
    enabled = true
  }

  deletion_protection = var.environment == "prod" ? true : false

  depends_on = [
    google_project_iam_member.gke_sa_roles,
  ]
}

# GKE Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.environment}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = local.config.gke_node_count

  autoscaling {
    min_node_count = local.config.gke_min_node_count
    max_node_count = local.config.gke_max_node_count
  }

  node_config {
    preemptible  = local.config.gke_preemptible
    machine_type = local.config.gke_machine_type

    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = merge(local.common_labels, {
      environment = var.environment
    })

    # Production nodes get taints
    dynamic "taint" {
      for_each = var.environment == "prod" ? [1] : []
      content {
        key    = "environment"
        value  = "prod"
        effect = "NO_SCHEDULE"
      }
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = local.config.gke_enable_autoupgrade
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = var.environment == "prod" ? "BLUE_GREEN" : "SURGE"

    dynamic "blue_green_settings" {
      for_each = var.environment == "prod" ? [1] : []
      content {
        standard_rollout_policy {
          batch_percentage    = 100
          batch_node_count    = 1
          batch_soak_duration = "60s"
        }
        node_pool_soak_duration = "60s"
      }
    }
  }
}

# Arbitrum Sequencer Node Pool
resource "google_container_node_pool" "sequencer_nodes" {
  count      = var.enable_sequencer_pool ? 1 : 0
  name       = "${var.environment}-sequencer-pool"
  location   = var.region  # Use regional cluster location
  cluster    = google_container_cluster.primary.name

  # Single zone configuration for sequencer
  node_locations = ["${var.region}-a"]
  node_count     = 2

  autoscaling {
    min_node_count = local.config.sequencer_min_nodes
    max_node_count = local.config.sequencer_max_nodes
  }

  node_config {
    preemptible  = false           # Sequencer should not be preemptible
    machine_type = "n2-standard-4" # 4 vCPU, 16GB RAM

    disk_size_gb = 200
    disk_type    = "pd-ssd"

    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = merge(local.common_labels, {
      environment = var.environment
      node-type   = "sequencer"
      workload    = "arbitrum-sequencer"
    })

    # Taints to ensure only sequencer workloads run on these nodes
    taint {
      key    = "workload"
      value  = "sequencer"
      effect = "NO_SCHEDULE"
    }

    # Additional taint for prod environment
    dynamic "taint" {
      for_each = var.environment == "prod" ? [1] : []
      content {
        key    = "environment"
        value  = "prod"
        effect = "NO_SCHEDULE"
      }
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true  # Required for release channel
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE" # Always use SURGE for sequencer nodes
  }
}

# Cloud SQL MySQL Instance
resource "google_sql_database_instance" "mysql" {
  count            = var.enable_cloud_sql ? 1 : 0
  name             = "${var.environment}-mysql-instance"
  database_version = "MYSQL_8_4"
  region           = var.region

  deletion_protection = var.environment == "prod" ? true : false

  settings {
    tier              = local.config.db_tier
    availability_type = local.config.db_availability_type
    disk_size         = local.config.db_disk_size
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled            = true
      start_time         = "03:00"
      binary_log_enabled = true
      backup_retention_settings {
        retained_backups = local.config.db_backup_days
      }
      transaction_log_retention_days = local.config.db_backup_days
    }

    database_flags {
      name  = "general_log"
      value = "off"
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = var.environment == "prod" ? "stable" : "canary"
    }

    user_labels = local.common_labels
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Cloud SQL Database
resource "google_sql_database" "database" {
  count    = var.enable_cloud_sql ? 1 : 0
  name     = var.db_name
  instance = google_sql_database_instance.mysql[0].name
}

# Cloud SQL User
resource "google_sql_user" "user" {
  count    = var.enable_cloud_sql ? 1 : 0
  name     = var.db_user
  instance = google_sql_database_instance.mysql[0].name
  password = random_password.db_password[0].result
}

# Cloud Memorystore Redis
resource "google_redis_instance" "redis" {
  count          = var.enable_redis ? 1 : 0
  name           = "${var.environment}-redis"
  tier           = local.config.redis_tier
  memory_size_gb = local.config.redis_memory_size
  region         = var.region

  authorized_network = google_compute_network.vpc.id

  auth_enabled            = local.config.redis_auth_enabled
  transit_encryption_mode = local.config.redis_tls_enabled ? "SERVER_AUTHENTICATION" : "DISABLED"

  redis_version = "REDIS_7_0"
  display_name  = "${var.environment} Redis Instance"

  redis_configs = var.environment == "prod" ? {
    maxmemory-policy = "allkeys-lru"
    save             = "900 1 300 10 60 10000"
  } : {}

  labels = local.common_labels

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Kubernetes Namespaces
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name = "argocd"
    }
  }
  depends_on = [google_container_node_pool.primary_nodes]
}

resource "kubernetes_namespace" "nginx_ingress" {
  metadata {
    name = "nginx-ingress"
    labels = {
      name = "nginx-ingress"
    }
  }
  depends_on = [google_container_node_pool.primary_nodes]
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      name = "cert-manager"
    }
  }
  depends_on = [google_container_node_pool.primary_nodes]
}

resource "kubernetes_namespace" "external_dns" {
  count = var.enable_external_dns ? 1 : 0
  metadata {
    name = "external-dns"
    labels = {
      name = "external-dns"
    }
  }
  depends_on = [google_container_node_pool.primary_nodes]
}

resource "kubernetes_namespace" "sequencer" {
  count = var.enable_sequencer_pool ? 1 : 0
  metadata {
    name = "arbitrum-sequencer"
    labels = {
      name = "arbitrum-sequencer"
    }
  }
  depends_on = [google_container_node_pool.primary_nodes]
}

# Kubernetes Service Account for External DNS
resource "kubernetes_service_account" "external_dns" {
  count = var.enable_external_dns ? 1 : 0
  metadata {
    name      = "external-dns"
    namespace = kubernetes_namespace.external_dns[0].metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.external_dns_sa[0].email
    }
  }
}

# Kubernetes Service Account for Sequencer
resource "kubernetes_service_account" "sequencer" {
  count = var.enable_sequencer_pool ? 1 : 0
  metadata {
    name      = "arbitrum-sequencer"
    namespace = kubernetes_namespace.sequencer[0].metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.gke_sa.email
    }
  }
}

# Database Secret
resource "kubernetes_secret" "db_credentials" {
  count = var.enable_cloud_sql ? 1 : 0
  metadata {
    name      = "mysql-credentials"
    namespace = "default"
  }

  data = {
    host     = google_sql_database_instance.mysql[0].private_ip_address
    port     = "3306"
    database = var.db_name
    username = var.db_user
    password = random_password.db_password[0].result
  }

  type       = "Opaque"
  depends_on = [google_container_node_pool.primary_nodes]
}

# Redis Secret
resource "kubernetes_secret" "redis_credentials" {
  count = var.enable_redis ? 1 : 0
  metadata {
    name      = "redis-credentials"
    namespace = "default"
  }

  data = {
    host        = google_redis_instance.redis[0].host
    port        = "6379"
    auth_string = local.config.redis_auth_enabled ? google_redis_instance.redis[0].auth_string : ""
  }

  type       = "Opaque"
  depends_on = [google_container_node_pool.primary_nodes]
}

# NGINX Ingress Controller
resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.8.3"
  namespace        = kubernetes_namespace.nginx_ingress.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    controller = {
      replicaCount = local.config.nginx_replicas
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
      service = {
        type = "LoadBalancer"
        annotations = {
          "cloud.google.com/load-balancer-type" = "External"
        }
      }
      metrics = {
        enabled = true
      }
    }
  })]

  depends_on = [google_container_node_pool.primary_nodes]
}

# Cert-Manager
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.13.2"
  namespace        = kubernetes_namespace.cert_manager.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      create = true
      name   = "cert-manager"
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.cert_manager_sa.email
      }
    }
    nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
    tolerations = var.environment == "prod" ? [{
      key      = "environment"
      operator = "Equal"
      value    = "prod"
      effect   = "NoSchedule"
    }] : []
    webhook = {
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
    }
    cainjector = {
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
    }
  })]

  depends_on = [google_container_node_pool.primary_nodes]
}

# ClusterIssuer for Let's Encrypt
resource "null_resource" "cluster_issuer" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -f - <<EOF
      apiVersion: cert-manager.io/v1
      kind: ClusterIssuer
      metadata:
        name: letsencrypt-${var.environment}
      spec:
        acme:
          server: ${local.config.cert_issuer_server}
          email: ${var.cert_manager_email}
          privateKeySecretRef:
            name: letsencrypt-${var.environment}
          solvers:
          - http01:
              ingress:
                class: nginx
          - dns01:
              cloudDNS:
                project: ${var.project_id}
      EOF
    EOT
  }

  depends_on = [
    helm_release.cert_manager,
    google_container_node_pool.primary_nodes
  ]
}

# External DNS
resource "helm_release" "external_dns" {
  count            = var.enable_external_dns ? 1 : 0
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = "1.13.1"
  namespace        = kubernetes_namespace.external_dns[0].metadata[0].name
  create_namespace = false

  values = [yamlencode({
    provider = "google"
    google = {
      project = var.project_id
    }
    domainFilters = [var.domain_suffix]
    zoneIdFilters = [var.dns_zone_name]
    policy        = local.config.external_dns_policy
    serviceAccount = {
      create = false
      name   = kubernetes_service_account.external_dns[0].metadata[0].name
    }
    nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
    tolerations = var.environment == "prod" ? [{
      key      = "environment"
      operator = "Equal"
      value    = "prod"
      effect   = "NoSchedule"
    }] : []
  })]

  depends_on = [
    google_container_node_pool.primary_nodes,
    kubernetes_service_account.external_dns
  ]
}

# ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.6"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    controller = {
      replicas     = local.config.argocd_replicas
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
    }
    server = {
      replicas     = local.config.argocd_replicas
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        annotations = {
          "cert-manager.io/cluster-issuer"                 = "letsencrypt-${var.environment}"
          "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
          "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
          "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
        }
        hosts    = ["argocd-${var.environment}.${var.domain_suffix}"]
        paths    = ["/"]
        pathType = "Prefix"
        tls = [{
          secretName = "argocd-server-tls"
          hosts      = ["argocd-${var.environment}.${var.domain_suffix}"]
        }]
      }
      ingressGrpc = {
        enabled          = true
        ingressClassName = "nginx"
        annotations = {
          "nginx.ingress.kubernetes.io/backend-protocol" = "GRPC"
        }
        hosts    = ["argocd-grpc-${var.environment}.${var.domain_suffix}"]
        paths    = ["/"]
        pathType = "Prefix"
        tls = [{
          secretName = "argocd-grpc-tls"
          hosts      = ["argocd-grpc-${var.environment}.${var.domain_suffix}"]
        }]
      }
      config = {
        "application.instanceLabelKey" = "argocd.argoproj.io/instance"
      }
      extraArgs = ["--insecure"]
    }
    repoServer = {
      replicas     = local.config.argocd_replicas
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
    }
    applicationSet = {
      replicas     = local.config.argocd_replicas
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
    }
    notifications = {
      enabled      = var.environment == "prod"
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
    }
    redis = {
      enabled      = true
      nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
      tolerations = var.environment == "prod" ? [{
        key      = "environment"
        operator = "Equal"
        value    = "prod"
        effect   = "NoSchedule"
      }] : []
    }
  })]

  depends_on = [
    google_container_node_pool.primary_nodes,
    helm_release.nginx_ingress,
    null_resource.cluster_issuer
  ]
}

# ArgoCD Image Updater
resource "helm_release" "argocd_image_updater" {
  name             = "argocd-image-updater"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-image-updater"
  version          = "0.9.1"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false

  values = [yamlencode({
    config = {
      registries = [
        {
          name     = "Docker Hub"
          api_url  = "https://registry-1.docker.io"
          prefix   = "docker.io"
          ping     = true
          insecure = false
        },
        {
          name        = "Google Artifact Registry"
          api_url     = "https://asia-northeast3-docker.pkg.dev"
          prefix      = "asia-northeast3-docker.pkg.dev"
          ping        = true
          insecure    = false
          credentials = "ext:/auth/auth.sh"
          credsexpire = "30m"
          default     = true
        }
      ]
    }
    serviceAccount = {
      create      = true
      annotations = var.enable_secret_manager ? {
        "iam.gke.io/gcp-service-account" = google_service_account.artifact_registry_reader[0].email
      } : {}
    }
    volumes = [
      {
        name = "auth-scripts"
        configMap = {
          name        = "argocd-image-updater-auth"
          defaultMode = 493  # 0755 in decimal
        }
      }
    ]
    volumeMounts = [
      {
        name      = "auth-scripts"
        mountPath = "/auth"
      }
    ]
    nodeSelector = var.environment == "prod" ? { environment = "prod" } : {}
    tolerations = var.environment == "prod" ? [{
      key      = "environment"
      operator = "Equal"
      value    = "prod"
      effect   = "NoSchedule"
    }] : []
  })]

  depends_on = [
    helm_release.argocd,
    kubernetes_config_map.argocd_image_updater_config
  ]
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.primary.location
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.subnet.name
}

output "database_private_ip" {
  description = "Database private IP address"
  value       = var.enable_cloud_sql ? google_sql_database_instance.mysql[0].private_ip_address : null
}

output "database_connection_name" {
  description = "Database connection name"
  value       = var.enable_cloud_sql ? google_sql_database_instance.mysql[0].connection_name : null
}

output "redis_host" {
  description = "Redis host"
  value       = var.enable_redis ? google_redis_instance.redis[0].host : null
}

output "redis_port" {
  description = "Redis port"
  value       = var.enable_redis ? google_redis_instance.redis[0].port : null
}

output "argocd_url" {
  description = "ArgoCD URL"
  value       = "https://argocd-${var.environment}.${var.domain_suffix}"
}

output "nginx_ingress_ip" {
  description = "NGINX Ingress external IP"
  value       = "Check kubectl get svc -n nginx-ingress to get the external IP"
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region=${var.region} --project=${var.project_id}"
}

output "sequencer_node_pool_name" {
  description = "Sequencer node pool name"
  value       = var.enable_sequencer_pool ? google_container_node_pool.sequencer_nodes[0].name : null
}
