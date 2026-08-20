variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "name_prefix" {
  description = "Short prefix applied to all resource names, e.g. 'nodeapp'"
  type        = string
  default     = "nodeapp"
}

variable "github_repo" {
  description = "GitHub repo allowed to use Workload Identity Federation, 'owner/repo'"
  type        = string
}

variable "container_image" {
  description = "Full Artifact Registry image reference, e.g. asia-south1-docker.pkg.dev/PROJECT/nodeapp-repo/api:latest"
  type        = string
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 5
}

variable "allow_unauthenticated" {
  description = "Whether the Cloud Run service allows public unauthenticated access"
  type        = bool
  default     = false
}

variable "sql_deletion_protection" {
  type    = bool
  default = true
}

variable "alert_email" {
  description = "Recipient for critical (>80% sustained) alerts"
  type        = string
}

variable "google_chat_webhook_url" {
  description = "Google Chat webhook for warning (>70%) alerts"
  type        = string
  sensitive   = true
}
