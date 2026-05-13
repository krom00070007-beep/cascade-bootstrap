---
name: cascade-browser-auth-funnel
description: Bearer auth + Tailscale Funnel + Host whitelist для cascade-browser MCP-server (BR-104 step 3). Включает FastMCP transport_security configuration, BearerAuthMiddleware pattern (constant-time compare), Windows netsh portproxy для WSL2, Funnel CLI команды, claude.ai connector setup, rotation procedure. Применяется при настройке нового deployment (SER10, MSI rebuild), при изменении hostname, при ротации Bearer токена.
---

# cascade-browser — Auth + Funnel layer

_Версия 1.0 от 2026-05-14. Базируется на commit `27b6e94` (BR-104 step 3)._

## Stack

```
claude.ai consumer
   ↓ HTTPS Authorization: Bearer <43-char token>
   ↓ Tailscale Funnel (public TLS termination, edge: Warsaw/Sao Paulo/...)
   ↓ Win netsh portproxy 0.0.0.0:8767 → 127.0.0.1:8767   [if WSL2 без mirrored mode]
   ↓ Starlette ASGI app, BearerAuthMiddleware (BaseHTTPMiddleware) — 401 if not match
   ↓ FastMCP(transport_security=TransportSecuritySettings(allowed_hosts=[...])) — 421 if Host wrong
   ↓ FastMCP @mcp.tool() handlers
   ↓ bridge_listener.py + Native Host + Chrome ext
```

3 layer защиты на HTTP уровне:
1. **Tailscale Funnel** — TLS только (public exposure)
2. **Bearer middleware** — autorization
3. **Host whitelist** — DNS rebinding защита

## Setup на новой ноде

### Step 1 — `auth.py` module

`mcp-server/src/auth.py` (создан в BR-104 step 3 commit):

```python
import logging, os, secrets, stat
from pathlib import Path
from typing import Optional
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

DEFAULT_BEARER_FILE = Path.home() / '.cascade-browser' / 'bearer.txt'
TOKEN_BYTES = 32

def _bearer_path() -> Path:
    override = os.environ.get('CASCADE_BROWSER_BEARER_FILE')
    return Path(override) if override else DEFAULT_BEARER_FILE

def load_or_create_bearer_token(path: Optional[Path] = None) -> str:
    path = path or _bearer_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.exists():
        token = path.read_text(encoding='utf-8').strip()
        if token:
            cur = stat.S_IMODE(path.stat().st_mode)
            if cur != 0o600:
                os.chmod(path, 0o600)
            return token
    token = secrets.token_urlsafe(TOKEN_BYTES)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(token, encoding='utf-8')
    os.chmod(tmp, 0o600)
    tmp.replace(path)
    return token

class BearerAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, token: str):
        super().__init__(app)
        if not token:
            raise ValueError('BearerAuthMiddleware requires non-empty token')
        self._token = token

    async def dispatch(self, request: Request, call_next):
        header = request.headers.get('authorization') or request.headers.get('Authorization')
        if not header:
            return JSONResponse({'ok': False, 'error': 'auth_required',
                                 'message': 'Missing Authorization header'}, status_code=401)
        parts = header.split(None, 1)
        if len(parts) != 2 or parts[0].lower() != 'bearer':
            return JSONResponse({'ok': False, 'error': 'auth_scheme',
                                 'message': "Authorization scheme must be 'Bearer'"}, status_code=401)
        presented = parts[1].strip()
        if not secrets.compare_digest(presented, self._token):
            return JSONResponse({'ok': False, 'error': 'auth_invalid',
                                 'message': 'Bearer token does not match'}, status_code=401)
        return await call_next(request)
```

Ключевое: **`secrets.compare_digest`** — constant-time compare (защита от timing oracles).

### Step 2 — FastMCP + TransportSecuritySettings в `server.py`

```python
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from auth import BearerAuthMiddleware, load_or_create_bearer_token

ALLOWED_HOSTS = [
    '127.0.0.1', f'127.0.0.1:{MCP_PORT}',
    'localhost', f'localhost:{MCP_PORT}',
    '<this-hostname>.tail80c5d4.ts.net',
    f'<this-hostname>.tail80c5d4.ts.net:{MCP_PORT}',
    # add OTHER nodes that may be Funnel'd to this server (rare)
]

mcp = FastMCP(
    'cascade-browser',
    host=MCP_HOST, port=MCP_PORT,
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=ALLOWED_HOSTS,
    ),
)

# В main():
bearer_token = load_or_create_bearer_token()
app = mcp.streamable_http_app()
app.add_middleware(BearerAuthMiddleware, token=bearer_token)
config = uvicorn.Config(app, host=MCP_HOST, port=MCP_PORT, log_level='info', access_log=False)
http_server = uvicorn.Server(config)
await http_server.serve()
```

`enable_dns_rebinding_protection=True` + `allowed_hosts` — Host header проверяется на каждый запрос. Mismatch → 421.

