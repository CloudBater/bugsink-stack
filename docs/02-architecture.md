# 02 — Reference Architecture

Two valid deployment shapes. Pick based on blast-radius tolerance.

## Option A — Single shared instance (simplest)

One BugSink instance. All environments (dev, staging, prod) feed it. SDK tags events by `environment` so you can filter.

```
┌─────────────────────────────────────┐
│ Kubernetes Cluster                  │
│                                     │
│  ┌──────────┐     ┌─────────────┐   │
│  │ dev apps │────▶│             │   │
│  ├──────────┤     │   BugSink   │   │
│  │ staging  │────▶│  (in-cluster│───┼──▶ Slack
│  ├──────────┤     │   SVC DSN)  │   │
│  │ prod     │────▶│             │   │
│  └──────────┘     └─────────────┘   │
│                        │            │
│                        ▼            │
│                   ┌─────────┐       │
│                   │ Postgres│       │
│                   └─────────┘       │
└─────────────────────────────────────┘
           │
           ▼
    bugsink.example.com  ─── team dashboard (WAF / IP allowlist)
```

**Pros:** Cheapest, simplest, one thing to monitor.
**Cons:** If BugSink goes down during an incident, you lose prod error visibility at the worst possible moment.

## Option B — Split prod / non-prod (recommended for production workloads)

Two BugSink instances in two separate cloud projects/accounts. Prod errors go to prod BugSink; everything else goes to non-prod BugSink.

```
┌─────────────────────────────┐      ┌─────────────────────────────┐
│ Non-prod project            │      │ Prod project                │
│ (e.g. GCP dev project,      │      │ (e.g. GCP prod project,     │
│  AWS non-prod account)      │      │  AWS prod account)          │
│                             │      │                             │
│  ┌──────────┐   ┌─────────┐ │      │  ┌──────────┐   ┌─────────┐ │
│  │ dev app  │──▶│ BugSink │ │      │  │ prod app │──▶│ BugSink │ │
│  ├──────────┤   │  (dev-  │ │      │  └──────────┘   │  (prod) │ │
│  │ staging  │──▶│ bugsink)│ │      │                 └─────────┘ │
│  └──────────┘   └─────────┘ │      │                      │      │
│                      │      │      │                      ▼      │
│                      ▼      │      │                 ┌─────────┐ │
│                 ┌─────────┐ │      │                 │ Postgres│ │
│                 │ Postgres│ │      │                 │  prod   │ │
│                 │ (dev)   │ │      │                 └─────────┘ │
│                 └─────────┘ │      └─────────────────────────────┘
└─────────────────────────────┘
       dev-bugsink.example.com          bugsink.example.com
```

**Pros:**
- **Blast radius isolation** — non-prod noise/outages can't affect prod visibility
- **Data residency** — prod user data stays in the prod cloud project/account
- **Simpler networking** — each BugSink serves only its own cluster's SDK traffic via in-cluster DNS; no cross-cloud connectivity needed
- **Per-env access control** — prod dashboard can have stricter IP allowlist than dev

**Cons:** Roughly 2x the cost (~$30-50/mo vs $15-25/mo). Two instances to monitor.

## When to pick which

| Team size | Traffic | Pick |
|-----------|---------|------|
| 1-3 devs, pre-launch | < 100 events/day | **Option A** |
| 3-10 devs, growing | 100-1k events/day | **Option A** initially, migrate to B when revenue covers the delta |
| 10+ devs, production | > 1k events/day | **Option B** |
| Regulated / data residency requirements | any | **Option B** |

**Migration from A → B is straightforward** — stand up the second instance, flip prod's DSN to point at it, done. Historical events stay on the old instance.

## SDK traffic path (important)

**Critical detail for both options:** errors are POSTed from your app pods to BugSink over the Kubernetes internal service DNS:

```
http://<key>@bugsink-svc.bugsink-ns.svc.cluster.local/1
```

This traffic **never leaves the cluster** — no public DNS resolution, no NAT egress, no WAF/Cloud Armor in the path. This is why:

- You can lock the public BugSink dashboard behind a tight IP allowlist without breaking SDK ingest
- You don't pay egress on error events
- Latency is consistent (sub-ms, pod-to-pod)

The public dashboard URL (`bugsink.example.com`) is used for:
1. Humans browsing errors in a web browser
2. `sentry-cli` source-map uploads (see [`docs/08-source-maps.md`](08-source-maps.md)) — this path DOES touch the public URL and is the one thing that complicates Option B's "everything stays in cluster" claim

## Components

| Component | Role | Typical config |
|-----------|------|----------------|
| BugSink Django app | Event ingest, grouping, dashboard | 1 pod, 200m/256Mi, 4 gunicorn workers |
| Postgres | Event storage | `db-f1-micro` (dev) or `db-g1-small` (prod), 5-10 GB |
| Object storage (optional) | Source-map files, event attachments | PVC (default) or GCS/S3 bucket |
| Ingress + TLS | HTTPS dashboard | Cloud-specific (GKE Ingress + ManagedCert / AWS ALB + ACM) |
| WAF / IP allowlist | Dashboard access control | Cloud Armor (GCP) / AWS WAF |
| Uptime monitoring | Watch the watcher | GCP Uptime Check / CloudWatch Canary |
| Slack integration | Alert routing | Incoming webhook |

## Next

- Deploy: pick [GCP GKE](03-deploy-gcp-gke.md), [AWS EKS](04-deploy-aws-eks.md), or [Docker Compose](05-deploy-docker-compose.md)
- Integrate SDK: [backend](06-backend-integration.md) / [frontend](07-frontend-integration.md)
- Harden: [security](09-security-hardening.md), [uptime](10-uptime-monitoring.md)
