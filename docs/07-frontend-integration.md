# 07 — Frontend Integration

Frontend is where BugSink earns its keep — server logs already give you backend errors, but browser errors are invisible without this.

Build-time DSN injection is the main pattern. Use `NEXT_PUBLIC_SENTRY_DSN`, `VITE_SENTRY_DSN`, `REACT_APP_SENTRY_DSN`, etc., depending on framework.

---

## React (Vite or CRA)

`npm install @sentry/react`

```tsx
// src/sentry.ts
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,  // Vite
  // dsn: process.env.REACT_APP_SENTRY_DSN,  // Create React App
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_IMAGE_TAG,
  integrations: [
    Sentry.browserTracingIntegration(),
    Sentry.replayIntegration({ maskAllText: true }),  // optional
  ],
  tracesSampleRate: 0.0,  // errors-only
  replaysSessionSampleRate: 0.0,
  replaysOnErrorSampleRate: 0.0,
});
```

```tsx
// src/main.tsx
import "./sentry";  // import FIRST, before React
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <Sentry.ErrorBoundary fallback={<p>Something went wrong.</p>}>
    <App />
  </Sentry.ErrorBoundary>
);
```

---

## Vue 3

`npm install @sentry/vue`

```ts
// src/main.ts
import { createApp } from "vue";
import * as Sentry from "@sentry/vue";
import App from "./App.vue";
import router from "./router";

const app = createApp(App);

Sentry.init({
  app,
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_IMAGE_TAG,
  integrations: [
    Sentry.browserTracingIntegration({ router }),
  ],
  tracesSampleRate: 0.0,
});

app.use(router).mount("#app");
```

---

## Angular

`npm install @sentry/angular`

```ts
// src/main.ts
import { enableProdMode } from "@angular/core";
import { platformBrowserDynamic } from "@angular/platform-browser-dynamic";
import * as Sentry from "@sentry/angular";
import { AppModule } from "./app/app.module";
import { environment } from "./environments/environment";

Sentry.init({
  dsn: environment.sentryDsn,
  environment: environment.name,
  release: environment.imageTag,
  integrations: [
    Sentry.browserTracingIntegration(),
  ],
  tracesSampleRate: 0.0,
});

if (environment.production) {
  enableProdMode();
}

platformBrowserDynamic()
  .bootstrapModule(AppModule)
  .catch((err) => console.error(err));
```

```ts
// src/app/app.module.ts
import { ErrorHandler, NgModule } from "@angular/core";
import * as Sentry from "@sentry/angular";
import { Router } from "@angular/router";

@NgModule({
  providers: [
    { provide: ErrorHandler, useValue: Sentry.createErrorHandler() },
    { provide: Sentry.TraceService, deps: [Router] },
  ],
})
export class AppModule {}
```

---

## Next.js

`npm install @sentry/nextjs`

Use the wizard for initial setup:

```bash
npx @sentry/wizard@latest -i nextjs
```

Then edit the generated files to point at BugSink:

```ts
// sentry.client.config.ts
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.NEXT_PUBLIC_IMAGE_TAG,
  tracesSampleRate: 0.0,
});
```

```ts
// sentry.server.config.ts
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  // Server-side can use the in-cluster DSN
  dsn: process.env.SENTRY_DSN_SERVER || process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 0.0,
});
```

```ts
// sentry.edge.config.ts
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
});
```

Wrap your `next.config.ts`:

```ts
import { withSentryConfig } from "@sentry/nextjs";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // ...
};

export default withSentryConfig(nextConfig, {
  org: "your-org",
  project: "your-project",
  silent: !process.env.CI,
  widenClientFileUpload: true,
  // Don't upload source maps during build — handled by in-cluster Job instead
  disableLogger: true,
  sourcemaps: {
    disable: true,  // see docs/08-source-maps.md for the Job-based approach
  },
});
```

---

## Svelte / SvelteKit

`npm install @sentry/sveltekit`

```ts
// src/hooks.client.ts
import * as Sentry from "@sentry/sveltekit";

Sentry.init({
  dsn: import.meta.env.PUBLIC_SENTRY_DSN,
  environment: import.meta.env.MODE,
});

export const handleError = Sentry.handleErrorWithSentry();
```

```ts
// src/hooks.server.ts
import * as Sentry from "@sentry/sveltekit";
import { sequence } from "@sveltejs/kit/hooks";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
});

export const handle = Sentry.sentryHandle();
export const handleError = Sentry.handleErrorWithSentry();
```

---

## Vanilla JS / no framework

`npm install @sentry/browser` — or load the CDN bundle.

```html
<script src="https://browser.sentry-cdn.com/7.100.0/bundle.min.js"></script>
<script>
  Sentry.init({
    dsn: "https://<key>@bugsink.example.com/1",
    environment: "production",
  });
</script>
```

---

## Ad-blocker / corporate proxy mitigation

Some ad-blockers (e.g. uBlock Origin's "EasyPrivacy" list) block requests that look like Sentry. If you see reports that "some users' errors don't show up," this is usually why.

**Fix: tunnel through your own backend.** The Sentry SDKs support a `tunnel` option:

```ts
Sentry.init({
  dsn: "...",
  tunnel: "/api/sentry-tunnel",  // a route on your own origin
});
```

Implement the tunnel route in your backend:

```ts
// Next.js API route example
export async function POST(req: Request) {
  const envelope = await req.text();
  const dsn = new URL(process.env.SENTRY_DSN!);
  const projectId = dsn.pathname.replace("/", "");
  const url = `${dsn.protocol}//${dsn.host}/api/${projectId}/envelope/`;
  return fetch(url, {
    method: "POST",
    body: envelope,
    headers: { "Content-Type": "application/x-sentry-envelope" },
  });
}
```

Ad-blockers don't block `/api/sentry-tunnel` on your own domain. Now events flow again.

---

## Environment separation in one place

Tag events consistently across frontend and backend:

```ts
environment: process.env.NODE_ENV,  // "development" | "staging" | "production"
release: process.env.IMAGE_TAG,     // git SHA or version tag
```

On the BugSink dashboard, filter by `environment` to see only prod issues. Stable `release` tags let you see "this error started appearing in v1.14.0."

---

## Verify it's working

Put a test error button in your app somewhere:

```tsx
<button onClick={() => { throw new Error("BugSink test error"); }}>
  Test error
</button>
```

Click it, check the BugSink dashboard. If the source map is working, the stack trace should show the original TSX file and line number, not minified JS.

If source maps aren't resolving: see [`docs/08-source-maps.md`](08-source-maps.md).