### Step 3 — Windows netsh portproxy

WSL1 (MSI) шарит loopback с Windows → НЕ нужен portproxy если оба процесса на 127.0.0.1.

WSL2 (SER10 после 15.05) — если в `.wslconfig` НЕТ `networkingMode=mirrored` → нужен portproxy.

PowerShell **admin**:

```powershell
# Открыть Funnel доступ на Win :8767 → проксить в loopback (где WSL server слушает)
netsh interface portproxy add v4tov4 listenport=8767 listenaddress=0.0.0.0 connectport=8767 connectaddress=127.0.0.1

# Проверить:
netsh interface portproxy show v4tov4
```

Если используется WSL2 с mirrored — portproxy НЕ нужен (loopback shared).

### Step 4 — Tailscale Funnel

**Prerequisites** (admin.tailscale.com):
- DNS → "Use MagicDNS" ON
- DNS → "HTTPS Certificates" ON
- Machines → выбрать эту ноду → "Funnel" ON
- ACL `nodeAttrs` — `funnel` attribute для этой ноды (default `autogroup:member` имеет grant)

**Start Funnel** (PowerShell admin или WSL через `cmd.exe /c`):

```bash
cmd.exe /c "tailscale.exe funnel --bg 8767"
cmd.exe /c "tailscale.exe funnel status"
# Ожидаемое:
# Funnel on:
#     https://<hostname>.tail80c5d4.ts.net
#         |-- / proxy http://127.0.0.1:8767
```

Cert provisioning: 10-60 секунд. Если >60s → escalate (см. [[cascade-tailscale-troubleshooting]]).

### Step 5 — claude.ai Connector setup

1. claude.ai → Settings → Connectors → Add Connector
2. Name: `cascade-browser-msi` (или `-ser10` в зависимости от ноды)
3. URL: `https://<hostname>.tail80c5d4.ts.net/mcp`
4. Authorization → Bearer Token → paste `cat ~/.cascade-browser/bearer.txt`
5. Save + Test connection → должно показать список 10 tools

## End-to-end verification

```bash
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
URL="https://<hostname>.tail80c5d4.ts.net/mcp"

# Test 1: 401 без Bearer (защита работает)
curl -s -o /dev/null -w "no-bearer: %{http_code}\n" -X POST "$URL" \
    -H "Content-Type: application/json" -d '{}'
# expect: 401

# Test 2: 200 с Bearer + initialize
curl -s -o /tmp/init.txt -w "init: %{http_code}\n" -X POST "$URL" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{
        "protocolVersion":"2025-03-26","capabilities":{},
        "clientInfo":{"name":"verify","version":"0.1"}}}'
# expect: 200

# Test 3: 421 на spoofed Host (DNS rebinding защита)
curl -s -o /dev/null -w "spoof-host: %{http_code}\n" -X POST "$URL" \
    -H "Host: evil.example.com" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d '{}'
# expect: 421 (allowed_hosts whitelist прокинул)
```

Если все 3 теста зелёные — auth + Funnel + Host whitelist работают как задумано.

## Bearer rotation (regular hygiene)

См. [[cascade-tailscale-funnel]] секция "Bearer token rotation" для полного script + triggers + Telegram-нотификация.

TLDR;

```bash
NEW=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
mv ~/.cascade-browser/bearer.txt ~/.cascade-browser/bearer.txt.bak.$(date +%s)
echo "$NEW" > ~/.cascade-browser/bearer.txt
chmod 600 ~/.cascade-browser/bearer.txt
sudo systemctl restart cascade-browser.service   # или kill+nohup
```

Затем обновить claude.ai Connector с новым токеном.

## Adding a new node hostname

Когда добавляешь SER10 (или другую ноду), Bearer-protected Funnel:

1. **Patch `server.py` `ALLOWED_HOSTS`** — добавить hostname с/без порта:
   ```python
   ALLOWED_HOSTS = [
       ...,
       'ser10-tha-1.tail80c5d4.ts.net',
       'ser10-tha-1.tail80c5d4.ts.net:8767',
   ]
   ```
2. Restart service. (systemctl restart cascade-browser.service)
3. На новой ноде — `bearer.txt` генерится автоматически при первом запуске сервера (НЕ копировать с другой ноды — новый токен)
4. На admin — toggle Funnel ON для новой ноды
5. На admin — toggle HTTPS Certificates ON (если ещё не для tailnet)
6. На новой ноде — `tailscale.exe funnel --bg 8767`
7. Add claude.ai Connector с новым URL+Bearer (если consumer там)

## Cross-refs

- [[cascade-browser-overview]] — общая карта
- [[cascade-tailscale-funnel]] — Funnel CLI + prerequisites + общие Cascade паттерны
- [[cascade-tailscale-troubleshooting]] — WSL2 mirrored networking, 421 host, cert provisioning
- [[cascade-browser-safety]] — Bearer + allowed_hosts как часть general safety
