param([hashtable]$Config)

# 08-tailscale-up — join tailnet with MSI hostname + tags

$ErrorActionPreference = 'Stop'
function Log { param([string]$M); Write-Host "[08] $M" -ForegroundColor Cyan }

# Verify tailscale.exe is installed
$ts = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if (-not $ts) {
    Log "FATAL: tailscale.exe не найден. Install via winget в Phase 1."
    exit 1
}
Log "tailscale: $($ts.Source)"

# Already joined?
$status = tailscale.exe status 2>$null
if ($status -match $Config.MSI_HOSTNAME) {
    Log "Already joined as $($Config.MSI_HOSTNAME) — skipping"
    tailscale.exe ip -4
    return
}

# Build tailscale up command
$cmd = "tailscale.exe up --hostname=$($Config.MSI_HOSTNAME) --accept-routes=true --accept-dns=false --ssh=false"
if ($Config.TAILSCALE_TAGS) {
    $cmd += " --advertise-tags=$($Config.TAILSCALE_TAGS)"
}

if ($Config.TAILSCALE_AUTHKEY) {
    $cmd += " --auth-key=$($Config.TAILSCALE_AUTHKEY)"
    Log "Using pre-auth key"
} else {
    Log "No auth key — interactive OAuth required"
}

Log "Running: $cmd (auth key redacted)"
Invoke-Expression $cmd

# Verify
Start-Sleep -Seconds 3
$tsIp = tailscale.exe ip -4 2>&1
Log "tailnet IP: $tsIp"
"tailnet IP $tsIp" | Out-File 'C:\Cascade\logs\tailnet-ip.txt' -Encoding ASCII

Log "Phase 8 done"
