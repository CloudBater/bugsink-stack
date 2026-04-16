# 09 — Security Hardening

BugSink contains stack traces, request headers, user context, and sometimes sensitive application state. It's a juicy target. Lock it down.

## Threat model

What you're protecting against:
- **Unauthorized dashboard access** (someone finds the URL, brute-forces login)
- **Data exfiltration** (SQL injection, SSRF → read events)
- **Abuse of ingest endpoint** (someone floods BugSink with garbage events to mask real issues or drive up storage)

What you're NOT protecting against (by design):
- Nation-state adversaries (use a commercial solution + dedicated security team)
- Insider threat with infrastructure access (mitigate with audit logging, not with BugSink config)

## Layer 1 — Don't expose the dashboard to the open internet

**This is the #1 hardening step.** Default to internal-only access.

Four options, pick one:

| Option | Complexity | Who can reach it |
|--------|-----------|------------------|
| **IP allowlist at WAF/Cloud Armor** | Low | Office + cluster NAT egress |
| **VPN-only** | Medium | Anyone on the VPN |
| **Cloudflare Access / Tailscale** | Low (SaaS) | Authenticated team members |
| **Bastion / jump box** | High | Via SSH tunnel |

### IP allowlist (recommended for most teams)

- GCP: Cloud Armor `SecurityPolicy` — default `deny(403)` + allow rules for office IPs and cluster NAT egress IP
- AWS: WAFv2 WebACL with an IPSet — same pattern

See `examples/terraform/gcp/cloud-armor.tf` and `examples/terraform/aws/waf.tf` for ready-to-apply policies.

**Why not IAP (GCP) / ALB auth (AWS)?** These OAuth-based gateways break SDK ingest and `sentry-cli` upload flows. Both expect to negotiate with a browser. Don't use them for BugSink; use IP allowlist or VPN instead.

## Layer 2 — Separate ingest from dashboard (optional)

If your threat model demands it, split the two:

- Dashboard URL (`bugsink.example.com`) — strict IP allowlist
- Ingest URL (`ingest.bugsink.example.com`) — open to the world, protected by DSN key validation at BugSink's application layer

BugSink doesn't split these natively; you'd do it at the Ingress layer (two Ingress resources → same Service, different hostnames, different Cloud Armor/WAF policies).

For most teams, this is over-engineered. The in-cluster SVC DSN already keeps SDK ingest off the public internet for apps running in the same cluster.

## Layer 3 — Rotate credentials regularly

- `SECRET_KEY` (Django) — Not typically rotated (rotating invalidates existing sessions). Stored in ExternalSecret / Secrets Manager.
- Admin password — Rotate quarterly. Use a password manager. Don't put it in the repo.
- API tokens (for `sentry-cli`) — Rotate if a developer who had access leaves the team.

Store all of these in:
- GCP Secret Manager (dev project for non-prod, prod project for prod)
- AWS Secrets Manager (same split)
- **Not** in values.yaml, **not** in committed `.env` files, **not** in Slack messages.

## Layer 4 — PII scrub (if required)

By default, `send_default_pii=True` captures:
- Request headers (including `Authorization`, `Cookie`)
- User IP
- User identifiers (if set via `sentry_sdk.set_user()`)

For self-hosted BugSink, this is usually fine — the data never leaves your infra. But if you have regulatory requirements (HIPAA, strict PCI, etc.), scrub at the SDK level:

```python
def before_send(event, hint):
    if 'request' in event and 'headers' in event['request']:
        for h in ['Authorization', 'Cookie', 'X-Api-Key']:
            event['request']['headers'].pop(h, None)
    return event

sentry_sdk.init(dsn=..., before_send=before_send, send_default_pii=False)
```

Scrubbing at the SDK is better than scrubbing at the BugSink side — sensitive data never leaves the app pod.

## Layer 5 — Least-privilege IAM

The BugSink pod's service account should have only:
- Cloud SQL Client / RDS connect permission
- Secrets Manager read access for its own secrets (not all secrets)

Grant via Workload Identity (GCP) or IRSA (AWS). **Do not put service account keys in the image.**

## Layer 6 — Network egress (optional)

If you're paranoid, restrict the BugSink pod's egress:
- Can reach Postgres (port 5432)
- Can reach Secrets Manager (HTTPS)
- Maybe Slack webhook (HTTPS)
- Nothing else

Use a NetworkPolicy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: bugsink-egress
  namespace: bugsink
spec:
  podSelector:
    matchLabels:
      app: bugsink
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}  # allow in-cluster (Postgres, DNS)
    ports:
    - protocol: TCP
      port: 5432
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]
    ports:
    - protocol: TCP
      port: 443  # Slack webhooks, Secrets Manager API
```

Adjust for your cluster's DNS and service CIDR.

## Layer 7 — Audit logging

BugSink's access logs go to stdout → your cluster's logging stack (Cloud Logging, CloudWatch Logs). You can see who logged in when. That's usually enough.

For stricter audit requirements, ship logs to an immutable store (Google's Cloud Audit Logs, AWS CloudTrail + S3 with Object Lock, or Vault audit device).

## Layer 8 — Backup + disaster recovery

Postgres backups are automatic on Cloud SQL / RDS (daily, 7-day retention by default). Test the restore procedure at least once.

Event files on PVC: consider a nightly `rclone` to GCS/S3 if you need recovery from volume loss.

```bash
# example: mirror PVC to bucket nightly via CronJob
kubectl create cronjob bugsink-backup \
  --schedule="0 3 * * *" \
  --image=rclone/rclone \
  --command -- rclone sync /data gcs:my-backup-bucket/bugsink/
```

## Checklist for production

- [ ] Dashboard behind WAF/Cloud Armor IP allowlist (or VPN/Tailscale)
- [ ] TLS (ACM/ManagedCertificate)
- [ ] SECRET_KEY in Secrets Manager, synced via ExternalSecret
- [ ] DB password in Secrets Manager
- [ ] Admin + shared team accounts (not per-user)
- [ ] API token for CI/Helm Job, rotated if someone leaves
- [ ] PII scrub configured if regulated
- [ ] Pod service account scoped to only what it needs
- [ ] Uptime check + Slack alert on BugSink itself
- [ ] Postgres automated backups enabled, restore tested
- [ ] Event file PVC backup strategy (optional)
