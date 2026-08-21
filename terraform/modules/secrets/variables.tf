variable "name_prefix" {
  type = string
}

variable "db_user" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_name" {
  type = string
}

variable "db_ssl_ca_cert" {
  description = "Cloud SQL instance's server CA certificate (PEM), stored as a secret so the app can verify Cloud SQL's TLS identity"
  type        = string
  sensitive   = true
}

variable "runtime_service_account_email" {
  description = "Cloud Run runtime service account that is allowed to read these secrets"
  type        = string
}