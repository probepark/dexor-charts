terraform {
  required_version = ">= 1.0"

  backend "gcs" {
    bucket = "dexor-terraform-state"
    prefix = "terraform/perf/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
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
  description = "Environment name"
  type        = string
  default     = "perf"
}

variable "dev_network_name" {
  description = "The name of the dev VPC network to use"
  type        = string
  default     = "dev-vpc"
}

variable "dev_cluster_name" {
  description = "The name of the dev GKE cluster to use"
  type        = string
  default     = "dev-gke-cluster"
}

variable "perf_namespace" {
  description = "Kubernetes namespace for Performance resources"
  type        = string
  default     = "kaia-dex-perf"
}

variable "application_secrets" {
  description = "Map of application secrets to store in Secret Manager"
  type        = map(string)
  default     = {}
}

# CDN Variables
variable "cdn_sites" {
  description = "Map of CDN site configurations"
  type = map(object({
    domains                = list(string)           # List of domains/CNAMEs for this site
    index_page             = optional(string)       # Main page (default: index.html)
    error_page             = optional(string)       # Error page (default: 404.html)
    cors_origins           = optional(list(string)) # CORS allowed origins
    retention_days         = optional(number)       # Days to retain content
    enable_versioning      = optional(bool)         # Enable bucket versioning
    cache_mode             = optional(string)       # CDN cache mode
    client_ttl             = optional(number)       # Client cache TTL
    default_ttl            = optional(number)       # CDN default TTL
    max_ttl                = optional(number)       # CDN max TTL
    custom_headers         = optional(list(string)) # Additional response headers
    enable_spa_routing     = optional(bool)         # Enable SPA routing for HTML
  }))
  default = {}
  
  validation {
    condition     = length(var.cdn_sites) >= 0
    error_message = "CDN sites configuration must be valid."
  }
}

variable "default_site" {
  description = "Default site key to use when no host matches"
  type        = string
  default     = ""
}

variable "use_managed_certificate" {
  description = "Whether to use Google-managed SSL certificates"
  type        = bool
  default     = true
}

variable "create_dns_records" {
  description = "Whether to create DNS records automatically"
  type        = bool
  default     = true
}

variable "dns_managed_zone_name" {
  description = "The name of the Cloud DNS managed zone"
  type        = string
  default     = ""
}

variable "enable_cdn_workload_identity" {
  description = "Enable workload identity for CDN operations"
  type        = bool
  default     = false
}

variable "cdn_github_repositories" {
  description = "List of GitHub repositories for CDN deployment"
  type        = list(string)
  default     = []
}

# Additional CDN variables
variable "enable_cloud_armor" {
  description = "Enable Cloud Armor security policies"
  type        = bool
  default     = false
}

variable "cloud_armor_rules" {
  description = "Cloud Armor security policy rules"
  type        = map(any)
  default     = {}
}

variable "enable_versioning" {
  description = "Enable versioning for storage buckets"
  type        = bool
  default     = false
}

variable "ssl_private_key" {
  description = "SSL private key for custom certificates"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssl_certificate" {
  description = "SSL certificate for custom certificates"
  type        = string
  default     = ""
}

variable "enable_http_redirect" {
  description = "Enable HTTP to HTTPS redirect"
  type        = bool
  default     = true
}

# CDN caching variables
variable "cdn_client_ttl" {
  description = "Default client TTL for CDN"
  type        = number
  default     = 3600
}

variable "cdn_default_ttl" {
  description = "Default TTL for CDN"
  type        = number
  default     = 3600
}

variable "cdn_max_ttl" {
  description = "Maximum TTL for CDN"
  type        = number
  default     = 86400
}

variable "cdn_serve_while_stale" {
  description = "Serve while stale for CDN"
  type        = number
  default     = 86400
}

variable "custom_response_headers" {
  description = "Custom response headers for CDN"
  type        = list(string)
  default     = []
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Reference existing dev VPC
data "google_compute_network" "dev_vpc" {
  name    = var.dev_network_name
  project = var.project_id
}

# Note: Private VPC connection is expected to exist from dev environment setup

# Reference existing dev GKE cluster
data "google_container_cluster" "dev_cluster" {
  name     = var.dev_cluster_name
  location = var.region
  project  = var.project_id
}

# ==============================================================================
# PROVIDERS CONFIGURATION
# ==============================================================================

provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure Kubernetes provider to use dev cluster
provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.dev_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.dev_cluster.master_auth[0].cluster_ca_certificate)
}

data "google_client_config" "default" {}

# ==============================================================================
# LOCALS
# ==============================================================================

locals {
  common_labels = {
    environment = "perf"
    managed_by  = "terraform"
    project     = "kaia-orderbook-dex"
  }
}

# ==============================================================================
# RANDOM PASSWORDS
# ==============================================================================

resource "random_password" "db_password" {
  length  = 32
  special = true
}

# ==============================================================================
# CLOUD SQL MYSQL FOR PERFORMANCE
# ==============================================================================

resource "google_sql_database_instance" "perf_mysql" {
  name             = "perf-mysql-instance"
  database_version = "MYSQL_8_4"
  region           = var.region

  settings {
    tier              = "db-g1-small"  # Basic tier same as QA
    availability_type = "ZONAL"        # Single zone same as QA
    disk_type         = "PD_SSD"
    disk_size         = 20             # 20GB same as QA
    disk_autoresize   = true

    backup_configuration {
      enabled            = true
      start_time         = "03:00"
      location           = var.region
      binary_log_enabled = true  # For MySQL PITR
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.dev_vpc.id
      ssl_mode = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"  # Perf allows both
    }

    database_flags {
      name  = "slow_query_log"
      value = "on"
    }

    database_flags {
      name  = "long_query_time"
      value = "2"  # Same as QA
    }

    database_flags {
      name  = "max_connections"
      value = "1000"  # Same as QA
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "canary"  # Perf uses canary like dev
    }

    user_labels = local.common_labels
  }

  deletion_protection = false
}

