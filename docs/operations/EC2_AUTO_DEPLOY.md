# Automatic EC2 deployment after CI

## Deployment gate

The EC2 host checks the public GitHub repository every five minutes with a systemd timer. A revision is eligible only when:

1. It is the current tip of `main` in the configured repository.
2. Its latest push run of `.github/workflows/ci.yml` completed successfully.
3. Backend, both Web clients, Recommendation, Mobile, E2E, container builds and `deployment-checks` all succeeded. The expected `deploy-staging` skip on `main` is allowed; other unsuccessful jobs block deployment.
4. Both Vercel deployment contexts succeeded, and the combined commit status is successful.

The gate is checked again after the EC2 builds, immediately before replacing containers. A newer `main` or a changed check postpones activation. GitHub failures, rate limits and unavailable checks leave the running services in place.

GitHub's public REST endpoints provide the run and status information. The deployment host makes outbound HTTPS requests; application env files and the SSH private key stay outside Git. No GitHub Actions runner is installed on the production host.

## Install once

Requirements: Ubuntu with systemd, Python 3, Git, Docker Compose v2, a clean `main` checkout with the expected HTTPS `origin`, and the existing EC2 env files. From the checkout, substitute its absolute path:

```bash
sudo bash scripts/deploy/install-ec2-autodeploy.sh /absolute/path/to/checkout
sudo systemctl list-timers dalitu-autodeploy.timer
```

The installer writes:

| Path | Purpose |
|---|---|
| `/usr/local/lib/dalitu-autodeploy/ec2_autodeploy.py` | Installed controller, independent of Git checkout changes |
| `/etc/dalitu-autodeploy.json` | Host paths, public health URLs and required Vercel contexts; root permissions |
| `/var/lib/dalitu-autodeploy/state.json` | Last healthy SHA/run, pending deployment and failed revision |
| `/var/lib/dalitu-autodeploy/rollback/` | Previous Compose/Caddy files and pinned image references |
| `dalitu-autodeploy.service` / `.timer` | One deployment at a time, checked every five minutes |

Run the installer again to upgrade the installed controller. It preserves the existing host configuration and deployment state.

The controller runs as root to manage Docker and switches to the checkout owner for Git. Its systemd unit permits that UID transition with `NoNewPrivileges=false`; the CI deployment job exercises this same transition under the service sandbox properties.

## Update transaction

1. Lock the deployment to prevent overlapping runs. Recover an interrupted activation from its saved checkpoint.
2. Check GitHub CI and Vercel for the exact `main` SHA.
3. Require a clean tracked checkout, the expected remote, existing env files and at least 3 GiB free disk. Untracked configuration files are preserved; no reset or clean command is used.
4. Snapshot the Compose/Caddy configuration actually used by the running containers and pin their current image IDs with rollback tags.
5. Fetch and fast-forward `main` to the verified SHA. Build API and Recommendation images sequentially, each tagged with that SHA. The API's diagnostic endpoint reports the embedded SHA.
6. Validate Compose/Caddy and run the migration service while the old application containers are still running.
7. Check GitHub again. Recreate API, Recommendation and Caddy with the built images and existing named volumes.
8. Verify both loopback and public HTTPS health endpoints, the API SHA and running image IDs. Then write the successful deployment marker and update the default local image tags.
9. On activation or health failure, recreate the previous containers from the snapshot and pinned images, verify them, and quarantine the failed SHA. A later successful `main` SHA remains eligible.

An interrupted activation is rolled back on the next service invocation. Build failures leave the existing application containers running. Deployment has a short interruption while containers are recreated on this single host.

Rollback restores application images and proxy configuration. Database migrations and named volumes remain in place; migrations deployed by this mechanism must retain compatibility with the previous application version. Recommendation `/health` checks its HTTP process; model readiness is a separate operational check.

## Inspect and operate

```bash
# See why a revision is waiting, or the last deployed/rolled-back SHA.
sudo journalctl -u dalitu-autodeploy.service --since today
sudo cat /var/lib/dalitu-autodeploy/state.json

# Check eligibility without building or replacing containers.
sudo python3 /usr/local/lib/dalitu-autodeploy/ec2_autodeploy.py --check-only

# Trigger the same checked deployment immediately.
sudo systemctl start dalitu-autodeploy.service

# Retry a quarantined SHA after fixing an operational problem.
sudo python3 /usr/local/lib/dalitu-autodeploy/ec2_autodeploy.py --retry-failed

# Stop automatic updates for maintenance, then resume them.
sudo systemctl stop dalitu-autodeploy.timer
sudo systemctl start dalitu-autodeploy.timer
```

After changing env files, use the existing Compose recreation command. Default local image tags point to the last healthy deployment. The installed controller is upgraded with the installer when its source changes.

The deployment keeps rollback images and the Docker build cache. Check disk usage periodically. The 3 GiB preflight prevents starting another build when space is low; remove only reviewed, unused images/cache while retaining the active and rollback images.

## Verification

`deployment-checks` runs the gate and recovery unit tests and validates installer syntax. The `container` job depends on these checks and builds both API and Recommendation Dockerfiles. The EC2 host waits for the completed workflow, including these container builds.

References: [GitHub workflow runs REST API](https://docs.github.com/en/rest/actions/workflow-runs), [GitHub workflow jobs REST API](https://docs.github.com/en/rest/actions/workflow-jobs), [GitHub combined commit status](https://docs.github.com/en/rest/commits/statuses#get-the-combined-status-for-a-specific-reference).
