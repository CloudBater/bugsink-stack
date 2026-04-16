# Prompt: Integrate the Sentry SDK

> Paste after BugSink infra is up and you have a DSN. Agent wires up the SDK in your FE and BE.

---

BugSink is running and I have a DSN. Wire up the Sentry SDK in my frontend and backend.

## What I'll give you

- **Frontend DSN**: `http://<key>@bugsink.example.com/1`
- **Backend DSN (in-cluster preferred)**: `http://<key>@bugsink-svc.bugsink.svc.cluster.local/1`
- **Framework versions** (I'll paste `package.json` / `pyproject.toml` / `*.csproj` for you)
- **Deployment envs** (dev, staging, prod) and how they're wired in my existing deploy config

## Your workflow

1. **Read the relevant integration snippet** from `bugsink-stack/integrations/{framework}/README.md`.

2. **Write the SDK init code** in my project:
   - **Frontend**: add a `sentry.ts` (or framework-appropriate) file, import it from the entry point
   - **Backend**: add Sentry init in my framework's bootstrap file (settings.py, main.ts, Program.cs, etc.)

3. **Wire up environment variables**:
   - Add `SENTRY_DSN` / `NEXT_PUBLIC_SENTRY_DSN` to my deployment env per cloud/deploy pattern
   - Reference Secret Manager / Secrets Manager if the DSN should be secret (it's usually not, but the auth token for source-map upload is)
   - Update `.env.example` / `docker-compose.yml` / Helm values / Terraform as applicable
   - **Use env-specific DSNs** — dev/staging → non-prod BugSink, prod → prod BugSink

4. **Add a test endpoint / button**:
   - Backend: `/sentry-test` endpoint that raises an error
   - Frontend: a test page or button that throws
   - Help me verify events actually land

5. **Configure release tracking**:
   - Pass `IMAGE_TAG` / git SHA as both a build arg and an env var
   - Include `release` in SDK init

6. **Source maps (FE only)**:
   - Check if build already produces source maps; enable if not
   - Add `sentry-cli sourcemaps inject` to the Dockerfile after the build step
   - For the upload step, add a Helm post-install Job based on `examples/k8s/sourcemap-upload-job.yaml` OR add upload to the CI pipeline if egress is simpler
   - Create the `bugsink-auth-token` Kubernetes secret referencing the Secrets Manager entry for the BugSink API token

7. **Open PRs** — one for backend, one for frontend (unless it's a monorepo, then one PR with clear sections). Follow my team's PR conventions.

## PR content

Each PR should include:
- Title: `feat(observability): integrate Sentry SDK with BugSink`
- Summary of changes per file
- Test plan: "Deploy to dev, click the test button, verify event appears in BugSink dashboard"
- Rollback: "Remove `SENTRY_DSN` env var, redeploy. SDK init becomes no-op."
- Screenshot placeholder for "first captured event" (I'll fill in after deploy)

## Guard rails

- **Don't deploy**. Open PR, wait for review + my manual deploy.
- **Don't break existing logging.** BugSink is supplementary; existing Cloud Logging / CloudWatch output should continue unchanged.
- **Scrub sensitive data**. Add a `before_send` hook that strips `Authorization`, `Cookie`, `X-Api-Key` headers. See `docs/09-security-hardening.md`.
- **Verify the DSN format**. If I paste a DSN that looks like `https://...`, confirm I want public URL. If in-cluster, it should be `http://` (TLS is handled at Ingress).

## After the PR is merged

```markdown
## Verification after deploy

- [ ] Deploy to dev environment
- [ ] Click the test error button → event appears in BugSink dashboard
- [ ] Stack trace shows original source file + line number (if source maps working)
- [ ] `environment` tag is correctly set
- [ ] `release` tag matches the deployed image SHA
- [ ] Slack alert fires for new issues
- [ ] Roll to staging, then prod
```

Ready to implement?
