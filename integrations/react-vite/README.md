# React (Vite) + BugSink

## Install

```bash
npm install @sentry/react
```

## src/sentry.ts

```typescript
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_IMAGE_TAG || "unknown",
  integrations: [
    Sentry.browserTracingIntegration(),
    // Optional: session replay on errors only
    // Sentry.replayIntegration({ maskAllText: true }),
  ],
  tracesSampleRate: 0.0,
  replaysOnErrorSampleRate: 0.0,
});
```

## src/main.tsx

```tsx
import "./sentry";  // IMPORT FIRST — before React
import React from "react";
import ReactDOM from "react-dom/client";
import * as Sentry from "@sentry/react";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <Sentry.ErrorBoundary fallback={<ErrorFallback />}>
    <App />
  </Sentry.ErrorBoundary>
);

function ErrorFallback() {
  return (
    <div>
      <h1>Something went wrong.</h1>
      <p>We've been notified and are working on a fix.</p>
    </div>
  );
}
```

## Environment (.env)

```
VITE_SENTRY_DSN=http://<key>@bugsink.example.com/1
VITE_IMAGE_TAG=v1.2.3
```

Vite exposes env vars prefixed with `VITE_` to the client bundle. Other frameworks have different prefixes (CRA uses `REACT_APP_`).

## Test it

```tsx
<button onClick={() => { throw new Error("BugSink React test"); }}>
  Trigger test error
</button>
```

Click → check BugSink dashboard.

## Source maps

See [`docs/08-source-maps.md`](../../docs/08-source-maps.md). Summary:

1. Vite generates source maps at build if `build.sourcemap: true` in `vite.config.ts`
2. Add `sentry-cli sourcemaps inject ./dist` to your Docker build step
3. Upload via Helm post-install Job with `--release "${ENVIRONMENT}-${VITE_IMAGE_TAG}"`
4. SDK init `release` must match the upload `--release`

## User context

```tsx
import * as Sentry from "@sentry/react";
import { useEffect } from "react";

function App({ user }) {
  useEffect(() => {
    if (user) {
      Sentry.setUser({ id: user.id, email: user.email });
    } else {
      Sentry.setUser(null);
    }
  }, [user]);
  // ...
}
```
