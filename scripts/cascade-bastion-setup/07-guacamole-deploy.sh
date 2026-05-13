#!/bin/bash
# 07-guacamole-deploy — Apache Guacamole stack через docker compose
#
# 3 services:
#   - guacd (Guacamole daemon — handles RDP/VNC/SSH protocols)
#   - guacamole (web UI + servlet container) — listens on 8080
#   - postgres (DB для users + connections)
#
# Compose file: /opt/guacamole/docker-compose.yml

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"

GUAC_DIR=/opt/guacamole
mkdir -p $GUAC_DIR/init

# Compose file
cat > $GUAC_DIR/docker-compose.yml <<COMPOSE
services:
  guacd:
    image: guacamole/guacd:1.5.4
    container_name: guacd
    restart: unless-stopped
    networks:
      - guacnet

  postgres:
    image: postgres:16
    container_name: guac-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: guacamole_db
      POSTGRES_USER: guacamole_user
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
      - ./init:/docker-entrypoint-initdb.d
    networks:
      - guacnet

  guacamole:
    image: guacamole/guacamole:1.5.4
    container_name: guacamole
    restart: unless-stopped
    depends_on:
      - guacd
      - postgres
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      GUACD_HOSTNAME: guacd
      POSTGRES_HOSTNAME: postgres
      POSTGRES_DATABASE: guacamole_db
      POSTGRES_USER: guacamole_user
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    networks:
      - guacnet

networks:
  guacnet:
COMPOSE

# Generate Guacamole DB schema
docker run --rm guacamole/guacamole:1.5.4 /opt/guacamole/bin/initdb.sh --postgresql > $GUAC_DIR/init/initdb.sql

# Bootstrap stack
cd $GUAC_DIR
docker compose pull
docker compose up -d

# Wait for guacamole to be ready
echo "[07] waiting Guacamole to start..."
for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -sf http://127.0.0.1:8080/guacamole/ >/dev/null 2>&1; then
        echo "[07] Guacamole ready on http://127.0.0.1:8080/guacamole/"
        break
    fi
    sleep 5
done

# Change default password if set in config
# (Default guacadmin/guacadmin — change via web UI after first login)
echo "[07] Guacamole deployed. Default login: ${GUACAMOLE_ADMIN_USER}/${GUACAMOLE_ADMIN_PASS}"
echo "[07] ⚠️ Change password ASAP в Settings → Preferences"
