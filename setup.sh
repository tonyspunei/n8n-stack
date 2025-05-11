#!/usr/bin/env bash
set -euo pipefail
export TZ="Europe/Berlin"

echo "== n8n stack bootstrap =="

# -- detect repo root -------------------------------------------------
REPO_DIR="$(dirname "$(readlink -f "$0")")"
cd "$REPO_DIR"

# --- NEW: ensure exec bits are present -------------------------------
chmod +x n8nctl scripts/*.sh 2>/dev/null || true
# ---------------------------------------------------------------------

# 1) copy .env if missing
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Edit .env now (DOMAIN_NAME, passwords, etc.)"
  read -rp "Open editor? [y/N] " ans
  [[ $ans == [yY]* ]] && ${EDITOR:-nano} .env
fi

# 2) prerequisites
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release ufw rclone

echo "[debug] PATH = $PATH"
echo -n "[debug] which docker = "; which docker || echo "not found"
echo -n "[debug] whereis docker = "; whereis docker

# Docker Engine + compose‑plugin
SKIP_DOCKER_INSTALL=${SKIP_DOCKER_INSTALL:-0}
if ! command -v docker &>/dev/null; then
  if [[ "$SKIP_DOCKER_INSTALL" == 1 ]]; then
    echo "[setup] Docker already present – skipping engine install"
  else
    echo "Installing Docker Engine..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  fi
fi

echo "[n8nctl debug] PATH=$PATH"
which docker 2>/dev/null || echo "[n8nctl debug] 'docker' not in PATH"

# 3) **always** make n8nctl reachable
CTL_SRC="$REPO_DIR/n8nctl"
CTL_LINK="/usr/local/bin/n8nctl"
chmod +x "$CTL_SRC"
ln -sf "$CTL_SRC" "$CTL_LINK"
echo "[setup] Linked n8nctl → $CTL_LINK"

# 4) firewall hardening (unless skipped)
SKIP_FIREWALL=${SKIP_FIREWALL:-0}
if [[ "$SKIP_FIREWALL" == 0 ]]; then
  bash ./scripts/firewall.sh
else
  echo "[setup] SKIP_FIREWALL=1 – skipping UFW rules"
fi

# 5) guarded compose pull + up
set +e
docker compose pull
docker compose up -d
COMPOSE_RC=$?
set -e

if [[ $COMPOSE_RC -ne 0 ]]; then
  echo "[setup] ⚠️  docker compose up failed (rc=$COMPOSE_RC)."
  echo "         Most likely missing or wrong vars in .env."
  echo "         Fix them and run:  n8nctl up"
else
  echo "[setup] Stack is running.  Try:  n8nctl version"
fi

echo "== bootstrap done =="