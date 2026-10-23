# System monitoring integrations

The admin system monitor reads operational data from the API running on EC2 and from provider read APIs. Set secrets in `.env.ec2-api` on EC2; do not add their values to this repository. Use `Docs/HuTube.env` as the source for the provider credentials.

## EC2 API environment

Add the following variables to `.env.ec2-api`. After changing the file, run `sudo docker compose -f docker-compose.ec2.yml up -d --no-deps --force-recreate api` to load the values into the running container.

| Variable | Used for | Where to get it |
| --- | --- | --- |
| `NEON_API_KEY` | Current month compute usage | Create a Neon API key with read access |
| `NEON_ORG_ID` | Selects the Neon organization | Neon organization settings |
| `NEON_PROJECT_ID` | Selects this Neon project | Neon project settings or project URL |
| `UPSTASH_EMAIL` | Upstash Developer API authentication | Email used by the Upstash account |
| `UPSTASH_API_KEY` | Redis plan and usage API | Upstash Console → Account → Developer API; use a read-only key |
| `UPSTASH_REDIS_DATABASE_ID` | Selects the Redis database | Upstash database details |

The existing `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` remain the Redis connection and health-check credentials. They do not grant access to the Upstash account usage API.

EC2 host RAM is read directly from Linux `/proc/meminfo`; this does not require a CloudWatch Agent or AWS access key.

## What the monitor records

- Neon database size, active connections, and the PostgreSQL connection limit are queried directly from the connected database. Neon monthly compute usage comes from the Neon Consumption API; Neon only exposes that endpoint to supported plans.
- Upstash current storage, database limits, and current-month request totals come from the Upstash Developer API.
- The resources panel shows one host RAM gauge for EC2: used, total, and available memory. The API process memory signal remains available in the alerts tab.
- API request traffic is collected in process memory for up to 24 hours and resets on an API restart. Direct Recommendation Service requests are not included.
- Cloudflare R2 usage continues to come from Cloudflare Analytics.
- Failed video uploads, failed rendition processing, SePay webhook outcomes, administrator actions, and alert state transitions are written to `audit_logs` and shown in recent activity.

The page refreshes every minute. Upstash usage is cached for five minutes and Neon consumption for 15 minutes. Neon consumption can return HTTP 403 when the account plan does not support the endpoint; database size and connections remain measured directly. See [Neon consumption API](https://api-docs.neon.tech/reference/getconsumptionhistoryperprojectv2) and [Upstash database stats](https://upstash.com/docs/devops/developer-api/redis/get_database_stats).
