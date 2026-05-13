#!/bin/bash
# MIG-001 T8 — Bootstrap cascade-browser MCP server stack on SER10.
#
# Run inside WSL as usersstas, after T7 cloned the repo.
#
# What this does:
#   1. Install python3.12-venv (apt) — required by run-server.sh on Ubuntu 24.04
#   2. python -m venv .venv + install requirements.txt + requirements-dev.txt
#   3. Run pytest tests/ — must show 59/59 green (10 auth + 49 nav tools as of BR-105)
#   4. Generate fresh Bearer token at ~/.cascade-browser/bearer.txt (chmod 600).
#      DO NOT copy MSI's token — different Funnel hostname → different token.
#
# Logs to /tmp/mig-001-07-cascade-browser-setup.log.

set -euo pipefail
LOG=/tmp/mig-001-07-cascade-browser-setup.log
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date -Iseconds) MIG-001 T8 cascade-browser-setup start ===="

cd ~/projects/cascade-browser/mcp-server

# --- 8.1 Ensure python3.12-venv (pip + ensurepip both need it) ---
if ! python3 -c "import ensurepip" 2>/dev/null; then
    echo "[1/4] Installing python3.12-venv..."
    sudo apt update -y
    sudo apt install -y python3.12-venv
else
    echo "[1/4] python3.12-venv already available."
fi

# --- 8.2 venv + deps ---
echo "[2/4] Creating venv and installing requirements..."
if [ ! -d .venv ] || [ ! -x .venv/bin/pip ]; then
    rm -rf .venv
    python3 -m venv .venv
fi
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt
if [ -f requirements-dev.txt ]; then
    .venv/bin/pip install -q -r requirements-dev.txt
fi
.venv/bin/python -c "import mcp; from importlib.metadata import version; print('mcp', version('mcp'))"

# --- 8.3 pytest ---
echo "[3/4] Running pytest..."
if ! .venv/bin/python -m pytest tests/ -q; then
    echo "FATAL: pytest failed. Likely causes:"
    echo "  - Python version mismatch (we expect 3.12)"
    echo "  - missing dev deps (re-check requirements-dev.txt)"
    echo "  - WSL2 networking issue on TestClient"
    exit 1
fi

# --- 8.4 Bearer token (NEW, do NOT copy MSI's) ---
echo "[4/4] Bearer token..."
mkdir -p ~/.cascade-browser
chmod 700 ~/.cascade-browser
if [ ! -s ~/.cascade-browser/bearer.txt ]; then
    .venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))' > ~/.cascade-browser/bearer.txt
    chmod 600 ~/.cascade-browser/bearer.txt
    echo "  Generated new Bearer token ($(wc -c <~/.cascade-browser/bearer.txt) bytes)."
else
    echo "  ~/.cascade-browser/bearer.txt already exists — leaving alone."
fi

# Show token start/end for sanity (NOT full value)
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
echo "  Token preview: ${TOKEN:0:6}...${TOKEN: -4} (len=${#TOKEN})"
echo ""
echo "  COPY this token (full) somewhere safe — Telegram Saved Messages is the conventional spot:"
echo "    tg-send-text \"cascade-browser SER10 Bearer (issued \$(date +%Y-%m-%d)): \$(cat ~/.cascade-browser/bearer.txt)\""

echo ""
echo "==== T8 done ===="
echo "Next: T9 (install systemd unit cascade-browser.service — see configs/systemd/cascade-browser.service)"
