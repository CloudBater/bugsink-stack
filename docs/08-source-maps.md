# 08 — Source Maps

The part everyone gets wrong first time.

## The problem

Your bundler (Vite, Webpack, esbuild, Next.js, etc.) minifies your JS. A stack trace looks like:

```
TypeError: Cannot read property 'x' of undefined
  at fn (main.js:1:2048)
  at inner (main.js:1:1520)
```

Useless. You want:

```
TypeError: Cannot read property 'x' of undefined
  at Dashboard.render (src/pages/Dashboard.tsx:42:15)
  at handleClick (src/components/Chart.tsx:88:7)
```

That requires two things:
1. **Source maps generated** at build time (`.js.map` files)
2. **Source maps uploaded** to BugSink so it can resolve minified lines → original source

The official Sentry SDKs use [debug IDs](https://docs.sentry.io/platforms/javascript/sourcemaps/troubleshooting_js/artifact-bundles/) to match stack-trace frames with the correct source map. This is more robust than the old filename-based matching.

## The three-step recipe

### Step 1 — Inject debug IDs at build time

`sentry-cli sourcemaps inject` adds a unique ID to every minified JS file AND its corresponding `.js.map`. Add this to your Dockerfile **after the build step**:

```dockerfile
# Dockerfile
FROM node:20 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build  # produces .next/, dist/, build/, etc.

# Install sentry-cli (cached layer)
RUN curl -sL https://sentry.io/get-cli/ | sh

# Inject debug IDs into the built artifacts
RUN sentry-cli sourcemaps inject ./dist

FROM node:20-slim
COPY --from=builder /app/dist /app
CMD ["node", "/app/server.js"]
```

This step doesn't need BugSink credentials — it just edits the build artifacts.

### Step 2 — Upload source maps to BugSink

You have two options:

**Option A — During CI/CD (simple, but you need egress allowlisted)**

Add `sentry-cli sourcemaps upload` to your build pipeline AFTER `inject`. The CI runner talks to BugSink's public URL.

```bash
sentry-cli --url https://bugsink.example.com \
  --auth-token $SENTRY_AUTH_TOKEN \
  sourcemaps upload \
  --release "${ENVIRONMENT}-${IMAGE_TAG}" \
  ./dist
```

CI runner's egress IP needs to be in your BugSink WAF allowlist. On GCP Cloud Build, the egress IP is unpredictable (pool of Google Cloud IPs) — you'd have to allowlist a broad range. This usually rules out Option A for private BugSink.

**Option B — In-cluster Helm Job (recommended for private BugSink)**

Run the upload as a Kubernetes Job triggered by Helm's `post-install,post-upgrade` hook. The Job runs inside your cluster and uses the in-cluster SVC DNS for BugSink — no WAF traversal needed for most of the flow.

```yaml
# helm/templates/sourcemap-upload-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-sourcemap-upload
  annotations:
    helm.sh/hook: post-install,post-upgrade
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: upload
        image: {{ .Values.image.repository }}:{{ .Values.image.tag }}  # same image that has the built artifacts
        env:
        - name: SENTRY_AUTH_TOKEN
          valueFrom:
            secretKeyRef:
              name: bugsink-auth-token
              key: SENTRY_AUTH_TOKEN
        - name: SENTRY_URL
          value: {{ .Values.sentry.uploadJob.internalUrl }}  # http://bugsink-svc.bugsink.svc.cluster.local
        command:
        - /bin/sh
        - -c
        - |
          sentry-cli --url "$SENTRY_URL" \
            --auth-token "$SENTRY_AUTH_TOKEN" \
            sourcemaps upload \
            --release "{{ .Values.environment }}-{{ .Values.image.tag }}" \
            /app/dist
```

Create the API token secret once per namespace:

```bash
kubectl create secret generic bugsink-auth-token \
  --from-literal=SENTRY_AUTH_TOKEN="$(
    # fetch from your cloud's secret manager
    gcloud secrets versions access latest --secret=bugsink-api-token
  )"
```

### Step 3 — Tag your SDK init with the matching release

```ts
Sentry.init({
  dsn: ...,
  release: `${process.env.NODE_ENV}-${process.env.IMAGE_TAG}`,
});
```

This must match what you used in the `sentry-cli sourcemaps upload --release` flag. Otherwise BugSink sees events but doesn't know which source map to use.

---

## Caveat: the chunk-upload redirect

`sentry-cli` uploads in two steps:
1. GET `/api/0/organizations/.../chunk-upload/` — response includes an **absolute URL** derived from BugSink's `BASE_URL` env (e.g. `https://bugsink.example.com/api/...`)
2. POST chunks to that absolute URL

Even if you start the Job against the in-cluster SVC DNS, step 2 hits the **public URL** because that's what the server returned. So the Job's egress leaves the cluster → NAT → WAF/Cloud Armor.

**Fix:** allowlist your cluster's NAT egress IP in the BugSink WAF/Cloud Armor policy.

- GCP: find the IP via `gcloud compute routers get-nats`. Allowlist in Cloud Armor at priority 1100 or so.
- AWS: find the NAT GW EIP in the VPC console. Allowlist in WAFv2 IPSet.

This is still tighter than allowlisting CI egress ranges, but it's a real gotcha. Budget 15 minutes the first time you set this up.

---

## Artifact types: what gets uploaded

`sentry-cli sourcemaps upload ./dist` scans for:
- `*.js` and `*.mjs` files
- Their sibling `*.js.map` and `*.mjs.map` files
- Any `*.html` (for inline source maps)

Check the BugSink dashboard → project → Artifacts after deploy. You should see a release with hundreds of files (typical large FE app has ~800-1000 artifacts).

## Debugging: source maps aren't resolving

1. Verify artifacts uploaded: BugSink dashboard → Artifacts → your release → should list files
2. Verify release tag matches: compare SDK init `release` vs upload `--release`
3. Verify debug IDs are in the minified JS: `grep 'sentry-dbid' ./dist/*.js | head` — should show IDs
4. Verify debug IDs in the `.js.map` file too: `grep 'debug_id' ./dist/*.js.map | head`
5. Check the Issue detail page — there's usually a "source map status" indicator showing which frame matched / didn't match
