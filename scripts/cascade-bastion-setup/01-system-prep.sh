#!/bin/bash
# 01-system-prep — apt + hostname + admin user + unattended-upgrades

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-bastion-setup.conf"

echo "$HOSTNAME" > /etc/hostname
hostnamectl set-hostname "$HOSTNAME"

timedatectl set-timezone "${TZ:-UTC}" || true

export DEBIAN_FRONTEND=noninteractive
apt update -y
apt upgrade -y
apt install -y \
    curl wget ca-certificates gnupg lsb-release \
    git tmux htop jq net-tools dnsutils iputils-ping \
    iptables nftables fail2ban ufw \
    unattended-upgrades \
    python3 python3-pip \
    openssh-client

# Admin user
if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
    passwd -l "$ADMIN_USER"
fi

# SSH key for admin
mkdir -p /home/$ADMIN_USER/.ssh
chmod 700 /home/$ADMIN_USER/.ssh
if [ -n "${ADMIN_SSH_PUBKEY_SOURCE:-}" ]; then
    case "$ADMIN_SSH_PUBKEY_SOURCE" in
        github:*)
            curl -fsSL "https://github.com/${ADMIN_SSH_PUBKEY_SOURCE#github:}.keys" \
                -o /home/$ADMIN_USER/.ssh/authorized_keys
            ;;
    esac
fi
chown -R $ADMIN_USER:$ADMIN_USER /home/$ADMIN_USER/.ssh
chmod 600 /home/$ADMIN_USER/.ssh/authorized_keys 2>/dev/null || true

# Sudoers passwordless
echo "$ADMIN_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-$ADMIN_USER
chmod 440 /etc/sudoers.d/90-$ADMIN_USER

# unattended-upgrades
echo 'APT::Periodic::Update-Package-Lists "1"; APT::Periodic::Unattended-Upgrade "1";' \
    > /etc/apt/apt.conf.d/20auto-upgrades

echo "[01] system prep done"
