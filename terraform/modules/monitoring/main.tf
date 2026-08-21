############################################
# Notification channels
############################################

resource "google_monitoring_notification_channel" "email" {
  display_name = "${var.name_prefix} email alerts"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_notification_channel" "gchat" {
  display_name = "${var.name_prefix} Google Chat warnings"
  type         = "webhook_tokenauth"
  # For webhook_tokenauth channels, the Monitoring API only accepts a
  # single "url" label - there's no separate auth_token label. The
  # webhook URL itself already carries its auth token in the query
  # string (...&token=...), so nothing needs to be split out. The URL
  # is still sensitive as a whole - keep passing it in via a TF_VAR /
  # CI secret, never commit it in a .tfvars file.
  labels = {
    url = var.google_chat_webhook_url
  }
}

############################################
# Log-based metric - counts 5xx application errors from Cloud Run logs.
# Gives us an app-level signal in addition to raw CPU/memory.
############################################

resource "google_logging_metric" "error_count" {
  name   = "${var.name_prefix}-5xx-errors"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="${var.cloud_run_service_name}"
    httpRequest.status>=500
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

############################################
# CPU alert policy
# - >70% for one datapoint -> WARNING -> Google Chat
# - >80% sustained across subsequent datapoints -> CRITICAL -> email
#
# Note: run.googleapis.com/container/cpu/utilizations (and the memory
# equivalent below) are DISTRIBUTION-valued, DELTA-kind metrics (a
# histogram per sampling interval, not a single scalar) - ALIGN_MEAN
# doesn't apply to distributions and Google's API rejects it outright.
# ALIGN_PERCENTILE_99 is the standard aligner for these metrics, and
# arguably the more correct choice for alerting anyway: it captures
# spikes an average would smooth over.
############################################

resource "google_monitoring_alert_policy" "cpu_warning" {
  display_name = "${var.name_prefix} Cloud Run CPU > 70% (warning)"
  combiner      = "OR"
  severity      = "WARNING"

  conditions {
    display_name = "CPU utilization > 70%"
    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_revision"
        AND resource.labels.service_name = "${var.cloud_run_service_name}"
        AND metric.type = "run.googleapis.com/container/cpu/utilizations"
      EOT
      comparison      = "COMPARISON_GT"
      threshold_value = 0.70
      duration        = "0s" # fire on first datapoint above threshold
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.gchat.id]

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "cpu_critical" {
  display_name = "${var.name_prefix} Cloud Run CPU > 80% sustained (critical)"
  combiner      = "OR"
  severity      = "CRITICAL"

  conditions {
    display_name = "CPU utilization > 80% for 3 consecutive datapoints"
    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_revision"
        AND resource.labels.service_name = "${var.cloud_run_service_name}"
        AND metric.type = "run.googleapis.com/container/cpu/utilizations"
      EOT
      comparison      = "COMPARISON_GT"
      threshold_value = 0.80
      # duration + trigger.count together enforce "subsequent datapoints",
      # not just a single spike, before escalating to email.
      duration = "180s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
      trigger {
        count = 3
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    auto_close = "1800s"
  }
}

############################################
# Memory alert policy - same 70%/80% pattern
############################################

resource "google_monitoring_alert_policy" "memory_warning" {
  display_name = "${var.name_prefix} Cloud Run memory > 70% (warning)"
  combiner      = "OR"
  severity      = "WARNING"

  conditions {
    display_name = "Memory utilization > 70%"
    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_revision"
        AND resource.labels.service_name = "${var.cloud_run_service_name}"
        AND metric.type = "run.googleapis.com/container/memory/utilizations"
      EOT
      comparison      = "COMPARISON_GT"
      threshold_value = 0.70
      duration        = "0s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.gchat.id]

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "memory_critical" {
  display_name = "${var.name_prefix} Cloud Run memory > 80% sustained (critical)"
  combiner      = "OR"
  severity      = "CRITICAL"

  conditions {
    display_name = "Memory utilization > 80% for 3 consecutive datapoints"
    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_revision"
        AND resource.labels.service_name = "${var.cloud_run_service_name}"
        AND metric.type = "run.googleapis.com/container/memory/utilizations"
      EOT
      comparison      = "COMPARISON_GT"
      threshold_value = 0.80
      duration        = "180s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
      trigger {
        count = 3
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    auto_close = "1800s"
  }
}