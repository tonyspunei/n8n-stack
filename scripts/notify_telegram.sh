#!/usr/bin/env bash
MSG=${1:-"n8n event"}
curl -s -X POST \
  "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TG_CHAT_ID}" \
  --data-urlencode text="$MSG" >/dev/null
