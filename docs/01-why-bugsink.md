# 01 — Why BugSink?

## The problem

Most teams running a production web application hit the same three pain points eventually:

1. **Frontend errors are invisible.** Unless a user emails you, you have no idea when the browser is throwing. A minified stack trace in a server log (`main.js:1:2048`) is worthless.
2. **Backend errors are buried.** Your log aggregator stores them, but nobody actively watches. You only find out when someone goes digging after a complaint.
3. **No grouping.** The same error across 500 users looks like 500 noisy events instead of one tracked issue.

The industry answer is **Sentry** or a compatible alternative. The question is: which one, and do you self-host?

## The tradeoffs

| Option | Cost | Ops burden | Data residency | When it's right |
|--------|------|------------|----------------|-----------------|
| **Sentry Cloud** | $26+/seat/mo + event overage | None | Sentry's infra | Small team, no data residency needs, OK with per-event pricing |
| **Sentry Self-Hosted** | Free | Heavy (Postgres + Redis + Kafka + ClickHouse + Zookeeper + Relay + several Celery workers) | Your infra | Large team that will use advanced features (performance monitoring, session replay, profiling) |
| **GlitchTip** | Free | Medium (Postgres + Redis + Celery + Django) | Your infra | Mid-size team, want Sentry-compatible + a little lighter |
| **BugSink** | Free | Light (Postgres + Django, single pod) | Your infra | Small-to-mid team, errors-only, want minimal ops |

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
