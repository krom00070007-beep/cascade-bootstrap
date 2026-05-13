#!/bin/bash
# 02-sshd-harden — key-only sshd, no password, no x11, no rootlogin password
# Fixes systemic gap found by cascade-doctor: 5/5 audited Cascade servers had
# permitrootlogin=yes, passwordauth=yes, x11=yes (critical findings).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-server-setup.conf"

SSHD_CONF=/etc/ssh/sshd_config

# Backup current
cp "$SSHD_CONF" "${SSHD_CONF}.bak-$(date +%Y%m%d-%H%M%S)"

# Patch each directive (idempotent — keeps existing value if already correct)
patch_sshd() {
    local key="$1" val="$2"
    if grep -qE "^#?${key}" "$SSHD_CONF"; then
        sed -i "s/^#\?${key}.*/${key} ${val}/" "$SSHD_CONF"
    else
        echo "${key} ${val}" >> "$SSHD_CONF"
    fi
}

patch_sshd "PermitRootLogin" "prohibit-password"   # key-only root (no password)
patch_sshd "PasswordAuthentication" "no"
patch_sshd "ChallengeResponseAuthentication" "no"
patch_sshd "KbdInteractiveAuthentication" "no"
patch_sshd "UsePAM" "yes"                          # keep PAM for session setup
patch_sshd "PermitEmptyPasswords" "no"
patch_sshd "X11Forwarding" "no"
patch_sshd "PrintMotd" "no"
patch_sshd "ClientAliveInterval" "60"
patch_sshd "ClientAliveCountMax" "3"

# Только специфичные алгоритмы (modern, без legacy)
patch_sshd "KexAlgorithms" "sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512"
patch_sshd "Ciphers" "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
patch_sshd "MACs" "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com"

# Validate
if sshd -t 2>&1 | tee /tmp/sshd-test.out; then
    systemctl reload sshd
    echo "[02] sshd hardened + reloaded"
else
    echo "ERROR: sshd config test failed. Restoring backup."
    cp "${SSHD_CONF}.bak-$(date +%Y%m%d-%H%M%S | cut -c-15)"* "$SSHD_CONF"  # safest match
    exit 1
fi
