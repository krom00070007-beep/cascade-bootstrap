# MIG-001 T2 — Windows pre-flight for SER10 Pattaya-1 (ser10-tha-1).
# Run from elevated PowerShell (Administrator) on Win11 stock.
#
# What this does:
#   1. Verify Win11 build >= 22000
#   2. Enable WSL + VirtualMachinePlatform features
#   3. wsl --update (kernel 6.6.114+) and --set-default-version 2
#   4. winget install Tailscale + Git
#   5. Tell operator to reboot if virtualization features were freshly enabled
#
# Output log: C:\Cascade\logs\01-preflight.log
#
# REBOOT NOTICE: if either WSL or VirtualMachinePlatform feature was OFF before
# this script ran, Windows REQUIRES a reboot before `wsl --install -d Ubuntu`
# will work. The script will exit with a reboot message in that case.

$ErrorActionPreference = 'Stop'
$LogDir = 'C:\Cascade\logs'
$LogFile = Join-Path $LogDir '01-preflight.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log {
    param([string]$Msg)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Log "==== MIG-001 T2 preflight start ===="

# --- 1. Win11 build check ---
$ver = [System.Environment]::OSVersion.Version
Log "OS version: $($ver.Major).$($ver.Minor).$($ver.Build)"
if ($ver.Build -lt 22000) {
    Log "FATAL: Build $($ver.Build) < 22000 — not Windows 11. Abort."
    exit 1
}

# --- 2. Enable WSL + VirtualMachinePlatform ---
$wslEnabled = $false
$vmEnabled  = $false
$rebootNeeded = $false

$wsl = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wsl.State -ne 'Enabled') {
    Log "Enabling Microsoft-Windows-Subsystem-Linux..."
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
    $rebootNeeded = $true
} else {
    Log "WSL feature already enabled."
    $wslEnabled = $true
}

$vm = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vm.State -ne 'Enabled') {
    Log "Enabling VirtualMachinePlatform..."
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
    $rebootNeeded = $true
} else {
    Log "VirtualMachinePlatform feature already enabled."
    $vmEnabled = $true
}

if ($rebootNeeded) {
    Log "REBOOT REQUIRED — Windows features were just enabled."
    Log "After reboot, re-run this script. It will skip already-enabled features and continue to wsl --update."
    Write-Host ""
    Write-Host "==== REBOOT NOW: Restart-Computer ====" -ForegroundColor Yellow
    exit 0
}

# --- 3. wsl --update + default version 2 ---
Log "Running wsl --update..."
wsl --update 2>&1 | Tee-Object -FilePath $LogFile -Append | Out-Null

Log "Setting wsl default version to 2..."
wsl --set-default-version 2 2>&1 | Tee-Object -FilePath $LogFile -Append | Out-Null

# --- 4. winget install Tailscale + Git ---
$wingetOk = $false
try { winget --version | Out-Null; $wingetOk = $true } catch { Log "WARN: winget not available — install manually" }

if ($wingetOk) {
    foreach ($pkg in @('tailscale.tailscale','Git.Git')) {
        Log "Installing $pkg via winget..."
        winget install --id=$pkg -e --silent --accept-package-agreements --accept-source-agreements 2>&1 |
            Tee-Object -FilePath $LogFile -Append | Out-Null
    }
} else {
    Log "MANUAL: download Tailscale from https://tailscale.com/download/windows"
    Log "MANUAL: download Git from https://git-scm.com/download/win"
}

# --- 5. Done ---
Log "==== T2 preflight done — proceed to T3 (02-wsl-install.ps1) ===="
Write-Host ""
Write-Host "Next: run 02-wsl-install.ps1 from same elevated PowerShell." -ForegroundColor Green
