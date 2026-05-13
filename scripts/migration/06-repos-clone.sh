#!/bin/bash
# MIG-001 T7 — Clone cascade-state + cascade-browser, wire post-commit hook,
# symlink cascade-state-push helper, optionally apply MSI's Claude Code settings.
#
# Run inside WSL Ubuntu as usersstas. Requires ssh-agent loaded with the SER10
# id_ed25519 if the repos are private (cascade-state is public; cascade-browser
# is public too as of MIG-001 — adjust the GH URLs if you've made them private).
#
# Prerequisites:
#   - T4 done (ssh keypair generated; git installed)
#   - The SER10 pubkey is registered on github.com under krom00070007-beep
#     (add via https://github.com/settings/keys — paste contents of
#      ~/.ssh/id_ed25519.pub printed at end of T4)
#
# Logs to /tmp/mig-001-06-repos-clone.log.

set -euo pipefail
LOG=/tmp/mig-001-06-repos-clone.log
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date -Iseconds) MIG-001 T7 repos-clone start ===="

REPOS_DIR="$HOME/projects"
mkdir -p "$REPOS_DIR"
cd "$REPOS_DIR"

# --- 7.1 cascade-state ---
if [ ! -d "$REPOS_DIR/cascade-state" ]; then
    echo "[1/4] Cloning cascade-state..."
    git clone git@github.com:krom00070007-beep/cascade-state.git
else
    echo "[1/4] cascade-state already present — git pull..."
    (cd cascade-state && git pull --rebase)
fi

cd "$REPOS_DIR/cascade-state"

# Verify / install post-commit hook (auto-push mirror to opus)
if [ ! -f .git/hooks/post-commit ]; then
    if [ -f configs/git-hooks/post-commit ]; then
        echo "  Installing post-commit hook from configs/git-hooks/..."
        cp configs/git-hooks/post-commit .git/hooks/post-commit
        chmod +x .git/hooks/post-commit
    else
        echo "  WARN: no post-commit hook in repo configs/. Auto-push to opus disabled."
        echo "  Copy from MSI later: scp msi-cowork:~/projects/cascade-state/.git/hooks/post-commit .git/hooks/"
    fi
else
    echo "  post-commit hook present."
fi

# --- 7.2 cascade-browser ---
cd "$REPOS_DIR"
if [ ! -d "$REPOS_DIR/cascade-browser" ]; then
    echo "[2/4] Cloning cascade-browser..."
    git clone git@github.com:krom00070007-beep/cascade-browser.git
else
    echo "[2/4] cascade-browser already present — git pull..."
    (cd cascade-browser && git pull --rebase)
fi

# --- 7.3 Symlink cascade-state-push into ~/bin (if helper lives in repo) ---
echo "[3/4] cascade-state-push symlink..."
mkdir -p ~/bin
if [ -f "$REPOS_DIR/cascade-state/bin/cascade-state-push" ]; then
    chmod +x "$REPOS_DIR/cascade-state/bin/cascade-state-push"
    ln -sf "$REPOS_DIR/cascade-state/bin/cascade-state-push" ~/bin/cascade-state-push
    echo "  Linked ~/bin/cascade-state-push -> $REPOS_DIR/cascade-state/bin/cascade-state-push"
else
    echo "  WARN: $REPOS_DIR/cascade-state/bin/cascade-state-push not found"
    echo "  Copy from MSI: scp msi-cowork:~/bin/cascade-state-push ~/bin/ && chmod +x ~/bin/cascade-state-push"
fi

# --- 7.4 Claude Code SessionStart hook from MSI snapshot ---
echo "[4/4] Claude Code settings.json (optional from MSI backup)..."
mkdir -p ~/.claude
if [ -f "$REPOS_DIR/cascade-state/configs/msi-claude-settings.json" ]; then
    if [ ! -f ~/.claude/settings.json ]; then
        cp "$REPOS_DIR/cascade-state/configs/msi-claude-settings.json" ~/.claude/settings.json
        echo "  Copied MSI snapshot to ~/.claude/settings.json"
        echo "  REVIEW: ~/.claude/settings.json may contain MSI-specific paths — check before use."
    else
        echo "  ~/.claude/settings.json already exists — leaving alone."
    fi
else
    echo "  No MSI snapshot in cascade-state/configs/ — skipping. You can re-create settings.json fresh."
fi

echo ""
echo "==== T7 done ===="
echo "Next: T8 (07-cascade-browser-setup.sh)"
