#!/bin/bash
# 12-add-beelink-connection — добавить connection к Beelink в Guacamole DB
#
# Это создаёт RDP connection через SQL insert в Guacamole postgres.
# Юзер сможет открыть https://krom7.ru, login, и сразу увидит "Beelink" в списке.
#
# Beelink должен:
#   1. Иметь Tailscale установлен (см. INSTALL.md Step 5)
#   2. Иметь RDP enabled (Windows: Settings → Remote Desktop ON)
#   3. Tailscale-IP резолвиться через MagicDNS как $BEELINK_TAILSCALE_HOST

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"

# Resolve Beelink IP
if [ -n "${BEELINK_TAILSCALE_IP:-}" ]; then
    TARGET="$BEELINK_TAILSCALE_IP"
elif [ -n "${BEELINK_TAILSCALE_HOST:-}" ]; then
    TARGET=$(tailscale status | grep -E "^[0-9.]+\s+$BEELINK_TAILSCALE_HOST\s" | awk '{print $1}' | head -1)
    if [ -z "$TARGET" ]; then
        echo "[12] WARN: $BEELINK_TAILSCALE_HOST not found в tailscale status."
        echo "[12] Beelink либо offline либо не в tailnet."
        echo "[12] Skipping connection insert. Add manually позже через Guacamole UI."
        exit 0
    fi
fi

if [ -z "${TARGET:-}" ]; then
    echo "[12] No target host/IP configured — skipping"
    exit 0
fi

CONNECTION_NAME="Beelink-Pattaya"
PROTO="${BEELINK_PROTOCOL:-rdp}"
PORT="${BEELINK_PORT:-3389}"
USERNAME="${BEELINK_USERNAME:-krom0}"

echo "[12] Adding Guacamole connection: $CONNECTION_NAME ($PROTO://$TARGET:$PORT)"

# SQL для insert через docker exec
SQL=$(cat <<SQL
DO \$\$
DECLARE
    conn_id INT;
BEGIN
    -- Skip if already exists
    SELECT connection_id INTO conn_id FROM guacamole_connection
    WHERE connection_name = '$CONNECTION_NAME' LIMIT 1;

    IF conn_id IS NULL THEN
        -- Create connection
        INSERT INTO guacamole_connection (connection_name, protocol)
        VALUES ('$CONNECTION_NAME', '$PROTO')
        RETURNING connection_id INTO conn_id;

        -- Add parameters
        INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
            (conn_id, 'hostname', '$TARGET'),
            (conn_id, 'port', '$PORT'),
            (conn_id, 'username', '$USERNAME'),
            (conn_id, 'ignore-cert', 'true'),
            (conn_id, 'security', 'any'),
            (conn_id, 'resize-method', 'display-update'),
            (conn_id, 'enable-drive', 'true'),
            (conn_id, 'create-drive-path', 'true'),
            (conn_id, 'drive-path', '/mnt/guacdrive');

        -- Grant access to admin
        INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
        SELECT entity_id, conn_id, perm::guacamole_object_permission_type
        FROM guacamole_entity, unnest(ARRAY['READ', 'UPDATE', 'DELETE', 'ADMINISTER']) AS perm
        WHERE name = '${GUACAMOLE_ADMIN_USER:-guacadmin}' AND type = 'USER';

        RAISE NOTICE 'Created connection % (id=%)', '$CONNECTION_NAME', conn_id;
    ELSE
        RAISE NOTICE 'Connection already exists: id=%', conn_id;
    END IF;
END \$\$;
SQL
)

docker exec -i guac-postgres psql -U guacamole_user -d guacamole_db <<<"$SQL"

echo "[12] Connection $CONNECTION_NAME added. Open https://$DOMAIN to access."
