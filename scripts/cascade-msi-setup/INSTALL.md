# INSTALL.md — cascade-msi-setup пошаговая инструкция

_Detailed step-by-step deployment guide для нового Windows 11 box._
_Версия 1.0._

Для общего обзора — см. `README.md`. Этот документ — **детальная инструкция оператора** с примерами вывода + checkpoint'ами.

---

## Pre-flight requirements

### ✅ Что должно быть готово ДО запуска

1. **Windows 11 build ≥ 22000** (`winver` → Settings)
2. **PowerShell admin** access
3. **Internet** (для winget + GitHub + apt + Tailscale)
4. **Минимум 8 GB RAM** (WSL2 захочет 2-4 GB на distro)
5. **Минимум 30 GB free disk** (Ubuntu image ~3 GB, snapshot ~10 GB, logs/code ~5 GB)
6. **Tailscale account** — `krom00070007@gmail.com` или дать другой в config

### ⚠️ Reboot будет требоваться

Скрипт enable'ит Windows features (WSL + VirtualMachinePlatform) что **требует reboot**. После Phase 1 скрипт **остановится с promptом** для restart. После reboot — запусти `.\00-bootstrap-msi.ps1` ещё раз, он продолжит с Phase 2.

---

## Step 0 — Pre-flight setup (10-15 минут)

### Step 0.1 — Tailscale auth key

📋 В браузере (на другой машине):

1. https://login.tailscale.com/admin/settings/keys
2. **"Generate auth key"**
3. Settings:
   - ✅ Reusable
   - ❌ Ephemeral
   - ✅ Pre-approved
   - ✅ Tags: `tag:cascade-backup` (или другой)
     - ⚠️ Этот tag должен быть в `tagOwners` policy file. Если нет — добавь сначала (см. cascade-tailscale-acl skill)
4. **Generate** → скопируй `tskey-auth-XXX...`

### Step 0.2 — GitHub access prepared

cascade-state — private repo. Нужен SSH key зарегистрирован в github.com.

Скрипт сгенерирует новый SSH ключ на новой машине. Будет prompt после Phase 3 — нужно добавить pubkey в github.com.

Заранее: открой https://github.com/settings/keys в браузере, готов к paste.

### Step 0.3 — Решить hostname + role

| Параметр | Значение |
|---|---|
| Hostname | `desktop-4sl95n4` (если rebuild MSI) или новый (`desktop-lenovo`, `desktop-work`, и т.д.) |
| Tailscale tag | `tag:cascade-backup` (если control-point) или `tag:cascade-mobile` (если mobile lab) |
| Windows user | `krom0` (default MSI) или новый |

---

## Step 1 — Download + config (5 минут)

### Step 1.1 — Open PowerShell admin

📋 Win+R → `powershell` → Ctrl+Shift+Enter → Yes (UAC)

```powershell
# Verify admin
[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent().IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# Should return: True
```

### Step 1.2 — Allow PowerShell scripts

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Step 1.3 — Download cascade-msi-setup

```powershell
mkdir C:\Cascade
cd C:\Cascade
mkdir cascade-msi-setup
cd cascade-msi-setup

$files = @(
    '00-bootstrap-msi.ps1','01-win-prep.ps1','02-wsl-install.ps1','03-wsl-base.sh',
    '04-claude-code.sh','05-repos-clone.sh','06-cascade-browser-setup.sh',
    '07-cascade-browser-run.sh','08-tailscale-up.ps1','09-funnel-portproxy.ps1',
    '10-cascade-doctor.ps1','11-validate.sh',
    'cascade-msi-setup.conf.sample','README.md','INSTALL.md'
)

foreach ($f in $files) {
    $url = "https://raw.githubusercontent.com/krom00070007-beep/cascade-bootstrap/main/scripts/cascade-msi-setup/$f"
    Write-Host "Downloading $f..."
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $f
}

dir
```

Should show 15 файлов downloaded.

### Step 1.4 — Создать config

```powershell
Copy-Item cascade-msi-setup.conf.sample cascade-msi-setup.conf
notepad cascade-msi-setup.conf
```

В notepad заполни **обязательно**:

```bash
MSI_HOSTNAME="desktop-NEW-host"        # уникальный hostname в tailnet
WSL_USER="usersstas"                   # Linux user внутри WSL
WIN_USER="krom0"                       # Windows account name
TZ="Asia/Bangkok"

TAILSCALE_AUTHKEY="tskey-auth-XXX..."  # из Step 0.1
TAILSCALE_TAGS="tag:cascade-backup"

GIT_USER_EMAIL="krom00070007@gmail.com"
GIT_USER_NAME="krom00070007-beep"
```

Сохрани (Ctrl+S, закрой notepad).

