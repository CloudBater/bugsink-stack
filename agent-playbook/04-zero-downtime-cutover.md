# Prompt: Zero-downtime cutover (shared → split architecture)

> Paste when moving from a single shared BugSink to split prod + non-prod instances.

---

I'm splitting my single BugSink instance into prod + non-prod per `bugsink-stack/docs/11-split-vs-shared.md`. Drive the zero-downtime cutover described in `docs/12-zero-downtime-cutover.md`.

## Current state

- One BugSink instance at `bugsink.example.com` serving dev/staging/prod events, in my non-prod cloud project
- I want prod events to go to a new instance in my prod cloud project
- New canonical URLs:
  - `bugsink.example.com` → **new prod instance** (in prod cloud project)
  - `dev-bugsink.example.com` → **existing instance** (renamed, staying in non-prod project, serves dev/staging/sandbox)

## Your workflow

Follow the 6-step sequence in `docs/12-zero-downtime-cutover.md`. Open PRs per step; don't execute anything without my explicit "go".

### Step 1 (T-1 day): lower DNS TTL

- Change `bugsink.example.com` A-record TTL to 60s (was 300s or whatever)
- No PR needed — just tell me to do it in Cloudflare / Route 53 manually (or open a tiny PR if my DNS is Terraform-managed)

### Step 2: provision the new prod instance

- Reuse prompt 02 (`02-provision-infra.md`) to generate a new Terraform config for the prod cloud project
- Use a **temporary hostname** `bugsink-prod.example.com` (NOT the final one — don't touch the real DNS yet)
- After apply + verify, open the PR to merge

### Step 3: add the new non-prod hostname (`dev-bugsink.example.com`) to the existing instance

- Update existing instance's Ingress to serve **both** `bugsink.example.com` AND `dev-bugsink.example.com`
- Add a new ManagedCert / ACM cert for `dev-bugsink.example.com`
- Add the Cloudflare / Route 53 A-record `dev-bugsink` → existing instance IP
- Wait for cert provisioning (5-15 min)
- Verify: `curl -I https://dev-bugsink.example.com/accounts/login/` → 200

At this point: team can access non-prod via either URL. No impact.

### Step 4: cutover day

All in one sitting (~10 min work, < 1 min dashboard gap):

1. Remove `bugsink.example.com` from existing instance's Ingress `hosts`
2. Flip `bugsink.example.com` DNS A-record → prod instance IP
3. Add `bugsink.example.com` to prod instance's Ingress, provision new ManagedCert / ACM cert
4. Delete the temporary `bugsink-prod.example.com` Ingress + DNS record

Open as separate PRs if Ingress config is in separate repos, otherwise one PR with clear commit messages.

### Step 5: smoke test

- Log in at `bugsink.example.com` → should show prod instance (empty, brand new)
- Log in at `dev-bugsink.example.com` → should show existing events, existing projects, existing users
- Trigger a test error from prod → appears at `bugsink.example.com`
- Trigger a test error from dev → appears at `dev-bugsink.example.com`
- Both uptime checks healthy

### Step 6 (T+1 day): restore DNS TTL

- Change TTL back to 300s (or whatever your normal is)

## SDK DSN updates

After cutover (or before, during step 2):
- Non-prod envs (dev, staging, sandbox) point at the existing (renamed) instance — SDK DSN uses the **in-cluster SVC DNS**, so NO SDK change is needed because the SVC name didn't change
- Prod env points at the new prod instance — SDK DSN needs to be updated to the new in-cluster SVC DNS

This is a prod-only deploy. Stage it carefully:
- First: deploy prod with new DSN pointed at a warm prod BugSink
- Verify: click a test error button on prod, check new instance dashboard
- Rollback plan: revert the DSN env var to the old DSN, redeploy (SDK init fails soft)

## Guard rails

- **Run every step past me first.** Each step is low-risk on its own but stacking them creates complexity. I want to see each PR before it merges.
- **Verify cert provisioning before DNS flip.** ManagedCert / ACM can take 10-30 min. Don't flip DNS if the new cert isn't Active yet.
- **Announce in team Slack** before step 4 with a rollback plan.
- **Keep the old instance's data.** Don't delete anything during cutover. Non-prod historical events stay on the renamed instance.

## After cutover

```markdown
## Cutover verification

- [ ] bugsink.example.com → prod instance (empty, new)
- [ ] dev-bugsink.example.com → renamed existing instance (historical data intact)
- [ ] Prod uptime check updated to new instance's IP (or domain-based, unchanged)
- [ ] Prod Slack alert routing updated to #alerts-prod (not the combined dev/staging channel)
- [ ] All team members notified of the new non-prod URL
- [ ] Bookmarks updated in team docs
- [ ] Old instance's Kubernetes resources renamed? (optional — can stay "sandbox" internally)
```

Ready to start with Step 1 (TTL lowering)?
