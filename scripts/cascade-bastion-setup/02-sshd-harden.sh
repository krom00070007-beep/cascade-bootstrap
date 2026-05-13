#!/bin/bash
# 02-sshd-harden (re-use pattern from cascade-server-setup)
set -euo pipefail

SSHD_CONF=/etc/ssh/sshd_config
cp "$SSHD_CONF" "${SSHD_CONF}.bak-$(date +%Y%m%d-%H%M%S)"

patch_sshd() {
    local key="$1" val="$2"
    if grep -qE "^#?${key}" "$SSHD_CONF"; then
        sed -i "s/^#\?${key}.*/${key} ${val}/" "$SSHD_CONF"
    else
        echo "${key} ${val}" >> "$SSHD_CONF"
    fi
}

patch_sshd "PermitRootLogin" "prohibit-password"
patch_sshd "PasswordAuthentication" "no"
patch_sshd "ChallengeResponseAuthentication" "no"
patch_sshd "X11Forwarding" "no"
patch_sshd "PrintMotd" "no"
patch_sshd "ClientAliveInterval" "60"
patch_sshd "ClientAliveCountMax" "3"

if sshd -t; then
    systemctl reload sshd
    echo "[02] sshd hardened"
else
    echo "ERROR: sshd config test failed"
    exit 1
fi
