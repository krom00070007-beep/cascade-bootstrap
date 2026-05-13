#!/bin/bash
# 04-swap — configure swap file
# Fixes systemic gap: opus + bkk-exit + msk-vps-bridge had no swap.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-server-setup.conf"

SWAP_FILE="/swap.img"
SIZE_MB="${SWAP_SIZE_MB:-1024}"

# Existing?
if [ -f "$SWAP_FILE" ] && swapon --show=NAME --noheadings | grep -q "^$SWAP_FILE$"; then
    echo "[04] swap уже configured ($SWAP_FILE active)"
    swapon --show
    exit 0
fi

# Create swap
fallocate -l "${SIZE_MB}M" "$SWAP_FILE" 2>/dev/null || \
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SIZE_MB"

chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE"
swapon "$SWAP_FILE"

# Persistent
if ! grep -q "^${SWAP_FILE}" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

# Tune swappiness (low — only use swap when really needed)
SYSCTL_FILE=/etc/sysctl.d/99-cascade-swap.conf
cat > "$SYSCTL_FILE" <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
sysctl -p "$SYSCTL_FILE" >/dev/null

echo "[04] swap configured: $SWAP_FILE (${SIZE_MB} MB), swappiness=10"
free -h | head -3
