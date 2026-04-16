# 03 — Deploy to GCP GKE

End-to-end walkthrough. Assumes an existing GKE cluster + a GCP project you have owner/editor on.

## Prerequisites

- GKE cluster (Autopilot or Standard, any recent version)
- `gcloud`, `kubectl`, `helm` installed and authenticated
- A GCP project with billing enabled
- Workload Identity enabled on the cluster (recommended)
- (Optional) External DNS integration for Cloudflare / Cloud DNS — else manual A records

**Estimated setup time:** 45-90 minutes first time, 15-30 minutes subsequent deploys.

---

## Step 1 — Create the Postgres backing store (Cloud SQL)

```bash
PROJECT_ID=your-project
REGION=asia-east1  # pick one near your cluster

gcloud sql instances create bugsink-pg \
  --project=$PROJECT_ID \
  --database-version=POSTGRES_16 \
  --tier=db-f1-micro \
  --region=$REGION \
  --network=default \
  --no-assign-ip \
  --enable-google-private-path \
  --backup-start-time=02:00 \
  --retained-backups-count=7
```

For production, use `db-g1-small` (1.7 GB RAM) instead of `db-f1-micro`.

**Why private IP:** the BugSink pod reaches Postgres via the Cloud SQL Auth Proxy sidecar over private networking. No public IP, no public internet exposure.

```bash
gcloud sql databases create bugsink --instance=bugsink-pg --project=$PROJECT_ID

DB_PASSWORD=$(openssl rand -base64 24)
gcloud sql users create bugsink \
  --instance=bugsink-pg \
  --password="$DB_PASSWORD" \
  --project=$PROJECT_ID
```

---

## Step 2 — Store secrets in Secret Manager

```bash
# Database password
echo -n "$DB_PASSWORD" | gcloud secrets create bugsink-db-password \
  --data-file=- --project=$PROJECT_ID

# Django SECRET_KEY
python3 -c "import secrets; print(secrets.token_urlsafe(50))" | \
  gcloud secrets create bugsink-secret-key --data-file=- --project=$PROJECT_ID
```

Grant the Kubernetes service account access:

```bash
# Create a GCP service account for BugSink
gcloud iam service-accounts create bugsink-sa --project=$PROJECT_ID

# Grant Cloud SQL Client role (needed by the proxy sidecar)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:bugsink-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

# Grant Secret Manager accessor role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:bugsink-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Bind to Kubernetes SA (Workload Identity)
gcloud iam service-accounts add-iam-policy-binding \
  bugsink-sa@$PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:$PROJECT_ID.svc.id.goog[bugsink/bugsink]"
```

---

## Step 3 — Install External Secrets Operator

Skip if already installed.

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

---

## Step 4 — Create the namespace and Kubernetes service account

```bash
kubectl create namespace bugsink

kubectl create serviceaccount bugsink -n bugsink
kubectl annotate serviceaccount bugsink -n bugsink \
  iam.gke.io/gcp-service-account=bugsink-sa@$PROJECT_ID.iam.gserviceaccount.com
```

---

## Step 5 — Deploy BugSink via Helm

The `examples/helm/bugsink/` chart in this repo is ready to use. Copy it, set values, install.

```bash
cd examples/helm/bugsink
cp values.example.yaml values.yaml
```

Edit `values.yaml` — minimum fields to fill:

```yaml
image:
  repository: bugsink/bugsink
  tag: "2.1.2"

namespace: bugsink

serviceAccount:
  name: bugsink  # the one we created with Workload Identity

database:
  postgres:
    enabled: true
    instanceConnectionName: your-project:asia-east1:bugsink-pg
    dbName: bugsink
    user: bugsink

secrets:
  # ExternalSecret will sync these from GCP Secret Manager
  externalSecret:
    enabled: true
    gcpProject: your-project

ingress:
  enabled: true
  className: gce  # GKE default Ingress
  host: bugsink.example.com
  tls:
    managedCertificate: true

cloudArmor:
  enabled: true
  policyName: bugsink-internal-only  # we create this in Step 7

bugsink:
  allowedHosts: "*"  # GCP LB health check sends pod-IP Host header; see gotchas
  baseUrl: https://bugsink.example.com
```

Install:

```bash
helm install bugsink . -n bugsink -f values.yaml
```

Watch for pod to come up:

```bash
kubectl get pods -n bugsink -w
```

---

## Step 6 — DNS + TLS

Point `bugsink.example.com` at the Ingress's global static IP:

```bash
kubectl get ingress -n bugsink
# Copy the ADDRESS column, set as A record in your DNS provider
```

