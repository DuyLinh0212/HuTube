# EC2 deployment: API and Recommendation Service

This Compose file runs the .NET API, Python Recommendation Service, and Caddy reverse proxy. It expects PostgreSQL and R2 to be provided by the existing external services; it does not start PostgreSQL or either web app.

## Environment files

Create these files on the EC2 host and keep them out of Git:

- `.env.ec2-api` at the repository root: database connection string, JWT signing key/issuer/audience, auth web/admin URLs and allowed origins, recommendation service/admin tokens, storage settings, and any email/Google settings the API uses.
- `recommendation-service/.env.ec2`: `CORS_ALLOWED_ORIGINS`, matching `RECOMMENDER_SERVICE_TOKEN` and `RECOMMENDER_ADMIN_TOKEN`, and the four R2 settings (`Storage__R2__AccountId`, `Storage__R2__AccessKeyId`, `Storage__R2__SecretAccessKey`, `Storage__R2__BucketName`).
- `Caddyfile` routes `api.dalitu.app` to the API and `recommendation.dalitu.app` to Recommendation Service. Caddy obtains and renews public HTTPS certificates automatically after both DNS names point to this EC2 host and inbound TCP 80/443 is allowed in its AWS Security Group.

Use the supplied `Docs/HuTube.env` and `Docs/HuTube-recommendation-services.env` as the source, but copy only these runtime settings. Do not put Neon management, Render, or Upstash management API keys in the application environment. The API's `Recommendation__ServiceToken` and `Recommendation__AdminToken` must exactly match the corresponding Python service tokens. Set `CORS_ALLOWED_ORIGINS` to a JSON array of the actual browser client origins. The Compose file sets service-to-service URLs to Docker network names automatically.

## Start

From the repository root on EC2:

```bash
docker compose -f docker-compose.ec2.yml up -d --build
docker compose -f docker-compose.ec2.yml ps
docker compose -f docker-compose.ec2.yml logs --tail=100 api recommendation
```

The API and Recommendation Service bind to `127.0.0.1:5080` and `127.0.0.1:8000`. Caddy listens on host ports 80/443, redirects HTTP to HTTPS, and routes the two public hostnames. Add inbound TCP 80 and 443 to the EC2 Security Group; do not open 5080 or 8000. The web/mobile clients call the public Recommendation Service URL directly, so set their service base URL to `https://recommendation.dalitu.app/api/v1` and include their actual origins in `CORS_ALLOWED_ORIGINS`.

Local health checks on EC2:

```bash
curl -fsS http://127.0.0.1:5080/health
curl -fsS http://127.0.0.1:8000/health
```

`/health` confirms the processes respond; it does not confirm that recommendation artifacts are present or that R2 is configured. Check service logs and the model status endpoint for those details.
