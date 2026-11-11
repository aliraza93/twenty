#!/usr/bin/env bash
# Starts Twenty CRM. Requires Docker Desktop running.
set -e
cd "$(dirname "$0")"
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
  echo "or with Homebrew: brew install --cask docker   (then open Docker.app once)"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Starting Docker Desktop..."
  open -a Docker
  until docker info >/dev/null 2>&1; do sleep 2; done
fi
docker compose -f docker-compose.local.yml pull
docker compose -f docker-compose.local.yml up -d
echo "Waiting for Twenty to become healthy (first run takes a few minutes for DB migrations)..."
until curl -fs http://localhost:3000/healthz >/dev/null 2>&1; do sleep 5; printf "."; done
echo
echo "Twenty is up: http://localhost:3000"
open http://localhost:3000
