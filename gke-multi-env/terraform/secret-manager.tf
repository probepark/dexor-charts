# ==============================================================================
# SECRET MANAGER CONFIGURATION
# ==============================================================================

# Enable Secret Manager API
resource "google_project_service" "secret_manager" {
  count              = var.enable_secret_manager ? 1 : 0
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Service Account for Secret Manager access
resource "google_service_account" "secret_manager_sa" {
  count        = var.enable_secret_manager ? 1 : 0
  account_id   = "${var.environment}-secret-manager-sa"
  display_name = "${var.environment} Secret Manager Service Account"
}

# IAM binding for Secret Manager access
resource "google_project_iam_member" "secret_manager_sa_accessor" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.secret_manager_sa[0].email}"
}

# Workload Identity binding for Kubernetes
resource "google_service_account_iam_member" "secret_manager_workload_identity" {
  count              = var.enable_secret_manager ? 1 : 0
  service_account_id = google_service_account.secret_manager_sa[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/secret-manager-sa]"
}

# Database password secret
resource "google_secret_manager_secret" "db_password" {
  count     = var.enable_cloud_sql && var.enable_secret_manager ? 1 : 0
  secret_id = "${var.environment}-mysql-password"

  labels = merge(local.common_labels, {
    type = "database"
  })

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.secret_manager]
}

resource "google_secret_manager_secret_version" "db_password" {
  count       = var.enable_cloud_sql && var.enable_secret_manager ? 1 : 0
  secret      = google_secret_manager_secret.db_password[0].id
  secret_data = random_password.db_password[0].result
}

# Redis auth string secret
resource "google_secret_manager_secret" "redis_auth" {
  count     = var.enable_redis && var.enable_secret_manager && local.config.redis_auth_enabled ? 1 : 0
  secret_id = "${var.environment}-redis-auth"

  labels = merge(local.common_labels, {
    type = "cache"
  })

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.secret_manager]
}

resource "google_secret_manager_secret_version" "redis_auth" {
  count       = var.enable_redis && var.enable_secret_manager && local.config.redis_auth_enabled ? 1 : 0
  secret      = google_secret_manager_secret.redis_auth[0].id
  secret_data = google_redis_instance.redis[0].auth_string
}

# Application configuration secret (combined JSON)
resource "google_secret_manager_secret" "app_config" {
  count     = var.enable_secret_manager ? 1 : 0
  secret_id = "${var.environment}-app-config"

  labels = merge(local.common_labels, {
    type = "application"
  })

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.secret_manager]
}

# Create JSON configuration with all secrets
locals {
  app_config_json = var.enable_secret_manager ? jsonencode({
    rw_db_dsn        = var.enable_cloud_sql ? "mysql://${var.db_user}:${random_password.db_password[0].result}@${google_sql_database_instance.mysql[0].private_ip_address}:3306/${var.db_name}" : ""
    ro_db_dsn        = var.enable_cloud_sql ? "mysql://${var.db_user}:${random_password.db_password[0].result}@${google_sql_database_instance.mysql[0].private_ip_address}:3306/${var.db_name}" : ""
    kaiascan_api_key = lookup(var.application_secrets, "kaiascan_api_key", "")
    auth_sign_key    = lookup(var.application_secrets, "auth_sign_key", "")
    crypto_key       = lookup(var.application_secrets, "crypto_key", "")
    redis_host       = var.enable_redis ? google_redis_instance.redis[0].host : ""
    redis_password   = var.enable_redis && local.config.redis_auth_enabled ? google_redis_instance.redis[0].auth_string : ""
  }) : "{}"
}

resource "google_secret_manager_secret_version" "app_config" {
  count       = var.enable_secret_manager ? 1 : 0
  secret      = google_secret_manager_secret.app_config[0].id
  secret_data = local.app_config_json
}

# ArgoCD admin password secret (keeping for ArgoCD management)
resource "random_password" "argocd_admin_password" {
  count   = var.enable_secret_manager ? 1 : 0
  length  = 16
  special = true
}

resource "google_secret_manager_secret" "argocd_admin_password" {
  count     = var.enable_secret_manager ? 1 : 0
  secret_id = "${var.environment}-argocd-admin-password"

  labels = merge(local.common_labels, {
    type = "infrastructure"
  })

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.secret_manager]
}

resource "google_secret_manager_secret_version" "argocd_admin_password" {
  count       = var.enable_secret_manager ? 1 : 0
  secret      = google_secret_manager_secret.argocd_admin_password[0].id
  secret_data = random_password.argocd_admin_password[0].result
}

# Kubernetes Service Account for Secret Manager
resource "kubernetes_service_account" "secret_manager" {
  count = var.enable_secret_manager ? 1 : 0
  metadata {
    name      = "secret-manager-sa"
    namespace = "default"
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.secret_manager_sa[0].email
    }
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Secret Manager CSI Driver configuration
resource "kubernetes_secret" "secret_manager_csi" {
  count = var.enable_secret_manager_csi && var.enable_secret_manager ? 1 : 0

  metadata {
    name      = "secret-manager-csi"
    namespace = "kube-system"
  }

  data = {
    "app-config-provider.yaml" = yamlencode({
      apiVersion = "secrets-store.csi.x-k8s.io/v1"
      kind       = "SecretProviderClass"
      metadata = {
        name      = "${var.environment}-app-config-provider"
        namespace = "default"
      }
      spec = {
        provider = "gcp"
        parameters = {
          secrets = "name=\"${var.environment}-app-config\";version=\"latest\""
        }
        secretObjects = [{
          secretName = "app-config"
          type       = "Opaque"
          data = [{
            objectName = "${var.environment}-app-config"
            key        = "config.json"
          }]
        }]
      }
    })
  }

  depends_on = [google_container_node_pool.primary_nodes]
}