# Twenty CRM deployment

Production instance: <https://crm.twixrsolutions.com>

Runs on the `wishdumps-prod` droplet (134.199.177.66), alongside the wishdumps
Laravel stack. The two share only nginx and the kernel: Twenty's Postgres and
Redis are its own containers, bound to loopback.

## Layout

| Path | Purpose |
| --- | --- |
| `docker-compose.prod.yml` | The production stack: server, worker, db, redis |
| `bootstrap-server.sh` | One-time provisioning (swap, Docker, secrets, TLS) |
| `deploy.sh` | Rolls a new image out, with backup and rollback |
| `backup.sh` | Nightly `pg_dump`, keeps 14 days |
| `nginx/` | vhost for crm.twixrsolutions.com |
| `local/` | Unrelated: run Twenty on your Mac for development |

On the server everything lives in `/opt/twenty`, owned by `deploy`.

## How a deploy happens

Push to `main` → `.github/workflows/deploy-production.yml`:

1. Builds `packages/twenty-docker/twenty/Dockerfile` (target `twenty`) on a
   GitHub runner, because the droplet has nowhere near the RAM to build it.
2. Pushes to `ghcr.io/aliraza93/twenty:sha-<short>` and `:latest`.
3. rsyncs this `deploy/` directory to `/opt/twenty` (never `.env`).
4. Runs `deploy.sh` with the new image tag, which dumps the database, starts
   the stack, waits for `/healthz`, and rolls back to the previous image if it
   does not come up.
5. Verifies `https://crm.twixrsolutions.com/healthz` from outside.

Build and deploy together take roughly 30-50 minutes, almost all of it the
image build.

### Deploying by hand

```bash
gh workflow run "Deploy production" --repo aliraza93/twenty   # full build
ssh deploy@134.199.177.66 'bash /opt/twenty/deploy.sh ghcr.io/aliraza93/twenty:sha-abc1234'
```

## Secrets

`/opt/twenty/.env` is generated once by `bootstrap-server.sh` and is the only
copy. CI never writes it.

**`ENCRYPTION_KEY` cannot change once data exists** - it decrypts stored
third-party tokens. Back that file up somewhere durable.

GitHub side: secrets `SSH_PRIVATE_KEY`, `SSH_HOST`; variables `SSH_USER`,
`DEPLOY_PATH`.

## Memory

The droplet is shared, so every container has a hard memory limit: server
1024M, worker 640M, db 384M, redis 96M, with Node heaps capped below those.
There is a 2G swapfile as a backstop. The point is that a Twenty spike can
never OOM-kill the PHP stack.

If Twenty feels slow, check `docker stats` before raising a limit, and
remember wishdumps needs roughly 1.1G at peak.

## Upstream workflows

This is a fork of `twentyhq/twenty`, which ships 57 workflows of its own.
They are disabled through the Actions API rather than deleted, so the fork
still merges cleanly from upstream. After syncing upstream, check whether new
workflows arrived and disable them too:

```bash
gh api repos/aliraza93/twenty/actions/workflows --paginate \
  --jq '.workflows[] | select(.state=="active") | "\(.id)\t\(.name)"'
```

Only "Deploy production" should be active.

## Operations

```bash
cd /opt/twenty
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f --tail=100 server worker
docker stats --no-stream
./backup.sh
```

Restore a dump:

```bash
gunzip -c backups/twenty-YYYYMMDD-HHMMSS.sql.gz | \
  docker compose -f docker-compose.prod.yml exec -T db psql -U twenty -d default
```

Certificates renew through the system certbot timer, which already handles the
wishdumps domains.
