# Local Microservices Infrastructure

Docker Compose infrastructure for running IdentityService and NotificationService locally.

## Included services

| Service | Host address | Purpose |
| --- | --- | --- |
| SQL Server | `localhost,14330` | `IAM` and `Notification` databases |
| Kafka | `localhost:19094` | Integration events |
| Redis | `localhost:16379` | Pending push notifications and caching |
| Kafka UI | <http://localhost:18080> | Kafka administration |
| Mailpit | <http://localhost:18025> | Local email testing |
| Seq | <http://localhost:18082> | Centralized logs |
| Jaeger | <http://localhost:16696> | Distributed traces |
| MinIO API | <http://localhost:19000> | S3-compatible object storage |
| MinIO console | <http://localhost:19001> | Object-storage administration |

## Prerequisites

- Docker Desktop with Docker Compose

## Start

From the Infrastructure repository root:

```powershell
docker compose up -d
```

Check container health and status:

```powershell
docker compose ps
```

SQL Server initialization creates separate `IAM` and `Notification` databases and their local service accounts.

## Stop

Stop the containers while preserving their data:

```powershell
docker compose down
```

To remove the containers and all persisted local data:

```powershell
docker compose down --volumes
```

## Local credentials

Credentials in `docker-compose.yml` are intended only for local development. Change them before using the stack in a shared environment, and never reuse them in production.

Mailpit uses the following local UI credentials:

```text
Username: mailpit
Password: Mailpit123!
```

## Networking

All containers join the `shared-app-network` Docker network. Applications running directly on the host should use the host addresses listed above; containerized applications should use Docker service names and internal container ports.

## Stress testing

The optional k6 harness can generate an exact number of registration requests and verify the resulting users, outbox events, emails, and pending push notifications. It starts at 1,000 requests and is configurable up to 1,000,000 without editing the script.

See [`load-tests/README.md`](./load-tests/README.md) before running it. The load generator uses the opt-in `load-test` Compose profile and is never started by a normal `docker compose up`.
