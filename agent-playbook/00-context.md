# Agent Context — BugSink Stack

> Paste this FIRST into your agent's chat so it has the background.

You are helping me deploy **BugSink**, a self-hosted error-tracking tool that speaks the Sentry SDK protocol. I'm using the `bugsink-stack` repo (https://github.com/CloudBater/bugsink-stack) as the source of truth for deployment patterns.

## The repo's structure

```
bugsink-stack/
├── docs/                    # 15 chapters of reference material — READ THESE FIRST
├── examples/
│   ├── k8s/                 # Raw Kubernetes manifests
│   ├── helm/bugsink/        # Helm chart
│   ├── terraform/gcp/       # GCP infra-as-code
│   ├── terraform/aws/       # AWS infra-as-code
│   ├── docker-compose/      # Single-host fallback
│   └── cicd/                # CI/CD templates
├── integrations/            # Per-framework SDK snippets (React, Vue, Angular, Next.js, Django, FastAPI, .NET, Express)
└── agent-playbook/          # These prompts (you're reading one now)
```

## Critical reading order for you (the agent)

Before you suggest anything, read:

1. `docs/01-why-bugsink.md` — tradeoffs / when to use
2. `docs/02-architecture.md` — single vs split deployment shapes
3. `docs/13-gotchas.md` — cloud-agnostic lessons
4. `docs/14-gotchas-gcp.md` or `docs/15-gotchas-aws.md` — cloud-specific
5. The deployment walkthrough for my cloud: `docs/03-deploy-gcp-gke.md` OR `docs/04-deploy-aws-eks.md`
6. My framework's integration snippet under `integrations/`

## What you must not do

- **Do not `terraform apply`, `helm install`, or `kubectl apply` without my explicit "go ahead"**. Generate plans, show me diffs, wait for approval.
- **Do not invent IP addresses** for office allowlist, NAT egress, or anything else. If I haven't told you, ask.
- **Do not put actual secret values** (passwords, API tokens, SECRET_KEYs) in Terraform, YAML, or committed files. Always reference Secrets Manager / Secret Manager by name.
- **Do not deploy to prod first**. Always stage dev, verify, then prod.

## What you must do

- **Ask about cloud, cluster, domain, framework** at the start. Don't guess.
- **Produce PRs, not direct pushes**. Use the repo's existing branch + PR conventions (check recent merged PRs if unsure).
- **Match the existing commit style** in the target repo. Look at `git log --oneline -20` before making commits.
- **After each major step, summarize what changed and what's left**.

## Context I'll give you

Before we start, I'll tell you:

- Cloud: **[GCP / AWS]**
- Region: **[e.g. asia-east1, us-east-1]**
- Cluster name: **[e.g. my-gke-cluster]**
- Dashboard domain: **[e.g. bugsink.example.com]**
- Frontend framework: **[e.g. React + Vite, Next.js 14]**
- Backend framework: **[e.g. Django 5, FastAPI, .NET 8]**
- Deployment shape: **[single shared instance / prod+non-prod split]**

Ready? Paste one of the task prompts (`01-plan-deployment.md`, `02-provision-infra.md`, etc.) after this context message.
