# cascade-msi-setup — bootstrap MSI как Cascade control point
#
# Полная автоматическая установка fresh Windows 11 box → MSI Cascade BACKUP:
#   - Windows features (WSL + VirtualMachinePlatform)
#   - winget Tailscale + Git + Chrome
#   - WSL Ubuntu-24.04 install (interactive prompt)
#   - WSL base setup (apt + ssh-keygen + ssh-config)
#   - Claude Code via curl install.sh (NOT npm — known issue)
#   - Repos clone: cascade-state + cascade-browser (+ cascade-bootstrap mirror)
#   - cascade-browser MCP server install (venv + tests + bearer token)
#   - cascade-browser MCP server run (nohup ./run-server.sh)
#   - Tailscale up (--hostname + tags + --ssh=false + --advertise-routes?)
#   - Tailscale Funnel (netsh portproxy + tailscale funnel --bg)
#   - cascade-doctor install + Windows Task Scheduler 12:00 Bangkok daily
#
# Usage (PowerShell admin):
#   cp cascade-msi-setup.conf.sample cascade-msi-setup.conf
#   notepad cascade-msi-setup.conf  # заполнить
#   .\00-bootstrap-msi.ps1
#
# Time: ~30-60 минут (большая часть — WSL install + apt + Tailscale auth)
# Idempotent: можно повторно запускать, пропускает уже-сделанные phases

$ErrorActionPreference = 'Stop'

# ============================================================
# Pre-flight
# ============================================================

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "FATAL: must run from elevated PowerShell." -ForegroundColor Red
    exit 1
}

$ScriptDir = $PSScriptRoot
$ConfPath = Join-Path $ScriptDir 'cascade-msi-setup.conf'
$LogDir = 'C:\Cascade\logs'
$LogFile = Join-Path $LogDir 'cascade-msi-setup.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log { param([string]$M); $l="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $M"; Write-Host $l -ForegroundColor Cyan; Add-Content -Path $LogFile $l }

Log "==== cascade-msi-setup start ===="

if (-not (Test-Path $ConfPath)) {
    Log "FATAL: config not found: $ConfPath"
    Log "Run: Copy-Item cascade-msi-setup.conf.sample cascade-msi-setup.conf; notepad cascade-msi-setup.conf"
    exit 1
}

# Load config (PS doesn't have native bash-style sourcing — parse manually)
$Config = @{}
Get-Content $ConfPath | ForEach-Object {
    if ($_ -match '^([A-Z_]+)="?([^"]*)"?$') {
        $Config[$Matches[1]] = $Matches[2]
    }
}
Log "Config loaded: HOSTNAME=$($Config.MSI_HOSTNAME), WIN_USER=$($Config.WIN_USER), WSL_USER=$($Config.WSL_USER)"

# ============================================================
# Phase 1 — Windows features + winget packages
# ============================================================

Log "--- Phase 1: 01-win-prep.ps1 ---"
& "$ScriptDir\01-win-prep.ps1" -Config $Config

# Check if reboot needed после Phase 1
$WslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($WslFeature.RestartRequired) {
    Log ""
    Log "==== REBOOT REQUIRED ===="
    Log "Phase 1 enabled Windows features that require reboot."
    Log "After reboot, re-run этот же script (.\00-bootstrap-msi.ps1) — он продолжит с Phase 2."
    Log ""
    Read-Host "Press Enter to reboot now, or Ctrl+C to reboot manually later"
    Restart-Computer
}

# ============================================================
# Phase 2 — WSL install
# ============================================================

Log "--- Phase 2: 02-wsl-install.ps1 ---"
& "$ScriptDir\02-wsl-install.ps1" -Config $Config

# ============================================================
# Phase 3 — WSL base setup (внутри WSL)
# ============================================================

Log "--- Phase 3: 03-wsl-base.sh (inside WSL) ---"
# Copy config into WSL для downstream scripts
wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash -c "mkdir -p ~/.cascade-msi-setup"
wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash -c "cat > ~/.cascade-msi-setup/conf <<'EOF'
$(Get-Content $ConfPath | Out-String)
EOF"

# Copy bash scripts into WSL
foreach ($f in @('03-wsl-base.sh','04-claude-code.sh','05-repos-clone.sh','06-cascade-browser-setup.sh','07-cascade-browser-run.sh','11-validate.sh')) {
    $src = "$ScriptDir\$f"
    $dst = "/home/$($Config.WSL_USER)/.cascade-msi-setup/$f"
    if (Test-Path $src) {
        wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash -c "mkdir -p ~/.cascade-msi-setup"
        Get-Content $src | wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash -c "cat > $dst && chmod +x $dst"
    }
}

wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash ~/.cascade-msi-setup/03-wsl-base.sh

# ============================================================
# Phase 4 — Claude Code
# ============================================================

Log "--- Phase 4: 04-claude-code.sh ---"
wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash ~/.cascade-msi-setup/04-claude-code.sh

# ============================================================
# Phase 5 — Repos clone (cascade-state + cascade-browser)
# ============================================================

Log "--- Phase 5: 05-repos-clone.sh ---"
wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash ~/.cascade-msi-setup/05-repos-clone.sh

# ============================================================
# Phase 6 — cascade-browser MCP setup (venv + pytest + bearer)
# ============================================================

Log "--- Phase 6: 06-cascade-browser-setup.sh ---"
wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash ~/.cascade-msi-setup/06-cascade-browser-setup.sh

# ============================================================
# Phase 7 — cascade-browser MCP run (nohup)
# ============================================================

Log "--- Phase 7: 07-cascade-browser-run.sh ---"
wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash ~/.cascade-msi-setup/07-cascade-browser-run.sh

# ============================================================
# Phase 8 — Tailscale up (Win-side)
# ============================================================

Log "--- Phase 8: 08-tailscale-up.ps1 ---"
& "$ScriptDir\08-tailscale-up.ps1" -Config $Config

# ============================================================
# Phase 9 — Funnel + portproxy
# ============================================================

Log "--- Phase 9: 09-funnel-portproxy.ps1 ---"
& "$ScriptDir\09-funnel-portproxy.ps1" -Config $Config

# ============================================================
# Phase 10 — cascade-doctor (Win Task Scheduler)
# ============================================================

if ($Config.ENABLE_CASCADE_DOCTOR -eq 'true') {
    Log "--- Phase 10: 10-cascade-doctor.ps1 ---"
    & "$ScriptDir\10-cascade-doctor.ps1" -Config $Config
} else {
    Log "Skipping cascade-doctor (ENABLE_CASCADE_DOCTOR=false)"
}

# ============================================================
# Phase 11 — Validation
# ============================================================

Log "--- Phase 11: 11-validate.sh ---"
$ValidateOutput = wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash ~/.cascade-msi-setup/11-validate.sh
Write-Host $ValidateOutput

# ============================================================
# DONE
# ============================================================

Log "==== cascade-msi-setup DONE ===="
Log ""
Log "Next steps (manual):"
Log "  1. admin.tailscale.com → Machines → $($Config.MSI_HOSTNAME) → Toggle Funnel ON + Disable key expiry"
Log "  2. claude.ai → Settings → Connectors → Add: https://$($Config.TAILSCALE_FUNNEL_HOSTNAME)/mcp + Bearer (см. ~/.cascade-browser/bearer.txt)"
Log "  3. Send Bearer в Telegram Saved для cross-device sync (см. cascade-tailscale-funnel skill)"
Log ""
Log "Log: $LogFile"
