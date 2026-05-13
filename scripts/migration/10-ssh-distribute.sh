#!/bin/bash
# MIG-001 T11 — Distribute SER10 pubkey to ALLOWED Cascade nodes only.
#
# Run inside WSL on SER10 as usersstas, after T4 (key generated).
#
# Loads ~/.ssh/id_ed25519.pub onto each ALLOWED node via ssh-copy-id (will
# prompt for password the first time per node).
#
# CRITICAL — FORBIDDEN nodes that this script MUST NEVER touch:
#   - gl-mt6000-1 (100.109.97.16)   — home router; family loses internet if it errors
#   - gl-mt6000 Thai (100.76.55.53) — recovery node; ANY change can brick it
#   - glkvm (100.76.24.102)         — emergency access; must stay independent
#   - beget-cascade-in/out          — container SSH refused; not ours to manage
#
# These are absent from ALLOWED_NODES by design. Do not add them.

set -euo pipefail
LOG=/tmp/mig-001-10-ssh-distribute.log
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date -Iseconds) MIG-001 T11 ssh-distribute start ===="

PUB=~/.ssh/id_ed25519.pub
if [ ! -f "$PUB" ]; then
    echo "FATAL: $PUB not found. Run T4 (03-wsl-base.sh) first."
    exit 1
fi

# Each entry: "label|user@host" — must reach via tailnet IP (not public).
ALLOWED_NODES=(
    "opus-cwr-bkk|root@100.70.212.16"
    "bkk-exit|root@100.125.240.18"
    "vultr-amsterdam|root@100.78.149.108"
    "stockholm|root@100.70.187.116"
    "msk-vps|root@100.103.182.81"
    # Add more as they come back online; russia-vps-exit / timeweb-spb are
    # commented out until their roles are re-confirmed:
    # "russia-vps-exit|root@..."
    # "timeweb-spb|root@..."
)

# MSI is handled specially (user account, not root)
MSI_LABEL="msi-cowork"
MSI_TARGET="usersstas@100.117.0.35"

# --- Run per node ---
declare -i OK=0 FAIL=0
for entry in "${ALLOWED_NODES[@]}"; do
    label="${entry%%|*}"
    target="${entry##*|}"
    echo ""
    echo "==== distributing → $label ($target) ===="
    if ssh-copy-id -i "$PUB" -o PasswordAuthentication=yes -o StrictHostKeyChecking=accept-new "$target"; then
        OK=$((OK+1))
        # Verify by trying a no-op login
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" 'echo ok' >/dev/null 2>&1; then
            echo "   verify: passwordless login works"
        else
            echo "   verify: passwordless login FAILED (key copy may have appended but file is wrong)"
        fi
    else
        FAIL=$((FAIL+1))
        echo "   FAILED (ssh-copy-id refused — check tailnet/SSH on this node)"
    fi
done

# --- MSI ---
echo ""
echo "==== distributing → $MSI_LABEL ($MSI_TARGET) ===="
echo "  Approach: scp pubkey to MSI as a temp file, then append remotely (avoids ssh-copy-id quirks across user accounts)."
if scp "$PUB" "$MSI_TARGET:~/.ssh/ser10-pubkey.tmp" 2>&1; then
    if ssh "$MSI_TARGET" 'mkdir -p ~/.ssh && cat ~/.ssh/ser10-pubkey.tmp >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm ~/.ssh/ser10-pubkey.tmp'; then
        echo "   appended to ~/.ssh/authorized_keys on MSI"
        OK=$((OK+1))
    else
        echo "   append step FAILED"
        FAIL=$((FAIL+1))
    fi
else
    echo "   scp FAILED"
    FAIL=$((FAIL+1))
fi

echo ""
echo "==== T11 done: $OK ok / $FAIL failed ===="
if [ "$FAIL" -gt 0 ]; then
    echo "Re-run for failed nodes individually after fixing the cause."
fi
echo "Next: T12 (11-state-init.sh)"
