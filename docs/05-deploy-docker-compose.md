# 05 — Deploy with Docker Compose

Single-host deployment. Great for:
- Local dev
- Staging/demo environments without Kubernetes
- Homelab / side projects
- Proof-of-concept before committing to K8s

Not recommended for production unless you really know what you're doing with backups and monitoring.

## Quick start

```bash
cd examples/docker-compose
cp .env.example .env
# Edit .env — set SECRET_KEY, CREATE_SUPERUSER_* at minimum
docker compose up -d
open http://localhost:8000
```

First login uses the credentials from `CREATE_SUPERUSER_EMAIL` and `CREATE_SUPERUSER_PASSWORD` in `.env`.

## What's in the stack

See [`examples/docker-compose/docker-compose.yml`](../examples/docker-compose/docker-compose.yml):

- `bugsink` — the app (Python 3.12, gunicorn, 4 workers)
- `postgres` — Postgres 16, persistent volume
- `traefik` (optional) — TLS terminator with Let's Encrypt for publicly-exposed setups

## Persistent volumes

- `pg-data` — Postgres data directory
- `bugsink-data` — event files, source maps

Back these up if you care about the data. A simple cron:

```bash
docker exec bugsink-postgres pg_dump -U bugsink bugsink | gzip > /backup/bugsink-$(date +%F).sql.gz
```

## Upgrading

```bash
docker compose pull
docker compose up -d
```

BugSink runs its own migrations on startup.

## When to migrate off

Move to Kubernetes when:
- You need high availability
- The event volume overwhelms a single host
- You want Slack alerts integrated with your existing monitoring stack
- Compliance requires something more auditable

Migration path: `pg_dump` from compose setup → `pg_restore` into managed Postgres → deploy BugSink on K8s pointing at the new DB. Zero data loss if done with a brief maintenance window.

## Publicly exposing it

If you must expose this to the internet (vs VPN-only):

1. Terminate TLS (Let's Encrypt via Traefik in the compose example)
2. Put a reverse proxy in front with IP allowlisting (Cloudflare Access, Tailscale, or nginx with `allow`/`deny`)
3. Use a strong admin password
4. Still monitor it — set up an external uptime check (see [`docs/10-uptime-monitoring.md`](10-uptime-monitoring.md))

**SDK traffic note:** since your app pods aren't in the same Kubernetes cluster, all error events hit BugSink over the public internet. That means the public URL needs to accept SDK POSTs. Don't IP-allowlist so tightly that your app servers can't reach it.
