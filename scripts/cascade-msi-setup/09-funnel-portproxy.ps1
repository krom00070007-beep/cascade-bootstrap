param([hashtable]$Config)

# 09-funnel-portproxy — netsh portproxy + Tailscale Funnel
# For WSL1: loopback shared — portproxy опционально (внутри Win loopback и WSL loopback одни и те же)
# For WSL2: portproxy mandatory (если не mirrored networkingMode)

$ErrorActionPreference = 'Stop'
function Log { param([string]$M); Write-Host "[09] $M" -ForegroundColor Cyan }

$Port = if ($Config.MCP_PORT) { $Config.MCP_PORT } else { '8767' }

# ============================================================
# netsh portproxy (Win → WSL loopback)
# ============================================================

Log "Configuring netsh portproxy $Port..."

# Remove existing rule if any
netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 2>$null | Out-Null

# Add fresh
netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=127.0.0.1
Log "portproxy: 0.0.0.0:$Port → 127.0.0.1:$Port"

netsh interface portproxy show v4tov4 | Out-String | Write-Host

# ============================================================
# Tailscale Funnel
# ============================================================

Log "Starting Tailscale Funnel on $Port..."

# Stop existing funnel if any
tailscale.exe funnel reset 2>$null | Out-Null

# Start --bg (background, persistent)
tailscale.exe funnel --bg $Port

Start-Sleep -Seconds 3
$funnelStatus = tailscale.exe funnel status 2>&1
Log "Funnel status:"
$funnelStatus | Out-String | Write-Host

Log "Phase 9 done"
Log ""
Log "🚨 ВАЖНО: проверь admin.tailscale.com:"
Log "  - DNS → HTTPS Certificates: ON"
Log "  - Machines → $($Config.MSI_HOSTNAME) → Funnel: ON"
Log "  - ACL: nodeAttrs funnel grant для этого tag"
