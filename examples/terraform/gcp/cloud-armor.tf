# Cloud Armor SecurityPolicy — default deny, allow office + cluster + uptime checkers.
#
# GCP publishes the uptime-checker IP list (54 IPs as of 2026). Due to Cloud Armor's
# 10-IPs-per-rule cap, we split across 6 rules (priorities 1200-1205).

data "http" "uptime_check_ips" {
  url = "https://monitoring.googleapis.com/v3/uptimeCheckIps?pageSize=200"
}

locals {
  uptime_ips_raw = jsondecode(data.http.uptime_check_ips.response_body).uptimeCheckIps
  uptime_ips     = [for ip in local.uptime_ips_raw : "${ip.ipAddress}/32"]
  # Chunk into groups of 10 for Cloud Armor
  uptime_chunks = [
    for i in range(0, length(local.uptime_ips), 10) :
    slice(local.uptime_ips, i, min(i + 10, length(local.uptime_ips)))
  ]
}

resource "google_compute_security_policy" "bugsink" {
  name        = "${var.name}-internal-only"
  description = "Default deny; allow office + cluster NAT + GCP uptime checkers."

  # Priority 1000: office IPs
  rule {
    priority    = 1000
    action      = "allow"
    description = "Office IPs"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = length(var.office_ips) > 0 ? var.office_ips : ["0.0.0.0/32"]
      }
    }
  }

  # Priority 1100: cluster NAT egress (for sentry-cli chunk-upload redirect)
  rule {
    priority    = 1100
    action      = "allow"
    description = "Cluster Cloud NAT egress"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["${var.cluster_nat_ip}/32"]
      }
    }
  }

  # Priorities 1200-1205: GCP uptime checker IPs (up to 6 rules × 10 IPs = 60 slots)
  dynamic "rule" {
    for_each = local.uptime_chunks
    content {
      priority    = 1200 + rule.key
      action      = "allow"
      description = "GCP uptime checkers chunk ${rule.key + 1}/${length(local.uptime_chunks)}"
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = rule.value
        }
      }
    }
  }

  # Default deny (priority 2147483647 is implicit; be explicit for audit clarity)
  rule {
    priority    = 2147483647
    action      = "deny(403)"
    description = "Default deny"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
