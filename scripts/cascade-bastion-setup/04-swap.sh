#!/bin/bash
# 04-swap (re-use)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"

SWAP_FILE="/swap.img"
SIZE_MB="${SWAP_SIZE_MB:-2048}"

if [ -f "$SWAP_FILE" ] && swapon --show=NAME --noheadings | grep -q "^$SWAP_FILE$"; then
    echo "[04] swap already configured"
    exit 0
fi

fallocate -l "${SIZE_MB}M" "$SWAP_FILE" 2>/dev/null || dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SIZE_MB"
chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE"
swapon "$SWAP_FILE"

if ! grep -q "^${SWAP_FILE}" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

cat > /etc/sysctl.d/99-cascade-swap.conf <<'EOF'
vm.swappiness = 10
EOF
sysctl -p /etc/sysctl.d/99-cascade-swap.conf >/dev/null
echo "[04] swap configured (${SIZE_MB} MB)"
