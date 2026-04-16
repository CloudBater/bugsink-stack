# 14 — Gotchas (GCP-Specific)

GCP-only issues layered on top of [`13-gotchas.md`](13-gotchas.md).

---

## 1. `cloud.google.com/neg` Service annotation can silently disappear

The **#1 cause** of intermittent 502 `failed_to_pick_backend` errors on GKE Ingress.

GKE's NEG Controller auto-adds `cloud.google.com/neg: '{"ingress":true}'` to Services referenced by an Ingress. Most of the time. Sometimes — usually after a Helm upgrade that rewrites the Service — the annotation gets stripped and the NEG Controller doesn't re-add it. The NEG then stops reconciling. Pod rotations leave stale IPs in the NEG. Ingress tries the dead IP → 502.

**Symptoms:**
- Intermittent 502s with `statusDetails: "failed_to_pick_backend"` in LB logs
- `gcloud compute backend-services get-health` shows an IP that's not the current pod
- `kubectl get svc -o yaml` shows no `cloud.google.com/neg-status` annotation (normally populated by the controller)

**Fix (immediate):**

```bash
kubectl annotate svc <svc> -n <ns> cloud.google.com/neg='{"ingress":true}' --overwrite
```

NEG Controller reconciles within ~30 seconds; stale IP gets replaced.

**Fix (permanent):** declare the annotation in your Helm chart's Service template so it never gets stripped:

```yaml
# helm/templates/service.yaml
metadata:
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
```

---

## 2. Cloud Armor `inIpRange` CEL has a 5-entry cap

Want to allowlist the 54 GCP uptime-checker source IPs via a CEL expression? You can't fit them in one rule:

```
srcIpRanges: ["1.2.3.4/32", "5.6.7.8/32", ...]  # works up to 10 per srcIpRanges
```

vs.

```
expression: 'inIpRange(origin.ip, "1.2.3.4/32") || inIpRange(origin.ip, ...) ...'
```

CEL expressions hit a 5-clause cap.

**Fix:** use `srcIpRanges` (supports 10 IPs per rule). Split the 54-IP list across 6 rules (priorities 1200-1205). See `examples/terraform/gcp/cloud-armor.tf`.

---

## 3. ManagedCertificate provisioning requires a healthy backend

GKE ManagedCert won't move from `Provisioning` → `Active` until the backend service has a healthy target. Chicken-and-egg:
- Cert won't provision because backend is unhealthy
- Backend is unhealthy because some health check is 4xx-ing
- You can't test the backend externally because the cert isn't ready

**Fix:**
1. Deploy the pod first (BugSink on a `http://` Ingress if needed temporarily, or just internal port-forward to verify the pod is healthy)
2. Once pod is healthy, the ManagedCert provisioning completes within 10-30 min

Watch status:

```bash
kubectl describe managedcertificate -n <ns>
```

---

## 4. Cloud Build egress IP is unpredictable

You can't allowlist "Cloud Build" in Cloud Armor — GCP doesn't publish a stable egress range. This is why source-map upload belongs in an in-cluster Helm Job, not in the Cloud Build step.

---

## 5. Cloud SQL proxy sidecar `--private-ip` on private-only instances

If you created the Cloud SQL instance with `--no-assign-ip` (recommended), the Auth Proxy must connect over private networking:

```yaml
- name: cloud-sql-proxy
  image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.x
  args:
  - --private-ip
  - --port=5432
  - your-project:region:instance-name
```

Without `--private-ip`, the proxy tries to reach the Cloud SQL public IP — which doesn't exist → connection refused.

---

## 6. Cloud SQL proxy refreshes ephemeral certs every ~55 min

The proxy maintains a long-lived TLS tunnel to Cloud SQL. Every ~55 minutes it refreshes the ephemeral cert. If Django's connection pool has a long-lived connection that crosses this boundary, the connection dies and the next query throws.

**Symptom:** periodic `OperationalError: server closed the connection unexpectedly` every hour-ish.

**Fix:** set `CONN_MAX_AGE=0` in Django's `DATABASES` setting. This makes Django open a fresh connection per request instead of pooling. Tiny perf hit (~1ms per request for TCP handshake) is worth the reliability.

Long-term: run PgBouncer as a sidecar or use `django-db-connection-pool` with a RECYCLE interval shorter than the cert refresh window.

---

## 7. Helm values.yaml pattern for StatefulSet PVC

`volumeClaimTemplates` on a StatefulSet is **immutable after creation**. Any change to the PVC spec in values.yaml will fail `helm upgrade` with a confusing error about StatefulSet update policy.

**Fix:** to change PVC size or class, delete the StatefulSet with `--cascade=orphan` (keeps the pods running), then `helm upgrade`:

```bash
kubectl delete statefulset bugsink -n bugsink --cascade=orphan
helm upgrade bugsink . -n bugsink -f values.yaml
```

---

## 8. GKE Autopilot restrictions

On Autopilot clusters, you can't:
- Set arbitrary securityContext fields
- Use `hostPath` volumes
- Run privileged containers

BugSink doesn't need any of these. But if you're trying to apply a generic k8s manifest from the wild, you may hit `invalid value` errors on Autopilot that work on Standard clusters.

---

## 9. Cloud Build region vs prod region mismatch

If your prod GKE cluster is in `asia-southeast1` but your Cloud Build trigger runs in `asia-east1`, the build artifacts are pushed to a regional Artifact Registry in `asia-east1`. Prod cluster can pull cross-region but pays egress.

**Fix:** match Cloud Build region to target cluster region for prod triggers.

---

## 10. `gcloud` configuration context confusion

If you have multiple GCP projects (dev + prod), forgetting to switch configurations before running `gcloud` commands leads to deploying to the wrong project.

**Fix:** use `gcloud config configurations`:

```bash
gcloud config configurations create prod
gcloud config set project prod-project-id
gcloud config configurations activate prod  # explicit switch
```

Or always pass `--project=...` on every command. Scripts should echo the active project before destructive ops.
