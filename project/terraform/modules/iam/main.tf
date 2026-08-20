############################################
# Runtime service account - identity Cloud Run actually runs as.
# Only what the APP needs at runtime: read specific secrets + connect
# to Cloud SQL via the private network (no Cloud SQL Admin API needed
# since we use private IP, not the Cloud SQL Auth Proxy).
############################################

resource "google_service_account" "runtime" {
  account_id   = "${var.name_prefix}-run-sa"
  display_name = "Cloud Run runtime SA - ${var.name_prefix}"
}

# Custom role instead of a broad predefined role: only the specific
# secret-read permission the app needs.
resource "google_project_iam_custom_role" "secret_reader" {
  role_id     = "${replace(var.name_prefix, "-", "_")}_secretReader"
  title       = "${var.name_prefix} minimal secret reader"
  description = "Read-only access to Secret Manager secret versions"
  permissions = [
    "secretmanager.versions.access",
    "secretmanager.secrets.get",
  ]
}

resource "google_project_iam_member" "runtime_secret_role" {
  project = var.project_id
  role    = google_project_iam_custom_role.secret_reader.id
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

# Cloud Trace / structured logging from the app itself (writing app logs
# via stdout is auto-collected by Cloud Run without extra IAM, but if the
# app ever writes custom log entries via the API this is needed).
resource "google_project_iam_member" "runtime_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "runtime_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

############################################
# CI/CD deployer service account - used ONLY by GitHub Actions,
# authenticated via Workload Identity Federation (no JSON key file).
############################################

resource "google_service_account" "deployer" {
  account_id   = "${var.name_prefix}-deployer"
  display_name = "GitHub Actions deployer - ${var.name_prefix}"
}

resource "google_project_iam_custom_role" "deployer_role" {
  role_id     = "${replace(var.name_prefix, "-", "_")}_deployer"
  title       = "${var.name_prefix} CI/CD deployer"
  description = "Minimal permissions to push images and deploy the Cloud Run revision"
  permissions = [
    "run.services.get",
    "run.services.update",
    "run.services.create",
    "run.routes.invoke",
    "artifactregistry.repositories.uploadArtifacts",
    "artifactregistry.repositories.downloadArtifacts",
    "artifactregistry.tags.create",
    "artifactregistry.tags.list",
  ]
}

resource "google_project_iam_member" "deployer_role_binding" {
  project = var.project_id
  role    = google_project_iam_custom_role.deployer_role.id
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# The deployer needs to "actAs" the runtime SA to deploy a Cloud Run
# revision that runs as that SA - scoped to that one SA only, not
# project-wide serviceAccountUser.
resource "google_service_account_iam_member" "deployer_can_actas_runtime" {
  service_account_id = google_service_account.runtime.name
  role                = "roles/iam.serviceAccountUser"
  member              = "serviceAccount:${google_service_account.deployer.email}"
}

############################################
# Workload Identity Federation - GitHub Actions -> GCP, no JSON keys.
############################################

resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "${var.name_prefix}-gh-pool"
  display_name              = "GitHub Actions pool"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id         = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.name_prefix}-gh-provider"
  display_name                       = "GitHub OIDC provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Restrict to only this repo, and (recommended) only the default branch,
  # so a fork or unrelated repo can never mint a token for this identity.
  attribute_condition = "assertion.repository == '${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.deployer.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}
