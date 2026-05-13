#!/bin/bash
# 01-system-prep — apt baseline + timezone + locale + unattended-upgrades
# Called from 00-bootstrap.sh after config loaded.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-server-setup.conf"

# Hostname
echo "$HOSTNAME" > /etc/hostname
hostnamectl set-hostname "$HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts || \
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts

# Timezone
if [ -n "${TZ:-}" ]; then
    timedatectl set-timezone "$TZ" || true
fi

# Locale
if [ -n "${LOCALE:-}" ]; then
    locale-gen "$LOCALE" 2>/dev/null || true
    update-locale LANG="$LOCALE" LC_ALL="$LOCALE" || true
fi

# Admin user
if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
    # No password — key-only login
    passwd -l "$ADMIN_USER"  # lock password (key-only)
fi

# Apt baseline
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get -y install \
    curl wget ca-certificates gnupg \
    git tmux htop \
    jq net-tools dnsutils iputils-ping mtr-tiny \
    iptables nftables \
    fail2ban ufw \
    unattended-upgrades \
    python3 python3-pip \
    || true

# unattended-upgrades
if [ "${ENABLE_UNATTENDED_UPGRADES:-true}" = "true" ]; then
    dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || \
        echo 'APT::Periodic::Update-Package-Lists "1"; APT::Periodic::Unattended-Upgrade "1";' \
            > /etc/apt/apt.conf.d/20auto-upgrades
fi

# SSH key for admin user
mkdir -p /home/$ADMIN_USER/.ssh
chmod 700 /home/$ADMIN_USER/.ssh

if [ -n "${ADMIN_SSH_PUBKEY_SOURCE:-}" ]; then
    case "$ADMIN_SSH_PUBKEY_SOURCE" in
        github:*)
            USER_GH="${ADMIN_SSH_PUBKEY_SOURCE#github:}"
            curl -fsSL "https://github.com/${USER_GH}.keys" -o /home/$ADMIN_USER/.ssh/authorized_keys.new
            ;;
        file:*)
            cp "${ADMIN_SSH_PUBKEY_SOURCE#file:}" /home/$ADMIN_USER/.ssh/authorized_keys.new
            ;;
        *)
            echo "WARN: Unknown ADMIN_SSH_PUBKEY_SOURCE format: $ADMIN_SSH_PUBKEY_SOURCE"
            ;;
    esac
    if [ -s /home/$ADMIN_USER/.ssh/authorized_keys.new ]; then
        cat /home/$ADMIN_USER/.ssh/authorized_keys.new >> /home/$ADMIN_USER/.ssh/authorized_keys
        # Dedupe
        sort -u /home/$ADMIN_USER/.ssh/authorized_keys > /home/$ADMIN_USER/.ssh/authorized_keys.dedup
        mv /home/$ADMIN_USER/.ssh/authorized_keys.dedup /home/$ADMIN_USER/.ssh/authorized_keys
        rm /home/$ADMIN_USER/.ssh/authorized_keys.new
    fi
fi
chown -R "$ADMIN_USER:$ADMIN_USER" /home/$ADMIN_USER/.ssh
chmod 600 /home/$ADMIN_USER/.ssh/authorized_keys 2>/dev/null || true

# Sudoers — passwordless for admin (key-only access predicate)
echo "$ADMIN_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-$ADMIN_USER
chmod 440 /etc/sudoers.d/90-$ADMIN_USER

echo "[01] system prep done"
