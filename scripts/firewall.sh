#!/usr/bin/env bash
set -euo pipefail

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow http
ufw allow https

# Ensure Docker respects UFW by adding a DOCKER-USER chain rule
iptables -I DOCKER-USER -j RETURN

ufw --force enable
echo "UFW hardened & enabled"
