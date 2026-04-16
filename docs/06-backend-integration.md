# 06 — Backend Integration

Every Sentry SDK works against BugSink — same DSN mechanism, same protocol. Official snippets below.

Set `SENTRY_DSN` via environment variable (not hardcoded). For Kubernetes, use a ConfigMap or ExternalSecret per environment.

---

## Python — Django

`pip install 'sentry-sdk[django]'`

```python
# settings.py
import os
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

sentry_sdk.init(
    dsn=os.environ.get("SENTRY_DSN"),
    integrations=[DjangoIntegration()],
    environment=os.environ.get("ENVIRONMENT", "development"),
    release=os.environ.get("IMAGE_TAG", "unknown"),
    send_default_pii=True,  # safe for self-hosted
    traces_sample_rate=0.0,  # errors-only, no APM
)
```

With Celery:

```python
from sentry_sdk.integrations.celery import CeleryIntegration

sentry_sdk.init(
    dsn=...,
    integrations=[DjangoIntegration(), CeleryIntegration()],
    ...
)
```

---

## Python — FastAPI

`pip install 'sentry-sdk[fastapi]'`

```python
import os
import sentry_sdk
from fastapi import FastAPI

sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    environment=os.environ.get("ENVIRONMENT", "development"),
    send_default_pii=True,
)

app = FastAPI()
```

FastAPI integration auto-captures unhandled exceptions. No middleware needed.

---

## Python — Flask

`pip install 'sentry-sdk[flask]'`

```python
import sentry_sdk
from sentry_sdk.integrations.flask import FlaskIntegration

sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    integrations=[FlaskIntegration()],
)
```

---

## Node.js — Express

`npm install @sentry/node`

```javascript
// app.js
const Sentry = require("@sentry/node");
const express = require("express");

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.IMAGE_TAG,
});

const app = express();

// The request handler must be the first middleware on the app
app.use(Sentry.Handlers.requestHandler());

// ... your routes ...

// The error handler must be before any other error middleware but after all controllers
app.use(Sentry.Handlers.errorHandler());
```

---

## Node.js — NestJS

`npm install @sentry/node`

```typescript
// main.ts
import * as Sentry from "@sentry/node";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
});

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // ...
}
```

Create an exception filter that pipes through Sentry:

```typescript
import { Catch, ArgumentsHost, ExceptionFilter } from "@nestjs/common";
import * as Sentry from "@sentry/node";

@Catch()
export class SentryFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    Sentry.captureException(exception);
    throw exception;
  }
}
```

---

## .NET — ASP.NET Core

```bash
dotnet add package Sentry.AspNetCore
```

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseSentry(options =>
{
    options.Dsn = builder.Configuration["SENTRY_DSN"];
    options.Environment = builder.Configuration["ENVIRONMENT"];
    options.Release = builder.Configuration["IMAGE_TAG"];
    options.SendDefaultPii = true;
    options.TracesSampleRate = 0.0;  // errors-only
});

var app = builder.Build();
// ...
app.Run();
```

`appsettings.Production.json`:

```json
{
  "Sentry": {
    "Dsn": "https://<key>@bugsink.example.com/1",
    "Environment": "production"
  }
}
```

---

## Go

`go get github.com/getsentry/sentry-go`

```go
import (
    "github.com/getsentry/sentry-go"
    "os"
    "time"
)

err := sentry.Init(sentry.ClientOptions{
    Dsn:              os.Getenv("SENTRY_DSN"),
    Environment:      os.Getenv("ENVIRONMENT"),
    Release:          os.Getenv("IMAGE_TAG"),
    AttachStacktrace: true,
})
if err != nil {
    log.Fatalf("sentry.Init: %s", err)
}
defer sentry.Flush(2 * time.Second)
```

For HTTP:

```go
import sentryhttp "github.com/getsentry/sentry-go/http"

sentryHandler := sentryhttp.New(sentryhttp.Options{})
http.Handle("/", sentryHandler.Handle(yourHandler))
```

---

## Ruby — Rails

```ruby
# Gemfile
gem "sentry-ruby"
gem "sentry-rails"
```

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env
  config.release = ENV["IMAGE_TAG"]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.send_default_pii = true
  config.traces_sample_rate = 0.0
end
```

---

## PHP — Laravel

`composer require sentry/sentry-laravel`

```php
// config/sentry.php
return [
    'dsn' => env('SENTRY_DSN'),
    'environment' => env('APP_ENV'),
    'release' => env('IMAGE_TAG'),
    'send_default_pii' => true,
];
```

In `app/Exceptions/Handler.php`:

```php
public function register(): void
{
    $this->reportable(function (Throwable $e) {
        if (app()->bound('sentry')) {
            app('sentry')->captureException($e);
        }
    });
}
```

---

## In-cluster DSN vs public DSN

If your backend runs in the same Kubernetes cluster as BugSink:

```
SENTRY_DSN=http://<key>@bugsink-svc.bugsink.svc.cluster.local/1
```

This avoids public DNS, WAF/Cloud Armor, and TLS overhead. It's what you want for the hot path.

If your backend runs outside the cluster (EC2/GCE VM, Lambda, etc.):

```
SENTRY_DSN=https://<key>@bugsink.example.com/1
```

Just make sure your app's egress IP is in the WAF allowlist (or punch a hole specifically for SDK ingest — see [`docs/09-security-hardening.md`](09-security-hardening.md)).

---

## Common patterns

### Filter noisy errors

```python
def before_send(event, hint):
    # Drop known-noisy exceptions
    if 'exc_info' in hint:
        exc_type, exc_value, tb = hint['exc_info']
        if isinstance(exc_value, (ConnectionResetError, BrokenPipeError)):
            return None
    return event

sentry_sdk.init(dsn=..., before_send=before_send)
```

### Scrub sensitive fields

```python
def before_send(event, hint):
    if 'request' in event and 'headers' in event['request']:
        event['request']['headers'].pop('Authorization', None)
        event['request']['headers'].pop('Cookie', None)
    return event
```

Most SDKs scrub common PII by default when `send_default_pii=False`. With `send_default_pii=True` you see user context (useful for self-hosted, where the data doesn't leave your infra).

### Custom context

```python
sentry_sdk.set_user({"id": user.id, "email": user.email})
sentry_sdk.set_tag("subscription_tier", user.plan)
sentry_sdk.add_breadcrumb(category="checkout", message="User reached payment step", level="info")
```

---

## Verify it's working

Throw a test error:

```python
# Python
sentry_sdk.capture_message("Hello from BugSink test", level="info")
raise Exception("intentional test error")
```

Check the BugSink dashboard. The event should appear within a few seconds. If it doesn't:
- Check `SENTRY_DSN` env var is set (print it at startup)
- Check network path (can the pod reach the BugSink SVC?)
- Check BugSink logs for 500 responses (see [`docs/13-gotchas.md`](13-gotchas.md) for common causes)
