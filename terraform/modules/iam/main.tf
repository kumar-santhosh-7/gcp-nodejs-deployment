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

# No logging.logWriter / monitoring.metricWriter grant here: the app only
# ever logs via stdout (pino), which Cloud Run's own logging agent
# collects automatically without any IAM grant on the runtime SA. Those
# two roles would only be needed if the app called the Logging/Monitoring
# APIs directly - add them then, not preemptively.

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
  description = "Minimal permissions to push images, deploy the Cloud Run revision, and run the migration job"
  permissions = [
    "run.services.get",
    "run.services.update",
    "run.services.create",
    "run.routes.invoke",
    "run.jobs.get",
    "run.jobs.update",
    "run.jobs.run",
    "run.executions.get",
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
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}

############################################
# `deployer` also runs terraform-apply.yml (plan/apply for network,
# Cloud SQL, Secret Manager, IAM, and monitoring), in addition to
# cd.yml's routine image deploys. That means this single identity now
# needs much more than run.*/artifactregistry.* - the roles below add
# what Terraform needs for the rest of the module set. This is a
# deliberate simplicity-over-separation trade-off: because cd.yml's
# automatic, workflow_run-triggered deploy uses the exact same SA,
# anything that can trigger CD now sits behind an identity that can
# also touch networking, IAM, and Secret Manager - a compromise of the
# CD path is a compromise of these permissions too. A stricter posture
# would give terraform-apply.yml its own, separate identity instead;
# see git history for that version if you want to revisit it.
#
# Scoped predefined roles rather than one hand-rolled custom role: GCP
# custom roles require exact permission strings (no wildcards), so
# enumerating every permission this many resource types need by hand
# would be fragile to keep correct as the module grows. Each role below
# is scoped to a single GCP service and none of them is a primitive
# Owner/Editor/Viewer role.
#
# One predefined role per GCP service this Terraform config manages:
# compute.networkAdmin (VPC/subnet/firewall/global address), vpcaccess.admin
# (Serverless VPC Access connector), servicenetworking.networksAdmin
# (Private Services Access peering), cloudsql.admin (instance/database/user),
# secretmanager.admin (secrets/versions/IAM), artifactregistry.admin (repo +
# cleanup policy, on top of the narrower custom role above), run.admin
# (service + job, likewise on top of the narrower custom role),
# monitoring.alertPolicyEditor and monitoring.notificationChannelEditor
# (alert policies/channels), logging.configWriter (log-based metrics),
# iam.serviceAccountAdmin (manage the runtime/deployer SAs),
# iam.workloadIdentityPoolAdmin (WIF pool/provider), iam.roleAdmin (the
# custom secretReader/deployer roles), resourcemanager.projectIamAdmin
# (bind those roles at project level), and serviceusage.serviceUsageAdmin
# (enable required APIs).
############################################

locals {
  deployer_infra_roles = [
    "roles/compute.networkAdmin",
    "roles/vpcaccess.admin",
    "roles/servicenetworking.networksAdmin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/artifactregistry.admin",
    "roles/run.admin",
    "roles/monitoring.alertPolicyEditor",
    "roles/monitoring.notificationChannelEditor",
    "roles/logging.configWriter",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/iam.roleAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
  ]
}

resource "google_project_iam_member" "deployer_infra_roles" {
  for_each = toset(local.deployer_infra_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

# Terraform state itself lives in a GCS bucket created manually (see
# environments/prod/backend.tf), outside this config. Grant access to
# ONLY that bucket rather than a project-wide storage role, so this SA
# can't read/write any other bucket in the project.
resource "google_storage_bucket_iam_member" "deployer_state_bucket" {
  bucket = var.state_bucket_name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.deployer.email}"
}

############################################
# Workload Identity Federation - GitHub Actions -> GCP, no JSON keys.
############################################

resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "${var.name_prefix}-gh-pool"
  display_name              = "GitHub Actions pool"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
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
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}