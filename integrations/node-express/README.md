# Express + BugSink

## Install

```bash
npm install @sentry/node
```

## app.js

```javascript
const Sentry = require("@sentry/node");
const express = require("express");

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV || "development",
  release: process.env.IMAGE_TAG,
  beforeSend(event) {
    // Scrub auth headers
    if (event.request?.headers) {
      delete event.request.headers.authorization;
      delete event.request.headers.cookie;
    }
    return event;
  },
});

const app = express();

// Request handler MUST be first
app.use(Sentry.Handlers.requestHandler());
app.use(Sentry.Handlers.tracingHandler());  // optional

app.get("/", (req, res) => res.send("ok"));

app.get("/error-test", (req, res) => {
  throw new Error("Test error from Express");
});

// Error handler MUST be before other error middleware but after all controllers
app.use(Sentry.Handlers.errorHandler());

app.listen(3000);
```

## Capturing handled exceptions

```javascript
try {
  await doRiskyWork();
} catch (err) {
  Sentry.captureException(err);
  // fallback
}
```

## User context (attach per request)

```javascript
app.use((req, res, next) => {
  if (req.user) {
    Sentry.setUser({ id: req.user.id, email: req.user.email });
  }
  next();
});
```

## Environment

```bash
SENTRY_DSN=http://<key>@bugsink.example.com/1 \
NODE_ENV=production \
IMAGE_TAG=v1.2.3 \
node app.js
```

## Docker

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY . .
EXPOSE 3000
CMD ["node", "app.js"]
```

Set `SENTRY_DSN` via your K8s Deployment env block. Rotate via ExternalSecret.