# Cloud SQL Database
resource "google_sql_database" "perf_database" {
  name     = "kaia_orderbook_perf"
  instance = google_sql_database_instance.perf_mysql.name
}

# Cloud SQL User
resource "google_sql_user" "perf_user" {
  name     = "kaia_perf"
  instance = google_sql_database_instance.perf_mysql.name
  password = random_password.db_password.result
}

# ==============================================================================
# CLOUD MEMORYSTORE REDIS FOR PERFORMANCE
# ==============================================================================

resource "google_redis_instance" "perf_redis" {
  name           = "perf-redis"
  tier           = "BASIC"  # Basic tier same as QA
  memory_size_gb = 2        # 2GB same as QA
  region         = var.region

  authorized_network = data.google_compute_network.dev_vpc.id

  auth_enabled            = true
  transit_encryption_mode = "DISABLED"  # No TLS same as QA

  redis_version = "REDIS_7_0"
  display_name  = "Performance Redis Instance"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  labels = local.common_labels
}

# ==============================================================================
# KUBERNETES RESOURCES
# ==============================================================================

# Create Performance namespace
resource "kubernetes_namespace" "perf" {
  metadata {
    name = var.perf_namespace
    labels = {
      name        = var.perf_namespace
      environment = "perf"
    }
  }
}

# MySQL Secret for Performance
resource "kubernetes_secret" "perf_mysql_credentials" {
  metadata {
    name      = "mysql-perf-secret"
    namespace = kubernetes_namespace.perf.metadata[0].name
  }

  data = {
    mysql-password = base64encode(random_password.db_password.result)
    mysql-host     = google_sql_database_instance.perf_mysql.private_ip_address
    mysql-port     = "3306"
    mysql-database = google_sql_database.perf_database.name
    mysql-user     = google_sql_user.perf_user.name
  }

  type = "Opaque"
}

# Redis Secret for Performance
resource "kubernetes_secret" "perf_redis_credentials" {
  metadata {
    name      = "redis-perf-secret"
    namespace = kubernetes_namespace.perf.metadata[0].name
  }

  data = {
    redis-password = base64encode(google_redis_instance.perf_redis.auth_string)
    redis-host     = google_redis_instance.perf_redis.host
    redis-port     = tostring(google_redis_instance.perf_redis.port)
  }

  type = "Opaque"
}

# ConfigMap with connection information
resource "kubernetes_config_map" "perf_database_config" {
  metadata {
    name      = "database-connection-perf"
    namespace = kubernetes_namespace.perf.metadata[0].name
  }

  data = {
    mysql-host     = google_sql_database_instance.perf_mysql.private_ip_address
    mysql-port     = "3306"
    mysql-database = google_sql_database.perf_database.name
    mysql-user     = google_sql_user.perf_user.name
    redis-host     = google_redis_instance.perf_redis.host
    redis-port     = tostring(google_redis_instance.perf_redis.port)
  }
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "mysql_instance_name" {
  description = "The name of the MySQL instance"
  value       = google_sql_database_instance.perf_mysql.name
}

output "mysql_private_ip" {
  description = "The private IP address of the MySQL instance"
  value       = google_sql_database_instance.perf_mysql.private_ip_address
}

output "mysql_connection_name" {
  description = "The connection name of the MySQL instance"
  value       = google_sql_database_instance.perf_mysql.connection_name
}

output "mysql_database_name" {
  description = "The name of the MySQL database"
  value       = google_sql_database.perf_database.name
}

output "mysql_user" {
  description = "The MySQL user"
  value       = google_sql_user.perf_user.name
}

output "mysql_password" {
  description = "The MySQL user password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "redis_host" {
  description = "The Redis host"
  value       = google_redis_instance.perf_redis.host
}

output "redis_port" {
  description = "The Redis port"
  value       = google_redis_instance.perf_redis.port
}

output "redis_auth_string" {
  description = "The Redis auth string"
  value       = google_redis_instance.perf_redis.auth_string
  sensitive   = true
}

output "vpc_network" {
  description = "The VPC network being used"
  value       = data.google_compute_network.dev_vpc.name
}

output "gke_cluster" {
  description = "The GKE cluster being used"
  value       = data.google_container_cluster.dev_cluster.name
}

output "namespace" {
  description = "The Kubernetes namespace for Performance resources"
  value       = kubernetes_namespace.perf.metadata[0].name
}

# Secret Manager outputs
output "secret_manager_service_account" {
  description = "The Secret Manager service account email"
  value       = google_service_account.perf_secret_manager_sa.email
}

output "mysql_secret_name" {
  description = "The name of the MySQL password secret in Secret Manager"
  value       = google_secret_manager_secret.perf_mysql_password.secret_id
}

output "redis_secret_name" {
  description = "The name of the Redis auth secret in Secret Manager"
  value       = google_secret_manager_secret.perf_redis_auth.secret_id
}

output "app_config_secret_name" {
  description = "The name of the application config secret in Secret Manager"
  value       = google_secret_manager_secret.perf_app_config.secret_id
}