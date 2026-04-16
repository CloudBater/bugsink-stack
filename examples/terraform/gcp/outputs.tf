output "cloud_sql_connection_name" {
  value       = google_sql_database_instance.bugsink.connection_name
  description = "project:region:instance — use in bugsink Helm values.database.gcp.instanceConnectionName"
}

output "secret_key_name" {
  value       = google_secret_manager_secret.secret_key.secret_id
  description = "GCP Secret Manager secret ID for BugSink SECRET_KEY"
}

output "db_password_name" {
  value       = google_secret_manager_secret.db_password.secret_id
  description = "GCP Secret Manager secret ID for BugSink DB password"
}

output "cloud_armor_policy_name" {
  value       = google_compute_security_policy.bugsink.name
  description = "Attach to BackendConfig.spec.securityPolicy.name"
}

output "service_account_email" {
  value       = google_service_account.bugsink.email
  description = "GCP SA bound via Workload Identity to the BugSink K8s SA"
}

output "uptime_check_id" {
  value       = google_monitoring_uptime_check_config.bugsink.uptime_check_id
  description = "GCP uptime check ID"
}
