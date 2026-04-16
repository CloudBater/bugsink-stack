# 04 — Deploy to AWS EKS

End-to-end walkthrough. Mirrors the GKE one but with AWS-native services.

## Prerequisites

- EKS cluster (any recent version)
- `aws` CLI, `kubectl`, `helm` installed and authenticated
- AWS Load Balancer Controller installed on the cluster ([install guide](https://kubernetes-sigs.github.io/aws-load-balancer-controller/))
- External Secrets Operator installed (skip if already there)
- IRSA (IAM Roles for Service Accounts) enabled on the cluster

**Estimated setup time:** 60-90 minutes first time.

---

## Step 1 — Create the Postgres backing store (RDS)

```bash
AWS_REGION=us-east-1
VPC_ID=vpc-xxxxxxxx   # the VPC your EKS cluster runs in
SUBNET_IDS=subnet-a,subnet-b,subnet-c   # private subnets in that VPC

# Create a DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name bugsink-subnet-group \
  --db-subnet-group-description "BugSink Postgres subnets" \
  --subnet-ids $SUBNET_IDS \
  --region $AWS_REGION

# Create a security group that only allows traffic from the EKS pods' SG
aws ec2 create-security-group \
  --group-name bugsink-rds-sg \
  --description "BugSink RDS access from EKS" \
  --vpc-id $VPC_ID \
  --region $AWS_REGION
# Add inbound rule: port 5432 from your EKS node SG

# Create the RDS instance
DB_PASSWORD=$(openssl rand -base64 24)
aws rds create-db-instance \
  --db-instance-identifier bugsink-pg \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16 \
  --master-username bugsink \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage 20 \
  --db-subnet-group-name bugsink-subnet-group \
  --vpc-security-group-ids sg-xxxxxxxx \
  --no-publicly-accessible \
  --backup-retention-period 7 \
  --preferred-backup-window "02:00-03:00" \
  --region $AWS_REGION
```

For production, use `db.t3.small` or `db.t4g.small`.

**No proxy sidecar needed** — unlike GCP Cloud SQL, RDS is directly reachable via VPC networking from pods. Simpler.

---

## Step 2 — Store secrets in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name bugsink/db-password \
  --secret-string "$DB_PASSWORD" \
  --region $AWS_REGION

SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
aws secretsmanager create-secret \
  --name bugsink/secret-key \
  --secret-string "$SECRET_KEY" \
  --region $AWS_REGION
```

---

## Step 3 — Create IAM role for BugSink pod (IRSA)

```bash
CLUSTER_NAME=my-eks-cluster
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

# Trust policy (allows the bugsink Kubernetes SA to assume this role)
cat > /tmp/trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/$OIDC_PROVIDER"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "$OIDC_PROVIDER:sub": "system:serviceaccount:bugsink:bugsink",
        "$OIDC_PROVIDER:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF

aws iam create-role --role-name bugsink-pod-role \
  --assume-role-policy-document file:///tmp/trust.json

# Policy: allow reading our BugSink secrets
cat > /tmp/policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["secretsmanager:GetSecretValue"],
    "Resource": [
      "arn:aws:secretsmanager:$AWS_REGION:$ACCOUNT_ID:secret:bugsink/*"
    ]
  }]
}
EOF

aws iam put-role-policy --role-name bugsink-pod-role \
  --policy-name bugsink-secrets-read \
  --policy-document file:///tmp/policy.json
```

---

## Step 4 — Create namespace + service account

```bash
kubectl create namespace bugsink
kubectl create serviceaccount bugsink -n bugsink

kubectl annotate serviceaccount bugsink -n bugsink \
  eks.amazonaws.com/role-arn=arn:aws:iam::$ACCOUNT_ID:role/bugsink-pod-role
```

---

## Step 5 — Deploy BugSink via Helm

Use the same chart in `examples/helm/bugsink/`. For EKS, the values look like:

```yaml
image:
  repository: bugsink/bugsink
  tag: "2.1.2"

namespace: bugsink
serviceAccount:
  name: bugsink

database:
  # Direct RDS, no proxy sidecar
  url: "postgres://bugsink:$(DB_PASSWORD)@bugsink-pg.xxx.us-east-1.rds.amazonaws.com:5432/bugsink"

