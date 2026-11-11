#!/usr/bin/env bash
# Nightly database dump. Keeps 14 days.
set -euo pipefail
APP_DIR="${APP_DIR:-/opt/twenty}"
cd "$APP_DIR"
set -a; . ./.env; set +a
mkdir -p backups
F="backups/twenty-$(date +%Y%m%d-%H%M%S).sql.gz"
docker compose -f docker-compose.prod.yml exec -T db \
  pg_dump -U "$PG_DATABASE_USER" "$PG_DATABASE_NAME" | gzip > "$F"
find backups -name 'twenty-*.sql.gz' -mtime +14 -delete
echo "wrote $F"
