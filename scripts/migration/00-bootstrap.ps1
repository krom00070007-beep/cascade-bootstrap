# MIG-001 T0 — One-shot bootstrap for a fresh SER10 box with Win11 + internet.
#
# Run from elevated PowerShell. This script:
#   1. Downloads the PUBLIC cascade-bootstrap repo as a ZIP (no git required)
#   2. Extracts to C:\Cascade\state\
#   3. Hands off to scripts/migration/01-windows-preflight.ps1
#
# Single-command flow expected on the SER10 operator's side:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   iwr -UseBasicParsing https://raw.githubusercontent.com/krom00070007-beep/cascade-bootstrap/main/scripts/migration/00-bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1
#   & $env:TEMP\bootstrap.ps1
#
# Why a separate cascade-bootstrap public repo (vs cascade-state private):
# cascade-state has topology / handoffs / state metadata that should not be
# public. cascade-bootstrap is an infra-scripts-only mirror, safe to publish.
# After T4 (SSH keygen) + GitHub SSH key registration, the operator can
# `git clone git@github.com:krom00070007-beep/cascade-state.git` to get the
# private state/* content.
#
# OR, if downloaded manually via USB / Telegram (offline fallback):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\00-bootstrap.ps1

$ErrorActionPreference = 'Stop'
$LogDir = 'C:\Cascade\logs'
$LogFile = Join-Path $LogDir '00-bootstrap.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log { param([string]$M); $l="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $M"; Write-Host $l -ForegroundColor Cyan; Add-Content -Path $LogFile $l }

Log "==== MIG-001 T0 bootstrap start ===="

# --- 0. Admin check ---
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "FATAL: must run from elevated PowerShell (Run as Administrator)." -ForegroundColor Red
    exit 1
}
Log "Running as Administrator ✓"

# --- 1. Network sanity ---
Log "Checking github.com reachability..."
try {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com' -Method Head -TimeoutSec 10 | Out-Null
    Log "github.com reachable ✓"
} catch {
    Log "FATAL: github.com unreachable — check internet / firewall. Without internet, use the offline starter kit (USB / Telegram tar.gz) instead."
    exit 1
}

# --- 2. Download repo ZIP ---
$RepoUrl = 'https://github.com/krom00070007-beep/cascade-bootstrap/archive/refs/heads/main.zip'
$Zip = Join-Path $env:TEMP 'cascade-bootstrap-main.zip'
$Dst = 'C:\Cascade\state'

Log "Downloading $RepoUrl..."
Invoke-WebRequest -UseBasicParsing -Uri $RepoUrl -OutFile $Zip
$size = (Get-Item $Zip).Length
Log "Downloaded $size bytes to $Zip"

# --- 3. Extract ---
$Tmp = Join-Path $env:TEMP "cascade-state-bootstrap-$([Guid]::NewGuid())"
Log "Extracting to $Tmp..."
Expand-Archive -Force -Path $Zip -DestinationPath $Tmp
$ExtractedRoot = Get-ChildItem $Tmp | Where-Object { $_.PSIsContainer } | Select-Object -First 1
Log "Repo root in extract: $($ExtractedRoot.FullName)"

# --- 4. Install to C:\Cascade\state ---
if (Test-Path $Dst) {
    Log "WARN: $Dst already exists — backing up to $Dst.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item -Path $Dst -Destination "$Dst.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}
New-Item -ItemType Directory -Force -Path 'C:\Cascade' | Out-Null
Move-Item -Path $ExtractedRoot.FullName -Destination $Dst
Log "Installed to $Dst"

# --- 5. Hand off to 01-windows-preflight.ps1 ---
$Pref = Join-Path $Dst 'scripts\migration\01-windows-preflight.ps1'
if (-not (Test-Path $Pref)) {
    Log "FATAL: $Pref not found in extracted repo. Layout may have changed — abort."
    exit 1
}
Log "Handoff to: $Pref"
Write-Host ""
Write-Host "==== T0 bootstrap done. Running T2 preflight... ====" -ForegroundColor Green
Write-Host ""
& $Pref