secrets:
  externalSecret:
    enabled: true
    provider: aws  # chart renders AWS SecretStore
    awsRegion: us-east-1

ingress:
  enabled: true
  className: alb
  host: bugsink.example.com
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:...:certificate/...
    alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:us-east-1:...:regional/webacl/bugsink-internal-only/...
    alb.ingress.kubernetes.io/healthcheck-path: /accounts/login/
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "30"

bugsink:
  allowedHosts: "bugsink.example.com,localhost"  # ALB passes real Host header; no need for *
  baseUrl: https://bugsink.example.com
```

Install:

```bash
helm install bugsink examples/helm/bugsink -n bugsink -f values.yaml
```

**Key ALB annotations explained:**
- `target-type: ip` — ALB sends traffic to pod IPs directly (via AWS VPC CNI). Required for most production setups.
- `healthcheck-path: /accounts/login/` — BugSink returns 200 there, unlike `/` which redirects.
- `wafv2-acl-arn` — attach WAF ACL for IP allowlisting (see Step 7).

---

## Step 6 — TLS with ACM

Request a certificate in ACM for `bugsink.example.com`:

```bash
aws acm request-certificate \
  --domain-name bugsink.example.com \
  --validation-method DNS \
  --region $AWS_REGION
```

Add the DNS validation CNAME to your DNS provider. When the cert goes `ISSUED`, copy its ARN into the Ingress annotation above.

---

## Step 7 — Lock down public access (AWS WAF)

Create a WAFv2 WebACL that allows only your office IPs + GCP uptime checkers (or AWS Synthetics source IPs) + NAT GW EIP for source-map uploads.

```bash
# Create an IP set for office IPs
aws wafv2 create-ip-set \
  --name bugsink-allow-ips \
  --scope REGIONAL \
  --ip-address-version IPV4 \
  --addresses "203.0.113.0/24" "198.51.100.5/32" \
  --region $AWS_REGION

# Create a WebACL with default-block and allow-on-IP-set rule
# (easier via Terraform — see examples/terraform/aws/waf.tf)
```

The Helm chart's `wafv2-acl-arn` annotation attaches the WebACL to the ALB.

**AWS WAF IP sets scale to 10,000 entries each** — unlike Cloud Armor's 10-IP-per-rule cap. Simpler to manage.

---

## Step 8 — Uptime check + Slack alerting

Use CloudWatch Synthetics or Route 53 Health Checks.

```bash
# Route 53 Health Check (simpler)
aws route53 create-health-check \
  --caller-reference "$(date +%s)" \
  --health-check-config '{
    "Type": "HTTPS",
    "FullyQualifiedDomainName": "bugsink.example.com",
    "ResourcePath": "/accounts/login/",
    "RequestInterval": 30,
    "FailureThreshold": 2
  }'

# Then create a CloudWatch alarm on the health check status,
# and an SNS topic with a Slack subscription (or direct Slack webhook Lambda).
```

Full Terraform in `examples/terraform/aws/uptime.tf`.

---

## Step 9 — First login

```bash
kubectl exec -it -n bugsink bugsink-0 -c bugsink -- \
  bugsink-manage createsuperuser
```

Then visit `https://bugsink.example.com`, log in, create a project, grab the DSN.

---

## Step 10 — Source maps

See [`docs/08-source-maps.md`](08-source-maps.md).

---

## Troubleshooting

- **Pod can't reach RDS** → check SG rules. RDS SG must allow inbound 5432 from EKS node SG or pod CIDR.
- **Ingress has no address** → ALB Controller not installed, or IAM permissions missing. Check `kubectl logs -n kube-system deployment/aws-load-balancer-controller`.
- **ACM cert stuck pending** → DNS validation record missing or wrong. Re-check `aws acm describe-certificate` output.
- **502 from ALB** → health check failing. Check `alb.ingress.kubernetes.io/healthcheck-path` points at something that returns 200 (not redirect).
- **SDK can't POST events** → if you see 403, check the WAF WebACL didn't block the cluster's source IP. Source-map upload path needs NAT GW EIP in the allowlist.
