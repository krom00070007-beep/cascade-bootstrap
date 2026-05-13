param([hashtable]$Config)

# 02-wsl-install — Ubuntu-24.04 distro в WSL

$ErrorActionPreference = 'Stop'
function Log { param([string]$M); Write-Host "[02] $M" -ForegroundColor Cyan }

# Check if Ubuntu-24.04 already installed
$existing = wsl --list --quiet 2>$null
if ($existing -match 'Ubuntu-24\.04') {
    Log "Ubuntu-24.04 already installed — skipping"
} else {
    Log "Installing Ubuntu-24.04 — interactive: username=$($Config.WSL_USER), password write down"
    Write-Host ""
    Write-Host "==== Interactive WSL prompt incoming ====" -ForegroundColor Yellow
    Write-Host "Use:"
    Write-Host "  Username: $($Config.WSL_USER)"
    Write-Host "  Password: <your choice, write down>"
    Write-Host "After Ubuntu prompt — type 'exit' to return here."
    Write-Host ""
    wsl --install -d Ubuntu-24.04
}

# Append PATH=$HOME/bin to .bashrc (idempotent)
$patch = 'grep -q "HOME/bin:.PATH" ~/.bashrc || echo ''export PATH=$HOME/bin:$PATH'' >> ~/.bashrc'
wsl -d Ubuntu-24.04 -u $Config.WSL_USER -- bash -c $patch | Out-Null

# Also set default WSL distro
wsl --set-default Ubuntu-24.04 2>&1 | Out-Null

Log "Phase 2 done — Ubuntu-24.04 ready"
