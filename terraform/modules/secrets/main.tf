locals {
  secrets = {
    db_user        = var.db_user
    db_password    = var.db_password
    db_name        = var.db_name
    db_ssl_ca_cert = var.db_ssl_ca_cert
  }
}

resource "google_secret_manager_secret" "secret" {
  for_each  = local.secrets
  secret_id = "${var.name_prefix}-${each.key}"

  replication {
    auto {}
  }

  labels = {
    app = var.name_prefix
  }
}

resource "google_secret_manager_secret_version" "secret_version" {
  for_each    = local.secrets
  secret      = google_secret_manager_secret.secret[each.key].id
  secret_data = each.value
}

# Least privilege: only the runtime service account may READ these
# secret values. No broad "Secret Manager Admin" grants anywhere.
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each  = local.secrets
  secret_id = google_secret_manager_secret.secret[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.runtime_service_account_email}"
}