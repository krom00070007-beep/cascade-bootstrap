# MIG-001 T6 — Join SER10 to Tailscale tailnet as ser10-tha-1.
# Run from elevated PowerShell on Windows (Tailscale must be installed via T2).
#
# What this does:
#   1. tailscale.exe up with --hostname=ser10-tha-1, --accept-routes=true,
#      --accept-dns=false, --ssh=false (Tailscale SSH is FORBIDDEN org-wide).
#   2. Open browser for OAuth — Stanislav picks krom00070007@gmail.com account.
#   3. Verify tailscale status.
#   4. Record the new tailnet IP to C:\Cascade\logs\tailnet-ip.txt for later use.
#
# CRITICAL: --ssh=false is non-negotiable. There are two prior incidents where
# Tailscale SSH (--ssh=true) caused authorization mismatches across the fleet.
# All nodes use legacy systemd sshd + key auth; Tailscale SSH stays off.

$ErrorActionPreference = 'Stop'
$LogDir = 'C:\Cascade\logs'
$LogFile = Join-Path $LogDir '05-tailscale-join.log'
$IpFile  = Join-Path $LogDir 'tailnet-ip.txt'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log { param([string]$M); $l="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $M"; Write-Host $l; Add-Content -Path $LogFile $l }

Log "==== MIG-001 T6 tailscale-join start ===="

# --- 1. Verify tailscale.exe is on PATH ---
$ts = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if (-not $ts) {
    Log "FATAL: tailscale.exe not on PATH. Install via T2 or set PATH to C:\Program Files\Tailscale\."
    exit 1
}
Log "tailscale.exe: $($ts.Source)"

# --- 2. Tailscale up (will open browser if not already authenticated) ---
Log "Running: tailscale.exe up --hostname=ser10-tha-1 --accept-routes=true --accept-dns=false --ssh=false"
Log "Browser will open. Pick account krom00070007@gmail.com."
tailscale.exe up `
    --hostname=ser10-tha-1 `
    --accept-routes=true `
    --accept-dns=false `
    --ssh=false 2>&1 | Tee-Object -FilePath $LogFile -Append | Out-Null

# --- 3. Status check ---
Start-Sleep -Seconds 3
Log "Verifying connection..."
$status = tailscale.exe status 2>&1
Add-Content -Path $LogFile -Value $status
Write-Host $status

# --- 4. Record tailnet IP ---
$ip = tailscale.exe ip -4 2>&1
if ($ip -match '^\d+\.\d+\.\d+\.\d+$') {
    Log "tailnet IP: $ip"
    Set-Content -Path $IpFile -Value $ip
    Log "Recorded to $IpFile"
} else {
    Log "WARN: tailscale.exe ip -4 returned: $ip — investigate manually"
}

Log "==== T6 done ===="
Write-Host ""
Write-Host "Next: T7 (06-repos-clone.sh) inside WSL." -ForegroundColor Green
Write-Host "Tailnet IP for nodes.md / DNS / docs: $ip" -ForegroundColor Green
