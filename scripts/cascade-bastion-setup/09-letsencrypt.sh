#!/bin/bash
# 09-letsencrypt — certbot + Let's Encrypt SSL for $DOMAIN
# Then rewrite nginx site config с full reverse proxy + SSL

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"

# certbot install
apt install -y certbot python3-certbot-nginx

# Verify DNS points to us
EXPECTED_IP=$(curl -s ifconfig.me 2>/dev/null)
DNS_IP=$(dig +short $DOMAIN | head -1)
if [ "$EXPECTED_IP" != "$DNS_IP" ]; then
    echo "WARN: DNS mismatch for $DOMAIN"
    echo "  Public IP (нашего сервера): $EXPECTED_IP"
    echo "  $DOMAIN A record: $DNS_IP"
    echo "  Let's Encrypt cert request likely fail. Verify DNS A record + propagation."
    echo "  Continuing — Let's Encrypt itself даст clear error если DNS не там."
fi

# Issue cert
echo "[09] Requesting Let's Encrypt cert for $DOMAIN..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL:-admin@$DOMAIN}" --redirect

# Verify
systemctl status nginx --no-pager | head -5

# Auto-renew (certbot installs systemd timer)
systemctl status certbot.timer --no-pager 2>&1 | head -3

echo "[09] Let's Encrypt cert installed. Auto-renewal via certbot.timer."
