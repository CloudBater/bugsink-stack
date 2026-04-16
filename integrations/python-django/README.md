# Django + BugSink

## Install

```bash
pip install 'sentry-sdk[django]'
```

## settings.py

```python
import os
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

SENTRY_DSN = os.environ.get("SENTRY_DSN")
if SENTRY_DSN:
    sentry_sdk.init(
        dsn=SENTRY_DSN,
        integrations=[DjangoIntegration()],
        environment=os.environ.get("ENVIRONMENT", "development"),
        release=os.environ.get("IMAGE_TAG", "unknown"),
        send_default_pii=True,   # safe for self-hosted
        traces_sample_rate=0.0,  # errors-only
        before_send=scrub_sensitive_data,
    )


def scrub_sensitive_data(event, hint):
    """Strip auth tokens from captured request headers."""
    if 'request' in event and 'headers' in event['request']:
        for header_name in ['Authorization', 'Cookie', 'X-Api-Key']:
            event['request']['headers'].pop(header_name, None)
    return event
```

## With Celery

```python
from sentry_sdk.integrations.celery import CeleryIntegration

sentry_sdk.init(
    dsn=SENTRY_DSN,
    integrations=[DjangoIntegration(), CeleryIntegration()],
    # ...
)
```

## Manual capture

```python
import sentry_sdk

# Set per-request user context in middleware
class SentryUserMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.user.is_authenticated:
            sentry_sdk.set_user({
                "id": request.user.id,
                "email": request.user.email,
            })
        return self.get_response(request)

# Capture a handled exception
try:
    risky_operation()
except MyException as e:
    sentry_sdk.capture_exception(e)
    # ... fallback behavior
```

## Verify

```python
# In a Django shell
python manage.py shell
>>> import sentry_sdk; sentry_sdk.capture_message("Test from Django", level="info")
```

Check BugSink dashboard — event should appear within a few seconds.
