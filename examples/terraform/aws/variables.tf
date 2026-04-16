variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "bugsink"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for RDS + EKS"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for RDS"
}

variable "eks_node_sg_id" {
  type        = string
  description = "Security group of EKS nodes — will be allowed to reach RDS"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "office_ips" {
  type        = list(string)
  description = "CIDR blocks for office IPs"
  default     = []
}

variable "cluster_nat_eip" {
  type        = string
  description = "NAT Gateway EIP (for sentry-cli source-map upload)"
}

variable "slack_webhook_url" {
  type      = string
  sensitive = true
}

variable "dashboard_host" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "eks_oidc_provider" {
  type        = string
  description = "OIDC provider URL (without https://) from aws eks describe-cluster"
}

variable "k8s_namespace" {
  type    = string
  default = "bugsink"
}

variable "k8s_service_account" {
  type    = string
  default = "bugsink"
}
