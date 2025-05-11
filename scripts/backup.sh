#!/usr/bin/env bash
set -euo pipefail

########################################################################
# n8n backup script — v2
# 1. Loads .env, detects the real docker‑compose project name
# 2. Dumps Postgres
# 3. Archives the n8n_data volume
# 4. Prunes on‑node backups older than N days
# 5. Syncs to rclone remote   (optional)
# 6. Sends Telegram notice    (optional)
########################################################################

# ---------------------------------------------------------------------
# Settings (edit if you like)
# ---------------------------------------------------------------------
REPO_DIR="$(dirname "$(readlink -f "$0")")/.."       # repo root
COMPOSE_FILE="$REPO_DIR/docker-compose.yml"          # path to compose
BACKUP_DIR="$REPO_DIR/backups"                       # where to keep files
KEEP_DAYS=7                                          # prune threshold
RCLONE_REMOTE="gdrive:n8n-backups"                   # rclone target
TZ_DEFAULT="Europe/Berlin"                           # timezone
# ---------------------------------------------------------------------

export TZ="${GENERIC_TIMEZONE:-$TZ_DEFAULT}"
export PATH=/usr/local/bin:/usr/bin:/bin:$PATH

cd "$REPO_DIR"

# ---------------------------------------------------------------------
# Load .env so we have DB_USER / DB_PASS / DB_NAME, Telegram vars, etc.
# ---------------------------------------------------------------------
if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs)
fi

# ---------------------------------------------------------------------
# Pick docker compose binary
# ---------------------------------------------------------------------
if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose -f $COMPOSE_FILE"
else
  DC="docker compose -f $COMPOSE_FILE"
fi

# ---------------------------------------------------------------------
# Figure out the real volume name that Docker created
#   Compose names volumes <project>_<volume>
#   project = directory name unless COMPOSE_PROJECT_NAME is set
# ---------------------------------------------------------------------
project=$(
  awk '
    BEGIN{print ENVIRON["COMPOSE_PROJECT_NAME"]; exit}
  ' /dev/null
)
[[ -z "$project" ]] && project="$(basename "$REPO_DIR")"
VOL_NAME="${project}_n8n_data"

# ---------------------------------------------------------------------
# Timestamp & folder housekeeping
# ---------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"
TS=$(date +"%F-%H%M")

# ---------------------------------------------------------------------
# 1) dump Postgres
# ---------------------------------------------------------------------
DB_CONTAINER=$($DC ps -q db)
if [[ -z "$DB_CONTAINER" ]]; then
  echo "[backup] ERROR: could not find Postgres container" >&2
  exit 1
fi
echo "[backup] dumping Postgres…"
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" \
  > "$BACKUP_DIR/db-$TS.sql"

# ---------------------------------------------------------------------
# 2) archive n8n filesystem
# ---------------------------------------------------------------------
echo "[backup] archiving n8n_data volume ($VOL_NAME)…"
docker run --rm \
  -v "$VOL_NAME":/data \
  -v "$BACKUP_DIR":/backup \
  alpine \
  sh -c "tar czf /backup/n8nfs-$TS.tar.gz -C /data ."

# ---------------------------------------------------------------------
# 3) prune old backups
# ---------------------------------------------------------------------
echo "[backup] pruning local backups older than $KEEP_DAYS days…"
find "$BACKUP_DIR" -type f -mtime "+$KEEP_DAYS" -delete

# ---------------------------------------------------------------------
# 4) rclone sync (optional)
# ---------------------------------------------------------------------
if command -v rclone >/dev/null 2>&1; then
  echo "[backup] syncing to $RCLONE_REMOTE …"
  rclone sync "$BACKUP_DIR" "$RCLONE_REMOTE"
fi

# ---------------------------------------------------------------------
# 5) Telegram notification (optional)
# ---------------------------------------------------------------------
if [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" ]]; then
  curl -s -X POST \
    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TG_CHAT_ID" \
    --data-urlencode text="✅ n8n backup complete ($TS)" >/dev/null
fi

echo "[backup] done — files live in $BACKUP_DIR"
