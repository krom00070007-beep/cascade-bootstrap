param([hashtable]$Config)

# 01-win-prep — Windows features + winget packages

$ErrorActionPreference = 'Stop'
function Log { param([string]$M); Write-Host "[01] $M" -ForegroundColor Cyan }

# ============================================================
# Windows features
# ============================================================

$rebootNeeded = $false

$features = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
foreach ($f in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $f).State
    if ($state -ne 'Enabled') {
        Log "Enabling $f..."
        dism.exe /online /enable-feature /featurename:$f /all /norestart | Out-Null
        $rebootNeeded = $true
    } else {
        Log "$f already enabled"
    }
}

# wsl --update
Log "wsl --update..."
wsl --update 2>&1 | Out-Null

# wsl set default version 2
wsl --set-default-version 2 2>&1 | Out-Null

# ============================================================
# winget packages
# ============================================================

$wingetOk = $false
try { winget --version | Out-Null; $wingetOk = $true } catch { Log "WARN: winget not available — install via Microsoft Store" }

if ($wingetOk) {
    $packages = @(
        'tailscale.tailscale',
        'Git.Git',
        'Google.Chrome',
        'Microsoft.PowerShell'
    )
    foreach ($pkg in $packages) {
        Log "winget install $pkg..."
        winget install --id=$pkg -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    }
}

# ============================================================
# Cascade dir on Windows
# ============================================================

New-Item -ItemType Directory -Force -Path 'C:\Cascade\logs' | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\$($Config.WIN_USER)\cascade-msi-setup" | Out-Null

Log "Phase 1 done. Reboot needed: $rebootNeeded"
