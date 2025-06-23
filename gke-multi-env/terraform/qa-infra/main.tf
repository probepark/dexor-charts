terraform {
  required_version = ">= 1.0"

  backend "gcs" {
    bucket = "dexor-terraform-state"
    prefix = "terraform/qa/state"
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

variable "qa_namespace" {
  description = "Kubernetes namespace for QA resources"
  type        = string
  default     = "kaia-dex-qa"
}

variable "application_secrets" {
  description = "Map of application secrets to store in Secret Manager"
  type        = map(string)
  default     = {}
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
    environment = "qa"
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
# CLOUD SQL MYSQL FOR QA
# ==============================================================================

resource "google_sql_database_instance" "qa_mysql" {
  name             = "qa-mysql-instance"
  database_version = "MYSQL_8_4"
  region           = var.region

  settings {
    tier              = "db-g1-small"  # Basic tier for QA
    availability_type = "ZONAL"         # Single zone for QA
    disk_type         = "PD_SSD"
    disk_size         = 20              # 20GB for QA
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
      ssl_mode = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"  # QA allows both
    }

    database_flags {
      name  = "slow_query_log"
      value = "on"
    }

    database_flags {
      name  = "long_query_time"
      value = "2"
    }

    database_flags {
      name  = "max_connections"
      value = "1000"
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "canary"  # QA uses canary like dev
    }

    user_labels = local.common_labels
  }

  deletion_protection = false
}

# Cloud SQL Database
resource "google_sql_database" "qa_database" {
  name     = "kaia_orderbook_qa"
  instance = google_sql_database_instance.qa_mysql.name
}

# Cloud SQL User
resource "google_sql_user" "qa_user" {
  name     = "kaia_qa"
  instance = google_sql_database_instance.qa_mysql.name
  password = random_password.db_password.result
}

# ==============================================================================
# CLOUD MEMORYSTORE REDIS FOR QA
# ==============================================================================

resource "google_redis_instance" "qa_redis" {
  name           = "qa-redis"
  tier           = "BASIC"
  memory_size_gb = 2  # 2GB for QA
  region         = var.region

  authorized_network = data.google_compute_network.dev_vpc.id

  auth_enabled            = true
  transit_encryption_mode = "DISABLED"  # No TLS for QA

  redis_version = "REDIS_7_0"
  display_name  = "QA Redis Instance"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  labels = local.common_labels
}

# ==============================================================================
# KUBERNETES RESOURCES
# ==============================================================================

# Create QA namespace
resource "kubernetes_namespace" "qa" {
  metadata {
    name = var.qa_namespace
    labels = {
      name        = var.qa_namespace
      environment = "qa"
    }
  }
}

# MySQL Secret for QA
resource "kubernetes_secret" "qa_mysql_credentials" {
  metadata {
    name      = "mysql-qa-secret"
    namespace = kubernetes_namespace.qa.metadata[0].name
  }

  data = {
    mysql-password = base64encode(random_password.db_password.result)
    mysql-host     = google_sql_database_instance.qa_mysql.private_ip_address
    mysql-port     = "3306"
    mysql-database = google_sql_database.qa_database.name
    mysql-user     = google_sql_user.qa_user.name
  }

  type = "Opaque"
}

# Redis Secret for QA
resource "kubernetes_secret" "qa_redis_credentials" {
  metadata {
    name      = "redis-qa-secret"
    namespace = kubernetes_namespace.qa.metadata[0].name
  }

  data = {
    redis-password = base64encode(google_redis_instance.qa_redis.auth_string)
    redis-host     = google_redis_instance.qa_redis.host
    redis-port     = tostring(google_redis_instance.qa_redis.port)
  }

  type = "Opaque"
}

# ConfigMap with connection information
resource "kubernetes_config_map" "qa_database_config" {
  metadata {
    name      = "database-connection-qa"
    namespace = kubernetes_namespace.qa.metadata[0].name
  }

  data = {
    mysql-host     = google_sql_database_instance.qa_mysql.private_ip_address
    mysql-port     = "3306"
    mysql-database = google_sql_database.qa_database.name
    mysql-user     = google_sql_user.qa_user.name
    redis-host     = google_redis_instance.qa_redis.host
    redis-port     = tostring(google_redis_instance.qa_redis.port)
  }
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "mysql_instance_name" {
  description = "The name of the MySQL instance"
  value       = google_sql_database_instance.qa_mysql.name
}

output "mysql_private_ip" {
  description = "The private IP address of the MySQL instance"
  value       = google_sql_database_instance.qa_mysql.private_ip_address
}

output "mysql_connection_name" {
  description = "The connection name of the MySQL instance"
  value       = google_sql_database_instance.qa_mysql.connection_name
}

output "mysql_database_name" {
  description = "The name of the MySQL database"
  value       = google_sql_database.qa_database.name
}

output "mysql_user" {
  description = "The MySQL user"
  value       = google_sql_user.qa_user.name
}

output "mysql_password" {
  description = "The MySQL user password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "redis_host" {
  description = "The Redis host"
  value       = google_redis_instance.qa_redis.host
}

output "redis_port" {
  description = "The Redis port"
  value       = google_redis_instance.qa_redis.port
}

output "redis_auth_string" {
  description = "The Redis auth string"
  value       = google_redis_instance.qa_redis.auth_string
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
  description = "The Kubernetes namespace for QA resources"
  value       = kubernetes_namespace.qa.metadata[0].name
}

# Secret Manager outputs
output "secret_manager_service_account" {
  description = "The Secret Manager service account email"
  value       = google_service_account.qa_secret_manager_sa.email
}

output "mysql_secret_name" {
  description = "The name of the MySQL password secret in Secret Manager"
  value       = google_secret_manager_secret.qa_mysql_password.secret_id
}

output "redis_secret_name" {
  description = "The name of the Redis auth secret in Secret Manager"
  value       = google_secret_manager_secret.qa_redis_auth.secret_id
}

output "app_config_secret_name" {
  description = "The name of the application config secret in Secret Manager"
  value       = google_secret_manager_secret.qa_app_config.secret_id
}