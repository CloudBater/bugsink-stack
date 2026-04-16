# Terraform — GCP

Provisions:
- Cloud SQL Postgres instance
- GCP Secret Manager entries (SECRET_KEY, DB password)
- Cloud Armor SecurityPolicy with office IPs + cluster NAT egress + uptime-checker IPs
- Uptime check + alert policy + Slack notification channel

## Prerequisites

- Terraform >= 1.5
- `google` provider authenticated to the target project
- A Slack webhook URL for alerts

## Usage

```bash
cd examples/terraform/gcp
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set project_id, region, office_ips, slack_webhook_url, etc.

terraform init
terraform plan
terraform apply
```

Then feed the outputs into your Helm values.

## Outputs

- `cloud_sql_connection_name` — use in `database.gcp.instanceConnectionName`
- `secret_key_name` / `db_password_name` — use in ExternalSecret config
- `cloud_armor_policy_name` — attach to BackendConfig
- `uptime_check_id` — reference in alert policy

## Files

| File | What |
|------|------|
| `main.tf` | Provider + core resources |
| `cloud-sql.tf` | Postgres instance + DB + user |
| `secrets.tf` | Secret Manager entries |
| `cloud-armor.tf` | SecurityPolicy + office/cluster/uptime IP rules |
| `uptime.tf` | Uptime check + alert policy + Slack channel |
| `iam.tf` | Service account + Workload Identity binding |
| `variables.tf` | Input variables |
| `outputs.tf` | Outputs for consumers |
| `terraform.tfvars.example` | Template — copy to terraform.tfvars |
