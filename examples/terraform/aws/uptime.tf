resource "aws_route53_health_check" "bugsink" {
  fqdn              = var.dashboard_host
  port              = 443
  type              = "HTTPS"
  resource_path     = "/accounts/login/"
  request_interval  = 30
  failure_threshold = 2
  measure_latency   = true

  tags = { Name = "${var.name}-dashboard" }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

# Slack webhook via a tiny Lambda subscriber.
# In practice, use AWS Chatbot / a dedicated Slack app for richer messages.
# Minimal version here assumes you've deployed a webhook-forwarder Lambda separately.
# Alternatively, subscribe an HTTPS endpoint directly — but raw SNS → Slack is ugly.
resource "aws_sns_topic_subscription" "slack" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
  # NOTE: Slack webhooks don't follow the SNS subscription confirmation flow.
  # Use a Lambda forwarder in production; this raw subscription is for reference only.
}

resource "aws_cloudwatch_metric_alarm" "bugsink_down" {
  alarm_name          = "${var.name}-dashboard-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = <<-EOT
    BugSink dashboard DOWN (${var.dashboard_host})

    Triage:
    1. kubectl get pod -n ${var.k8s_namespace}
    2. kubectl logs -n ${var.k8s_namespace} bugsink-0 -c bugsink --tail=50
    3. kubectl describe ingress -n ${var.k8s_namespace}
    4. curl https://${var.dashboard_host}/accounts/login/
    5. Check recent helm deploys
  EOT

  dimensions = {
    HealthCheckId = aws_route53_health_check.bugsink.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  treat_missing_data = "breaching"
}
