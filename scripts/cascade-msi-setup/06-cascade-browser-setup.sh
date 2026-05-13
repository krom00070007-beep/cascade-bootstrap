#!/bin/bash
# 06-cascade-browser-setup — venv, requirements, pytest, bearer token

set -euo pipefail

if [ -f ~/.cascade-msi-setup/conf ]; then source ~/.cascade-msi-setup/conf; fi

cd ~/projects/cascade-browser/mcp-server

echo "[06] Ensure python3.12-venv installed..."
if ! python3 -c "import ensurepip" 2>/dev/null; then
    sudo apt install -y python3.12-venv
fi

echo "[06] Creating venv..."
if [ ! -d .venv ] || [ ! -x .venv/bin/pip ]; then
    rm -rf .venv
    python3 -m venv .venv
fi
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt
[ -f requirements-dev.txt ] && .venv/bin/pip install -q -r requirements-dev.txt
.venv/bin/python -c "import mcp; from importlib.metadata import version; print('mcp', version('mcp'))"

echo "[06] Running pytest..."
if ! .venv/bin/python -m pytest tests/ -q; then
    echo "FATAL: pytest failed. Check dependencies."
    exit 1
fi

echo "[06] Bearer token..."
mkdir -p ~/.cascade-browser
chmod 700 ~/.cascade-browser
if [ -n "${CASCADE_BEARER_TOKEN:-}" ]; then
    echo "$CASCADE_BEARER_TOKEN" > ~/.cascade-browser/bearer.txt
    chmod 600 ~/.cascade-browser/bearer.txt
    echo "[06] Using pre-configured Bearer (from config)"
elif [ -s ~/.cascade-browser/bearer.txt ]; then
    echo "[06] Bearer token already exists — leaving alone"
else
    .venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))' > ~/.cascade-browser/bearer.txt
    chmod 600 ~/.cascade-browser/bearer.txt
    echo "[06] Generated new Bearer token"
fi

# Show preview (для logs)
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
echo "[06] Token preview: ${TOKEN:0:6}...${TOKEN: -4} (len=${#TOKEN})"
echo ""
echo "[06] **IMPORTANT:** Backup token в Telegram Saved:"
echo "     tg-send-text \"cascade-browser MSI Bearer (issued \$(date +%Y-%m-%d)): \$(cat ~/.cascade-browser/bearer.txt)\""
echo "     (если tg-send-text installed — иначе скопируй вручную)"
