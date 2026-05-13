#!/bin/bash
# MIG-001 T4 — WSL base setup on SER10 (run inside WSL Ubuntu-24.04 as usersstas).
#
# Prerequisites:
#   - T2 + T3 completed (Ubuntu installed, usersstas created)
#   - You are running this script INSIDE WSL, NOT PowerShell.
#
# What this does:
#   1. apt baseline (git, curl, build tools, python venv/pip, jq, node, tmux, htop, ssh)
#   2. Time sync from hardware clock
#   3. Generate ed25519 SSH keypair (cowork-ser10-tha-1-wsl2-YYYYMMDD) if absent
#   4. ~/.ssh/config with peer hostnames (opus-cwr-bkk, bkk-exit, msi-cowork, ...)
#
# Logs to /tmp/mig-001-03-wsl-base.log (and stdout).

set -euo pipefail
LOG=/tmp/mig-001-03-wsl-base.log
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date -Iseconds) MIG-001 T4 wsl-base start ===="

# --- 4.1 Apt baseline ---
echo "[1/4] apt update + upgrade + baseline tools..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y \
    git curl wget ca-certificates \
    build-essential \
    python3 python3-venv python3-pip python3-full \
    jq net-tools dnsutils tmux htop \
    openssh-client

# Node (used by cascade-browser dev tooling)
if ! command -v node >/dev/null; then
    sudo apt install -y nodejs npm
fi

# --- 4.2 Time sync (WSL2 sometimes drifts when host sleeps) ---
echo "[2/4] hwclock sync (best-effort)..."
sudo hwclock -s 2>/dev/null || echo "  (hwclock unavailable in WSL2 — skipping)"

# --- 4.3 SSH key generation (T1.3 = new keypair on SER10) ---
echo "[3/4] SSH keypair..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 \
        -C "cowork-ser10-tha-1-wsl2-$(date +%Y%m%d)" \
        -f ~/.ssh/id_ed25519 \
        -N ""
    echo "  Generated new ed25519 keypair."
else
    echo "  ~/.ssh/id_ed25519 already exists — leaving alone."
fi
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
echo ""
echo "=== SSH PUBKEY for distribution (T11) ==="
cat ~/.ssh/id_ed25519.pub
echo "=== Copy this — added to authorized_keys of 7 nodes in T11 ==="
echo ""

# --- 4.4 SSH config baseline ---
echo "[4/4] ~/.ssh/config..."
cat > ~/.ssh/config <<'CFG'
# MIG-001 SER10 baseline. Edit IPs if tailnet renumbers.

Host opus-cwr-bkk
    Hostname 100.70.212.16
    User root

Host bkk-exit
    Hostname 100.125.240.18
    User root

Host vultr-amsterdam
    Hostname 100.78.149.108
    User root

Host stockholm
    Hostname 100.70.187.116
    User root

Host msk-vps
    Hostname 100.103.182.81
    User root

Host msi-cowork
    Hostname 100.117.0.35
    User usersstas
CFG
chmod 600 ~/.ssh/config

echo ""
echo "==== T4 done — proceed to T5 (04-claude-code.sh) ===="
echo "Run: bash ~/projects/cascade-state/scripts/migration/04-claude-code.sh"
echo "     (after T7 clones repos; or run-time you can copy this single .sh first)"
