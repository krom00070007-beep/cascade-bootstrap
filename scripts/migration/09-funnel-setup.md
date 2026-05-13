# MIG-001 T10 — Tailscale Funnel + TransportSecuritySettings.allowed_hosts patch

After T9 (`systemd unit running`), the MCP server is listening on `127.0.0.1:8767`. To expose it to `claude.ai` we publish via Tailscale Funnel and add the SER10 hostname to the server's Host-header whitelist.

## Prerequisites

- Tailscale admin (https://admin.tailscale.com) has **HTTPS Certificates** + **Funnel** enabled for `ser10-tha-1`. If not — go enable now (one toggle in the admin UI for each).
- `cascade-browser.service` is active (T9 done).

## A. Patch `allowed_hosts` in `mcp-server/src/server.py`

The current production `allowed_hosts` (from MSI commit `27b6e94`) covers `desktop-4sl95n4.tail80c5d4.ts.net` but NOT `ser10-tha-1.tail80c5d4.ts.net`. The server returns `421 Invalid Host header` for any Host it doesn't know — this is the DNS-rebinding defence.

Edit `mcp-server/src/server.py`, locate `ALLOWED_HOSTS = [`, and append:

```python
ALLOWED_HOSTS = [
    '127.0.0.1',
    f'127.0.0.1:{MCP_PORT}',
    'localhost',
    f'localhost:{MCP_PORT}',
    'desktop-4sl95n4.tail80c5d4.ts.net',
    f'desktop-4sl95n4.tail80c5d4.ts.net:{MCP_PORT}',
    'ser10-tha-1.tail80c5d4.ts.net',                         # NEW
    f'ser10-tha-1.tail80c5d4.ts.net:{MCP_PORT}',             # NEW
]
```

Keep `desktop-4sl95n4.*` entries — MSI is the backup peer.

Commit + push:

```bash
cd ~/projects/cascade-browser
git checkout -b mig-001-allowed-hosts
git add mcp-server/src/server.py
git commit -m "BR-105 followup: ser10-tha-1.tail80c5d4.ts.net in allowed_hosts"
git push -u origin mig-001-allowed-hosts
# Open a PR or merge to main directly:
git checkout main && git merge --ff-only mig-001-allowed-hosts && git push origin main
```

Restart the service so the patched code is in memory:

```bash
sudo systemctl restart cascade-browser.service
sleep 2
sudo systemctl status cascade-browser.service --no-pager | head -5
```

## B. Start the Funnel

WSL has no Tailscale daemon — use `tailscale.exe` from the Windows side. The fastest way from WSL:

```bash
cmd.exe /c "tailscale.exe funnel --bg 8767"
```

Or from Windows admin PowerShell directly:

```powershell
tailscale.exe funnel --bg 8767
tailscale.exe funnel status
```

Expected output (after ~10-30 seconds of cert provisioning):

```
Funnel on:
    https://ser10-tha-1.tail80c5d4.ts.net
        |-- / proxy http://127.0.0.1:8767
```

**Cert provisioning timeout:** if more than 60 seconds pass without "Funnel on" appearing, escalate — there was a similar issue on MSI Stage 1. Check Tailscale admin to confirm HTTPS Certificates + Funnel are toggled on for this device.

## C. End-to-end verification

Pull the token, hit the Funnel URL:

```bash
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
FURL=https://ser10-tha-1.tail80c5d4.ts.net/mcp

# 401 without Bearer
curl -s -o /dev/null -w "no-bearer: HTTP %{http_code}\n" -X POST $FURL \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{}'

# 200 with valid Bearer + initialize
curl -s -o /tmp/funnel-init.txt -w "init: HTTP %{http_code}\n" -X POST $FURL \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke","version":"0.1"}}}'
head -c 200 /tmp/funnel-init.txt
```

Both must look like:
```
no-bearer: HTTP 401
init: HTTP 200
```

A 421 means the Host whitelist still doesn't include `ser10-tha-1.tail80c5d4.ts.net` — re-check the edit and that the service restarted.

## D. Replace claude.ai Connector URL

In Claude.ai Settings → Connectors, update the cascade-browser entry:

- URL: `https://ser10-tha-1.tail80c5d4.ts.net/mcp`
- Bearer: `<token from ~/.cascade-browser/bearer.txt>`

(Optional — keep MSI Connector as backup with its own token while transition is in flight.)

## Stop conditions (escalate)

| Symptom | Likely cause | Action |
|---|---|---|
| `Funnel on:` never appears | Cert provisioning stalled | Re-check Tailscale admin toggles; wait 90s; if still stuck, `tailscale.exe funnel off 8767` + retry |
| 421 Invalid Host header | `allowed_hosts` patch missing or service not restarted | Re-check Patch A; `systemctl restart cascade-browser.service` |
| 502 Bad Gateway from Funnel | local 8767 not listening | `systemctl status cascade-browser.service`; `journalctl -u cascade-browser -n 50` |
| 401 even with correct Bearer | wrong file copied? | `wc -c ~/.cascade-browser/bearer.txt` — must be 43-44 bytes |
