#!/bin/bash
# 04-claude-code — install Claude Code via native installer (NOT npm)
# Known issue: npm-distributed binary fails with "Exec format error" в WSL2.
# Native installer drops working binary, invoked via ld-linux.

set -euo pipefail

echo "[04] curl claude.ai/install.sh..."
if [ -z "$(ls ~/.claude/downloads/claude-*-linux-x64 2>/dev/null || true)" ]; then
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo "[04] ~/.claude/downloads already populated"
fi

CC_BIN=$(ls -t ~/.claude/downloads/claude-*-linux-x64 2>/dev/null | head -1)
if [ -z "$CC_BIN" ]; then
    echo "FATAL: no claude binary found"
    exit 1
fi
echo "[04] Binary: $CC_BIN"

# Verify via ld-linux
echo "[04] Verifying via /lib64/ld-linux-x86-64.so.2..."
if ! /lib64/ld-linux-x86-64.so.2 "$CC_BIN" --version >/dev/null 2>&1; then
    echo "FATAL: claude binary не запускается даже через ld-linux"
    echo "diagnostics:"
    file "$CC_BIN" || true
    ldd "$CC_BIN" || true
    exit 1
fi

# Wrapper в ~/bin (PATH в .bashrc)
mkdir -p ~/bin
cat > ~/bin/claude <<EOF
#!/bin/bash
# Pinned via ld-linux — npm install path broken on WSL2.
exec /lib64/ld-linux-x86-64.so.2 $CC_BIN "\$@"
EOF
chmod +x ~/bin/claude

hash -r 2>/dev/null || true
~/bin/claude --version

echo "[04] Claude Code installed"
