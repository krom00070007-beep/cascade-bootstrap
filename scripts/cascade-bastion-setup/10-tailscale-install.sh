#!/bin/bash
# 10-tailscale-install (re-use from cascade-server-setup)
set -euo pipefail

if command -v tailscale >/dev/null 2>&1; then
    echo "[10] tailscale already installed: $(tailscale --version | head -1)"
    exit 0
fi

curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
    -o /etc/apt/sources.list.d/tailscale.list

apt update -y
apt install -y tailscale
systemctl enable --now tailscaled

echo "[10] tailscale installed: $(tailscale --version | head -1)"
