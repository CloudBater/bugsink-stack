# Vue 3 (Vite) + BugSink

## Install

```bash
npm install @sentry/vue
```

## src/main.ts

```typescript
import { createApp } from "vue";
import * as Sentry from "@sentry/vue";
import App from "./App.vue";
import router from "./router";

const app = createApp(App);

Sentry.init({
  app,  // important — hooks into Vue's error handler
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_IMAGE_TAG || "unknown",
  integrations: [
    Sentry.browserTracingIntegration({ router }),
  ],
  tracesSampleRate: 0.0,
});

app.use(router).mount("#app");
```

## Environment

```
VITE_SENTRY_DSN=http://<key>@bugsink.example.com/1
VITE_IMAGE_TAG=v1.2.3
```

## User context

```typescript
import * as Sentry from "@sentry/vue";
import { watch } from "vue";
import { useAuthStore } from "@/stores/auth";

const auth = useAuthStore();
watch(() => auth.user, (user) => {
  if (user) {
    Sentry.setUser({ id: user.id, email: user.email });
  } else {
    Sentry.setUser(null);
  }
}, { immediate: true });
```

## Test

```html
<template>
  <button @click="() => { throw new Error('Vue test error'); }">
    Trigger test error
  </button>
</template>
```

## Source maps

Same flow as the React/Vite example. See [`docs/08-source-maps.md`](../../docs/08-source-maps.md).

Make sure `vite.config.ts` has `build.sourcemap: true`:

```typescript
export default defineConfig({
  build: {
    sourcemap: true,
  },
});
```
