#!/bin/bash
# 07-tailscale-up — join tailnet

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-server-setup.conf"

# Уже joined? skip
if tailscale status >/dev/null 2>&1; then
    CURR_HOST=$(hostname)
    CURR_TS=$(tailscale status --self --peers=false 2>/dev/null | head -1 | awk '{print $2}')
    if [ -n "$CURR_TS" ]; then
        echo "[07] tailscale уже joined: $CURR_TS"
        exit 0
    fi
fi

# Build tailscale up command
TS_CMD="tailscale up"
TS_CMD="$TS_CMD --hostname=$HOSTNAME"
TS_CMD="$TS_CMD --accept-routes=true"
TS_CMD="$TS_CMD --accept-dns=false"
TS_CMD="$TS_CMD --ssh=false"   # HARD RULE — Tailscale SSH always disabled

if [ -n "${TAILSCALE_TAGS:-}" ]; then
    TS_CMD="$TS_CMD --advertise-tags=$TAILSCALE_TAGS"
fi

if [ "${TAILSCALE_ADVERTISE_EXIT_NODE:-false}" = "true" ]; then
    TS_CMD="$TS_CMD --advertise-exit-node"
fi

if [ -n "${TAILSCALE_ADVERTISE_ROUTES:-}" ]; then
    TS_CMD="$TS_CMD --advertise-routes=$TAILSCALE_ADVERTISE_ROUTES"
fi

# Auth key или interactive OAuth
if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    TS_CMD="$TS_CMD --auth-key=$TAILSCALE_AUTHKEY"
    echo "[07] Using pre-auth key"
    eval "$TS_CMD"
else
    echo "[07] No TAILSCALE_AUTHKEY in config — interactive OAuth required."
    echo "[07] Run на этом сервере (после exit script):"
    echo "      $TS_CMD"
    echo "[07] И откройте URL который print'нется → выберите account krom00070007@gmail.com"
    echo ""
    echo "[07] Continuing setup without joining (Phase 8 будет skipped)..."
    exit 0
fi

# Verify
sleep 3
TS_IP=$(tailscale ip -4 2>/dev/null | head -1)
if [ -z "$TS_IP" ]; then
    echo "ERROR: tailscale up succeeded but no IP yet — check 'tailscale status' manually"
    exit 1
fi

echo "[07] tailscale joined. tailnet IP: $TS_IP"
tailscale status | head -5
