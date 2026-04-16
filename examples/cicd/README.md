# CI/CD Pipeline Templates

Copy-paste templates for integrating BugSink source-map upload into your build pipelines.

These examples cover the **"inject debug IDs in CI"** part. The **upload step is recommended to run as an in-cluster Helm Job** (see `docs/08-source-maps.md`), not in CI — this way CI egress doesn't need WAF allowlisting.

## Files

| File | What |
|------|------|
| `cloud-build.yaml` | Google Cloud Build |
| `github-actions.yml` | GitHub Actions |
| `gitlab-ci.yml` | GitLab CI |

## The general recipe

1. Build your FE app (produces `dist/` or `.next/`)
2. `sentry-cli sourcemaps inject ./dist` — adds debug IDs to the built JS
3. (Don't upload in CI — let the Helm post-install Job do it)
4. Build the Docker image with the injected artifacts
5. Push, deploy, done

If you MUST upload in CI (e.g. no Kubernetes):

```bash
sentry-cli --url $BUGSINK_URL \
  --auth-token $SENTRY_AUTH_TOKEN \
  sourcemaps upload \
  --release "${ENVIRONMENT}-${IMAGE_TAG}" \
  ./dist
```

Make sure your CI's egress IP is allowlisted at your WAF.
