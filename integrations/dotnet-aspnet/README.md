# ASP.NET Core + BugSink

## Install

```bash
dotnet add package Sentry.AspNetCore
```

## Program.cs

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseSentry(options =>
{
    options.Dsn = builder.Configuration["Sentry:Dsn"]
              ?? Environment.GetEnvironmentVariable("SENTRY_DSN");
    options.Environment = builder.Configuration["Sentry:Environment"]
                      ?? builder.Environment.EnvironmentName;
    options.Release = Environment.GetEnvironmentVariable("IMAGE_TAG") ?? "unknown";
    options.SendDefaultPii = true;
    options.TracesSampleRate = 0.0;

    options.SetBeforeSend(e =>
    {
        if (e.Request != null)
        {
            e.Request.Headers.Remove("Authorization");
            e.Request.Headers.Remove("Cookie");
        }
        return e;
    });
});

var app = builder.Build();

app.MapGet("/", () => "ok");
app.MapGet("/error-test", () =>
{
    throw new Exception("Test error from ASP.NET Core");
});

app.Run();
```

## appsettings.Production.json

```json
{
  "Sentry": {
    "Dsn": "http://<key>@bugsink.example.com/1",
    "Environment": "production"
  }
}
```

## User context

```csharp
using Sentry;

SentrySdk.ConfigureScope(scope =>
{
    scope.User = new SentryUser
    {
        Id = currentUser.Id.ToString(),
        Email = currentUser.Email,
    };
});
```

## Manual capture

```csharp
try
{
    await DoRiskyWork();
}
catch (Exception ex)
{
    SentrySdk.CaptureException(ex);
    // fallback
}
```

## Docker env

```dockerfile
ENV SENTRY_DSN=http://<key>@bugsink.example.com/1
ENV IMAGE_TAG=v1.2.3
```

Or supply via Kubernetes Deployment env block / ExternalSecret.
