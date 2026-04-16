# Prompt: Provision BugSink infrastructure

> Paste after plan approval (step 01). Agent writes code + opens PRs.

---

Per the deployment plan we agreed on, write the infrastructure code and open PRs.

## Your workflow

1. **Create a feature branch** following my team's conventions (check recent PRs for format — usually something like `feature/LT-XXXX-...` or `feat/...`).

2. **Write Terraform** in a new directory (e.g. `infra/terraform/bugsink/`) based on `bugsink-stack/examples/terraform/{gcp,aws}/`. Substitute the values I provided. Do NOT inline any secret values — reference Secret Manager / Secrets Manager entries by name.

3. **Write Helm values** in a new file (e.g. `k8s/bugsink/values.yaml`) based on `bugsink-stack/examples/helm/bugsink/values.{gcp,aws}.yaml`. Substitute cluster names, DB connection, secret references.

4. **Write Kubernetes manifests** only if not using Helm — otherwise skip.

5. **Run `terraform plan`** locally (if you have credentials) or just show me the expected plan as a comment in the PR.

6. **Open a PR** with:
   - Title: `feat(infra): provision BugSink instance for {env}`
   - Body: summary of resources, estimated cost, links to `bugsink-stack/docs/03-deploy-gcp-gke.md` (or EKS) for context
   - Checklist: what still needs to happen manually after merge (apply Terraform, create Slack webhook, DNS, first-time `createsuperuser`)

7. **Summarize for me**:
   - Files created
   - PR URL
   - What I need to approve / manually do next

## Guard rails

- **Before generating Terraform**, verify you have all these from me:
  - Cloud project / account ID
  - Region
  - VPC ID (AWS) or shared VPC config (GCP)
  - Office IP CIDR list
  - Cluster NAT egress IP
  - Slack webhook URL
  - Dashboard hostname
  - EKS OIDC provider (AWS) or GKE cluster location + name (GCP)

  If anything's missing, STOP and ask. Don't guess.

- **Never commit plaintext secrets** — even placeholder ones like "CHANGE_ME_PLEASE". Use Terraform `random_password` resources + Secret Manager entries.

- **Add `# <CHANGE_ME>` markers** on any line with a value I need to verify (e.g. hostnames).

- **Do not run `terraform apply`**. Generate code + PR, wait for my review and explicit approval before applying.

## After the PR is merged

In the PR description, include a follow-up checklist:

```markdown
## After merge

- [ ] `terraform init && terraform apply` in infra/terraform/bugsink/
- [ ] Verify Cloud SQL / RDS instance is Running
- [ ] Verify Secret Manager entries are populated
- [ ] Point DNS A-record at the Ingress IP (see outputs)
- [ ] Wait for ManagedCert / ACM cert to be Active
- [ ] `kubectl exec -it bugsink-0 -- bugsink-manage createsuperuser`
- [ ] Log in, create a project, grab the DSN — save to team password manager
- [ ] Validate uptime alert fires (scale replicas to 0, check Slack, scale back)
- [ ] Move to step 03 — integrate SDK into app code
```

Ready to generate the infrastructure code?