---

## Step 2 — Run bootstrap Phase 1 (5-10 минут + reboot)

### Step 2.1 — Запустить

```powershell
.\00-bootstrap-msi.ps1
```

**Expected output:**

```
[2026-05-15 14:00:00] ==== cascade-msi-setup start ====
[14:00:00] Config loaded: HOSTNAME=desktop-..., WIN_USER=krom0, WSL_USER=usersstas
[14:00:00] --- Phase 1: 01-win-prep.ps1 ---
[01] Enabling Microsoft-Windows-Subsystem-Linux...
[01] Enabling VirtualMachinePlatform...
[01] wsl --update...
[01] winget install tailscale.tailscale...
[01] winget install Git.Git...
[01] winget install Google.Chrome...
[01] Phase 1 done. Reboot needed: True

==== REBOOT REQUIRED ====
Phase 1 enabled Windows features that require reboot.
Press Enter to reboot now, or Ctrl+C to reboot manually later
```

### Step 2.2 — Reboot

Press Enter → машина перезагрузится.

---

## Step 3 — Re-run после reboot (Phase 2+) (5-10 минут)

### Step 3.1 — Open PowerShell admin again

После reboot:

```powershell
cd C:\Cascade\cascade-msi-setup
.\00-bootstrap-msi.ps1
```

Phase 1 будет skipped (features уже enabled).

### Step 3.2 — Phase 2: WSL install

```
[14:15:00] --- Phase 2: 02-wsl-install.ps1 ---
[02] Installing Ubuntu-24.04 — interactive: username=usersstas, password write down

==== Interactive WSL prompt incoming ====
Use:
  Username: usersstas
  Password: <your choice, write down>
After Ubuntu prompt — type 'exit' to return here.
```

Откроется новое окно Ubuntu prompt:

```
Installing, this may take a few minutes...
Please create a default UNIX user account...
Enter new UNIX username: usersstas
New password: <type>
Retype new password: <type>
```

⚠️ **WRITE DOWN PASSWORD** — нужен для sudo в WSL.

После создания → введи `exit` → return в PowerShell.

### Step 3.3 — Phase 3-7 проходят automatically

```
--- Phase 3: 03-wsl-base.sh ---
... apt update + upgrade + apt install + ssh-keygen + ~/.ssh/config ...

=== SSH pubkey (для распространения на peers): ===
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxx...xxx cowork-msi-wsl2-20260515

--- Phase 4: 04-claude-code.sh ---
... curl claude.ai/install.sh + ld-linux wrapper ...

--- Phase 5: 05-repos-clone.sh ---
[05] Cloning cascade-state (private — нужен GitHub SSH key)...

    ⚠️  STEP REQUIRED: добавь содержимое ~/.ssh/id_ed25519.pub в
    https://github.com/settings/keys
    Затем нажми Enter.

    Press Enter when GitHub SSH key added:
```

### Step 3.4 — Add SSH key to GitHub

📋 На admin браузере:

1. Скопировать **полный** pubkey строку из output выше (`ssh-ed25519 AAAA... cowork-msi-...`)
2. https://github.com/settings/keys → **New SSH key**
3. Title: `cowork-msi-wsl2-20260515-rebuild` (или нечто descriptive)
4. Key: paste pubkey
5. **Add SSH key**

📋 Назад в PowerShell — Enter.

```
--- Phase 5 continues ---
Cloning into 'cascade-state'...
[05] cascade-state cloned
... cascade-browser, cascade-bootstrap, symlinks ...

--- Phase 6: 06-cascade-browser-setup.sh ---
... venv + pytest 59/59 + bearer token ...
[06] Token preview: x14uML...kuZE (len=43)

--- Phase 7: 07-cascade-browser-run.sh ---
[07] Started cascade-browser server PID=12345
[07] Smoke test PASS: HTTP 200 on initialize
```

### Step 3.5 — Phase 8: Tailscale join

```
[14:35:00] --- Phase 8: 08-tailscale-up.ps1 ---
[08] tailscale: C:\Program Files\Tailscale\tailscale.exe
[08] Using pre-auth key
[08] Running: tailscale.exe up --hostname=... (auth key redacted)
[08] tailnet IP: 100.X.Y.Z
```

Если auth key не работал — fall back на OAuth (откроется браузер).

### Step 3.6 — Phase 9: Funnel

```
[14:36:00] --- Phase 9: 09-funnel-portproxy.ps1 ---
[09] Configuring netsh portproxy 8767...
[09] portproxy: 0.0.0.0:8767 → 127.0.0.1:8767
[09] Starting Tailscale Funnel on 8767...

Funnel status:
# Funnel on:
#     https://desktop-NEW-host.tail80c5d4.ts.net
```

