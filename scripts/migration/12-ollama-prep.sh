#!/bin/bash
# MIG-001 T16 — Install Ollama on SER10. Pull only a SMALL model for smoke test.
# Big models (70B class, ~45 GB RAM) wait until T15 RAM upgrade (28.05).
#
# Logs to /tmp/mig-001-12-ollama-prep.log.

set -euo pipefail
LOG=/tmp/mig-001-12-ollama-prep.log
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date -Iseconds) MIG-001 T16 ollama-prep start ===="

# --- 1. Install ---
if ! command -v ollama >/dev/null; then
    echo "[1/3] Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "[1/3] Ollama already installed: $(ollama --version)"
fi

# --- 2. Service ---
echo "[2/3] systemctl status ollama..."
if systemctl --quiet is-active ollama; then
    echo "  ollama.service active"
else
    sudo systemctl enable --now ollama
    sleep 2
    sudo systemctl status ollama --no-pager | head -5
fi

# --- 3. Smoke test with the SMALLEST model — DO NOT pull 70B on 32 GB RAM ---
echo "[3/3] Smoke-test with qwen2.5-coder:1.5b (≈ 1 GB)..."
ollama pull qwen2.5-coder:1.5b
echo ""
echo "Inference test:"
echo "hello, reply with one word" | timeout 60 ollama run qwen2.5-coder:1.5b || \
    echo "  (smoke test timed out or errored — diagnose with 'ollama logs')"

echo ""
echo "==== T16 done — Ollama installed, qwen2.5-coder:1.5b available ===="
echo ""
echo "After T15 RAM upgrade (28.05), pull the big models — examples:"
echo "  ollama pull llama3.3:70b-instruct-q4_K_M   # ~45 GB RAM"
echo "  ollama pull qwen2.5-coder:32b              # ~20 GB RAM"
echo "  ollama pull deepseek-r1:70b                # ~45 GB RAM"
echo "DO NOT pull these on 32 GB stock — system will swap thrash."
