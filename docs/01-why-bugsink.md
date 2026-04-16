# 01 — Why BugSink?

## The problem

Most teams running a production web application hit the same three pain points eventually:

1. **Frontend errors are invisible.** Unless a user emails you, you have no idea when the browser is throwing. A minified stack trace in a server log (`main.js:1:2048`) is worthless.
2. **Backend errors are buried.** Your log aggregator stores them, but nobody actively watches. You only find out when someone goes digging after a complaint.
3. **No grouping.** The same error across 500 users looks like 500 noisy events instead of one tracked issue.

The industry answer is **Sentry** or a compatible alternative. The question is: which one, and do you self-host?

## Feature comparison (2026)

Pricing sourced from [sentry.io/pricing](https://sentry.io/pricing). Self-hosted costs are rough cloud-infra estimates at small scale.

| Feature | BugSink (self-hosted) | Sentry Developer (Free) | Sentry Team | Sentry Business | Sentry Self-Hosted | GlitchTip (self-hosted) |
|---------|-----------------------|-------------------------|-------------|-----------------|--------------------|------------------------|
| **Monthly price** | ~$15-45 infra | $0 | **$26** annual | **$80** annual | ~$200-500 infra (heavy stack) | ~$20-40 infra |
| **Error quota** | Unlimited (you pay storage) | 5,000 | 50,000 | 50,000 | Unlimited | Unlimited |
| **Error overage** | Cloud SQL storage | Hard cap | $0.0003625 / error | $0.0003625 / error | None | None |
| **Tracing spans** | N/A (errors only) | 5M | 5M | 5M | Included | N/A |
| **Session replays** | N/A | 50 | 50 | 50 | Included | N/A |
| **Attachments** | PVC (5-50 GB) | 1 GB | 1 GB | 1 GB | Your disk | Your disk |
| **Users** | Unlimited | 1 | Unlimited | Unlimited | Unlimited | Unlimited |
| **Data retention** | Configurable (default 90d) | 30 days | 90 days | 90 days + sampled | Configurable | Configurable |
| **SAML / SCIM SSO** | ❌ shared account only | ❌ | ❌ | ✅ | ✅ (if you set it up) | ✅ OAuth |
| **Third-party integrations** | Webhook (Slack, etc.) | ❌ | ✅ | ✅ | ✅ | Limited |
| **Custom dashboards** | Limited | 10 | 20 | Unlimited | ✅ | Limited |
| **SOC2 / ISO 27001** | Your infra's posture | ❌ | ❌ | ✅ | Your infra's posture | Your infra's posture |
| **HIPAA / BAA** | Your infra's posture | ❌ | ❌ | ❌ (Enterprise only) | Your infra's posture | Your infra's posture |
| **Data residency (US/EU/your cloud)** | ✅ entirely yours | ❌ | ❌ | ❌ (Enterprise only) | ✅ | ✅ |
| **Ops burden** | Light (1 pod + Postgres) | None | None | None | **Heavy** (Kafka + ClickHouse + Redis + Celery + Relay + Zookeeper) | Medium (Django + Postgres + Redis + Celery) |
| **Setup time to "errors in Slack"** | ~1 hour (one-time) | 10 min | 10 min | 10 min | Days | Hours |
| **SDK compatibility** | Sentry SDK (exit ramp) | Sentry native | Sentry native | Sentry native | Sentry native | Sentry SDK (exit ramp) |

## Cost break-even by error volume

The big variable is error volume. Here's what each option costs at different points (Sentry Team overage math applied over its 50K/mo allowance):

| Monthly errors | BugSink | Sentry Team | Sentry Business | Cheapest by direct cost |
|----------------|---------|-------------|-----------------|-------------------------|
| 5,000 | $15 | $0 (Developer) / $26 (Team) | $80 | **Sentry Developer** (free) |
| 20,000 | $15 | $26 | $80 | BugSink (but set-up time evens it) |
| 50,000 | $15 | **$26** | $80 | Very close — call it a tie, pick on features |
| 100,000 | $15 | $26 + $18 = $44 | $80 | BugSink |
| 250,000 | $20 | $26 + $72 = $98 | $80 + $72 = $152 | **BugSink** |
| 500,000 | $25 | $26 + $163 = $189 | $80 + $163 = $243 | **BugSink** |
| 1,000,000 | $30 | $26 + $344 = $370 | $80 + $344 = $424 | **BugSink** |
| 10,000,000 | ~$80 (need db-g1-small + storage) | $26 + $3,606 = $3,632 | $80 + $3,606 = $3,686 | **BugSink** (~50x cheaper) |

> Sentry overage priced at $0.0003625/error (Team tier, 50-100K band; pricing tiers vary above that).
> BugSink cost scales sub-linearly — the big step is Postgres tier (`db-f1-micro` → `db-g1-small` → `db-n1-standard-2`).

**The crossover is around 50-100K errors/month.** Below that, Sentry Team's $26 flat fee is hard to beat once you factor in setup and ops time. Above that, BugSink pulls ahead sharply and the gap widens with volume.

## Decision guide by scenario

| Scenario | Best pick | Why |
|----------|-----------|-----|
| **Solo dev / side project** | Sentry Developer (Free) | 5K errors is plenty, $0 is unbeatable |
| **Startup, 2-5 devs, pre-PMF** | Sentry Team ($26) | Low volume, low cost, zero ops — focus on product |
| **Small team, <100K errors, no compliance** | Sentry Team | Cheaper than BugSink when you factor in your time |
| **Small team, needs HIPAA/SOC2/data residency** | **BugSink** | Sentry HIPAA requires Enterprise; data stays in your infra |
| **Mid team, 100K-1M errors/mo** | **BugSink** | Overages add up fast on Sentry; BugSink stays flat |
| **Mid team, need SAML SSO for 20+ users** | Sentry Business OR GlitchTip | BugSink has no SSO; GlitchTip does |
| **Large team, >1M errors/mo** | **BugSink** or Sentry Self-Hosted | SaaS overage = $400+/mo and climbing |
| **Regulated (HIPAA, PCI-DSS, financial, healthcare)** | **BugSink** | Full data residency, no vendor in the chain |
| **Need session replay + performance traces** | Sentry (Team or Business) | BugSink is errors-only by design |
| **Massive enterprise (10M+ errors, multi-region, BAA)** | Sentry Enterprise or Sentry Self-Hosted | BugSink works but features gap matters at scale |

## The three hidden costs of each choice

**BugSink hidden costs:**
- **Your time** — ~4-6 hours initial setup, ~30 min/month for Helm upgrades and patches
- **On-call for the monitoring tool itself** — you need to alert on BugSink's own uptime (see [`docs/10-uptime-monitoring.md`](10-uptime-monitoring.md))
- **No built-in SSO** — shared team account + IP allowlist is fine but not zero-trust

**Sentry Cloud hidden costs:**
- **Overages** — easy to blow through 50K errors in one buggy deploy
- **Seat-unrelated overages for logs, uptime checks, cron monitors, profiling** — they add up if you use multiple Sentry features
- **Vendor lock-in for data** — historical events are in Sentry's storage, hard to export if you leave

**Sentry Self-Hosted hidden costs:**
- **Heavy infrastructure** — 6+ services to run (Postgres + Redis + Kafka + ClickHouse + Zookeeper + Relay + Celery)
- **Upgrade pain** — multi-service migrations are rare but brutal
- **Requires a real ops person, not a side project**

## No lock-in either direction

BugSink, Sentry Cloud, Sentry Self-Hosted, and GlitchTip all speak the same SDK protocol. **Switching between them is a DSN change in your app, not a rewrite.** Historical events don't migrate (each tool's storage is proprietary), but future events just start flowing to the new backend.

