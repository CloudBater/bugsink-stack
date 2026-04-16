resource "aws_wafv2_ip_set" "office" {
  name               = "${var.name}-office-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.office_ips
}

resource "aws_wafv2_ip_set" "cluster" {
  name               = "${var.name}-cluster-nat"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = ["${var.cluster_nat_eip}/32"]
}

# Route 53 Health Checkers publish a stable IP list via JSON.
# https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/route-53-ip-addresses.html
data "http" "r53_health_check_ips" {
  url = "https://ip-ranges.amazonaws.com/ip-ranges.json"
}

locals {
  r53_ranges_raw = jsondecode(data.http.r53_health_check_ips.response_body).prefixes
  r53_hc_ranges  = [for p in local.r53_ranges_raw : p.ip_prefix if p.service == "ROUTE53_HEALTHCHECKS"]
}

resource "aws_wafv2_ip_set" "uptime" {
  name               = "${var.name}-uptime-checkers"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = local.r53_hc_ranges
}

resource "aws_wafv2_web_acl" "bugsink" {
  name  = "${var.name}-internal-only"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "allow-office"
    priority = 1
    action { allow {} }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.office.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-allow-office"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "allow-cluster-nat"
    priority = 2
    action { allow {} }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.cluster.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-allow-cluster"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "allow-uptime-checkers"
    priority = 3
    action { allow {} }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.uptime.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-allow-uptime"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-webacl"
    sampled_requests_enabled   = true
  }
}

terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
