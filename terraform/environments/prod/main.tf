terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

############################################
# Enable required APIs (idempotent, safe to re-run)
############################################

locals {
  required_apis = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each                   = toset(local.required_apis)
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

############################################
# Artifact Registry - Docker repo for the app image
############################################

resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "${var.name_prefix}-repo"
  format        = "DOCKER"
  description   = "Container images for ${var.name_prefix}"

  # Automatically clean up untagged/old images so the registry doesn't
  # silently accumulate stale, potentially-vulnerable images forever.
  cleanup_policies {
    id     = "keep-last-10-tagged"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  depends_on = [google_project_service.apis]
}

############################################
# Networking
############################################

module "network" {
  source      = "../../modules/network"
  name_prefix = var.name_prefix
  region      = var.region

  depends_on = [google_project_service.apis]
}

############################################
# IAM (deployer + runtime SAs, WIF)
############################################

module "iam" {
  source      = "../../modules/iam"
  project_id  = var.project_id
  name_prefix = var.name_prefix
  github_repo = var.github_repo

  depends_on = [google_project_service.apis]
}

############################################
# Cloud SQL (private IP only)
############################################

module "cloudsql" {
  source                 = "../../modules/cloudsql"
  name_prefix            = var.name_prefix
  region                 = var.region
  vpc_id                 = module.network.vpc_self_link
  private_vpc_connection = module.network.private_vpc_connection
  deletion_protection    = var.sql_deletion_protection
}

############################################
# Secret Manager
############################################

module "secrets" {
  source                        = "../../modules/secrets"
  name_prefix                   = var.name_prefix
  db_user                       = module.cloudsql.db_user
  db_password                   = module.cloudsql.db_password
  db_name                       = module.cloudsql.db_name
  db_ssl_ca_cert                = module.cloudsql.server_ca_cert
  runtime_service_account_email = module.iam.runtime_sa_email
}

############################################
# Cloud Run
############################################

module "cloudrun" {
  source                        = "../../modules/cloudrun"
  name_prefix                   = var.name_prefix
  region                        = var.region
  container_image               = var.container_image
  runtime_service_account_email = module.iam.runtime_sa_email
  vpc_connector_id              = module.network.connector_id
  db_private_ip                 = module.cloudsql.private_ip_address
  db_name                       = module.cloudsql.db_name
  db_user_secret_id             = module.secrets.secret_ids["db_user"]
  db_password_secret_id         = module.secrets.secret_ids["db_password"]
  db_ssl_ca_secret_id           = module.secrets.secret_ids["db_ssl_ca_cert"]
  min_instances                 = var.min_instances
  max_instances                 = var.max_instances
  allow_unauthenticated         = var.allow_unauthenticated
}

############################################
# Monitoring & alerts
############################################

module "monitoring" {
  source                  = "../../modules/monitoring"
  name_prefix             = var.name_prefix
  cloud_run_service_name  = module.cloudrun.service_name
  alert_email             = var.alert_email
  google_chat_webhook_url = var.google_chat_webhook_url
}
