#!/bin/bash
# 07-cascade-browser-run — start cascade-browser MCP server (nohup pattern для WSL1)
# В WSL2 предпочтительнее systemd-user; в WSL1 — nohup в background.

set -euo pipefail

cd ~/projects/cascade-browser/mcp-server

# Kill старый instance если был
pkill -f "python3 src/server.py" 2>/dev/null || true
sleep 1

LOG=/tmp/cascade-browser.log
nohup ./run-server.sh > "$LOG" 2>&1 &
SERVER_PID=$!
disown
echo "[07] Started cascade-browser server PID=$SERVER_PID, log=$LOG"

# Wait + verify
sleep 5
if ! ss -tln 2>/dev/null | grep -q ":8767"; then
    if pgrep -f "python3 src/server.py" >/dev/null; then
        echo "[07] Server running (PID $(pgrep -f 'python3 src/server.py'))"
    else
        echo "[07] WARN: server may have failed. Check log:"
        tail -20 "$LOG"
        exit 1
    fi
fi

# Quick local test
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8767/mcp \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke","version":"0.1"}}}')

if [ "$CODE" = "200" ]; then
    echo "[07] Smoke test PASS: HTTP $CODE on initialize"
else
    echo "[07] WARN: smoke test returned HTTP $CODE (expected 200)"
fi

echo "[07] cascade-browser running. To stop: pkill -f 'python3 src/server.py'"
