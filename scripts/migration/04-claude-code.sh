#!/bin/bash
# MIG-001 T5 — Install Claude Code on SER10 via NATIVE installer (NOT npm).
#
# Why not npm: on MSI WSL2 (and almost certainly SER10 WSL2 too) the npm-distributed
# `claude` binary fails with "Exec format error" via standard execve. The native
# installer drops a different binary that boots cleanly via the dynamic loader.
# Workaround established R-141..R-147 on MSI; verified working with v2.1.140.
#
# What this does:
#   1. curl https://claude.ai/install.sh | bash  → ~/.claude/downloads/claude-<VERSION>-linux-x64
#   2. Verify the binary can run via /lib64/ld-linux-x86-64.so.2 directly
#   3. Create ~/bin/claude wrapper that always invokes via ld-linux
#   4. Pin version 2.1.140 (do NOT auto-update beyond — Memory rule)
#
# Logs to /tmp/mig-001-04-claude-code.log.

set -euo pipefail
LOG=/tmp/mig-001-04-claude-code.log
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date -Iseconds) MIG-001 T5 claude-code start ===="

# --- 5.1 Native installer ---
if [ ! -d ~/.claude/downloads ] || [ -z "$(ls ~/.claude/downloads/claude-*-linux-x64 2>/dev/null || true)" ]; then
    echo "[1/4] Running claude.ai/install.sh..."
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo "[1/4] ~/.claude/downloads already populated — skipping installer"
fi

# --- 5.2 Locate freshly downloaded binary ---
CC_BIN=$(ls -t ~/.claude/downloads/claude-*-linux-x64 2>/dev/null | head -1)
if [ -z "$CC_BIN" ]; then
    echo "FATAL: no claude-*-linux-x64 found in ~/.claude/downloads/"
    echo "Check: ls -la ~/.claude/downloads/"
    exit 1
fi
echo "[2/4] Found binary: $CC_BIN"
ls -la "$CC_BIN"
file "$CC_BIN" || true

# --- 5.3 Verify via ld-linux ---
echo "[3/4] Verifying $CC_BIN runs via /lib64/ld-linux-x86-64.so.2..."
if ! /lib64/ld-linux-x86-64.so.2 "$CC_BIN" --version >/dev/null 2>&1; then
    echo "FATAL: claude binary does not run even via ld-linux."
    echo "Diagnostics:"
    echo "  file: $(file "$CC_BIN")"
    echo "  ldd:"
    ldd "$CC_BIN" || true
    exit 1
fi
echo "  Verified — runs cleanly."

# --- 5.4 Wrapper ---
echo "[4/4] Creating ~/bin/claude wrapper..."
mkdir -p ~/bin
cat > ~/bin/claude <<EOF
#!/bin/bash
# Pinned to 2.1.140 baseline (do NOT auto-update beyond — see Memory R-141..R-147 + R-407).
# If you need a newer version: re-run 04-claude-code.sh after testing the new binary
# manually via /lib64/ld-linux-x86-64.so.2 <new>/claude --version first.
exec /lib64/ld-linux-x86-64.so.2 $CC_BIN "\$@"
EOF
chmod +x ~/bin/claude

# Verify the wrapper resolves
hash -r 2>/dev/null || true
~/bin/claude --version

echo ""
echo "==== T5 done — Claude Code installed ===="
echo "Run \`claude\` from a new shell (ensure PATH=\$HOME/bin:\$PATH from T3)."
echo "Next: T6 (05-tailscale-join.ps1) from Windows admin PowerShell."
