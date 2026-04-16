# 11 — Split vs Shared Instances

When to run one BugSink for all environments vs one per blast radius.

## The two shapes

### Shared (Option A)

One BugSink instance. dev/staging/prod all point at it. SDK tags events by `environment` so you can filter on the dashboard.

```
    [dev]   ──┐
    [staging] ├──▶ bugsink.example.com
    [prod]  ──┘
```

### Split (Option B)

Two BugSink instances in two separate cloud projects/accounts:

```
    [dev]   ──┐
    [staging] ├──▶ dev-bugsink.example.com   (dev cloud project)
    [sandbox] ──┘

    [prod]    ──▶ bugsink.example.com        (prod cloud project)
```

## Why split is worth it (eventually)

1. **Blast radius isolation.** A buggy Helm upgrade on the non-prod BugSink (or a runaway migration) can't take down prod error visibility at exactly the moment you need it most.
2. **Data residency.** Prod user headers, IP addresses, stack traces stay in the prod cloud project. Regulators care about this.
3. **Access control granularity.** Prod dashboard can have a stricter IP allowlist than non-prod. Non-prod might be open to the whole office; prod might be open only to on-call.
4. **Slack routing per severity.** Prod alerts → `#alerts-prod`. Dev/staging → `#alerts-dev`. Without split, you're filtering in Slack, which is lossy.
5. **Independent upgrade cadence.** Upgrade non-prod BugSink first, catch regressions, then upgrade prod.

## Why shared is fine initially

- **Cost.** One instance = ~$15-25/mo. Two = ~$30-50/mo. Below any budget threshold once you have revenue.
- **Ops surface.** One thing to upgrade, one thing to monitor. Matters if your team is 2-3 people.
- **No cross-cloud networking.** Everything in one project/account = no VPC peering, no cross-region anything.

## Decision matrix

| Situation | Pick |
|-----------|------|
| Pre-launch, 1-3 devs | Shared |
| Post-launch, < 10 users, no regulatory needs | Shared |
| Post-launch, growing, some production traffic | **Start shared, plan the split** |
| Real paying customers, SLOs, regulated (SOC2/HIPAA/etc.) | **Split** |
| Enterprise customers, strict data residency | **Split** |
| Team of 10+, multiple squads | Split |

## Cost breakdown

### Shared (Option A)

| Component | GCP | AWS |
|-----------|-----|-----|
| Cloud SQL / RDS `db-f1-micro` / `db.t3.micro` | $7-10/mo | $12/mo |
| GKE Autopilot or 1 EKS node share | $3-5/mo | $5/mo |
| Cloud Armor / WAF | free (basic) | ~$5/mo |
| Egress | negligible (in-cluster) | negligible |
| **Total** | **~$15/mo** | **~$22/mo** |

### Split (Option B)

Roughly 2x (two of everything). GCP ~$35-45/mo, AWS ~$45-55/mo.

In both cases, negligible for a team generating real revenue. Significant for a side project.

## Migration from shared → split

When you're ready to split (usually after first real production traffic):

1. **Stand up the new prod BugSink** in the prod cloud project on a temporary hostname (e.g. `bugsink-prod.example.com`). Don't touch the existing shared instance yet.
2. **Verify the prod instance** — login, create projects, trigger a canary error from prod staging.
3. **Cut over one app at a time.** Update prod app's `SENTRY_DSN` to the new prod instance's in-cluster SVC DNS. Deploy. Watch events land in the new instance.
4. **Rename the shared instance.** Update its hostname to `dev-bugsink.example.com` (or similar). Tell the team the URL moved.
5. **Flip `bugsink.example.com` DNS** to point at the prod instance. Now the canonical URL serves prod, and non-prod has its own named URL.

See [`docs/12-zero-downtime-cutover.md`](12-zero-downtime-cutover.md) for the full zero-downtime swap sequence.

## What "split" doesn't mean

- Doesn't mean per-environment instances (dev, staging, sandbox, prod all separate). That's overkill and 4x the cost. One prod + one non-prod is the sweet spot.
- Doesn't mean you lose shared data. Historical events in the old shared instance stay there as `dev-bugsink`. You're not migrating 50,000 events to prod.
- Doesn't mean per-tenant BugSinks. If you have a multi-tenant SaaS, tag events by tenant ID in your SDK — don't spin up BugSink per tenant.

## Internal naming hint

When you rename, keep internal names (Kubernetes labels, Cloud SQL instance names, Secret Manager keys) **stable**. Only change the public hostname.

- Ingress `hosts: [dev-bugsink.example.com]` — public URL changes
- StatefulSet `name: bugsink` — internal k8s name stays
- Cloud SQL instance `bugsink-pg` — stays
- Secret Manager `bugsink-db-password` — stays

This avoids a cascading rename of everything and keeps Terraform diffs small.

Internal "rename everything" can come later (or never) — don't conflate it with the split.
