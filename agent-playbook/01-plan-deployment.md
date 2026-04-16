# Prompt: Plan a BugSink deployment

> Paste after `00-context.md`. Agent produces a written plan; no code changes yet.

---

Using the `bugsink-stack` repo as reference, write me a **deployment plan** for BugSink tailored to my stack.

## What I want in the plan

1. **Architecture choice** — single shared instance, or split prod vs non-prod? Pick the right one for my team size and traffic, referencing `docs/11-split-vs-shared.md`. Justify briefly (2-3 sentences).

2. **Infra shopping list** — every cloud resource that needs to be created, grouped by Terraform file. For each, tell me:
   - Resource name I should use
   - Size / tier
   - Which existing thing it depends on (VPC, subnets, IAM roles, etc.)
   - Estimated monthly cost

3. **Kubernetes resources** — StatefulSet, Service, Ingress, ExternalSecret, ServiceAccount. Note any cloud-specific annotations (GKE `cloud.google.com/neg` or AWS ALB annotations).

4. **WAF / Cloud Armor rules** — list every rule by priority, with its purpose and source IP range. Flag any IP I need to provide before infra can be applied (NAT egress, office IPs).

5. **Uptime monitoring** — where the check lives (GCP Monitoring / Route 53 Health Check), alert destination (Slack channel), triage runbook content.

6. **DNS** — list hostnames to create and where (Cloudflare / Route 53), what they'll point at, TTL.

7. **Order of operations** — numbered step list, each with:
   - What to run / apply
   - Expected outcome
   - Verification step
   - What to do if it fails

8. **Gotchas to watch** — pull the 3-5 most relevant gotchas from `docs/13-15` for my cloud/stack combo.

9. **What you'll need from me** — list of values I need to provide before you can write the actual code (e.g. "Cluster NAT egress IP", "Office CIDR blocks", "Slack webhook URL").

## Constraints

- Don't write any Terraform / YAML / code yet — this is planning only.
- Use the existing `examples/` files as templates in your head; don't paste them.
- Plan should fit in one Markdown document, under ~2 pages printed.

## After the plan

Once I approve, I'll paste `02-provision-infra.md` to move to the implementation step.

Ready to produce the plan? Start by confirming you understand the stack I described, then deliver the plan.
