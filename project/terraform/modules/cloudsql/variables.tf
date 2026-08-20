variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  description = "Self link / id of the VPC to attach the private IP to"
  type        = string
}

variable "private_vpc_connection" {
  description = "The google_service_networking_connection resource id this depends on"
  type        = any
}

variable "database_version" {
  type    = string
  default = "POSTGRES_15"
}

variable "tier" {
  description = "Machine tier. Use a small tier for dev/interview demo purposes."
  type        = string
  default     = "db-custom-1-3840"
}

variable "availability_type" {
  type    = string
  default = "ZONAL" # use "REGIONAL" for HA in real production
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_user" {
  type    = string
  default = "app_user"
}
