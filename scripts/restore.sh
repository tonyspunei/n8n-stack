#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "Usage: restore.sh <timestamp>"
  exit 1
fi
TS=$1
ROOT="$(dirname "$(readlink -f "$0")")/.."
export $(grep -v '^#' "$ROOT/.env" | xargs -d '\n')
compose() { docker compose -f "$ROOT/docker-compose.yml" "$@"; }

compose stop n8n

echo "[restore] restoring database dump…"
docker exec -i $(compose ps -q db) psql -U "$DB_USER" "$DB_NAME" \
  < "$ROOT/backups/db-$TS.sql"

echo "[restore] restoring n8n filesystem…"
docker run --rm \
  -v n8n_data:/data \
  -v "$ROOT/backups":/backup \
  alpine sh -c "rm -rf /data/* && tar xzf /backup/n8nfs-$TS.tar.gz -C /data"

compose up -d n8n
echo "Done. n8n is live on the restored snapshot $TS."
