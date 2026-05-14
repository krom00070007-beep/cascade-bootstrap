#!/bin/bash
# MIG-001 T9 — Install cascade-browser as a systemd service (WSL2 supports systemd
# when [boot]\nsystemd=true is in /etc/wsl.conf — Ubuntu-24.04 default).
#
# Replaces the nohup-based launch we used on MSI.
#
# What this does:
#   1. Ensure /etc/wsl.conf has systemd=true (if not, instruct reboot)
#   2. Install cascade-browser.service to /etc/systemd/system/
#   3. Touch /var/log/cascade-browser.log with proper ownership
#   4. daemon-reload, enable, start, sleep 3, status
#   5. Verify ports 8767/8768 listening
#
# Logs to /tmp/mig-001-09-systemd.log.

set -euo pipefail
LOG=/tmp/mig-001-09-systemd.log
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date -Iseconds) MIG-001 T9 systemd-install start ===="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="$SCRIPT_DIR/cascade-browser.service"
UNIT_DST=/etc/systemd/system/cascade-browser.service


# --- 0. WSL2 mirrored networking check (added 14.05) ---
WSLCFG="/mnt/c/Users/krom0/.wslconfig"
if ! grep -q "networkingMode=mirrored" "$WSLCFG" 2>/dev/null; then
    echo "WARN: $WSLCFG missing networkingMode=mirrored."
    echo "Append manually: [wsl2] / networkingMode=mirrored"
    echo "Then wsl --shutdown from PowerShell, then re-run this script."
    exit 1
else
    echo "[0/4] WSL2 mirrored networking: OK"
fi

# --- 1. systemd-in-WSL check ---
if ! grep -q '^systemd=true' /etc/wsl.conf 2>/dev/null; then
    echo "WARN: /etc/wsl.conf does not have systemd=true."
    echo "  Adding [boot] systemd=true now. You MUST run 'wsl --shutdown' from Windows"
    echo "  and re-enter WSL before systemd is available."
    sudo tee -a /etc/wsl.conf >/dev/null <<'EOF'

[boot]
systemd=true
EOF
    echo ""
    echo "==== ACTION: from Windows PowerShell run 'wsl --shutdown', then reopen WSL ===="
    echo "==== Then re-run this script. ===="
    exit 0
fi

# --- 2. Install unit file ---
if [ ! -f "$UNIT_SRC" ]; then
    echo "FATAL: $UNIT_SRC not found. Did you clone cascade-state?"
    exit 1
fi
echo "[1/4] Installing $UNIT_DST..."
sudo install -m 644 "$UNIT_SRC" "$UNIT_DST"

# --- 3. Log target ---
echo "[2/4] Preparing /var/log/cascade-browser.log..."
sudo touch /var/log/cascade-browser.log
sudo chown usersstas:usersstas /var/log/cascade-browser.log
sudo chmod 640 /var/log/cascade-browser.log

# --- 4. Enable + start ---
echo "[3/4] daemon-reload, enable, start..."
sudo systemctl daemon-reload
sudo systemctl enable cascade-browser.service
sudo systemctl restart cascade-browser.service
sleep 3
sudo systemctl status cascade-browser.service --no-pager | head -15

# --- 5. Port verification ---
echo "[4/4] Port listeners..."
if command -v ss >/dev/null; then
    ss -tlnp 2>/dev/null | grep -E ':876[78]' || echo "WARN: 8767/8768 not listening — check journalctl -u cascade-browser"
else
    echo "  (ss not available — skipping port probe)"
fi

echo ""
echo "==== T9 done — cascade-browser.service should be active and on boot ===="
echo "Logs: journalctl -u cascade-browser -f"
echo "Next: T10 (Funnel + allowed_hosts patch — see scripts/migration/10-funnel-setup.md)"
