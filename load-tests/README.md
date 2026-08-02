# Registration stress test

This harness sends unique registration requests to IdentityService and verifies the asynchronous path through its outbox, Kafka, email delivery, and pending push processing.

## Success criteria

For every requested registration, the verifier expects:

1. one Identity user;
2. one outbox event that has been dispatched;
3. one successful email delivery log;
4. one delivered push log.

For this test, a delivered push means NotificationService successfully stored the pending Redis message and attempted its SignalR publish. It does not mean a client received or acknowledged the message.

## Prerequisites

1. Start the Infrastructure Compose stack.
2. Start IdentityService on `http://localhost:5066`.
3. Start NotificationService.
4. Confirm both services are healthy and can reach SQL Server, Kafka, Redis, and Mailpit.

## Start with 1,000 requests

Use a unique lowercase run ID for each execution:

```powershell
cd "D:\My Projects\Microservice\Infrastructure"
$env:RUN_ID = "run-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$env:TOTAL_REQUESTS = "1000"
$env:VUS = "50"
docker compose --profile load-test run --rm k6
```

Keep the same `RUN_ID` and verify eventual processing:

```powershell
.\load-tests\verify-registration.ps1 `
  -RunId $env:RUN_ID `
  -ExpectedCount ([int]$env:TOTAL_REQUESTS) `
  -TimeoutSeconds 1800
```

The verifier polls because HTTP registration completes before Kafka consumers finish email and push processing.

## Scale gradually

Change only the environment variables; do not edit the JavaScript file:

```powershell
$env:RUN_ID = "run-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$env:TOTAL_REQUESTS = "10000"
$env:VUS = "100"
docker compose --profile load-test run --rm k6
```

Recommended progression:

| Total requests | Starting VUs | Suggested verifier timeout |
| ---: | ---: | ---: |
| 1,000 | 50 | 30 minutes |
| 10,000 | 100 | 1 hour |
| 100,000 | 250 | 4 hours |
| 1,000,000 | 500 | 24 hours or more |

These VU values are starting points, not capacity claims. Increase concurrency only after checking latency, failures, CPU, memory, disk usage, Kafka consumer lag, and SQL Server pressure.

For one million requests:

```powershell
$env:RUN_ID = "run-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$env:TOTAL_REQUESTS = "1000000"
$env:VUS = "500"
$env:MAX_DURATION = "24h"
docker compose --profile load-test run --rm k6
```

Then verify with a longer timeout:

```powershell
.\load-tests\verify-registration.ps1 `
  -RunId $env:RUN_ID `
  -ExpectedCount 1000000 `
  -TimeoutSeconds 86400 `
  -PollIntervalSeconds 30
```

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `BASE_URL` | `http://host.docker.internal:5066` | IdentityService base URL as seen by the k6 container |
| `TOTAL_REQUESTS` | `1000` | Exact number of attempted registration iterations |
| `VUS` | `50` | Concurrent k6 virtual users sharing the iterations |
| `MAX_DURATION` | `30m` | Maximum time allowed for request generation |
| `RUN_ID` | `loadtest` | Run-specific email tag; always override this for real runs |
| `TEST_PASSWORD` | `LoadTest!12345` | Password sent for generated test users |

## Monitor during the run

- Seq: <http://localhost:18082>
- Kafka UI and consumer lag: <http://localhost:18080>
- Mailpit: <http://localhost:18025>
- Jaeger: <http://localhost:16696>
- Containers: `docker stats`

Mailpit, Seq, SQL Server, Kafka, and Redis persist data in Docker volumes. A million registrations can consume substantial disk and memory. This harness deliberately does not delete test data.
