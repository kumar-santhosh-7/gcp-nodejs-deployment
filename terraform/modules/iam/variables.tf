variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "github_repo" {
  description = "GitHub repo allowed to federate, in 'owner/repo' form"
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the GCS bucket holding Terraform state (see environments/prod/backend.tf) - infra_deployer is granted access scoped to only this bucket"
  type        = string
}
