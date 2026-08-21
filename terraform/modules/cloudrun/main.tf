resource "google_cloud_run_v2_service" "service" {
  name     = "${var.name_prefix}-svc"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL" # switch to INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER for internal-only

  template {
    service_account = var.runtime_service_account_email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    vpc_access {
      connector = var.vpc_connector_id
      # PRIVATE_RANGES_ONLY: only traffic destined for RFC1918 ranges
      # (i.e. Cloud SQL private IP) goes through the connector. General
      # internet egress from the app still goes out normally, cheaper
      # and simpler than routing ALL traffic through the connector.
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.container_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
        cpu_idle = true
      }

      env {
        name  = "DB_HOST"
        value = var.db_private_ip
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_SSL"
        value = "true"
      }

      # Secrets pulled directly from Secret Manager by Cloud Run at
      # container start - never written into the image, repo, or CI logs.
      env {
        name = "DB_USER"
        value_source {
          secret_key_ref {
            secret  = var.db_user_secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = var.db_password_secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 2
        period_seconds         = 5
        failure_threshold      = 5
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds = 15
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # lifecycle {
  #   ignore_changes = all
  # }
}

# Who can invoke the service. Default: require authentication (no
# "allUsers" invoker binding). Flip var.allow_unauthenticated only for a
# demo/interview walkthrough, never as the real-world default.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  count    = var.allow_unauthenticated ? 1 : 0
  name     = google_cloud_run_v2_service.service.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
