variable "project_id" {
  type        = string
  description = "GCP project ID where BugSink infra lives."
}

variable "region" {
  type        = string
  default     = "asia-east1"
  description = "Region for Cloud SQL + regional resources."
}

variable "name" {
  type        = string
  default     = "bugsink"
  description = "Name prefix for all resources."
}

variable "db_tier" {
  type        = string
  default     = "db-f1-micro"
  description = "Cloud SQL tier. Use db-g1-small for production."
}

variable "office_ips" {
  type        = list(string)
  description = "CIDR blocks for office IPs allowed to reach the BugSink dashboard."
  default     = []
}

variable "cluster_nat_ip" {
  type        = string
  description = "Cluster's Cloud NAT egress IP (for sentry-cli chunk-upload)."
}

variable "slack_webhook_url" {
  type        = string
  sensitive   = true
  description = "Slack incoming webhook URL for alerts."
}

variable "dashboard_host" {
  type        = string
  description = "Public hostname for BugSink dashboard (e.g. bugsink.example.com)."
}

variable "k8s_namespace" {
  type        = string
  default     = "bugsink"
  description = "Kubernetes namespace for the BugSink SA (Workload Identity)."
}

variable "k8s_service_account" {
  type        = string
  default     = "bugsink"
  description = "Kubernetes SA name."
}
