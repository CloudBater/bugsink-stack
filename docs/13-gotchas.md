# 13 — Gotchas (Cloud-Agnostic)

Every one of these is a real incident someone else already lived through. Read before you start, save yourself days.

For cloud-specific gotchas, see [`14-gotchas-gcp.md`](14-gotchas-gcp.md) and [`15-gotchas-aws.md`](15-gotchas-aws.md).

---

## 1. BugSink container runs as UID 14237

BugSink's image uses a non-root user with UID `14237`. On first startup with a fresh PVC, the pod can't write to `/data` because the mount is owned by root.

**Fix:** init container to chown before the main container starts.

```yaml
initContainers:
- name: chown-data
  image: busybox:1.36
  command: ["sh", "-c", "chown -R 14237:14237 /data"]
  volumeMounts:
  - name: bugsink-data
    mountPath: /data
```

Or use the securityContext at the pod level:

```yaml
securityContext:
  fsGroup: 14237
```

---

## 2. IAP and BugSink don't mix

Google Cloud IAP (or any OAuth-gateway-before-your-app) breaks:
- SDK ingest (SDK can't negotiate OAuth flow)
- `sentry-cli` source-map upload (same reason)

**Fix:** don't use IAP. Use Cloud Armor IP allowlist instead. Same applies to AWS ALB authentication (Cognito / OIDC at the listener).

---

## 3. `ALLOWED_HOSTS` must be permissive or use the real hostname

BugSink is Django. Django checks `ALLOWED_HOSTS`. If the incoming `Host` header doesn't match, you get HTTP 400.

- GCP Load Balancer health checks hit the pod IP directly with `Host: <podIP>:8000`
- AWS ALB health checks can be configured to use the real hostname, but default to the target IP

**Fix (GCP):** set `ALLOWED_HOSTS=*` on BugSink. Cloud Armor upstream handles host filtering, so you're not opening host-header attacks.

**Fix (AWS):** in the ALB target group, configure health check with `Hostname` set to your real domain. Then `ALLOWED_HOSTS` can be restrictive.

---

## 4. `USE_X_REAL_IP` and `USE_X_FORWARDED_FOR` are mutually exclusive

Both env vars tell BugSink which header to trust for the client IP. Setting both = undefined behavior, sometimes drops the real IP and you see the LB's IP in logs and rate-limit keys.

**Fix:** set exactly one, depending on your LB:
- GCP LB: `X_FORWARDED_FOR_PROXY_COUNT=2` (LB prepends its own IP; count=2 strips LB + one upstream, leaving client IP)
- AWS ALB: `X_FORWARDED_FOR_PROXY_COUNT=1`

---

## 5. Cloud SQL Auth Proxy sidecar env ordering

If you use `DATABASE_URL=postgres://user:${DB_PASSWORD}@127.0.0.1:5432/bugsink` with `DB_PASSWORD` from a Secret, Kubernetes needs to substitute `$(VAR)` at container start. **`DB_PASSWORD` must be listed before `DATABASE_URL`** in the pod's env block, otherwise the substitution silently produces `postgres://user:@127.0.0.1...` (empty password).

**Fix:** always order secret-sourced vars before composite vars that reference them.

---

## 6. `loaddata` from SQLite creates duplicate auto-migrated rows

If you migrate from SQLite to Postgres via `dumpdata`/`loaddata`, and the target Postgres DB has already run migrations before you load, Django will have auto-created rows for:

- `phonehome.Installation` (BugSink-specific)
- `django_site` (Django's Site framework)
- Any model where migrations include `RunPython` data population

After `loaddata`, you'll have 2 rows in each — one from migrate, one from the SQLite export. BugSink's `Installation.objects.get()` will then throw `MultipleObjectsReturned` and every SDK POST returns 500.

**Fix:** either
- (a) add `--exclude=phonehome.installation --exclude=django.site` to your `dumpdata`, OR
- (b) after `loaddata`, deduplicate in Django shell:
  ```python
  from phonehome.models import Installation
  oldest = Installation.objects.order_by('created_at').first()
  Installation.objects.exclude(id=oldest.id).delete()
  ```

Keep the **older** row — it has the real `email_quota_usage` history.

---

## 7. Orphan pod after StatefulSet rename

If you change `metadata.name` or `spec.selector.matchLabels` on a StatefulSet, Kubernetes doesn't rename the existing pod — it leaves it orphaned with the old labels while creating a new pod with the new labels. Service endpoints see neither (old pod labels don't match SVC selector, new pod doesn't exist yet).

**Fix:** before helm upgrade, confirm label compatibility. If orphaned, reunite:

```bash
kubectl label pod bugsink-0 -n bugsink --overwrite \
  app.kubernetes.io/instance=bugsink-new
```

---

## 8. `SECRET_KEY` lost on helm upgrade

`helm upgrade` rewrites the Kubernetes Secret from the values.yaml template. If `values.bugsink.secretKey` is empty or missing, the Secret gets an empty value. The running pod keeps serving from its in-memory copy so nothing breaks **until** the next pod rotation, when the new pod reads the empty key and crashes with Django `security.W009`.

This is a silent time-bomb — can lurk for days between the bad upgrade and the next pod cycle.

**Fix:** move `SECRET_KEY` into an ExternalSecret that syncs from Secret Manager / AWS Secrets Manager. Remove it from `values.yaml` entirely. Helm still manages the rest of the Secret resource, but only the non-sensitive parts. Use `creationPolicy: Merge` on the ExternalSecret so both operators can coexist on the same Secret object.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: bugsink-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager  # or aws-secrets-manager
    kind: SecretStore
  target:
    name: bugsink-secret  # same name Helm uses
    creationPolicy: Merge
  data:
  - secretKey: SECRET_KEY
    remoteRef:
      key: bugsink-secret-key
  - secretKey: DB_PASSWORD
    remoteRef:
      key: bugsink-db-password
```

---

## 9. `sentry-cli` chunk-upload redirect leaves the cluster

`sentry-cli sourcemaps upload` does a 2-step flow:
1. GET `/api/0/organizations/.../chunk-upload/` → response includes **absolute URL** built from BugSink's `BASE_URL` env
2. POST chunks to that absolute URL

So even if your upload Job starts against the in-cluster SVC, step 2 uses the public URL. The Job's traffic exits the cluster via NAT, goes through the internet, hits your WAF/Cloud Armor, comes back in.

**Fix:** allowlist the cluster's NAT egress IP in your WAF/Cloud Armor policy.
- GCP: find via `gcloud compute routers get-nats`, allowlist at priority ~1100
- AWS: find NAT GW EIP, add to WAFv2 IPSet

See [`docs/08-source-maps.md`](08-source-maps.md) for the full setup.

---

## 10. Event retention uses storage faster than you think

BugSink defaults to 10,000 events per project before cleanup. A chatty app can hit this in a day.

**Symptoms:** Postgres storage fills up, backend alerts fire for "storage > 80%" on your Cloud SQL / RDS.

**Fix:** either
- Lower retention: set `retention_max_event_count=1000` per project (BugSink setting)
- Upsize Postgres storage
- Add a `before_send` in your SDK to filter noisy errors (404s, network timeouts, bot traffic)

---

## 11. Single shared DSN across environments hides environment bugs

If dev/staging/prod all use the same DSN, BugSink relies on your SDK's `environment` tag to separate them. If your SDK init misses the tag (e.g. `environment: undefined`), prod errors show up alphabetically interleaved with dev spam.

**Fix:** always set `environment` explicitly in SDK init. Never `process.env.NODE_ENV || 'unknown'`. Prefer one DSN per instance (the split architecture handles this cleanly).

---

## 12. CORS on the SDK ingest endpoint

BugSink handles CORS for the `/api/.../envelope/` endpoint automatically. But if you put it behind a CDN or proxy that strips CORS headers, browser SDK POSTs fail with CORS errors.

**Fix:** don't put the ingest endpoint behind a CDN that mutates headers. If you must, explicitly allow the Origin your app uses.

---

## 13. Release tag mismatch = unresolved source maps

Uploaded release `v1.14.0` but SDK init uses `v1.14`? Source maps won't match. Events show minified stack traces.

**Fix:** enforce consistency via a single `IMAGE_TAG` / `VERSION` env var used by both the upload command and the SDK init. CI should fail if the variable isn't set.

---

## 14. Slack webhook rate-limited during incidents

A large outage can fire hundreds of errors in seconds → hundreds of Slack webhook POSTs → Slack throttles your webhook → alert messages drop.

**Fix:** BugSink groups events into issues server-side. One new issue → one Slack message. But if you've configured alerts on "every new event" (don't), you'll hit this. Stick to issue-level alerting.

---

## 15. Timezone confusion in dashboard

BugSink dashboard shows event timestamps in the browser's local TZ. Postgres stores in UTC. Alert timestamps in Slack use the webhook's configured TZ (default UTC).

**Fix:** standardize on UTC in alerts and ops docs. Humans convert in their head.

---

## Meta-gotcha: read the logs before concluding "it's broken"

`kubectl logs -n bugsink bugsink-0 -c bugsink --tail=100` solves 80% of issues. Half the time the log says exactly what's wrong (empty SECRET_KEY, DB connection refused, ALLOWED_HOSTS rejected). Don't jump to reinstalling Helm before checking the pod's last 100 log lines.
