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

variable "runtime_service_account_email" {
  description = "Cloud Run runtime service account that is allowed to read these secrets"
  type        = string
}
