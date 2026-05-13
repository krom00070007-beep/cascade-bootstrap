#!/bin/bash
# MIG-001 T17 — Final E2E validation on SER10. Run AFTER T9 (systemd) + T10 (Funnel).
#
# Each check is a small bash one-liner; failures print but don't abort, so you
# see the full picture at the end.

set -uo pipefail
PASS=0; FAIL=0
FAIL_LIST=()

check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  \033[32m✓\033[0m %s\n" "$name"
        PASS=$((PASS+1))
    else
        printf "  \033[31m✗\033[0m %s\n" "$name"
        FAIL=$((FAIL+1))
        FAIL_LIST+=("$name")
    fi
}

echo "==== MIG-001 T17 validation start ($(date -Iseconds)) ===="
echo ""

check "claude --version (Claude Code on PATH)"            claude --version
check "claude reports 2.1.140 (pinned)"                   bash -c 'claude --version | grep -q "2\.1\.140"'
check "tailscale online + has tailnet IP"                 bash -c 'tailscale.exe status 2>/dev/null | grep -qE "^100\.[0-9]+\.[0-9]+\.[0-9]+"'
check "cascade-browser.service is active"                 systemctl is-active cascade-browser.service
check "port 8767 (MCP HTTP) listening"                    bash -c 'ss -tlnp 2>/dev/null | grep -q ":8767 "'
check "port 8768 (TCP bridge) listening"                  bash -c 'ss -tlnp 2>/dev/null | grep -q ":8768 "'
check "Bearer middleware: 401 without header"             bash -c '[ "$(curl -s -o /dev/null -w %{http_code} -X POST http://127.0.0.1:8767/mcp -H "Content-Type: application/json" -d {})" = "401" ]'
check "Bearer middleware: !=401 with valid Bearer"        bash -c 'TOKEN=$(cat ~/.cascade-browser/bearer.txt); code=$(curl -s -o /dev/null -w %{http_code} -X POST http://127.0.0.1:8767/mcp -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "Authorization: Bearer $TOKEN" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"v\",\"version\":\"0\"}}}"); [ "$code" != "401" ]'
check "Funnel returns 401 without Bearer"                 bash -c '[ "$(curl -sk -o /dev/null -w %{http_code} -X POST https://ser10-tha-1.tail80c5d4.ts.net/mcp -H "Content-Type: application/json" -d {})" = "401" ]'
check "Funnel reachable with valid Bearer (initialize)"   bash -c 'TOKEN=$(cat ~/.cascade-browser/bearer.txt); code=$(curl -sk -o /dev/null -w %{http_code} -X POST https://ser10-tha-1.tail80c5d4.ts.net/mcp -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "Authorization: Bearer $TOKEN" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"v\",\"version\":\"0\"}}}"); [ "$code" = "200" ]'
check "cascade-state pull works (SSH key fine)"           bash -c 'cd ~/projects/cascade-state && git pull --rebase --quiet'
check "cascade-state-push wrapper on PATH"                bash -c 'command -v cascade-state-push >/dev/null'
check "ollama installed (T16 done)"                       ollama --version
check "ssh-agent ~/.ssh/id_ed25519 present"               test -f "$HOME/.ssh/id_ed25519"
check "SER10 pubkey accepted by opus-cwr-bkk"             bash -c 'ssh -o BatchMode=yes -o ConnectTimeout=5 opus-cwr-bkk "echo ok"'
check "SER10 pubkey accepted by msi-cowork"               bash -c 'ssh -o BatchMode=yes -o ConnectTimeout=5 msi-cowork "echo ok"'

echo ""
echo "==== RESULT: $PASS passed / $FAIL failed ===="
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 SER10 Pattaya-1 deployment SUCCESS"
    exit 0
else
    echo "Failed checks:"
    printf "  - %s\n" "${FAIL_LIST[@]}"
    echo ""
    echo "Inspect:"
    echo "  systemctl status cascade-browser.service"
    echo "  journalctl -u cascade-browser -n 100 --no-pager"
    echo "  tailscale.exe status"
    echo "  tailscale.exe funnel status"
    exit 1
fi
