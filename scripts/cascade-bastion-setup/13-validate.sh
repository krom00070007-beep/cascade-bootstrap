#!/bin/bash
# 13-validate — E2E checks для bastion deployment

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"

PASS=0
FAIL=0
FAILS=()

check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  \033[32m✓\033[0m %s\n" "$name"
        PASS=$((PASS+1))
    else
        printf "  \033[31m✗\033[0m %s\n" "$name"
        FAIL=$((FAIL+1))
        FAILS+=("$name")
    fi
}

echo "==== cascade-bastion-setup validation ===="

check "nginx active" systemctl is-active nginx
check "docker active" systemctl is-active docker
check "Guacamole container healthy" bash -c 'docker ps --filter name=guacamole --format "{{.Status}}" | grep -q Up'
check "guacd container healthy" bash -c 'docker ps --filter name=guacd --format "{{.Status}}" | grep -q Up'
check "postgres container healthy" bash -c 'docker ps --filter name=guac-postgres --format "{{.Status}}" | grep -q Up'
check "Guacamole port 8080 listening" bash -c 'ss -tln | grep -q ":8080"'
check "nginx 443 listening (SSL)" bash -c 'ss -tln | grep -q ":443"'
check "Let'\''s Encrypt cert exists" bash -c "test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
check "tailscale joined" bash -c 'tailscale ip -4 | grep -qE "^100\."'
check "Tailscale RunSSH=false" bash -c 'tailscale debug prefs | grep RunSSH | grep -q false'
check "ufw active" systemctl is-active ufw
check "fail2ban active" systemctl is-active fail2ban

# HTTPS check from outside (via curl with -k since we'd be testing via Tailnet/loopback)
HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$DOMAIN/" || echo 0)
check "https://$DOMAIN returns 200/302" bash -c "[ \"$HTTPS_CODE\" = \"200\" ] || [ \"$HTTPS_CODE\" = \"302\" ]"

echo ""
echo "==== RESULT: $PASS passed / $FAIL failed ===="
if [ "$FAIL" -gt 0 ]; then
    echo "Failed:"
    printf "  - %s\n" "${FAILS[@]}"
fi
