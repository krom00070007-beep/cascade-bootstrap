#!/bin/bash
# 03-firewall — fail2ban + ufw configure
# Fixes systemic gap: bkk-exit + msk-vps-bridge had no fail2ban, vultr.guest had no ufw.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-server-setup.conf"

# ============================================================
# fail2ban
# ============================================================

# Уже установлен в 01-system-prep, здесь только enable
systemctl enable --now fail2ban

# Configure jail.local — sshd defaults
cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = 22
filter  = sshd
JAIL

systemctl reload fail2ban || systemctl restart fail2ban

# ============================================================
# ufw
# ============================================================

# Reset на чистое state (idempotent, comes from package defaults)
ufw --force reset

# Defaults
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (port 22)
ufw allow 22/tcp comment 'SSH'

# Allow Tailscale (UDP 41641 — direct WireGuard; iface tailscale0 will be
# created after Tailscale up; rule by port здесь работает как fallback)
ufw allow 41641/udp comment 'Tailscale WireGuard'

# Когда tailscale0 будет создан — добавим allow on iface (см. ниже)

# Allow custom subnet routes (если advertised)
if [ -n "${TAILSCALE_ADVERTISE_ROUTES:-}" ]; then
    IFS=',' read -ra ROUTES <<< "$TAILSCALE_ADVERTISE_ROUTES"
    for route in "${ROUTES[@]}"; do
        ufw allow from "$route" comment "Tailscale advertised route"
    done
fi

# Enable ufw (non-interactive)
ufw --force enable
systemctl enable --now ufw

# ============================================================
# Defer: rule for tailscale0 iface allowing all in
# This needs tailscale0 to exist — script 08 (after tailscale up) will
# call `ufw allow in on tailscale0`.
# ============================================================

echo "[03] firewall configured (fail2ban active, ufw active, SSH+Tailscale-UDP allowed)"
ufw status verbose | head -20
