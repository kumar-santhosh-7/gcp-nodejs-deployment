output "cloud_run_url" {
  value = module.cloudrun.service_url
}

output "workload_identity_provider" {
  value = module.iam.workload_identity_provider
}

output "deployer_sa_email" {
  value = module.iam.deployer_sa_email
}

output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}"
}

output "cloudsql_instance_connection_name" {
  value = module.cloudsql.connection_name
}
