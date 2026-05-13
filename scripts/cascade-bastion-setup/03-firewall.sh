#!/bin/bash
# 03-firewall — fail2ban + ufw + allow 80/443 + 22 + Tailscale UDP

set -euo pipefail

systemctl enable --now fail2ban
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd
[sshd]
enabled = true
port    = 22
filter  = sshd
EOF
systemctl reload fail2ban

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP (Let'\''s Encrypt)'
ufw allow 443/tcp comment 'HTTPS (Guacamole web)'
ufw allow 41641/udp comment 'Tailscale WireGuard'
ufw --force enable
systemctl enable --now ufw

echo "[03] firewall configured (22, 80, 443, 41641/udp open)"
ufw status verbose | head -15