### Step 3.7 — Phase 10: cascade-doctor

```
[14:37:00] --- Phase 10: 10-cascade-doctor.ps1 ---
[10] Creating C:\Users\krom0\cascade-doctor.bat...
[10] SUCCESS: Зарегистрированная задача "cascade-doctor-daily" была успешно создана.
[10] Verify: Время следующего запуска: 14.05.2026 12:00:00
```

### Step 3.8 — Phase 11: Validation

```
[14:38:00] --- Phase 11: 11-validate.sh ---
==== cascade-msi-setup validation start ====

  ✓ claude --version (in PATH)
  ✓ tailscale.exe reachable
  ✓ tailscale online + has IP
  ✓ Tailscale Funnel active
  ✓ cascade-browser :8767 listening
  ✓ cascade-browser :8768 listening
  ✓ Bearer 401 without auth
  ✓ Bearer 200 on initialize
  ✓ cascade-state pull works (SSH key)
  ✓ cascade-* skills symlinked (count > 5)
  ✓ cascade-doctor in PATH

==== RESULT: 11 passed / 0 failed ====
🎉 cascade-msi-setup deployment SUCCESS
```

🎉 Полная установка завершена.

---

## Step 4 — Post-deploy admin tasks (10 минут)

### Step 4.1 — admin.tailscale.com tasks

📋 https://login.tailscale.com/admin/machines

1. Найти new hostname в списке
2. Click → details
3. **Toggle ON:** "Allow this node as exit node" (если нужно — обычно не для backup control-point)
4. **Disable key expiry** ("Machine settings" → "Disable key expiry")
5. **Funnel ON** (если phase 9 уже не включил автоматически)

📋 DNS settings (one-time per tailnet):

- DNS → "Use MagicDNS" ON
- DNS → "HTTPS Certificates" ON

### Step 4.2 — Backup Bearer в Telegram

В WSL:

```bash
tg-send-text "cascade-browser MSI Bearer (rebuild $(date +%Y-%m-%d)): $(cat ~/.cascade-browser/bearer.txt)"
```

(если `tg-send-text` installed — иначе скопируй пакет руками и пошли в Telegram Saved)

### Step 4.3 — claude.ai Connector setup

📋 На любом устройстве через claude.ai web:

1. Settings → Connectors
2. **Add Connector** или Edit existing cascade-browser
3. URL: `https://<MSI_HOSTNAME>.tail80c5d4.ts.net/mcp`
4. Authorization: **Bearer** token из шага 4.2
5. **Test connection** → должен показать список 10 tools

### Step 4.4 — Test cascade-doctor run

📋 PowerShell:

```powershell
schtasks.exe /Run /TN cascade-doctor-daily
```

Через ~30 секунд проверь `~/cascade-doctor-reports/` (в WSL) — должен появиться новый report. Также придёт Telegram alert.

---

## Step 5 — Verification (5 минут)

### Step 5.1 — Tailscale status

```powershell
tailscale.exe status
```

Should show новый hostname + tailnet IP + другие peers online.

```powershell
tailscale.exe funnel status
```

Should show `Funnel on: https://<hostname>.tail80c5d4.ts.net`.

### Step 5.2 — cascade-browser smoke test

В WSL:

```bash
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
# Local
curl -s -o /dev/null -w "local: %{http_code}\n" -X POST http://127.0.0.1:8767/mcp \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke","version":"0.1"}}}'

# Via Funnel
curl -s -o /dev/null -w "funnel: %{http_code}\n" -X POST https://desktop-NEW-host.tail80c5d4.ts.net/mcp \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke","version":"0.1"}}}'
```

Expected: `local: 200`, `funnel: 200`.

### Step 5.3 — cascade-doctor manual test

В WSL:

```bash
~/bin/cascade-doctor --quiet
ls ~/cascade-doctor-reports/
cat ~/cascade-doctor-reports/$(date +%Y-%m-%d).md | head -30
```

### Step 5.4 — Skills available

В WSL:

```bash
ls ~/.claude/skills/ | grep cascade-
```

Should show ~14 cascade-* skills (8 tailscale + 6 browser).

---

## Step 6 — Daily operations

### Запустить cascade-doctor manually

```powershell
schtasks.exe /Run /TN cascade-doctor-daily
```

Or в WSL:

```bash
~/bin/cascade-doctor
```

### Stop / restart cascade-browser

В WSL:

```bash
# Stop
pkill -f "python3 src/server.py"

# Start
cd ~/projects/cascade-browser/mcp-server
nohup ./run-server.sh > /tmp/cascade-browser.log 2>&1 &
disown
```

### Update cascade-state / cascade-browser

