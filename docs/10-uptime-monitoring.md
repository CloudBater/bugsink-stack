# 10 — Uptime Monitoring (Monitor the Watcher)

**The second-most important chapter in this repo** (the first is gotchas).

## The 22-hour lesson

Real incident, anonymized: BugSink's dashboard returned HTTP 502 externally for **22 hours** before anyone noticed. The app itself was fine. Users weren't affected. But nobody was watching BugSink itself. A values.yaml change had written an empty `SECRET_KEY` into the k8s Secret; the running pod kept serving from its in-memory copy until a StatefulSet cycle forced a new pod to read the empty value and crashloop.

If we'd had a 5-minute uptime check in place, we'd have known in 10 minutes.

**Rule: set up the uptime check before you stop staring at the dashboard.**

## What to monitor

BugSink has two surfaces:

1. **Dashboard HTTPS endpoint** (`https://bugsink.example.com/accounts/login/`)
   - Expected: 200 OK
   - Broken when: pod crashloops, ingress misconfig, cert expires, DB unreachable
2. **Event ingest endpoint** (in-cluster SVC URL — rarely worth monitoring externally; monitor via synthetic event below)
   - Expected: 200 OK from an SDK-style POST
   - Harder to probe without a real SDK payload

Start with the dashboard check. Add an ingest-specific synthetic if you have the budget.

## GCP Uptime Check

```bash
PROJECT_ID=your-project
HOST=bugsink.example.com

gcloud monitoring uptime create bugsink-dashboard \
  --resource-type=uptime-url \
  --resource-labels=host=$HOST,project_id=$PROJECT_ID \
  --path=/accounts/login/ \
  --http-check-accepted-response-status-codes=200 \
  --period=5 \
  --project=$PROJECT_ID
```

Why `/accounts/login/` and not `/`? Because `/` returns 302 (redirect to login). Uptime checks treat 3xx as failure by default.

### Allowlist the uptime checkers in your WAF

GCP's uptime checkers have [54 source IPs](https://cloud.google.com/monitoring/uptime-checks#uptime_check_ip_list) as of 2026. Fetch the current list:

```bash
curl -s https://monitoring.googleapis.com/v3/uptimeCheckIps?pageSize=200 \
  | jq -r '.uptimeCheckIps[].ipAddress'
```

Add these to your Cloud Armor policy. **Gotcha:** Cloud Armor's `inIpRange` CEL expression is capped at **5 entries per rule**. The 54-IP list needs to be split across 6 rules (10 IPs per `srcIpRanges` is fine, but CEL expressions won't work around this cap).

Example split (priorities 1200-1205, 10 IPs each):

```bash
# Rule 1200
gcloud compute security-policies rules create 1200 \
  --security-policy=bugsink-internal-only \
  --src-ip-ranges="$(echo "$IPS" | head -10 | paste -sd, -)" \
  --action=allow \
  --description="GCP uptime checkers 1/6"

# ...repeat for 1201..1205 with the next 10 IPs each
```

See `examples/terraform/gcp/cloud-armor.tf` for the Terraformed version that handles this automatically.

## AWS CloudWatch Synthetics or Route 53 Health Check

**Route 53 Health Check** (simpler):

```bash
aws route53 create-health-check \
  --caller-reference "bugsink-$(date +%s)" \
  --health-check-config '{
    "Type": "HTTPS",
    "FullyQualifiedDomainName": "bugsink.example.com",
    "ResourcePath": "/accounts/login/",
    "RequestInterval": 30,
    "FailureThreshold": 2,
    "MeasureLatency": true
  }'
```

Route 53 Health Check source IPs are [published by AWS](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/route-53-ip-addresses.html) — allowlist in WAF.

**CloudWatch Synthetics Canary** (more flexible — can run a full browser flow, do a login, etc.):

```bash
# Needs a Lambda-style script and more setup. See examples/terraform/aws/synthetics-canary.tf
```

## Alert on failure → Slack

### GCP: Alert Policy + Notification Channel

```bash
# Create a Slack notification channel
gcloud alpha monitoring channels create \
  --display-name="BugSink Alerts" \
  --type=slack \
  --channel-labels=channel_name=#alerts \
  --user-labels=purpose=bugsink

# Create the alert policy (this is clunky via CLI; use Terraform)
# See examples/terraform/gcp/uptime.tf
```

### AWS: SNS topic + Slack subscription

```bash
# Create SNS topic
aws sns create-topic --name bugsink-alerts

# Subscribe Slack webhook via Lambda (or use a service like AWS Chatbot)
# See examples/terraform/aws/uptime.tf

# Create CloudWatch alarm on the health check status metric
aws cloudwatch put-metric-alarm \
  --alarm-name bugsink-dashboard-down \
  --metric-name HealthCheckStatus \
  --namespace AWS/Route53 \
  --statistic Minimum \
  --dimensions Name=HealthCheckId,Value=$HEALTH_CHECK_ID \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:...:bugsink-alerts
```

## Alert message content

A good alert is actionable. Make the Slack message include:

- What failed (hostname, path, status code)
- When (timestamp)
- **Triage runbook**: what to check first

Example alert template:

```
🚨 BugSink dashboard DOWN (https://bugsink.example.com/accounts/login/)
Started: 2026-04-15 14:32 UTC
Status: 502 / timeout / TLS error / ...

Triage steps:
1. kubectl get pod -n bugsink   (is the pod running?)
2. kubectl logs -n bugsink bugsink-0 -c bugsink --tail=50   (what's it saying?)
3. kubectl describe ingress -n bugsink   (cert valid? backend healthy?)
4. curl https://bugsink.example.com/accounts/login/   (from an allowlisted IP)
5. Check recent helm deploys (helm history bugsink -n bugsink)

If stuck, check docs/13-gotchas.md for common causes.
```

Don't assume the person paged will remember. Spell it out.

## Validate the alert fires

Before you declare victory, **trigger a test**. Scale the BugSink deployment to 0:

```bash
kubectl scale statefulset bugsink -n bugsink --replicas=0
```

Wait 2 periods (~10 min for a 5-min check). Slack alert should fire with full triage doc. Scale back to 1:

```bash
kubectl scale statefulset bugsink -n bugsink --replicas=1
```

Alert auto-closes (or manually close depending on platform).

Document the fire time and recovery time in a test log. This is the moment you'd have saved 22 hours.

## How often should the check run?

- **5 minutes** — GCP free tier default, fine for most teams. Max detection lag: 10 min.
- **1 minute** — if you really want tight SLO. Costs slightly more. Max detection lag: 2 min.
- Don't go faster than 1 min — false positives from brief network blips outweigh the benefit.

## Monitoring BugSink's backing Postgres

Your cloud provider already monitors managed Postgres. Hook up:
- GCP: Cloud SQL alerts for high CPU, low storage, replication lag
- AWS: RDS Enhanced Monitoring + CloudWatch alarms

For `db-f1-micro`, the main things that will bite:
- Storage fills up → add event retention policy
- CPU credit exhaustion on burstable instances → upsize to `db-g1-small`

## Final rule

Whatever you're monitoring, **test the alert firing path end-to-end**. A dashboard that says "configured" without a proven fire is worthless. Scale to zero, watch Slack, document the timestamp. Do it on day one.
