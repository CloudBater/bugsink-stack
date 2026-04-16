# Agent Playbook

Use an AI coding agent (Claude Code, Cursor, GitHub Copilot, etc.) to handle BugSink deployment end-to-end.

The prompts in this folder are self-contained: paste one into your agent, answer the questions it asks, review the PR it opens.

## How to use

1. **Clone this repo into the target project** (or reference it via URL). The agent will read `bugsink-stack/docs/` and `bugsink-stack/examples/` as source of truth.
2. **Pick a prompt from this folder** based on what you want to do:
   - [`01-plan-deployment.md`](01-plan-deployment.md) — agent writes a deployment plan tailored to your stack
   - [`02-provision-infra.md`](02-provision-infra.md) — agent runs the Terraform and Helm steps
   - [`03-integrate-sdk.md`](03-integrate-sdk.md) — agent wires up the Sentry SDK in your FE and BE codebases
   - [`04-zero-downtime-cutover.md`](04-zero-downtime-cutover.md) — agent executes the domain swap when moving from shared → split instances
3. **Paste the prompt into your agent's chat window**. Answer whatever clarifying questions it asks about your cloud, cluster, domain, etc.
4. **Review the diff / plan the agent produces before applying**. Don't skip this step — agents hallucinate IP addresses.

## Agent briefing: what you need to tell your agent

When you paste one of these prompts, you're asking the agent to:
- Read `docs/` (especially 01-02 for context, 13-15 for gotchas)
- Read `examples/` for ready-to-copy manifests
- Read `integrations/<your-framework>/` for SDK wiring

Tell your agent (or the prompt will tell it for you):
- **Your cloud**: GCP or AWS
- **Your cluster name / region**
- **Your FE framework** (React, Vue, Angular, Next.js, etc.)
- **Your BE framework** (Django, FastAPI, .NET, Express)
- **Your production domain**
- **Your GitHub org + PR conventions**

## Expected agent behavior

A well-briefed agent working through these prompts will:
- ✅ Generate Terraform from `examples/terraform/{gcp,aws}/` with your values substituted
- ✅ Generate a Helm values file with your domain, DB connection, Secrets Manager references
- ✅ Write SDK init code in your FE + BE projects
- ✅ Open a PR with deployment changes
- ✅ Write a summary of what was done + remaining manual steps (DNS configuration, Slack webhook URL)
- ❌ NOT execute `terraform apply` or `helm install` without your explicit "go" — these are side-effectful; ask first
- ❌ NOT invent IP addresses — if it doesn't know your NAT egress IP, it should ask

## Why use an agent for this?

The BugSink deployment is well-documented enough that the tedious parts (copying Terraform snippets, substituting values, wiring SDKs across multiple files) are genuinely mechanical. A coding agent can knock out steps 1-3 in 30 minutes while you review.

The interesting decisions (split vs shared, which envs feed which instance, how strict the WAF allowlist should be) are still on you — the agent will ask.

## What to review carefully

- **Cloud Armor / WAF rule IP addresses.** Agents hallucinate CIDR ranges. Verify against your actual office IPs and cluster NAT egress.
- **`SENTRY_DSN` wiring.** Make sure the DSN points at the right instance (dev vs prod). Agent might guess based on naming conventions.
- **Secrets.** The agent should NEVER put actual secret values in Terraform or YAML. It should only reference Secret Manager entries by name. Review for any accidental plaintext.
- **Rollout order.** If deploying to prod, the agent should stage dev first, verify, then prod. Reject PRs that deploy prod directly.

## Files

| File | When to use |
|------|-------------|
| [`00-context.md`](00-context.md) | Paste first to give agent full context on this repo |
| [`01-plan-deployment.md`](01-plan-deployment.md) | First-time deployment — agent produces a plan |
| [`02-provision-infra.md`](02-provision-infra.md) | After plan approval — agent writes Terraform/Helm |
| [`03-integrate-sdk.md`](03-integrate-sdk.md) | Wire up SDKs in your FE + BE |
| [`04-zero-downtime-cutover.md`](04-zero-downtime-cutover.md) | Split existing shared instance into prod + non-prod |
