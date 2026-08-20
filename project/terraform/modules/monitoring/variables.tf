variable "name_prefix" {
  type = string
}

variable "cloud_run_service_name" {
  type = string
}

variable "alert_email" {
  description = "Email address for critical (>80% sustained) alerts"
  type        = string
}

variable "google_chat_webhook_url" {
  description = "Google Chat incoming webhook URL for warning (>70%) alerts. Pass via CI secret / TF_VAR, never commit."
  type        = string
  sensitive   = true
}
