#!/usr/bin/env bash
# One-time provisioning for the Twenty CRM stack on the shared droplet.
# Idempotent: safe to re-run. Never edits the wishdumps vhost or nginx.conf.
set -euo pipefail

DOMAIN="${DOMAIN:-crm.twixrsolutions.com}"
APP_DIR="${APP_DIR:-/opt/twenty}"
CERT_EMAIL="${CERT_EMAIL:-}"
SWAP_SIZE="${SWAP_SIZE:-2G}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mFAILED: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"

# --- swap ------------------------------------------------------------------
# A memory backstop so a Twenty spike can never OOM-kill the PHP stack.
log "Swap"
if swapon --show | grep -q '/swapfile'; then
  echo "swapfile already active, leaving it alone"
else
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "created ${SWAP_SIZE} swapfile"
fi
# Prefer RAM, use swap only under real pressure.
sysctl -qw vm.swappiness=10
grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

# --- docker ----------------------------------------------------------------
log "Docker"
if command -v docker >/dev/null 2>&1; then
  echo "docker already installed: $(docker --version)"
else
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Cap the journald/container log growth on a small disk.
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
JSON
  systemctl restart docker
fi
systemctl enable --now docker

id -nG deploy | grep -qw docker || usermod -aG docker deploy

# --- app dir + secrets -----------------------------------------------------
log "App directory and secrets"
mkdir -p "$APP_DIR" /var/www/certbot "$APP_DIR/backups"
chown -R deploy:deploy "$APP_DIR"

if [ -f "$APP_DIR/.env" ]; then
  echo ".env already exists, keeping existing secrets"
else
  cat > "$APP_DIR/.env" <<ENVFILE
# Twenty CRM production environment. Generated $(date -Iseconds).
# ENCRYPTION_KEY and APP_SECRET must never change once data exists.
SERVER_URL=https://${DOMAIN}
TWENTY_IMAGE=ghcr.io/aliraza93/twenty:latest

PG_DATABASE_USER=twenty
PG_DATABASE_PASSWORD=$(openssl rand -hex 32)
PG_DATABASE_NAME=default

APP_SECRET=$(openssl rand -base64 32)
ENCRYPTION_KEY=$(openssl rand -base64 32)
ENVFILE
  chmod 600 "$APP_DIR/.env"
  chown deploy:deploy "$APP_DIR/.env"
  echo "generated fresh secrets in $APP_DIR/.env"
fi

# --- nginx -----------------------------------------------------------------
log "Nginx"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SRC/nginx/map-connection-upgrade.conf" /etc/nginx/conf.d/map-connection-upgrade.conf

CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
if [ -f "$CERT_PATH" ]; then
  echo "certificate already present"
  cp "$SRC/nginx/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}"
else
  echo "no certificate yet, installing bootstrap vhost"
  cp "$SRC/nginx/crm-bootstrap.conf" "/etc/nginx/sites-available/${DOMAIN}"
fi
ln -sfn "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"

# Never reload a config that does not parse: wishdumps shares this nginx.
nginx -t || die "nginx config test failed; wishdumps left untouched"
systemctl reload nginx

if [ ! -f "$CERT_PATH" ]; then
  log "Certificate"
  # Reuse the existing certbot account (the wishdumps certs registered without
  # an email); only a first-ever registration needs one.
  CERT_ARGS=""
  if ls /etc/letsencrypt/accounts/*/*/regr.json >/dev/null 2>&1; then
    echo "using existing certbot account"
  elif [ -n "$CERT_EMAIL" ]; then
    CERT_ARGS="-m $CERT_EMAIL"
  else
    CERT_ARGS="--register-unsafely-without-email"
  fi
  # shellcheck disable=SC2086
  certbot certonly --webroot -w /var/www/certbot \
    -d "$DOMAIN" --non-interactive --agree-tos $CERT_ARGS
  cp "$SRC/nginx/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}"
  nginx -t || die "nginx config test failed after cert install"
  systemctl reload nginx
  echo "certificate issued and TLS vhost installed"
fi

log "Done"
echo "App dir : $APP_DIR"
echo "Domain  : https://${DOMAIN}"
echo "Next    : push to main, or run deploy.sh on the server"
