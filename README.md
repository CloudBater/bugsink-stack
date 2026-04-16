# bugsink-stack

**A battle-tested, cloud-agnostic playbook for deploying self-hosted error tracking** using [BugSink](https://www.bugsink.com/) + any Sentry-compatible SDK.

Ship error tracking for your FE + BE stack in a day instead of a month. Every hard lesson learned the hard way is already in `docs/13-gotchas.md` so you don't have to rediscover them.

---

## What you get

- **Reference architecture** for single-instance and split (prod/non-prod) deployments
- **Full deploy walkthroughs** for GCP GKE and AWS EKS (+ a Docker Compose fallback)
- **SDK integration snippets** for React, Vue, Angular, Next.js, Django, FastAPI, ASP.NET Core, Express
- **Working Kubernetes manifests and Helm chart**
- **Terraform modules** for GCP (Cloud SQL + Cloud Armor + Secret Manager) and AWS (RDS + WAF + Secrets Manager)
- **CI/CD pipelines** for Cloud Build, GitHub Actions, GitLab CI
- **A dozen+ anonymized gotchas** from real production deployments
- **Agent playbook** — run the whole deployment with an AI coding agent using the prompts in `agent-playbook/`

## Who this is for

You want Sentry-like error tracking but:
- Don't want to pay per-seat / per-event pricing ($26+/mo/seat adds up)
- Need data residency (errors, stack traces, user context never leave your infra)
- Have a small-to-mid team and don't need a full Sentry deployment

BugSink is Sentry SDK protocol compatible, so every official Sentry SDK (`sentry-sdk`, `@sentry/react`, `@sentry/nextjs`, `Sentry.AspNetCore`, etc.) just works against it.

## Quick start (10 minutes, Docker Compose)

```bash
git clone https://github.com/CloudBater/bugsink-stack.git
cd bugsink-stack/examples/docker-compose
cp .env.example .env  # edit SECRET_KEY + admin credentials
docker compose up -d
open http://localhost:8000
```

Then plug the DSN it gives you into your app:

```python
# Python
import sentry_sdk
sentry_sdk.init(dsn="http://<key>@localhost:8000/1", environment="dev")
```

```javascript
// JS/TS
import * as Sentry from "@sentry/react";
Sentry.init({ dsn: "http://<key>@localhost:8000/1", environment: "dev" });
```

See `docs/06-backend-integration.md` and `docs/07-frontend-integration.md` for the full list of language/framework snippets.

## Production deploy (Kubernetes)

Three flavors, pick one:

| Platform | Walkthrough | Complexity |
|----------|-------------|------------|
| **GCP GKE** | [`docs/03-deploy-gcp-gke.md`](docs/03-deploy-gcp-gke.md) | Medium |
| **AWS EKS** | [`docs/04-deploy-aws-eks.md`](docs/04-deploy-aws-eks.md) | Medium |
| **Generic Kubernetes** | [`examples/k8s/`](examples/k8s/) | Easiest — just `kubectl apply` |

Each walkthrough covers:
1. Postgres backing store (managed Cloud SQL / RDS or self-hosted)
2. Kubernetes manifests / Helm chart
3. TLS + internal-only access (WAF / IP allowlist)
4. Source-map upload pipeline
5. Self-monitoring (uptime check on BugSink itself)
6. Slack alerting

## Recommended reading order

1. [Why BugSink](docs/01-why-bugsink.md) — pick the right tool
2. [Architecture](docs/02-architecture.md) — one instance or split?
3. Pick your cloud: [GKE](docs/03-deploy-gcp-gke.md) or [EKS](docs/04-deploy-aws-eks.md)
4. [Backend integration](docs/06-backend-integration.md)
5. [Frontend integration](docs/07-frontend-integration.md)
6. [Source maps](docs/08-source-maps.md) — the part everyone gets wrong first time
7. [Security hardening](docs/09-security-hardening.md) — IP allowlist, why not IAP
8. [Uptime monitoring](docs/10-uptime-monitoring.md) — monitor BugSink itself
9. [Gotchas](docs/13-gotchas.md) — read before you start, thank me later

## Using with an AI coding agent

The whole deployment can be handled by an agent. See [`agent-playbook/README.md`](agent-playbook/README.md). Copy-paste prompts, the agent does the work, you approve the PRs.

## Repo layout

```
bugsink-stack/
├── docs/                    # 15 chapters, start with 01-why-bugsink.md
├── examples/
│   ├── k8s/                 # Cloud-agnostic Kubernetes manifests
│   ├── helm/bugsink/        # Helm chart
│   ├── terraform/gcp/       # GCP infra-as-code
│   ├── terraform/aws/       # AWS infra-as-code
│   ├── docker-compose/      # Single-host fallback
│   └── cicd/                # CI/CD pipeline templates
├── integrations/            # SDK integration examples per framework
└── agent-playbook/          # AI agent prompt templates
```

## Contributing

Issues and PRs welcome. Especially:
- Gotchas from your deployment (we'll anonymize and merge)
- New framework integrations
- Additional clouds (Azure AKS, DigitalOcean, Linode, etc.)

## License

MIT — do whatever you want.

## Acknowledgements

- [BugSink](https://www.bugsink.com/) for building a lean, self-hostable error tracker
- [Sentry](https://sentry.io/) for creating the SDK protocol and OSS SDKs that everything else rides on
- The anonymized lessons in `docs/13-gotchas.md` came from real production deployments — thanks to every engineer who hit these and documented the fix
