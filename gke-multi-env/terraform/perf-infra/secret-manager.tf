# ==============================================================================
# SECRET MANAGER FOR PERFORMANCE ENVIRONMENT
# ==============================================================================

# Enable Secret Manager API (should already be enabled from dev, but ensuring)
resource "google_project_service" "secret_manager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Service Account for Performance Secret Manager access
resource "google_service_account" "perf_secret_manager_sa" {
  account_id   = "perf-secret-manager-sa"
  display_name = "Performance Secret Manager Service Account"
}

# Reference to dev backend service account
data "google_service_account" "dev_backend_sa" {
  account_id = "kaia-dex-backend-sa"
  project    = var.project_id
}

# Grant dev backend SA Workload Identity for Performance namespace
resource "google_service_account_iam_member" "dev_backend_sa_workload_identity_perf" {
  service_account_id = data.google_service_account.dev_backend_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[kaia-dex-perf/kaia-dex-backend-perf]"
}

# IAM binding for Secret Manager access
resource "google_project_iam_member" "perf_secret_manager_sa_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.perf_secret_manager_sa.email}"
}

# Workload Identity binding for Kubernetes
resource "google_service_account_iam_member" "perf_secret_manager_workload_identity" {
  service_account_id = google_service_account.perf_secret_manager_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[kaia-dex-perf/perf-secret-manager-sa]"
}

# Performance MySQL password secret
resource "google_secret_manager_secret" "perf_mysql_password" {
  secret_id = "perf-mysql-password"

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

# Grant dev backend SA access to Performance MySQL password
resource "google_secret_manager_secret_iam_member" "perf_mysql_password_dev_sa_access" {
  secret_id = google_secret_manager_secret.perf_mysql_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:kaia-dex-backend-sa@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_secret_manager_secret_version" "perf_mysql_password" {
  secret      = google_secret_manager_secret.perf_mysql_password.id
  secret_data = random_password.db_password.result
}

# Performance Redis auth string secret
resource "google_secret_manager_secret" "perf_redis_auth" {
  secret_id = "perf-redis-auth"

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

# Grant dev backend SA access to Performance Redis auth
resource "google_secret_manager_secret_iam_member" "perf_redis_auth_dev_sa_access" {
  secret_id = google_secret_manager_secret.perf_redis_auth.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:kaia-dex-backend-sa@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_secret_manager_secret_version" "perf_redis_auth" {
  secret      = google_secret_manager_secret.perf_redis_auth.id
  secret_data = google_redis_instance.perf_redis.auth_string
}

# Performance Application configuration secret (combined JSON)
resource "google_secret_manager_secret" "perf_app_config" {
  secret_id = "perf-app-config"

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

# Grant dev backend SA access to Performance app config
resource "google_secret_manager_secret_iam_member" "perf_app_config_dev_sa_access" {
  secret_id = google_secret_manager_secret.perf_app_config.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:kaia-dex-backend-sa@${var.project_id}.iam.gserviceaccount.com"
}

# Create JSON configuration with all secrets
locals {
  perf_app_config_json = jsonencode({
    rw_db_dsn        = "${google_sql_user.perf_user.name}:${random_password.db_password.result}@tcp(${google_sql_database_instance.perf_mysql.private_ip_address}:3306)/${google_sql_database.perf_database.name}?parseTime=true"
    ro_db_dsn        = "${google_sql_user.perf_user.name}:${random_password.db_password.result}@tcp(${google_sql_database_instance.perf_mysql.private_ip_address}:3306)/${google_sql_database.perf_database.name}?parseTime=true"
    kaiascan_api_key = lookup(var.application_secrets, "kaiascan_api_key", "")
    auth_sign_key    = lookup(var.application_secrets, "auth_sign_key", "")
    crypto_key       = lookup(var.application_secrets, "crypto_key", "")
    redis_host       = "${google_redis_instance.perf_redis.host}:6379"
    redis_password   = google_redis_instance.perf_redis.auth_string
  })
}

resource "google_secret_manager_secret_version" "perf_app_config" {
  secret      = google_secret_manager_secret.perf_app_config.id
  secret_data = local.perf_app_config_json
}

# Kubernetes Service Account for Secret Manager in Performance namespace
resource "kubernetes_service_account" "perf_secret_manager" {
  metadata {
    name      = "perf-secret-manager-sa"
    namespace = kubernetes_namespace.perf.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.perf_secret_manager_sa.email
    }
  }
}

# Secret Provider Class for Performance - commented out until CSI driver is installed
# resource "kubernetes_manifest" "perf_secret_provider_class" {
#   manifest = {
#     apiVersion = "secrets-store.csi.x-k8s.io/v1"
#     kind       = "SecretProviderClass"
#     metadata = {
#       name      = "perf-app-config-provider"
#       namespace = kubernetes_namespace.perf.metadata[0].name
#     }
#     spec = {
#       provider = "gcp"
#       parameters = {
#         secrets = "name=\"perf-app-config\";version=\"latest\"|name=\"perf-mysql-password\";version=\"latest\"|name=\"perf-redis-auth\";version=\"latest\""
#       }
#       secretObjects = [{
#         secretName = "app-config"
#         type       = "Opaque"
#         data = [
#           {
#             objectName = "perf-app-config"
#             key        = "config.json"
#           },
#           {
#             objectName = "perf-mysql-password"
#             key        = "mysql-password"
#           },
#           {
#             objectName = "perf-redis-auth"
#             key        = "redis-password"
#           }
#         ]
#       }]
#     }
#   }
# }