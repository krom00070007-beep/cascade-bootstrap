#!/bin/bash
# 06-docker-install — Docker CE + docker compose plugin
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
    echo "[06] docker already installed: $(docker --version)"
    exit 0
fi

# Add Docker apt repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

# Allow admin user в docker group
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"
usermod -aG docker "$ADMIN_USER" 2>/dev/null || true

echo "[06] docker installed: $(docker --version)"
echo "[06] docker compose: $(docker compose version)"
