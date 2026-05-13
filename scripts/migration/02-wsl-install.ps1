# MIG-001 T3 — Install Ubuntu-24.04 distro into WSL2.
# Run from elevated PowerShell after T2 (01-windows-preflight.ps1) completes.
#
# What this does:
#   1. wsl --install -d Ubuntu-24.04 (interactive — asks for username/password on first boot)
#   2. After Stanislav enters username=usersstas + password, this script appends
#      `export PATH=$HOME/bin:$PATH` to ~/.bashrc inside Ubuntu.
#
# Manual step in the middle: Ubuntu will spawn an interactive shell asking for
# UNIX username + password. Use:
#   - username: usersstas  (same as MSI for portability)
#   - password: <your choice — write it down>
# After the prompt completes, type `exit` to return to PowerShell. This script
# detects that and continues.

$ErrorActionPreference = 'Stop'
$LogFile = 'C:\Cascade\logs\02-wsl-install.log'

function Log { param([string]$M); $l="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $M"; Write-Host $l; Add-Content -Path $LogFile $l }

Log "==== MIG-001 T3 wsl-install start ===="

# Check if Ubuntu-24.04 already installed
$existing = wsl --list --quiet 2>$null
if ($existing -match 'Ubuntu-24\.04') {
    Log "Ubuntu-24.04 already installed — skipping wsl --install"
} else {
    Log "Running: wsl --install -d Ubuntu-24.04"
    Log "Ubuntu will start interactive. Use username=usersstas + a password you write down."
    Log "After Ubuntu prompt finishes, type 'exit' to return to PowerShell."
    Write-Host ""
    Write-Host "==== Ubuntu interactive prompt incoming ====" -ForegroundColor Yellow
    wsl --install -d Ubuntu-24.04
}

# Append PATH=$HOME/bin to .bashrc (idempotent)
Log "Appending PATH=`$HOME/bin to ~/.bashrc inside Ubuntu..."
$bashrcPatch = 'grep -q "HOME/bin:.PATH" ~/.bashrc || echo ''export PATH=$HOME/bin:$PATH'' >> ~/.bashrc'
wsl -d Ubuntu-24.04 -- bash -c $bashrcPatch

Log "==== T3 done — proceed to T4 (run 03-wsl-base.sh inside WSL) ===="
Write-Host ""
Write-Host "Next: open WSL and run scripts/migration/03-wsl-base.sh" -ForegroundColor Green
Write-Host "  wsl -d Ubuntu-24.04" -ForegroundColor Green
