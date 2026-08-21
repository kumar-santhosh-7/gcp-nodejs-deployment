resource "random_id" "suffix" {
  byte_length = 3
}

resource "google_sql_database_instance" "instance" {
  # Note: trivy's google-sql-encrypt-in-transit-data check currently only
  # recognizes the legacy `require_ssl` boolean, not the newer `ssl_mode`
  # attribute used below in ip_configuration - this is a known ruleset gap
  # (see aquasecurity/trivy discussion #6646), not a real finding. Google's
  # own docs recommend setting ssl_mode alone going forward and NOT setting
  # require_ssl alongside it. Trivy associates this check with the whole
  # resource block, so the ignore comment has to live here, not nested
  # next to ssl_mode itself.
  # trivy:ignore:google-sql-encrypt-in-transit-data
  name             = "${var.name_prefix}-pg-${random_id.suffix.hex}"
  database_version = var.database_version
  region           = var.region

  # Prevents `terraform destroy` from silently dropping the DB in prod.
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_autoresize   = true
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = 7
    }

    ip_configuration {
      # No public IP. The instance is only reachable over the private
      # VPC peering established by google_service_networking_connection.
      ipv4_enabled    = false
      private_network = var.vpc_id
      # Require SSL/TLS even on private connections as defense in depth.
      ssl_mode = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    # Additional Postgres audit/diagnostic logging flags - closes out
    # the remaining trivy findings on this instance (checkpoint, lock
    # wait, disconnection, and temp file logging).
    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "log_temp_files"
      value = "0"
    }

    maintenance_window {
      day  = 7 # Sunday
      hour = 3
    }
  }

  depends_on = [var.private_vpc_connection]
}

resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.instance.name
}

# Application DB user. Password is generated here and pushed to Secret
# Manager by the secrets module - it is never written to state as a
# plain output and never appears in CI/CD logs.
resource "random_password" "db_password" {
  length  = 24
  special = true
  # Avoid characters that commonly need escaping in connection strings /
  # shell contexts.
  override_special = "_-!#%^&*()+="
}

resource "google_sql_user" "app_user" {
  name     = var.db_user
  instance = google_sql_database_instance.instance.name
  password = random_password.db_password.result
}