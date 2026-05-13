#!/bin/bash
# 11-validate — final E2E health check для MSI deployment

set -uo pipefail
PASS=0
FAIL=0
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

echo "==== cascade-msi-setup validation start ($(date -Iseconds)) ===="
echo ""

# Claude Code
check "claude --version (in PATH)" claude --version

# Tailscale (Win-side)
check "tailscale.exe reachable" bash -c 'cmd.exe /c "tailscale.exe --version" 2>&1 | grep -qE "^[0-9]"'
check "tailscale online + has IP" bash -c 'cmd.exe /c "tailscale.exe status" 2>&1 | grep -qE "^100\.[0-9]+\.[0-9]+\.[0-9]+"'

# Funnel
check "Tailscale Funnel active" bash -c 'cmd.exe /c "tailscale.exe funnel status" 2>&1 | grep -q "Funnel on"'

# cascade-browser
check "cascade-browser :8767 listening" bash -c 'ss -tln 2>/dev/null | grep -q ":8767"'
check "cascade-browser :8768 listening" bash -c 'ss -tln 2>/dev/null | grep -q ":8768"'

TOKEN=$(cat ~/.cascade-browser/bearer.txt 2>/dev/null)
check "Bearer 401 without auth" bash -c "[ \"\$(curl -s -o /dev/null -w %{http_code} -X POST http://127.0.0.1:8767/mcp -H 'Content-Type: application/json' -d {} 2>&1)\" = \"401\" ]"
check "Bearer 200 on initialize" bash -c "[ \"\$(curl -s -o /dev/null -w %{http_code} -X POST http://127.0.0.1:8767/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -H 'Authorization: Bearer $TOKEN' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"v\",\"version\":\"0\"}}}')\" = \"200\" ]"

# cascade-state mirror
check "cascade-state pull works (SSH key)" bash -c 'cd ~/projects/cascade-state && git pull --rebase --quiet'

# Skills
SKILL_COUNT=$(ls ~/.claude/skills/cascade-* 2>/dev/null | wc -l)
check "cascade-* skills symlinked (count > 5)" bash -c "[ $SKILL_COUNT -gt 5 ]"

# cascade-doctor
check "cascade-doctor in PATH" command -v cascade-doctor

echo ""
echo "==== RESULT: $PASS passed / $FAIL failed ===="
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 cascade-msi-setup deployment SUCCESS"
    exit 0
else
    echo "Failed:"
    printf "  - %s\n" "${FAIL_LIST[@]}"
    exit 1
fi
