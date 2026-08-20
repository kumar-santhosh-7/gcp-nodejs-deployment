variable "name_prefix" {
  description = "Prefix used for all network resource names"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR range for the primary subnet"
  type        = string
  default     = "10.10.0.0/20"
}

variable "connector_cidr" {
  description = "CIDR range (/28) for the Serverless VPC Access connector"
  type        = string
  default     = "10.10.16.0/28"
}
