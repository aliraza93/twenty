#!/usr/bin/env bash
cd "$(dirname "$0")" && docker compose -f docker-compose.local.yml logs -f --tail=100 server worker
