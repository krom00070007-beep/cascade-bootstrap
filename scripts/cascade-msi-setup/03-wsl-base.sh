#!/bin/bash
# 03-wsl-base — apt baseline + SSH key + ~/.ssh/config peers
# Runs inside WSL Ubuntu-24.04 as $WSL_USER.

set -euo pipefail

# Load config copied by parent ps1
if [ -f ~/.cascade-msi-setup/conf ]; then
    source ~/.cascade-msi-setup/conf
fi

echo "[03] apt baseline..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y \
    git curl wget ca-certificates build-essential \
    python3 python3-venv python3-pip python3-full python3.12-venv \
    jq net-tools dnsutils iputils-ping mtr-tiny \
    tmux htop \
    openssh-client \
    keychain

# Time sync (hwclock не работает в WSL обычно — ok)
sudo hwclock -s 2>/dev/null || true

echo "[03] SSH key..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh

case "${SSH_KEY_STRATEGY:-generate}" in
    generate)
        if [ ! -f ~/.ssh/id_ed25519 ]; then
            ssh-keygen -t ed25519 -C "${SSH_KEY_COMMENT:-cowork-msi-wsl2-$(date +%Y%m%d)}" \
                -f ~/.ssh/id_ed25519 -N ""
            echo "[03] Generated new ed25519 keypair."
        else
            echo "[03] ~/.ssh/id_ed25519 already exists — leaving alone."
        fi
        ;;
    import:*)
        IMPORT_PATH="${SSH_KEY_STRATEGY#import:}"
        if [ -f "$IMPORT_PATH" ]; then
            cp "$IMPORT_PATH" ~/.ssh/id_ed25519
            ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub
            chmod 600 ~/.ssh/id_ed25519
            chmod 644 ~/.ssh/id_ed25519.pub
        else
            echo "[03] ERROR: import path $IMPORT_PATH not found"; exit 1
        fi
        ;;
esac

chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

echo ""
echo "=== SSH pubkey (для распространения на peers): ==="
cat ~/.ssh/id_ed25519.pub
echo ""

# ~/.ssh/config baseline
cat > ~/.ssh/config <<'CFG'
# MSI baseline. Edit IPs if tailnet renumbers.

Host opus-cwr-bkk
    Hostname 100.70.212.16
    User root

Host bkk-exit
    Hostname 100.125.240.18
    User root

Host vultr-amsterdam
    Hostname 100.78.149.108
    User root

Host msk-vps-bridge
    Hostname 100.103.182.81
    User root

Host msi
    Hostname 100.117.0.35
    User usersstas
CFG
chmod 600 ~/.ssh/config

# Git config
git config --global user.email "${GIT_USER_EMAIL:-krom00070007@gmail.com}"
git config --global user.name "${GIT_USER_NAME:-krom00070007-beep}"
git config --global init.defaultBranch main
git config --global pull.rebase true

echo "[03] WSL base done"
