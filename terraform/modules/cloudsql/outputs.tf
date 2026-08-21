output "instance_name" {
  value = google_sql_database_instance.instance.name
}

output "private_ip_address" {
  value = google_sql_database_instance.instance.private_ip_address
}

output "connection_name" {
  value = google_sql_database_instance.instance.connection_name
}

output "db_name" {
  value = google_sql_database.database.name
}

output "db_user" {
  value = google_sql_user.app_user.name
}

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}

# The instance's own server CA certificate (PEM), used by the app to
# verify Cloud SQL's TLS identity instead of disabling verification
# outright. server_ca_cert is a computed attribute the provider
# populates automatically once the instance exists - not something we
# set ourselves.
output "server_ca_cert" {
  value     = google_sql_database_instance.instance.server_ca_cert[0].cert
  sensitive = true
}