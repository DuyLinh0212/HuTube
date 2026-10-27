# Automatic EC2 deployment after CI

## Deployment gate

The EC2 host checks the public GitHub repository every five minutes with a systemd timer. A revision is eligible only when:

1. It is the current tip of `main` in the configured repository.
2. Its latest push run of `.github/workflows/ci.yml` completed successfully.
3. Backend, both Web clients, Recommendation, Mobile, E2E, container builds and `deployment-checks` all succeeded. Any unsuccessful or skipped job blocks deployment.
4. Both Vercel deployment contexts succeeded, and the combined commit status is successful.

GitHub Actions builds the images after the test jobs pass and publishes them to GHCR. EC2 downloads these images; it never compiles the application. The gate is checked again after downloading and preparing the images, immediately before replacing containers. A newer `main` or a changed check postpones activation. GitHub failures, rate limits and unavailable checks leave the running services in place.

GitHub's public REST endpoints provide the run and status information. The deployment host makes outbound HTTPS requests; application env files and the SSH private key stay outside Git. No GitHub Actions runner is installed on the production host.

## Published images

The existing public GHCR package `ghcr.io/duylinh0212/hutube/api` contains separate tags for the two services:

| Service | Tag published by the `main` workflow |
|---|---|
| API and migration | `<commit-sha>` |
| Recommendation | `recommendation-<commit-sha>` |

Both images use the same already-public package so EC2 can download them anonymously without a stored GitHub token or a second package-visibility setup. The build contexts contain public repository source; runtime env files and host secrets are not included. The package path is derived from the configured repository, lowercased, followed by `/api`.

The controller reads the immutable digest returned by each `docker pull`, inspects that digest rather than the tag, and checks its repository digest, commit revision, source repository, service label and Linux/amd64 platform. Compose receives only `ghcr.io/.../api@sha256:...` references. A missing image or invalid label fails deployment without a local-build fallback. The CI summary and `ec2-images-<sha>` artifact record both published digest references.

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
3. Require a clean tracked checkout, the expected remote and existing env files. Remove obsolete managed images and unused build cache, then require at least 3 GiB free disk for image downloads. Untracked configuration files are preserved; no reset or clean command is used.
4. Snapshot the Compose/Caddy configuration actually used by the running containers and pin their current image IDs with rollback tags.
5. Fetch and fast-forward `main` to the verified SHA. Pull the API and Recommendation images published by CI, validate their identity, and pin their digests. The production Compose file has no build definitions. The API's diagnostic endpoint reports the embedded SHA.
6. Validate Compose/Caddy and run the migration service while the old application containers are still running.
7. Check GitHub again. Recreate API, Recommendation and Caddy with the verified local images and existing named volumes, with building and additional pulls disabled.
8. Verify both loopback and public HTTPS health endpoints, the API SHA and running image IDs. Then write the successful deployment marker, update the default local image tags and clean obsolete builds again, retaining this release and its rollback images. Cleanup failure after success is logged without rolling back a healthy release.
9. On activation or health failure, recreate the previous containers from the snapshot and pinned images, verify them, and quarantine the failed SHA. A later successful `main` SHA remains eligible.

An interrupted activation is rolled back on the next service invocation. Registry/download/identity-check failures leave the existing application containers running. Deployment has a short interruption while containers are recreated on this single host; moving compilation to CI removes the build load but does not provide a zero-downtime rollout.

Rollback restores application images and proxy configuration. Database migrations and named volumes remain in place; migrations deployed by this mechanism must retain compatibility with the previous application version. Recommendation `/health` checks its HTTP process; model readiness is a separate operational check.

## Inspect and operate

```bash
# See why a revision is waiting, or the last deployed/rolled-back SHA.
sudo journalctl -u dalitu-autodeploy.service --since today
sudo cat /var/lib/dalitu-autodeploy/state.json

# Check eligibility without downloading or replacing containers.
sudo python3 /usr/local/lib/dalitu-autodeploy/ec2_autodeploy.py --check-only

# Reclaim build storage without deploying or restarting services.
sudo python3 /usr/local/lib/dalitu-autodeploy/ec2_autodeploy.py --cleanup-only

# Trigger the same checked deployment immediately.
sudo systemctl start dalitu-autodeploy.service

# Retry a quarantined SHA after fixing an operational problem.
sudo python3 /usr/local/lib/dalitu-autodeploy/ec2_autodeploy.py --retry-failed

# Stop automatic updates for maintenance, then resume them.
sudo systemctl stop dalitu-autodeploy.timer
sudo systemctl start dalitu-autodeploy.timer
```

After changing env files, use the existing Compose recreation command. Default local image tags point to the last healthy deployment. The installed controller is upgraded with the installer when its source changes.

Each eligible deployment cleans storage before downloading and after a healthy activation. Cleanup removes only obsolete commit tags in the exact configured GHCR package, legacy `dalitu-api:git-*`, `dalitu-recommendation:git-*` and managed rollback tags. Images referenced by any existing container (including stopped containers), the recorded healthy release, the most recent rollback checkpoint and interrupted/deferred deployment snapshots are protected. Manually named backups, branch tags and unrelated image packages are left alone; named volumes are never pruned and image removal never uses force. Older snapshot configuration files remain on disk but their obsolete images are no longer retained.

Legacy unused Docker build cache is pruned with `docker builder prune --all --force --keep-storage 512MB`. The host no longer needs a builder for deployments. Disk usage can exceed that cache allowance because active layers and protected images remain. The 3 GiB preflight blocks a download if cleanup cannot free enough space. A missing rollback checkpoint/image aborts cleanup before any image is removed. Maintenance uses the same deployment lock and refuses an interrupted transaction; recover that transaction through the normal service first.

## Verification

`deployment-checks` runs the gate, image identity, cleanup and recovery unit tests and validates installer syntax. The `container` job depends on the test jobs, builds both API and Recommendation Dockerfiles, and publishes both images for `main`. Feature branches and PRs validate builds without publishing. API publishing from `develop` remains available. The EC2 host waits for the completed `main` push workflow, including image publication, and both Vercel contexts.

References: [GitHub workflow runs REST API](https://docs.github.com/en/rest/actions/workflow-runs), [GitHub workflow jobs REST API](https://docs.github.com/en/rest/actions/workflow-jobs), [GitHub combined commit status](https://docs.github.com/en/rest/commits/statuses#get-the-combined-status-for-a-specific-reference).
