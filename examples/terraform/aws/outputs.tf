output "rds_endpoint" {
  value       = aws_db_instance.bugsink.endpoint
  description = "Use in Helm values.database.aws.endpoint"
}

output "secret_key_arn" {
  value = aws_secretsmanager_secret.secret_key.arn
}

output "db_password_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}

output "waf_acl_arn" {
  value       = aws_wafv2_web_acl.bugsink.arn
  description = "Attach to ALB via alb.ingress.kubernetes.io/wafv2-acl-arn"
}

output "pod_role_arn" {
  value       = aws_iam_role.pod.arn
  description = "Use in K8s ServiceAccount eks.amazonaws.com/role-arn annotation"
}

output "health_check_id" {
  value = aws_route53_health_check.bugsink.id
}
