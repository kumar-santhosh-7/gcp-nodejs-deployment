output "email_channel_id" {
  value = google_monitoring_notification_channel.email.id
}

output "gchat_channel_id" {
  value = google_monitoring_notification_channel.gchat.id
}
