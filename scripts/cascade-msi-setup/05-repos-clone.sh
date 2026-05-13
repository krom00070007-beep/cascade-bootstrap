#!/bin/bash
# 05-repos-clone — clone cascade-state + cascade-browser, setup post-commit hook,
# symlink skills в ~/.claude/skills/

set -euo pipefail

if [ -f ~/.cascade-msi-setup/conf ]; then source ~/.cascade-msi-setup/conf; fi

mkdir -p ~/projects
cd ~/projects

# ============================================================
# cascade-state (private — нужен SSH ключ зарегистрирован в GitHub)
# ============================================================

if [ ! -d ~/projects/cascade-state ]; then
    echo "[05] Cloning cascade-state (private — нужен GitHub SSH key)..."
    echo ""
    echo "    ⚠️  STEP REQUIRED: добавь содержимое ~/.ssh/id_ed25519.pub в"
    echo "    https://github.com/settings/keys"
    echo "    Затем нажми Enter."
    echo ""
    read -p "    Press Enter when GitHub SSH key added: "

    git clone git@github.com:krom00070007-beep/cascade-state.git
else
    echo "[05] cascade-state already cloned — git pull"
    (cd cascade-state && git pull --rebase)
fi

cd ~/projects/cascade-state
# post-commit hook (auto-push на opus)
if [ ! -f .git/hooks/post-commit ] && [ -f configs/git-hooks/post-commit ]; then
    cp configs/git-hooks/post-commit .git/hooks/post-commit
    chmod +x .git/hooks/post-commit
    echo "[05] post-commit hook installed"
fi

# ============================================================
# cascade-browser (public)
# ============================================================

cd ~/projects
if [ ! -d ~/projects/cascade-browser ]; then
    echo "[05] Cloning cascade-browser..."
    git clone https://github.com/krom00070007-beep/cascade-browser.git
else
    echo "[05] cascade-browser already cloned — git pull"
    (cd cascade-browser && git pull --rebase)
fi

# ============================================================
# cascade-bootstrap (public mirror — для skills)
# ============================================================

if [ ! -d ~/projects/cascade-bootstrap ]; then
    echo "[05] Cloning cascade-bootstrap..."
    git clone https://github.com/krom00070007-beep/cascade-bootstrap.git
fi

# ============================================================
# cascade-state-push symlink (для post-commit hook to opus mirror)
# ============================================================

mkdir -p ~/bin
if [ -f ~/projects/cascade-state/bin/cascade-state-push ]; then
    chmod +x ~/projects/cascade-state/bin/cascade-state-push
    ln -sf ~/projects/cascade-state/bin/cascade-state-push ~/bin/cascade-state-push
fi

# ============================================================
# Skills symlinks в ~/.claude/skills/
# ============================================================

mkdir -p ~/.claude/skills
for skill in $(ls ~/projects/cascade-state/skills/ 2>/dev/null); do
    target=~/projects/cascade-state/skills/$skill
    link=~/.claude/skills/$skill
    if [ ! -e "$link" ]; then
        ln -s "$target" "$link"
    fi
done
echo "[05] Skills symlinked: $(ls ~/.claude/skills/ | wc -l) total"

# ============================================================
# cascade-doctor symlink
# ============================================================

if [ -f ~/projects/cascade-state/scripts/cascade-doctor/cascade-doctor.sh ]; then
    chmod +x ~/projects/cascade-state/scripts/cascade-doctor/cascade-doctor.sh
    ln -sf ~/projects/cascade-state/scripts/cascade-doctor/cascade-doctor.sh ~/bin/cascade-doctor
    echo "[05] cascade-doctor symlinked"
fi

echo "[05] Repos clone done"
