#!/bin/bash
# 11-tailscale-up — join tailnet + optional chained exit к bkk-exit

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"

# Already joined?
if tailscale status >/dev/null 2>&1; then
    CURRENT_IP=$(tailscale ip -4 2>/dev/null | head -1)
    if [ -n "$CURRENT_IP" ]; then
        echo "[11] already joined: $CURRENT_IP"
    fi
else
    TS_CMD="tailscale up --hostname=$HOSTNAME --accept-routes=true --accept-dns=false --ssh=false"
    [ -n "${TAILSCALE_TAGS:-}" ] && TS_CMD="$TS_CMD --advertise-tags=$TAILSCALE_TAGS"
    [ -n "${TAILSCALE_AUTHKEY:-}" ] && TS_CMD="$TS_CMD --auth-key=$TAILSCALE_AUTHKEY"
    echo "[11] $TS_CMD (key redacted)"
    eval "$TS_CMD"
fi

# Chained exit (если задан USE_EXIT_NODE_HOSTNAME)
if [ -n "${USE_EXIT_NODE_HOSTNAME:-}" ]; then
    echo "[11] Configuring chain → $USE_EXIT_NODE_HOSTNAME"
    sleep 3
    EXIT_IP=$(tailscale status | grep -E "^[0-9.]+\s+$USE_EXIT_NODE_HOSTNAME\s" | awk '{print $1}' | head -1)
    if [ -n "$EXIT_IP" ]; then
        tailscale set --exit-node=$EXIT_IP
        echo "[11] Outbound теперь через $USE_EXIT_NODE_HOSTNAME ($EXIT_IP)"
    else
        echo "[11] WARN: peer $USE_EXIT_NODE_HOSTNAME not in tailnet — skipping chain"
    fi
fi

tailscale status --self | head -3
tailscale ip -4

echo "[11] Tailscale ready"
