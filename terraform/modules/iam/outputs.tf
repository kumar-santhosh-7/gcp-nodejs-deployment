output "runtime_sa_email" {
  value = google_service_account.runtime.email
}

output "deployer_sa_email" {
  value = google_service_account.deployer.email
}

output "workload_identity_provider" {
  description = "Full resource name to put in the GitHub Actions google-github-actions/auth step"
  value       = google_iam_workload_identity_pool_provider.github_provider.name
}