В WSL:

```bash
cd ~/projects/cascade-state && git pull
cd ~/projects/cascade-browser && git pull
```

### Backup Bearer (рекомендуется monthly)

```bash
tg-send-text "cascade-browser MSI Bearer (snapshot $(date +%Y-%m-%d)): $(cat ~/.cascade-browser/bearer.txt)"
```

---

## Troubleshooting per phase

| Phase | Symptom | Решение |
|---|---|---|
| 1 | `winget not available` | Install via Microsoft Store: "App Installer" |
| 2 | `wsl --install` fails | Manually: `wsl --update` сначала, потом `wsl --install -d Ubuntu-24.04` |
| 3 | `apt update` fails: DNS | Проверь `/etc/resolv.conf`: должен быть nameserver. Add `1.1.1.1` если нет. |
| 4 | `claude` not found после install | Re-source `.bashrc`: `source ~/.bashrc; hash -r` |
| 5 | git clone fails: Permission denied | SSH key не добавлен в github.com или не activate'нут. Verify: `ssh -T git@github.com` |
| 6 | pytest fails | Verify requirements.txt + requirements-dev.txt installed. `python3.12-venv` apt package needed. |
| 7 | HTTP 401 после start | Bearer mismatch — verify `cat ~/.cascade-browser/bearer.txt` равен тому что в `Authorization` header. |
| 8 | OAuth не открывается | Headless mode. Открой URL printed in console на ДРУГОЙ машине, авторизуйся → нода активируется. |
| 9 | Funnel status empty | Verify в admin: HTTPS Certificates ON + Funnel per-device ON. Cert provisioning ~30-60 сек. |
| 10 | schtasks не создаёт task | Try GUI: `taskschd.msc` → import .xml manually. |
| 11 | Some checks fail | Re-run individual scripts: `bash ~/.cascade-msi-setup/<script>.sh` |

---

## Rollback

⚠️ **Полный rollback удалит WSL + Tailscale + всё.**

```powershell
# 1. Stop services
schtasks.exe /Delete /TN cascade-doctor-daily /F
tailscale.exe funnel reset
netsh interface portproxy reset

# 2. Tailscale logout + uninstall
tailscale.exe logout
winget uninstall tailscale.tailscale

# 3. WSL: unregister Ubuntu
wsl --unregister Ubuntu-24.04

# 4. Optionally — disable WSL features (требует reboot)
# dism.exe /online /disable-feature /featurename:Microsoft-Windows-Subsystem-Linux /norestart
# Restart-Computer

# 5. Cleanup
Remove-Item -Recurse -Force C:\Cascade
Remove-Item -Recurse -Force C:\Users\krom0\cascade-doctor.bat
Remove-Item -Recurse -Force C:\Users\krom0\cascade-doctor-wrap.log
```

После этого — admin.tailscale.com → Machines → delete старую запись.

---

## FAQ

**Q: Можно ли delegate без VLAN admin OAuth?**
A: Если `TAILSCALE_AUTHKEY` valid + не expired — да, скрипт join'ит без браузера. Лучший vibe для headless deploy.

**Q: Сколько RAM нужно WSL?**
A: По умолчанию ~50% Win RAM. Можно тuneit в `~/.wslconfig` (см. config sample). Cascade-browser usage ~150 MB.

**Q: Если SSH ключ leaked — что делать?**
A: 1) Сгенерировать новый ed25519 на MSI, 2) Распространить новый pubkey на peers (ssh-copy-id), 3) Удалить старый из authorized_keys и github. См. `state/handoffs/2026-05-12-ssh-rotation-and-whisper-cleanup.md` для прецедента.

**Q: cascade-doctor работает только если Win user logged on?**
A: По умолчанию task создан с "Run only when user is logged on". Можно изменить в `taskschd.msc` → Properties → "Run whether user is logged on or not" (требует пароль).

**Q: Что если хочу 2 control points (MSI + Lenovo)?**
A: Запусти этот скрипт на Lenovo с разным hostname (`desktop-lenovo`) и tag (`tag:cascade-backup-2`). Cascade-browser на каждом будет иметь свой Bearer + Funnel URL.

---

## Cross-refs

- `README.md` — overview + список файлов
- `cascade-msi-setup.conf.sample` — template config
- `scripts/migration/` — MIG-001 SER10 deploy (overlapping)
- `scripts/cascade-server-setup/` — для headless Linux VDS (no Win)
- `docs/audits/cascade-architecture-errors-2026-05-14.md` — known issues
- `skills/cascade-tailscale-add-node/SKILL.md` — общий tailnet add-node workflow
- `skills/cascade-browser-overview/SKILL.md` — как использовать cascade-browser tools после deploy