ManagedCertificate provisioning takes 10-30 minutes. Watch:

```bash
kubectl describe managedcertificate -n bugsink
```

Status moves from `Provisioning` → `Active`. If it gets stuck, check:
- DNS has propagated (check `dig bugsink.example.com`)
- Ingress has a healthy backend (cert provisioning requires the backend to respond)

---

## Step 7 — Lock down public access (Cloud Armor)

BugSink should not be reachable from the open internet. Create a Cloud Armor security policy that denies everyone except your office IPs + the GCP uptime checkers + your cluster's Cloud NAT egress IP (needed for source-map uploads).

```bash
# Create the policy
gcloud compute security-policies create bugsink-internal-only \
  --description="Internal-only access to BugSink dashboard" \
  --project=$PROJECT_ID

# Default deny (already the default for custom rules, but be explicit)
gcloud compute security-policies rules create 2147483647 \
  --security-policy=bugsink-internal-only \
  --src-ip-ranges="*" \
  --action=deny-403 \
  --project=$PROJECT_ID

# Allow office IP(s)
gcloud compute security-policies rules create 1000 \
  --security-policy=bugsink-internal-only \
  --src-ip-ranges="203.0.113.0/24,198.51.100.5/32" \
  --action=allow \
  --description="Office IPs" \
  --project=$PROJECT_ID

# Allow cluster's Cloud NAT egress IP (for source-map Job chunk-upload)
CLUSTER_NAT_IP=$(gcloud compute routers get-nats NAT_ROUTER_NAME \
  --router-region=$REGION --project=$PROJECT_ID \
  --format='value(natIps)' | head -1)

gcloud compute security-policies rules create 1100 \
  --security-policy=bugsink-internal-only \
  --src-ip-ranges="$CLUSTER_NAT_IP/32" \
  --action=allow \
  --description="Cluster Cloud NAT egress (source-map upload)" \
  --project=$PROJECT_ID

# Allow GCP Uptime Checker source IPs (see infra/network for the full 54-IP list)
# Fetched via: curl 'https://monitoring.googleapis.com/v3/uptimeCheckIps'
# Due to Cloud Armor's 10-IP-per-rule cap, split across priorities 1200-1205.
# See examples/terraform/gcp/uptime-check-ips.tf in this repo.
```

The Helm chart wires this policy onto the Ingress via BackendConfig automatically if `cloudArmor.enabled: true` is set.

---

## Step 8 — Uptime check + Slack alerting

Monitor BugSink itself. If the dashboard goes down, we need to know — not wait 22 hours.

```bash
# Create the uptime check
gcloud monitoring uptime create bugsink-dashboard \
  --resource-type=uptime-url \
  --resource-labels=host=bugsink.example.com,project_id=$PROJECT_ID \
  --path=/accounts/login/ \
  --http-check-accepted-response-status-codes=200 \
  --period=5 \
  --project=$PROJECT_ID
```

For the alert policy + Slack notification channel, see [`examples/terraform/gcp/uptime.tf`](../examples/terraform/gcp/) — alert policies are clunky via CLI.

---

## Step 9 — First login

```bash
# Create the admin user
kubectl exec -it -n bugsink bugsink-0 -c bugsink -- \
  bugsink-manage createsuperuser
```

Then open `https://bugsink.example.com`, log in, create a project. Copy the DSN shown — this is what you'll plug into your SDKs.

---

## Step 10 — Source maps (frontend only)

See [`docs/08-source-maps.md`](08-source-maps.md). The short version: add a Helm post-install/upgrade Job that runs `sentry-cli sourcemaps upload` against the in-cluster BugSink SVC at deploy time.

---

## Step 11 — Plug in your app SDKs

- Backend: [`docs/06-backend-integration.md`](06-backend-integration.md)
- Frontend: [`docs/07-frontend-integration.md`](07-frontend-integration.md)

---

## Troubleshooting

- Pod in CrashLoopBackOff → check logs (`kubectl logs -n bugsink bugsink-0 -c bugsink`). Most common: missing SECRET_KEY or wrong DATABASE_URL.
- `failed_to_pick_backend` 502 from LB → Service missing `cloud.google.com/neg: '{"ingress":true}'` annotation. See [`docs/14-gotchas-gcp.md`](14-gotchas-gcp.md).
- Pod UNHEALTHY in backend service → `ALLOWED_HOSTS=*` missing. GCP LB health checks use pod IP as Host header. See gotchas.
- Cert stuck at Provisioning > 30 min → backend is unreachable. ManagedCertificate needs a healthy backend before provisioning completes.
