#!/bin/bash
# cascade-bastion-setup — bootstrap fresh Ubuntu 24 VDS как Cascade bastion
#
# Role: web-based remote desktop bridge к PC Beelink (Pattaya home) через
# Cascade tailnet (chained через bkk-exit / opus-cwr-bkk).
#
# Components:
#   - System: apt + sshd hardening + fail2ban + ufw + swap + sysctl tuning
#   - Docker + Apache Guacamole (guacd + guacamole + postgres)
#   - nginx + Let's Encrypt (krom7.ru → guacamole)
#   - Tailscale (join tailnet, tag:cascade-bastion, optional exit-node)
#   - Optional cascade-local-doctor (daily Telegram self-report)
#
# Access patterns после deploy:
#   A) Browser → https://krom7.ru → login → Beelink RDP via tunnel
#   B) Desktop client → Tailscale на клиента → прямой RDP к beelink.tail80c5d4.ts.net
#
# Time: 15-25 минут (Docker pull + apt + Let's Encrypt cert)
# Idempotent: можно перезапускать, пропускает done phases

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/var/log/cascade-bastion-setup.log
CONF="$SCRIPT_DIR/cascade-bastion-setup.conf"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: must run as root (sudo)"
    exit 1
fi

if [ ! -f "$CONF" ]; then
    echo "ERROR: config not found: $CONF"
    echo "Run: cp cascade-bastion-setup.conf.sample cascade-bastion-setup.conf && \$EDITOR cascade-bastion-setup.conf"
    exit 1
fi

source "$CONF"
touch "$LOG" && chmod 600 "$LOG"

log() {
    local msg="$*"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $msg"
    echo "[$ts] $msg" >> "$LOG"
}

log "==== cascade-bastion-setup start ===="
log "Domain: $DOMAIN, hostname: $HOSTNAME, Beelink target: ${BEELINK_TAILSCALE_HOST:-not set}"

# Phase 1: system prep
log "--- Phase 1: 01-system-prep.sh ---"
bash "$SCRIPT_DIR/01-system-prep.sh"

# Phase 2: sshd harden
log "--- Phase 2: 02-sshd-harden.sh ---"
bash "$SCRIPT_DIR/02-sshd-harden.sh"

# Phase 3: firewall (ufw + 80/443/22)
log "--- Phase 3: 03-firewall.sh ---"
bash "$SCRIPT_DIR/03-firewall.sh"

# Phase 4: swap
if [ "${SWAP_SIZE_MB:-2048}" -gt 0 ]; then
    log "--- Phase 4: 04-swap.sh ---"
    bash "$SCRIPT_DIR/04-swap.sh"
fi

# Phase 5: sysctl
log "--- Phase 5: 05-sysctl-tuning.sh ---"
bash "$SCRIPT_DIR/05-sysctl-tuning.sh"

# Phase 6: Docker
log "--- Phase 6: 06-docker-install.sh ---"
bash "$SCRIPT_DIR/06-docker-install.sh"

# Phase 7: Guacamole compose
log "--- Phase 7: 07-guacamole-deploy.sh ---"
bash "$SCRIPT_DIR/07-guacamole-deploy.sh"

# Phase 8: nginx
log "--- Phase 8: 08-nginx-install.sh ---"
bash "$SCRIPT_DIR/08-nginx-install.sh"

# Phase 9: Let's Encrypt
log "--- Phase 9: 09-letsencrypt.sh ---"
bash "$SCRIPT_DIR/09-letsencrypt.sh"

# Phase 10: Tailscale install
log "--- Phase 10: 10-tailscale-install.sh ---"
bash "$SCRIPT_DIR/10-tailscale-install.sh"

# Phase 11: Tailscale up + chained exit
log "--- Phase 11: 11-tailscale-up.sh ---"
bash "$SCRIPT_DIR/11-tailscale-up.sh"

# Phase 12: Add Beelink connection to Guacamole DB (manual SQL insert)
log "--- Phase 12: 12-add-beelink-connection.sh ---"
bash "$SCRIPT_DIR/12-add-beelink-connection.sh"

# Phase 13: validate
log "--- Phase 13: 13-validate.sh ---"
bash "$SCRIPT_DIR/13-validate.sh"

log "==== cascade-bastion-setup DONE ===="
log ""
log "Access (browser):"
log "  https://$DOMAIN"
log "  Username: $GUACAMOLE_ADMIN_USER"
log "  Password: $GUACAMOLE_ADMIN_PASS"
log "  ⚠️ Change password ASAP в Settings → Preferences"
log ""
log "Access (desktop):"
log "  Install Tailscale client → join cascade tailnet → RDP к $BEELINK_TAILSCALE_HOST"
log "  Or NoMachine / AnyDesk direct (vs Guacamole web)"
log ""
log "Full log: $LOG"
