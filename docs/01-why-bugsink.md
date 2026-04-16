# 01 — Why BugSink?

## The problem

Most teams running a production web application hit the same three pain points eventually:

1. **Frontend errors are invisible.** Unless a user emails you, you have no idea when the browser is throwing. A minified stack trace in a server log (`main.js:1:2048`) is worthless.
2. **Backend errors are buried.** Your log aggregator stores them, but nobody actively watches. You only find out when someone goes digging after a complaint.
3. **No grouping.** The same error across 500 users looks like 500 noisy events instead of one tracked issue.

The industry answer is **Sentry** or a compatible alternative. The question is: which one, and do you self-host?

## The tradeoffs

| Option | Direct cost | Ops burden | Data residency | When it's right |
|--------|-------------|------------|----------------|-----------------|
| **Sentry Cloud — Team** | **$26/mo** flat (50K errors, unlimited seats) | None | Sentry's infra (US/EU) | Small team, low-to-mid error volume, OK with SaaS |
| **Sentry Cloud — Business** | $80+/mo | None | Sentry's | Performance, replays, advanced workflows |
| **Sentry Self-Hosted** | Infra cost only, but stack is heavy (Postgres + Redis + Kafka + ClickHouse + Zookeeper + Relay + multiple Celery workers) | High | Your infra | Large team, already paying for ClickHouse+Kafka for other reasons |
| **GlitchTip** | Infra (~$20-40/mo) | Medium (Postgres + Redis + Celery + Django) | Your infra | Mid-size team, want Sentry-compatible + OAuth SSO |
| **BugSink** | **~$15-45/mo** infra (Postgres + single Django pod) | Light | Your infra | Small-to-mid team, errors-only, data residency matters |

## Honest cost comparison: BugSink vs Sentry Cloud

**Sentry Cloud Team at $26/mo is a real benchmark.** For a small team, if your only requirement is "errors in Slack," Sentry Cloud is often the cheapest, lowest-ops option — a $26 flat fee beats $15-45/mo of cloud infra plus your time setting up and maintaining it.

Break-even math for a small team:

| Scenario | Monthly | Pick |
|----------|---------|------|
| 1-3 devs, < 20K errors/mo, no data residency rules | Sentry Cloud Team $26 | **Sentry Cloud** |
| Small team but data residency required (SOC2, HIPAA, regulated industry) | BugSink ~$15-25 | **BugSink** |
| Small team, hobby/side project, want self-hosted for learning | BugSink ~$15 | **BugSink** |
| Mid team, 20-100K errors/mo, prod workload | BugSink ~$30 + ops time vs Sentry Team $26 + overages | **Do the math for your volume** |
| Large team, >100K errors/mo | Sentry Cloud overages get painful ($0.00022 per event over quota) | **BugSink or Sentry Self-Hosted** |
| Regulated + high volume | BugSink ~$45 | **BugSink (split architecture)** |

**BugSink wins when:**
- Data residency is a firm requirement (regulators, enterprise customers, paranoid CEO)
- You expect significant growth in error volume (self-hosted scales cheaper per event)
- You don't trust third-party uptime for your observability tool
- You want exit flexibility — BugSink uses the Sentry protocol, so migrating later is just a DSN change

**Sentry Cloud wins when:**
- You're a small team and $26/mo is below the "time to set up infra" threshold
- You want advanced features (performance monitoring, replays, profiling, issue alerting workflows)
- You don't want to be on-call for the monitoring tool itself

**If you pick BugSink and later regret it:** great news, that's a DSN change. Your app code doesn't know or care which Sentry-protocol server is on the other end. You haven't locked in.

**If you pick Sentry Cloud and later regret it:** same thing in reverse. Switching direction is just as easy.

This is a cheap decision to defer — start with whichever gets you to "errors in Slack in 30 minutes" and revisit in 6 months.

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
