# Angular + BugSink

## Install

```bash
npm install @sentry/angular
```

## src/main.ts

```typescript
import { enableProdMode } from "@angular/core";
import { platformBrowserDynamic } from "@angular/platform-browser-dynamic";
import * as Sentry from "@sentry/angular";
import { AppModule } from "./app/app.module";
import { environment } from "./environments/environment";

Sentry.init({
  dsn: environment.sentryDsn,
  environment: environment.name,
  release: environment.imageTag,
  integrations: [Sentry.browserTracingIntegration()],
  tracesSampleRate: 0.0,
});

if (environment.production) {
  enableProdMode();
}

platformBrowserDynamic()
  .bootstrapModule(AppModule)
  .catch((err) => console.error(err));
```

## src/environments/environment.ts

```typescript
export const environment = {
  production: false,
  name: "development",
  sentryDsn: "",  // set for dev if you want to test locally
  imageTag: "dev",
};
```

## src/environments/environment.prod.ts

```typescript
export const environment = {
  production: true,
  name: "production",
  sentryDsn: "http://<key>@bugsink.example.com/1",  // ideally injected at build time via replacements
  imageTag: "REPLACED_AT_BUILD",
};
```

## src/app/app.module.ts

```typescript
import { ErrorHandler, NgModule } from "@angular/core";
import { Router } from "@angular/router";
import * as Sentry from "@sentry/angular";

@NgModule({
  // ...
  providers: [
    { provide: ErrorHandler, useValue: Sentry.createErrorHandler() },
    { provide: Sentry.TraceService, deps: [Router] },
    { provide: APP_INITIALIZER, useFactory: () => () => {}, deps: [Sentry.TraceService], multi: true },
  ],
})
export class AppModule {}
```

## User context (inside a service)

```typescript
import { Injectable } from "@angular/core";
import * as Sentry from "@sentry/angular";

@Injectable({ providedIn: "root" })
export class AuthService {
  login(user: User) {
    Sentry.setUser({ id: user.id, email: user.email });
  }

  logout() {
    Sentry.setUser(null);
  }
}
```

## Test

```html
<button (click)="throwTest()">Test error</button>
```

```typescript
throwTest() {
  throw new Error("Angular test error");
}
```

## Source maps

- Enable in `angular.json`: `"sourceMap": true` under `configurations.production.sourceMap`
- Inject + upload with `sentry-cli` — same flow as other frameworks
- Match `release` between upload and `Sentry.init`
