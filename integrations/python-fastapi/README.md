# FastAPI + BugSink

## Install

```bash
pip install 'sentry-sdk[fastapi]'
```

## main.py

```python
import os
import sentry_sdk
from fastapi import FastAPI

sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    environment=os.environ.get("ENVIRONMENT", "development"),
    release=os.environ.get("IMAGE_TAG", "unknown"),
    send_default_pii=True,
    traces_sample_rate=0.0,
)

app = FastAPI()


@app.get("/")
def read_root():
    return {"status": "ok"}


@app.get("/error-test")
def trigger_error():
    1 / 0  # should appear in BugSink within seconds
```

## Manual capture + user context

```python
import sentry_sdk
from fastapi import Request, Depends

async def attach_user(request: Request):
    user = get_user_from_request(request)  # your auth logic
    if user:
        sentry_sdk.set_user({"id": user.id, "email": user.email})

@app.get("/protected", dependencies=[Depends(attach_user)])
async def protected_endpoint():
    # Any error here will be captured with user context
    return do_work()
```

## With background tasks (e.g. arq, RQ)

```python
from sentry_sdk.integrations.arq import ArqIntegration

sentry_sdk.init(
    dsn=...,
    integrations=[ArqIntegration()],
)
```

For other task queues, wrap the task body in `with sentry_sdk.start_transaction()` or `try/except + capture_exception`.

## Run

```bash
SENTRY_DSN="http://<key>@bugsink.example.com/1" uvicorn main:app --reload
```
