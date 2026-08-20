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
