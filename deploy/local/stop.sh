#!/usr/bin/env bash
# Stops Twenty CRM. Data is kept in Docker volumes.
cd "$(dirname "$0")" && docker compose -f docker-compose.local.yml down
