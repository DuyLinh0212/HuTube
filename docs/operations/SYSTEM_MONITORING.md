# System monitoring integrations

The admin system monitor reads operational data from the running API and from provider read APIs. Secrets are configured in the `hutube-api` Render service; do not add their values to this repository.

## Render environment

Add the following variables to the `hutube-api` service in Render. `render.yaml` declares them as `sync: false`, so Render keeps the values in its dashboard.

| Variable | Used for | Where to get it |
| --- | --- | --- |
| `NEON_API_KEY` | Current month compute usage | Create a Neon API key with read access |
| `NEON_ORG_ID` | Selects the Neon organization | Neon organization settings |
| `NEON_PROJECT_ID` | Selects this Neon project | Neon project settings or project URL |
| `UPSTASH_EMAIL` | Upstash Developer API authentication | Email used by the Upstash account |
| `UPSTASH_API_KEY` | Redis plan and usage API | Upstash Console → Account → Developer API; use a read-only key |
| `UPSTASH_REDIS_DATABASE_ID` | Selects the Redis database | Upstash database details |
| `RENDER_API_KEY` | Render CPU and memory metrics | Render Account Settings → API Keys |

The existing `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` remain the Redis connection and health-check credentials. They do not grant access to the Upstash account usage API.

Render automatically provides `RENDER_SERVICE_ID` and `RENDER_INSTANCE_ID` to the running service.

## What the monitor records

- Neon database size, active connections, and the PostgreSQL connection limit are queried directly from the connected database. Neon monthly compute usage comes from the Neon Consumption API; Neon only exposes that endpoint to supported plans.
- Upstash current storage, database limits, and current-month request totals come from the Upstash Developer API.
- Render CPU and memory usage/limits come from Render Metrics API samples.
- Cloudflare R2 usage continues to come from Cloudflare Analytics.
- Failed video uploads, failed rendition processing, SePay webhook outcomes, administrator actions, and alert state transitions are written to `audit_logs` and shown in recent activity.

The monitor caches provider metrics briefly to avoid polling provider APIs on every page refresh. Neon consumption is refreshed every 15 minutes.
