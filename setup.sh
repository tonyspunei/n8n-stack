#!/usr/bin/env bash
set -euo pipefail
export TZ="Europe/Berlin"

echo "== n8n stack bootstrap =="

# -- detect repo root -------------------------------------------------
REPO_DIR="$(dirname "$(readlink -f "$0")")"
cd "$REPO_DIR"

# 1) Ask for env if .env doesn’t exist
if [[ ! -f .env ]]; then
  echo "Copying .env.example → .env"
  cp .env.example .env
  echo "Please edit .env now (at minimum DOMAIN_NAME, SUBDOMAIN, passwords)."
  read -rp "Open editor? [y/N] " ans
  [[ $ans == y* || $ans == Y* ]] && ${EDITOR:-nano} .env
fi

# 2) Install prerequisites
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release ufw rclone

# Docker Engine + compose‑plugin
if ! command -v docker >/dev/null 2>&1; then
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

# 3) Firewall hardening
./scripts/firewall.sh

# 4) Bring the stack up
docker compose pull
docker compose up -d

# 5) Make n8nctl globally available
CTL_SRC="$(readlink -f "$REPO_DIR/n8nctl")"
CTL_LINK="/usr/local/bin/n8nctl"

chmod +x "$CTL_SRC"

if [[ ! -L "$CTL_LINK" || "$(readlink -f "$CTL_LINK")" != "$CTL_SRC" ]]; then
  ln -sf "$CTL_SRC" "$CTL_LINK"
  echo "Linked n8nctl → $CTL_LINK"
fi

echo "n8n should be reachable at https://$(grep SUBDOMAIN .env | cut -d= -f2).$(grep DOMAIN_NAME .env | cut -d= -f2)"
echo "You can now use the convenience CLI:  n8nctl backup | update | restore …"
