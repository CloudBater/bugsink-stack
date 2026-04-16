# Framework Integrations

Each subfolder contains a minimal, copy-ready integration example for a specific framework. These are **snippet-style** — not full scaffolded apps. Grab the relevant files and paste into your project.

## Backend

| Folder | Framework | Language |
|--------|-----------|----------|
| [`python-django`](python-django/) | Django 5.x | Python |
| [`python-fastapi`](python-fastapi/) | FastAPI | Python |
| [`dotnet-aspnet`](dotnet-aspnet/) | ASP.NET Core 8 | C# |
| [`node-express`](node-express/) | Express 4.x | Node.js |

## Frontend

| Folder | Framework | Language |
|--------|-----------|----------|
| [`react-vite`](react-vite/) | React 18 + Vite | TypeScript |
| [`vue-vite`](vue-vite/) | Vue 3 + Vite | TypeScript |
| [`angular`](angular/) | Angular 17 | TypeScript |
| [`nextjs`](nextjs/) | Next.js 14+ | TypeScript |

## Don't see your framework?

Every official Sentry SDK works with BugSink. Pattern is always:

```
1. Install the Sentry SDK for your framework
2. Call Sentry.init({ dsn: process.env.SENTRY_DSN }) at app startup
3. Set SENTRY_DSN in your deployment environment
```

See the [Sentry SDK directory](https://docs.sentry.io/platforms/) — pick your platform, follow the init steps, just point `dsn` at your BugSink instance instead of sentry.io.
