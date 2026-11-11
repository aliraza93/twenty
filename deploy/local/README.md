# Twenty CRM - local install on your Mac

For the production deployment see `../README.md`.

Official Docker Compose setup from twentyhq/twenty, with secrets already generated in `.env`.

## Run
1. Install Docker Desktop (Apple Silicon): `brew install --cask docker`, then open Docker.app once.
   Give it at least 4 GB RAM (Settings > Resources); Twenty needs 2 GB minimum.
2. `cd "/Volumes/Work/My Projects/twenty-crm/deploy/local" && ./start.sh`
3. Open http://localhost:3000 and create your workspace (the first account becomes admin).

## Daily use
- `./stop.sh`   stop (data is kept)
- `./start.sh`  start again
- `./logs.sh`   follow server/worker logs
- `./backup.sh` dump the database to `backups/`

## Notes
- `.env` holds ENCRYPTION_KEY and the DB password. Back it up somewhere safe (1Password etc). Never commit it.
- Containers use `restart: always`, so Twenty comes back whenever Docker Desktop starts.
- Upgrading: run `./backup.sh` first, then pin `TAG` in `.env` to the next release and `./start.sh`.
  Twenty upgrades should go one minor version at a time.
- API for Jarvis: Settings > APIs & Webhooks in Twenty to create an API key (REST + GraphQL).
- Moving to a server later: copy this folder, set SERVER_URL to the public https URL, restore a backup.
