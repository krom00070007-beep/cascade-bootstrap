#!/bin/bash
# 06-tailscale-install — install Tailscale via official apt repo

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-server-setup.conf"

# Если уже установлен — skip
if command -v tailscale >/dev/null 2>&1; then
    echo "[06] tailscale уже установлен: $(tailscale --version | head -1)"
    exit 0
fi

# Add Tailscale apt repo
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg

curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
    -o /etc/apt/sources.list.d/tailscale.list

apt-get update
apt-get install -y tailscale

# Enable + start daemon (will be idle until tailscale up)
systemctl enable --now tailscaled

echo "[06] tailscale installed: $(tailscale --version | head -1)"
