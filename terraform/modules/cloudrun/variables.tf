variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "container_image" {
  description = "Full Artifact Registry image path incl. tag/digest"
  type        = string
}

variable "runtime_service_account_email" {
  type = string
}

variable "vpc_connector_id" {
  type = string
}

variable "db_private_ip" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user_secret_id" {
  type = string
}

variable "db_password_secret_id" {
  type = string
}

variable "db_ssl_ca_secret_id" {
  type = string
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 5
}

variable "cpu_limit" {
  type    = string
  default = "1"
}

variable "memory_limit" {
  type    = string
  default = "512Mi"
}

variable "allow_unauthenticated" {
  type    = bool
  default = false
}