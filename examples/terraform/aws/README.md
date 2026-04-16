# Terraform — AWS

Provisions:
- RDS Postgres instance
- AWS Secrets Manager entries (SECRET_KEY, DB password)
- WAFv2 WebACL with office IPs + cluster NAT EIP + uptime check IPs
- Route 53 Health Check + SNS topic + CloudWatch alarm for Slack alerts
- IAM role for IRSA

## Prerequisites

- Terraform >= 1.5
- `aws` provider authenticated to the target account
- Existing VPC with private subnets for RDS
- A Slack webhook URL

## Usage

```bash
cd examples/terraform/aws
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform plan
terraform apply
```

## Outputs

- `rds_endpoint` — use in `database.aws.endpoint`
- `secret_key_arn` / `db_password_arn` — use in ExternalSecret config
- `waf_acl_arn` — attach to ALB via Ingress annotation
- `pod_role_arn` — use in K8s ServiceAccount's `eks.amazonaws.com/role-arn`

## Files

| File | What |
|------|------|
| `main.tf` | Provider + core |
| `rds.tf` | Postgres instance + SG |
| `secrets.tf` | Secrets Manager entries |
| `waf.tf` | WAFv2 WebACL + IPSets |
| `uptime.tf` | Route 53 HC + SNS + CloudWatch alarm |
| `iam.tf` | IRSA role |
| `variables.tf` | Input vars |
| `outputs.tf` | Outputs |
| `terraform.tfvars.example` | Template |