This makes the choice low-stakes — pick what makes sense today, switch in 6 months if you were wrong. The only truly sticky decision is "Sentry-compatible vs not" (e.g. Rollbar, Datadog Error Tracking use different protocols).

## TL;DR

- **Small team, low volume, no compliance rules:** Sentry Cloud Team at $26/mo. Don't overthink it.
- **Everyone else:** BugSink pulls ahead either on cost, compliance, or both.
- **Very large teams with deep pockets and complex needs:** Sentry Business or Enterprise, or Sentry Self-Hosted if you have an SRE team.

## Why BugSink (for most teams)

- **One pod.** Single Django app, single Postgres database. No Redis, Kafka, ClickHouse, Celery workers.
- **Sentry SDK compatible.** Your `sentry-sdk` / `@sentry/react` / etc. point at BugSink with a DSN change. No rewrite.
- **Runs on cheap hardware.** `200m CPU / 256Mi RAM + db-f1-micro Postgres` handles thousands of events per day. Total ~$15-25/mo.
- **Actively maintained.** Focused, opinionated, ships regularly.
- **Exit ramp preserved.** If you outgrow BugSink, every SDK already speaks Sentry — switching to GlitchTip or Sentry Cloud is a DSN change, not a rewrite.

## When NOT to pick BugSink

- You need **performance monitoring (APM), traces, session replay, or profiling.** BugSink is errors-only by design. Use OpenTelemetry + Tempo/Jaeger for traces; BugSink for errors.
- You need **SSO / OIDC** on the dashboard. BugSink has only username/password. Use a shared team account + VPN/IP allowlist, or pick GlitchTip (OAuth support).
- You have **tens of thousands of events per minute.** BugSink's single-pod architecture caps out sooner than Sentry's distributed one. Benchmark first.

## What BugSink does well

- Stack traces with source maps (FE) and full Python/Node/Ruby/PHP/.NET traces (BE)
- Issue grouping (deduplicate repeated errors)
- Release tracking
- Environment tagging (dev / staging / prod)
- Breadcrumbs (recent user actions leading up to the error)
- Slack / webhook integration
- REST API (read events, issues, projects, releases programmatically)

## Deployment footprint (reference)

```
┌──────────────────────┐
│ BugSink (1 pod)      │
│  ├─ Django app       │  200m CPU / 256Mi RAM
│  ├─ Gunicorn workers │
│  └─ Cloud SQL proxy  │
└──────────────────────┘
          │
          ▼
┌──────────────────────┐
│ Postgres             │
│  db-f1-micro         │  0.6 GB RAM, shared vCPU
│  5-10 GB storage     │  $7-10/mo
└──────────────────────┘
```

For high-volume or production-critical deployments, upsize Postgres to `db-g1-small` (1.7 GB RAM, ~$25/mo). See [`docs/11-split-vs-shared.md`](11-split-vs-shared.md).

## Bottom line

If you're a small-to-mid team and you want **"error alerts in Slack within a minute, stack traces that make sense, grouped issues you can close"** — BugSink is the fastest path from zero to running. If you end up needing more, switching later is cheap.
