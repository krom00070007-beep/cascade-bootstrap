#!/bin/bash
# cascade-server-setup — bootstrap fresh Ubuntu 24.04 server для роли:
#   - Tailscale Exit Node (advertise-exit-node, principal)
#   - Chained outbound через ДРУГОЙ Tailscale peer (--exit-node=<peer>)
#   - Local self-doctor monitoring (cron + Telegram self-report)
#
# Baked-in fixes для известных ошибок из проекта Cascade (см. cascade-architecture-errors-2026-05-14.md):
#   ✓ sshd hardening (PermitRootLogin prohibit-password, PasswordAuth no, X11 no)
#   ✓ fail2ban install + enabled
#   ✓ ufw configure (allow 22, tailscale0)
#   ✓ swap configure (default 1GB)
#   ✓ TCP BBR + large buffers (минимальная потеря скорости)
#   ✓ unattended-upgrades для security patches
#   ✓ ip_forward=1 (для exit-node functionality)
#   ✓ Tailscale apt repo (auto-update versions)
#   ✓ Tags + tagOwners workflow
#
# Usage (как root или sudo):
#   cp cascade-server-setup.conf.sample cascade-server-setup.conf
#   $EDITOR cascade-server-setup.conf
#   sudo ./00-bootstrap.sh
#
# Idempotent: можно перезапускать; пропускает уже-сделанные шаги.
# Logging: /var/log/cascade-server-setup.log

set -euo pipefail

# ============================================================
# Self-check + config load
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/var/log/cascade-server-setup.log
CONF="$SCRIPT_DIR/cascade-server-setup.conf"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Must run as root (use sudo)."
    exit 1
fi

if [ ! -f "$CONF" ]; then
    echo "ERROR: Config not found: $CONF"
    echo "Run: cp cascade-server-setup.conf.sample cascade-server-setup.conf && \$EDITOR cascade-server-setup.conf"
    exit 1
fi

# shellcheck source=/dev/null
source "$CONF"

touch "$LOG"
chmod 600 "$LOG"

log() {
    local msg="$*"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $msg"
    echo "[$ts] $msg" >> "$LOG"
}

abort() {
    log "ABORT: $*"
    exit 1
}

require_var() {
    local v="$1"
    if [ -z "${!v:-}" ]; then
        abort "Required config var $v is empty"
    fi
}

log "==== cascade-server-setup start ===="
log "Hostname: ${HOSTNAME:-?}, Admin: ${ADMIN_USER:-?}, TZ: ${TZ:-?}"

require_var HOSTNAME
require_var ADMIN_USER

# ============================================================
# Phase 1 — system prep
# ============================================================

log "--- Phase 1: 01-system-prep.sh ---"
bash "$SCRIPT_DIR/01-system-prep.sh"

# ============================================================
# Phase 2 — sshd hardening
# ============================================================

if [ "${HARDEN_SSHD:-true}" = "true" ]; then
    log "--- Phase 2: 02-sshd-harden.sh ---"
    bash "$SCRIPT_DIR/02-sshd-harden.sh"
else
    log "Skipping sshd harden (HARDEN_SSHD=false)"
fi

# ============================================================
# Phase 3 — firewall (fail2ban + ufw)
# ============================================================

log "--- Phase 3: 03-firewall.sh ---"
bash "$SCRIPT_DIR/03-firewall.sh"

# ============================================================
# Phase 4 — swap configure
# ============================================================

if [ "${SWAP_SIZE_MB:-1024}" -gt 0 ]; then
    log "--- Phase 4: 04-swap.sh (size=${SWAP_SIZE_MB}MB) ---"
    bash "$SCRIPT_DIR/04-swap.sh"
else
    log "Skipping swap (SWAP_SIZE_MB=0)"
fi

# ============================================================
# Phase 5 — sysctl tuning (performance)
# ============================================================

log "--- Phase 5: 05-sysctl-tuning.sh ---"
bash "$SCRIPT_DIR/05-sysctl-tuning.sh"

# ============================================================
# Phase 6 — Tailscale install
# ============================================================

log "--- Phase 6: 06-tailscale-install.sh ---"
bash "$SCRIPT_DIR/06-tailscale-install.sh"

# ============================================================
# Phase 7 — Tailscale up (interactive or pre-auth key)
# ============================================================

log "--- Phase 7: 07-tailscale-up.sh ---"
bash "$SCRIPT_DIR/07-tailscale-up.sh"

# ============================================================
# Phase 8 — Tailscale exit config (advertise + chained)
# ============================================================

log "--- Phase 8: 08-tailscale-exit-config.sh ---"
bash "$SCRIPT_DIR/08-tailscale-exit-config.sh"

# ============================================================
# Phase 9 — local-doctor install
# ============================================================

if [ "${ENABLE_LOCAL_DOCTOR:-true}" = "true" ]; then
    log "--- Phase 9: 09-local-doctor.sh ---"
    bash "$SCRIPT_DIR/09-local-doctor.sh"
else
    log "Skipping local-doctor (ENABLE_LOCAL_DOCTOR=false)"
fi

# ============================================================
# Done
# ============================================================

log "==== cascade-server-setup DONE ===="
log ""
log "Verify:"
log "  - tailscale.exe status  # should show this node + peers"
log "  - tailscale ip -4"
log "  - systemctl status fail2ban cascade-local-doctor.timer 2>/dev/null"
log "  - sysctl net.ipv4.ip_forward net.core.default_qdisc net.ipv4.tcp_congestion_control"
log "  - ufw status verbose"
log ""
log "Next steps (manual):"
log "  1. admin.tailscale.com → Machines → этот host → ✅ Approve subnet routes if advertised"
log "  2. admin.tailscale.com → Machines → этот host → ✅ Allow exit-node (для chained use)"
log "  3. На MSI cascade-doctor — добавить эту ноду в FULL_SSH_NODES (см. README)"
log "  4. Verify chained exit through this server:"
log "     ssh peer-using-this-exit 'curl -s ifconfig.me'   # should show this server's egress IP"
log ""
log "Full log: $LOG"
