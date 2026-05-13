# cascade-msi-setup — fresh Win 11 → MSI Cascade control point

Полная automated установка нового Windows 11 box как MSI-style Cascade peer:
- **Windows features** (WSL + Hyper-V) + winget Tailscale/Git/Chrome
- **WSL Ubuntu-24.04** + apt baseline + ssh-keygen + ~/.ssh/config peers
- **Claude Code 2.1.140+** via native installer (NOT npm — known bug)
- **Repos clone:** cascade-state (private) + cascade-browser + cascade-bootstrap mirror
- **cascade-browser MCP** server: venv + pytest + Bearer token
- **Tailscale Funnel** + Win netsh portproxy для `https://<hostname>.tail80c5d4.ts.net/mcp`
- **cascade-doctor** Windows Task Scheduler 12:00 Bangkok (READ-ONLY)
- **Skills symlinks** ~/.claude/skills/cascade-* (14 skills + cascade-collaboration)

## Когда использовать

- **Rebuild MSI** (после переустановки Windows или диска)
- **New backup control-point** на другой Windows box (Lenovo, ноут на работе, и т.д.)
- **Replicate MSI environment** на новой физической машине

⚠️ **Это НЕ для SER10 (Pattaya-1).** Для SER10 — см. `scripts/migration/` (MIG-001 deployment kit).

## Файлы

| File | Назначение | Lines |
|---|---|---|
| `00-bootstrap-msi.ps1` | Main PowerShell entry — calls phases 1-11 | 182 |
| `01-win-prep.ps1` | Windows features (WSL + VirtualMachinePlatform), winget Tailscale/Git/Chrome | 60 |
| `02-wsl-install.ps1` | `wsl --install -d Ubuntu-24.04` (interactive prompt) | 31 |
| `03-wsl-base.sh` | apt baseline + ssh-keygen + ~/.ssh/config peers | 93 |
| `04-claude-code.sh` | Native installer + ld-linux wrapper в ~/bin/claude | 44 |
| `05-repos-clone.sh` | cascade-state + cascade-browser + cascade-bootstrap + skills symlinks | 95 |
| `06-cascade-browser-setup.sh` | venv + requirements + pytest + bearer token gen | 52 |
| `07-cascade-browser-run.sh` | nohup ./run-server.sh + smoke test | 44 |
| `08-tailscale-up.ps1` | tailscale.exe up --hostname + --tags + --ssh=false | 46 |
| `09-funnel-portproxy.ps1` | netsh portproxy + tailscale funnel --bg 8767 | 49 |
| `10-cascade-doctor.ps1` | Win Task Scheduler register + .bat wrapper | 40 |
| `11-validate.sh` | E2E health check (10+ assertions) | 61 |
| `cascade-msi-setup.conf.sample` | Template config (Tailscale auth key, hostname, etc.) | 92 |
| `README.md` | Этот файл | — |
| `INSTALL.md` | Детальная пошаговая инструкция | см. INSTALL.md |

**Total:** 13 executable files + 1 config + 2 docs.

## Quick start (для experienced operator)

```powershell
# PowerShell admin:
cd C:\Cascade\cascade-msi-setup
Copy-Item cascade-msi-setup.conf.sample cascade-msi-setup.conf
notepad cascade-msi-setup.conf       # заполнить TAILSCALE_AUTHKEY + hostname
.\00-bootstrap-msi.ps1
```

Time: 30-60 минут (Windows features + WSL install + apt = большая часть).

⚠️ **Reboot будет требоваться** после Phase 1 если WSL feature только что enabled. Скрипт остановится, попросит reboot, после reboot — re-run, продолжит с Phase 2.

Подробно step-by-step с screenshots и checkpoint'ами — см. **INSTALL.md**.

## Pre-flight requirements

- Fresh Windows 11 (build >= 22000)
- Internet доступ (для winget + apt + GitHub + Tailscale)
- **PowerShell admin** access
- **Tailscale auth key** из admin.tailscale.com → Settings → Keys (см. INSTALL.md Step 0)
- **GitHub SSH key access** — после Phase 3 нужно добавить новый pubkey в github.com/settings/keys для `cascade-state` clone
- **Tailscale tag `tag:cascade-backup`** должен быть в `tagOwners` policy file

## Baked-in fixes для известных Cascade ошибок

(из `docs/audits/cascade-architecture-errors-2026-05-14.md`)

| Issue | Fix в setup |
|---|---|
| Claude Code via npm падает (Exec format error WSL2) | 04-claude-code.sh использует native installer + ld-linux wrapper |
| python3.12-venv отсутствует на fresh Ubuntu | 03-wsl-base.sh устанавливает |
| Bearer token utwerd в Telegram = forever-valid | Bearer auto-generated locally, не shared (но юзер должен sync в Telegram Saved вручную) |
| sshd hardening на 5 серверах overdue | На MSI side — n/a (sshd внутри WSL не публично exposed). Если будет SSH on Win — конфиг отдельно. |
| Tailscale `--ssh=true` запрещено | 08-tailscale-up.ps1 FORCES `--ssh=false` |
| WSL2 mirrored networking gap | 02-wsl-install.ps1 + 09-funnel-portproxy.ps1 настраивает portproxy как fallback |
| ssh-agent persistence через reboot | INSTALL.md документирует решение (systemd-user или .bashrc) |
| cascade-doctor для daily monitoring | 10-cascade-doctor.ps1 регистрирует Win Task Scheduler |

## Hard rules enforced

- ❌ `--ssh=false` ВСЕГДА в `tailscale up` (org-wide hard rule)
- ❌ npm install для Claude Code НЕ используется
- ❌ Forbidden nodes (gl-mt6000-*, glkvm, beget-*) НЕ упоминаются в этом setup
- ❌ Bearer token НЕ commit'ится в git

## Скрипт **не** делает

- ❌ Install Docker / Kubernetes / etc. (out of scope)
- ❌ Setup Windows Defender exclusions для WSL (нужно вручную если нужно)
- ❌ Backup existing files перед overwriting (assume fresh box)
- ❌ Multi-WSL distros (только Ubuntu-24.04)
- ❌ Configure Windows updates (separate concern)

## Post-deploy checklist (manual, см. INSTALL.md)

1. ✅ admin.tailscale.com → Machines → этот host → Funnel ON + Disable key expiry
2. ✅ claude.ai → Settings → Connectors → Add cascade-browser
3. ✅ Backup Bearer token в Telegram Saved
4. ✅ Test cascade-doctor manual run: `schtasks.exe /Run /TN cascade-doctor-daily`
5. ✅ Verify E2E через ssh peer + curl ifconfig.me (если chained routing включён где-то)

## Cross-refs

- `INSTALL.md` — детальная step-by-step инструкция
- `scripts/migration/` — MIG-001 для SER10 (overlapping but different target)
- `scripts/cascade-server-setup/` — для headless Linux VDS (без Windows host)
- `docs/audits/cascade-architecture-errors-2026-05-14.md` — какие ошибки fix'нуты
- `skills/cascade-tailscale-overview/SKILL.md` — общая карта tailnet
- `skills/cascade-browser-overview/SKILL.md` — как использовать cascade-browser tools после deploy
