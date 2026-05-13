#!/bin/bash
# 08-tailscale-exit-config — finalize exit-node + chained routing
#
# Two roles for this server:
#  1. ADVERTISE exit-node (peers use this server's egress IP)
#  2. USE another peer's exit-node (chain: client → этот → другой → internet)
#
# Также:
#  - ufw allow on tailscale0 iface (теперь когда iface существует)
#  - iptables NAT (Tailscale auto-handles, но verify)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-server-setup.conf"

# Check tailscale joined
if ! tailscale status >/dev/null 2>&1; then
    echo "[08] tailscale not joined yet — skip. Run 07 first (interactive)."
    exit 0
fi

# UFW: allow на tailscale0 (теперь iface есть)
ufw allow in on tailscale0 comment 'Tailscale tailnet traffic' || true
ufw reload

# Chained exit-node — set this server to route own outbound через USE_EXIT_NODE_HOSTNAME
if [ -n "${USE_EXIT_NODE_HOSTNAME:-}" ]; then
    echo "[08] Configuring chain: this server → $USE_EXIT_NODE_HOSTNAME → internet"

    # Resolve hostname to IP в tailnet (MagicDNS)
    EXIT_IP=$(tailscale status | grep -E "^[0-9.]+\s+$USE_EXIT_NODE_HOSTNAME\s" | awk '{print $1}' | head -1)
    if [ -z "$EXIT_IP" ]; then
        echo "WARN: cannot resolve $USE_EXIT_NODE_HOSTNAME in tailnet status."
        echo "       Verify peer is online + MagicDNS enabled."
        echo "       Skipping chained exit config."
    else
        echo "[08] Found $USE_EXIT_NODE_HOSTNAME at $EXIT_IP"

        SET_CMD="tailscale set --exit-node=$EXIT_IP"
        if [ "${USE_EXIT_NODE_LAN_ACCESS:-false}" = "true" ]; then
            SET_CMD="$SET_CMD --exit-node-allow-lan-access=true"
        fi

        $SET_CMD
        echo "[08] Chained exit-node configured: outbound через $USE_EXIT_NODE_HOSTNAME ($EXIT_IP)"
    fi
fi

# Verify
echo "[08] Final state:"
tailscale status --self | head -3
echo ""
echo "Advertised exit-node: $([ "${TAILSCALE_ADVERTISE_EXIT_NODE:-false}" = "true" ] && echo "yes" || echo "no")"
echo "Using exit-node:      ${USE_EXIT_NODE_HOSTNAME:-none (direct internet)}"
echo ""
echo "🚨 ВАЖНО: Открыть admin.tailscale.com → Machines → этот host:"
echo "   - ✅ Enable 'Allow this node as exit node' (если advertise=true)"
echo "   - ✅ Approve subnet routes (если advertised)"
echo "   - ✅ Disable key expiry (для control-points)"
echo ""
echo "Verify chained routing работает (с другой ноды tailnet):"
echo "   ssh peer 'curl -s ifconfig.me'"
echo "   Должен показать IP $USE_EXIT_NODE_HOSTNAME (NL для vultr-amsterdam)"
