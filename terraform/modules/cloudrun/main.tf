resource "google_cloud_run_v2_service" "service" {
  name     = "${var.name_prefix}-svc"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL" # switch to INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER for internal-only

  # Provider v6+ defaults this to true, which blocks `terraform destroy`
  # or forced replacement. Set to true for a real production service so
  # a stray destroy/apply can't silently drop it; left false here since
  # this module is actively being iterated on for a demo/interview build.

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
      env {
        name = "DB_SSL_CA"
        value_source {
          secret_key_ref {
            secret  = var.db_ssl_ca_secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 2
        period_seconds        = 5
        failure_threshold     = 5
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

  # cd.yml deploys new images directly via `gcloud run deploy`, bypassing
  # Terraform entirely, so the live image is always ahead of whatever
  # container_image this module was last applied with (often the
  # PLACEHOLDER_IMAGE used for `terraform plan` in CI). Without this,
  # every terraform apply would try to roll the service back to that
  # placeholder. client/client_version are read-only bookkeeping fields
  # that flip between "gcloud" and "terraform" depending on whichever
  # tool last touched the resource - ignored for the same reason.
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].containers[0].image,
    ]
  }
}

# One-shot schema migration job. Reuses the exact same image as the
# service (app/scripts/migrate.js), just with the command overridden.
# cd.yml updates this job's image and executes it (--wait) BEFORE
# deploying the new service revision, so traffic never hits a revision
# whose schema expectations haven't been applied yet.
resource "google_cloud_run_v2_job" "migrate" {
  name     = "${var.name_prefix}-migrate"
  location = var.region

  template {
    template {
      service_account = var.runtime_service_account_email
      max_retries     = 1
      timeout         = "120s"

      vpc_access {
        connector = var.vpc_connector_id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image   = var.container_image
        command = ["node"]
        args    = ["scripts/migrate.js"]

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
        env {
          name = "DB_SSL_CA"
          value_source {
            secret_key_ref {
              secret  = var.db_ssl_ca_secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  # See the ignore_changes note on google_cloud_run_v2_service.service
  # above - cd.yml updates this job's image directly too.
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].template[0].containers[0].image,
    ]
  }
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