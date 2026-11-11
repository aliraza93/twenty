#!/usr/bin/env bash
# Rolls the Twenty stack onto a new image. Invoked by CI over SSH, or by hand.
# Usage: deploy.sh ghcr.io/aliraza93/twenty:sha-abc1234
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/twenty}"
# Every docker compose call must resolve to this file; a bare
# `docker compose` here would find no default file and fail silently.
export COMPOSE_FILE=docker-compose.prod.yml
NEW_IMAGE="${1:-}"
HEALTH_URL="http://127.0.0.1:3000/healthz"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-420}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mFAILED: %s\033[0m\n' "$*" >&2; exit 1; }

[ -n "$NEW_IMAGE" ] || die "usage: deploy.sh <image-ref>"
cd "$APP_DIR" || die "$APP_DIR missing, run bootstrap-server.sh first"
[ -f .env ] || die ".env missing in $APP_DIR"

PREVIOUS_IMAGE="$(grep -E '^TWENTY_IMAGE=' .env | cut -d= -f2- || true)"
log "Current image: ${PREVIOUS_IMAGE:-none}"
log "New image:     $NEW_IMAGE"

log "Pulling image"
docker pull "$NEW_IMAGE" || die "could not pull $NEW_IMAGE"

# Back up the database before migrations run; the server entrypoint migrates
# automatically on boot and that is the only step here that is not reversible.
if docker compose ps --status running --services | grep -qx db; then
  log "Backing up database"
  mkdir -p backups
  BACKUP="backups/pre-deploy-$(date +%Y%m%d-%H%M%S).sql.gz"
  # shellcheck disable=SC1091
  set -a; . ./.env; set +a
  if docker compose exec -T db pg_dump -U "$PG_DATABASE_USER" "$PG_DATABASE_NAME" | gzip > "$BACKUP"; then
    echo "wrote $BACKUP ($(du -h "$BACKUP" | cut -f1))"
    ls -1t backups/pre-deploy-*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm --
  else
    rm -f "$BACKUP"
    die "database backup failed, refusing to deploy"
  fi
fi

log "Writing new image reference"
sed -i -E "s#^TWENTY_IMAGE=.*#TWENTY_IMAGE=${NEW_IMAGE//#/\\#}#" .env
grep -qE '^TWENTY_IMAGE=' .env || echo "TWENTY_IMAGE=$NEW_IMAGE" >> .env

log "Starting stack"
docker compose up -d --remove-orphans

log "Waiting for health (up to ${HEALTH_TIMEOUT}s)"
deadline=$(( $(date +%s) + HEALTH_TIMEOUT ))
until curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "--- server logs (tail) ---"
    docker compose logs --tail=60 server || true
    if [ -n "$PREVIOUS_IMAGE" ] && [ "$PREVIOUS_IMAGE" != "$NEW_IMAGE" ]; then
      log "Unhealthy, rolling back to $PREVIOUS_IMAGE"
      sed -i -E "s#^TWENTY_IMAGE=.*#TWENTY_IMAGE=${PREVIOUS_IMAGE//#/\\#}#" .env
      docker compose up -d
    fi
    die "server did not become healthy within ${HEALTH_TIMEOUT}s"
  fi
  sleep 5
  printf '.'
done
echo

log "Pruning old images"
docker image prune -af --filter "until=168h" >/dev/null 2>&1 || true

log "Deployed"
docker compose ps
curl -fsS "$HEALTH_URL" && echo
