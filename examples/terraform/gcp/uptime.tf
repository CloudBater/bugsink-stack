resource "google_monitoring_uptime_check_config" "bugsink" {
  display_name = "${var.name}-dashboard"
  timeout      = "10s"
  period       = "300s" # 5 minutes

  http_check {
    path           = "/accounts/login/"
    port           = 443
    use_ssl        = true
    validate_ssl   = true
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.dashboard_host
    }
  }
}

resource "google_monitoring_notification_channel" "slack" {
  display_name = "${var.name} Slack alerts"
  type         = "webhook_tokenauth"
  labels = {
    url = var.slack_webhook_url
  }
}

resource "google_monitoring_alert_policy" "bugsink_down" {
  display_name = "${var.name} dashboard DOWN"
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failed"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.bugsink.uptime_check_id}\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.project_id"]
      }
      trigger {
        count = 1
      }
    }
  }

  documentation {
    content   = <<-EOT
      BugSink dashboard is returning non-2xx or timing out.

      Triage:
      1. kubectl get pod -n ${var.k8s_namespace}
      2. kubectl logs -n ${var.k8s_namespace} bugsink-0 -c bugsink --tail=50
      3. kubectl describe ingress -n ${var.k8s_namespace}
      4. curl https://${var.dashboard_host}/accounts/login/ (from an allowlisted IP)
      5. Check recent helm deploys: helm history bugsink -n ${var.k8s_namespace}

      Common causes: empty SECRET_KEY (check ExternalSecret sync), DB unreachable,
      cert expired, Cloud Armor blocking uptime checker.
    EOT
    mime_type = "text/markdown"
  }

  notification_channels = [google_monitoring_notification_channel.slack.name]
  alert_strategy {
    auto_close = "1800s"
  }
}
