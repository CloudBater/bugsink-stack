# Next.js + BugSink

Next.js has three runtime targets (client, server, edge) — each needs its own Sentry init.

## Install

```bash
npm install @sentry/nextjs
# or use the wizard for auto-scaffolding:
# npx @sentry/wizard@latest -i nextjs
```

## sentry.client.config.ts

```typescript
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.NEXT_PUBLIC_IMAGE_TAG,
  tracesSampleRate: 0.0,
  // Optional: ignore known-noisy errors
  ignoreErrors: [
    "ResizeObserver loop limit exceeded",
    "Non-Error promise rejection captured",
  ],
});
```

## sentry.server.config.ts

```typescript
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  // Server-side can use the in-cluster DSN (bypasses public Ingress)
  dsn: process.env.SENTRY_DSN_SERVER || process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.IMAGE_TAG,
  tracesSampleRate: 0.0,
});
```

## sentry.edge.config.ts

```typescript
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
});
```

## next.config.ts

```typescript
import { withSentryConfig } from "@sentry/nextjs";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
};

export default withSentryConfig(nextConfig, {
  silent: !process.env.CI,
  widenClientFileUpload: true,
  disableLogger: true,
  // Let the in-cluster Helm Job handle source map uploads
  sourcemaps: { disable: true },
});
```

## instrumentation.ts (App Router)

```typescript
export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    await import("./sentry.server.config");
  }
  if (process.env.NEXT_RUNTIME === "edge") {
    await import("./sentry.edge.config");
  }
}
```

## Environment variables

Build-time (baked into the client bundle):
- `NEXT_PUBLIC_SENTRY_DSN` — client DSN

Runtime (server-only):
- `SENTRY_DSN_SERVER` — in-cluster SVC DSN for server-side
- `IMAGE_TAG` — release tag for server-side init

Cloud Build substitutions **can't include `://`** — use a Dockerfile ARG default:

```dockerfile
ARG NEXT_PUBLIC_SENTRY_DSN=http://placeholder@bugsink.example.com/1
ENV NEXT_PUBLIC_SENTRY_DSN=$NEXT_PUBLIC_SENTRY_DSN
RUN npm run build
```

## Ad-blocker tunnel

Some ad-blockers block `*sentry*` URLs. Tunnel through your own origin:

```typescript
Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tunnel: "/api/sentry-tunnel",
});
```

```typescript
// app/api/sentry-tunnel/route.ts
export async function POST(req: Request) {
  const envelope = await req.text();
  const dsn = new URL(process.env.NEXT_PUBLIC_SENTRY_DSN!);
  const projectId = dsn.pathname.replace("/", "");
  const target = `${dsn.protocol}//${dsn.host}/api/${projectId}/envelope/`;
  return fetch(target, {
    method: "POST",
    body: envelope,
    headers: { "Content-Type": "application/x-sentry-envelope" },
  });
}
```

## Test

Create a page component:

```tsx
"use client";

export default function TestPage() {
  return (
    <button onClick={() => { throw new Error("Next.js test error"); }}>
      Trigger error
    </button>
  );
}
```

Click → event in BugSink dashboard with full React stack trace.
