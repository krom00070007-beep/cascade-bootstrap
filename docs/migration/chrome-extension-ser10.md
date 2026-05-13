# MIG-001 T13 — Chrome extension setup on SER10

The cascade-browser Chrome extension is loaded as an **unpacked extension** in Developer Mode. Each Chrome install gets its own extension ID, so SER10 will have an ID different from MSI's `jlfceiffblminljolfeabnegmcdpdndg`. The Native Messaging Host manifest must be updated to whitelist the new ID.

## Prerequisites

- T8 done (cascade-browser repo cloned to `~/projects/cascade-browser`)
- Chrome installed on SER10 Windows
- The Native Host binary `cascade_browser_host.exe` either:
  - copied from MSI (`%LOCALAPPDATA%\cascade-browser\`), OR
  - rebuilt locally from `native-host/src/cascade_browser_host.py` via PyInstaller (see `native-host/build/`)

## Steps

### 1. Copy extension into a Win-readable path

WSL2 lets Chrome (Windows-side) read `\\wsl$\Ubuntu-24.04\home\usersstas\projects\cascade-browser\extension`, but Chrome's "Load unpacked" dialog has friction with UNC paths. Easier:

```bash
mkdir -p /mnt/c/Users/krom0/cascade-browser-ext
rsync -av --delete ~/projects/cascade-browser/extension/ /mnt/c/Users/krom0/cascade-browser-ext/
```

Re-run `rsync` whenever the extension changes.

### 2. Load unpacked in Chrome

1. `chrome://extensions/` → toggle **Developer mode** on (top right)
2. Click **Load unpacked**
3. Pick `C:\Users\krom0\cascade-browser-ext`
4. Extension loads. **Copy the ID** from the card (looks like 32 lowercase letters).

### 3. Update the Native Messaging Host manifest

The host manifest at `%LOCALAPPDATA%\cascade-browser\com.cascade.browser.json` whitelists which extensions can spawn the host. Update it:

```powershell
$manifest = "$env:LOCALAPPDATA\cascade-browser\com.cascade.browser.json"
# Open in notepad or PowerShell:
notepad $manifest
```

Edit the `allowed_origins` array:

```json
{
  "name": "com.cascade.browser",
  "description": "Cascade Browser native host",
  "path": "C:\\Users\\krom0\\AppData\\Local\\cascade-browser\\cascade_browser_host.exe",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://<PASTE_SER10_EXTENSION_ID>/"
  ]
}
```

Optional: keep MSI's ID in the array if the same host should serve both — but each machine has its own host install, so usually a single ID per machine.

### 4. Register the manifest under Chrome's registry key

```powershell
reg add "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.cascade.browser" /ve `
    /t REG_SZ /d "$env:LOCALAPPDATA\cascade-browser\com.cascade.browser.json" /f
```

### 5. Re-test the bridge

Chrome → `chrome://extensions/` → click **service worker** on the cascade-browser card to open DevTools for the SW. You should see:

```
[cascade-browser:SW-diag] DIAGNOSTIC START
[cascade-browser:SW-diag] attempting connectNative from service worker
[cascade-browser:SW-diag] port created: Object
[cascade-browser:SW-diag] hello-from-sw posted successfully
[cascade-browser:SW-diag] MSG from host: {"type":"handshake_ack","server_version":"..."}
```

`handshake_ack` arriving = SER10 Chrome ↔ Native Host ↔ MCP bridge is alive.

### 6. Smoke-test from WSL with `browser_ping`

```bash
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
# initialize → notifications/initialized → tools/call browser_ping
# (see ../09-funnel-setup.md section C for the full curl sequence)
```

`latency_ms` should be in single-digit ms locally (and ~30-80ms via Funnel from outside the LAN).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `connectNative` fails immediately | Manifest path wrong / registry entry wrong | Re-run reg add; check `%LOCALAPPDATA%\cascade-browser\com.cascade.browser.json` exists |
| SW sees port but no messages | Native Host crashed silently | Check `%LOCALAPPDATA%\cascade-browser\host.log` |
| `Specified native messaging host not found.` | Registry HKCU vs HKLM mismatch | We use HKCU. Re-check the reg add command — `/f` should have forced it |
| MSI extension ID instead of new one | `allowed_origins` not updated | Edit manifest, restart Chrome |
| MCP server gets nothing | Bridge :8768 not reachable | `ss -tlnp \| grep 8768` in WSL; `tailscale.exe ip -4` (TCP loopback in WSL is shared with Win in WSL2 mirrored networking — confirm `.wslconfig` has `networkingMode=mirrored` if needed) |
