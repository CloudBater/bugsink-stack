# 12 — Zero-Downtime Domain Cutover

When you need to move `bugsink.example.com` from one BugSink instance to another (typically during a split — see [`docs/11-split-vs-shared.md`](11-split-vs-shared.md)).

## What actually has downtime?

**Applications (the thing users touch): zero downtime.** SDK is fire-and-forget. If BugSink is unreachable for 30 seconds, the SDK logs a warning internally and the app keeps serving. Users see nothing.

**SDK ingest: unaffected by domain work.** Apps that live in the same cluster use in-cluster SVC DNS (`bugsink-svc.bugsink.svc.cluster.local`) — they never resolve `bugsink.example.com` at all.

**BugSink dashboard: brief interruption** during the DNS flip. Target is < 1 minute if you prep correctly.

## The zero-downtime sequence

6 steps. Do them in order. Steps 1-3 can be spread over days; steps 4-5 happen in one sitting.

### Step 1 — T-minus-1-day: lower DNS TTL

```bash
# Cloudflare example
# API or dashboard: set TTL on bugsink.example.com A-record to 60s
```

Do this at least 24 hours before cutover so the old 300s (or whatever) TTL has time to expire everywhere.

### Step 2 — Stand up the new instance on a temporary hostname

Deploy the new BugSink in its target cloud/project on a scratch hostname:

```yaml
# new instance Ingress
hosts:
- bugsink-new.example.com  # temporary
```

Provision the ManagedCert / ACM cert for this scratch hostname. Wait for `Active` / `ISSUED`.

Verify end-to-end: log in, create a project, trigger a test event from a canary deployment. Confirm it lands.

### Step 3 — Add the future hostname to the old instance as a second hostname

Before swapping, set up the old instance to serve BOTH its current hostname AND the new non-prod hostname (e.g. `dev-bugsink.example.com`). This lets you move users to the new URL before the DNS flip.

```yaml
# old instance Ingress
hosts:
- bugsink.example.com        # still serving current users
- dev-bugsink.example.com    # new URL for non-prod dashboard
```

- Provision the new ManagedCert / ACM cert for `dev-bugsink.example.com`
- Add Cloudflare A-record `dev-bugsink` → current instance's IP

Wait for cert provisioning (5-15 min). Verify you can reach the dashboard via both hostnames. Email / Slack the team: "non-prod dashboard has moved to `dev-bugsink.example.com`, bookmark the new URL. Old URL still works for now."

### Step 4 — Cutover (one sitting)

Three changes in rapid sequence:

1. **Remove the shared hostname from the old instance Ingress**
   ```yaml
   hosts:
   - dev-bugsink.example.com   # drop bugsink.example.com
   ```
   Apply (helm upgrade or kubectl apply). The old instance now only responds to `dev-bugsink.example.com`.

2. **Flip `bugsink.example.com` DNS to the new instance's IP**
   ```bash
   # Cloudflare API or dashboard
   # Update A-record: bugsink.example.com → new-instance-ip
   ```
   Clients start resolving to the new instance within ~60s (your lowered TTL).

3. **Swap the new instance's Ingress from the temp hostname to the real one**
   ```yaml
   # new instance Ingress
   hosts:
   - bugsink.example.com   # was bugsink-new.example.com
   ```
   Provision new ManagedCert for `bugsink.example.com`. Wait for `Active`.

Dashboard gap during this window: ~10 seconds to several minutes depending on cert provisioning speed. If you want truly zero gap, include `bugsink.example.com` on the new instance Ingress from step 2 (provision the cert in advance), so when DNS flips the new instance is already ready to serve it.

### Step 5 — Clean up

- Remove the temporary Cloudflare A-record for `bugsink-new.example.com`
- Delete the temporary ManagedCert

### Step 6 — T-plus-1-day: restore DNS TTL

```bash
# Cloudflare: set TTL back to 300s or whatever normal is
```

## What to test after cutover

1. `bugsink.example.com` → loads prod BugSink dashboard, not non-prod data
2. `dev-bugsink.example.com` → loads non-prod BugSink dashboard
3. Both uptime checks healthy (update the prod check to watch the new IP if needed)
4. SDK ingest from prod app → new instance (check the new instance's dashboard for recent events)
5. SDK ingest from non-prod app → old instance (now dev-bugsink; verify events landing)

## If something goes wrong mid-cutover

The safest rollback:

1. Restore DNS for `bugsink.example.com` to the old instance's IP
2. Put `bugsink.example.com` back on the old instance's Ingress
3. Keep the new instance running on its temp hostname (you can retry later)

Since TTL is at 60s, rollback propagates within minutes. You're not stuck.

## The "easy mode" alternative

If you can tolerate a 5-minute dashboard gap, you can do this in a single step:

1. Remove `bugsink.example.com` from old instance
2. Wait for DNS TTL expiry (~5 min with default TTL)
3. Add `bugsink.example.com` to new instance, provision cert

Simpler, but dashboard is hard-down during those 5 minutes + cert provisioning. Fine for small teams that are willing to announce a maintenance window. Not fine if on-call might need the dashboard mid-incident.

## Key point to remember

**Apps don't care.** SDK ingest is in-cluster and independent of this whole DNS song-and-dance. You are only moving the human-facing dashboard URL. Treat this like moving a bookmark, not like migrating a service.
