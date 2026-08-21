output "service_url" {
  value = google_cloud_run_v2_service.service.uri
}

output "service_name" {
  value = google_cloud_run_v2_service.service.name
}

output "migrate_job_name" {
  value = google_cloud_run_v2_job.migrate.name
}