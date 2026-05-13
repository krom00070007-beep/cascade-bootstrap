#!/bin/bash
# 08-nginx-install — nginx + base config + reverse proxy to Guacamole
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"

apt install -y nginx
systemctl enable --now nginx

# Initial site config (HTTP only — для Let's Encrypt challenge)
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # ACME challenge for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Temporary redirect — will be replaced by certbot
    location / {
        return 200 "cascade-bastion: $DOMAIN bootstrapping...\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
rm -f /etc/nginx/sites-enabled/default

# Test + reload
nginx -t
systemctl reload nginx

echo "[08] nginx installed, base config at /etc/nginx/sites-enabled/$DOMAIN"
