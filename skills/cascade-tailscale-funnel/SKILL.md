---
name: cascade-tailscale-funnel
description: Настройка Tailscale Funnel для публикации Cascade MCP-сервисов (cascade-browser, cascade-mcp state) на интернет через https://<hostname>.tail80c5d4.ts.net. Включает prerequisites (HTTPS Certificates toggle), CLI команды (--bg/status/off/reset), patch для TransportSecuritySettings.allowed_hosts, port-forward (Win netsh portproxy для WSL → Win сценария), troubleshooting cert provisioning.
---

# Cascade × Tailscale Funnel

## Когда применять

- Публикация cascade-browser MCP на интернет (для claude.ai connectors с мобильного / удалённо)
- Публикация cascade-state MCP `get_cascade_state` на opus (уже работает)
- Любой новый сервис в Cascade, который должен быть доступен по HTTPS без VPN-входа

## Prerequisites (без них Funnel не запустится)

1. **Tailscale ≥ v1.38.3** на ноде — проверить `tailscale.exe --version`
2. **MagicDNS включён** в admin.tailscale.com → DNS → "Use MagicDNS" ON
3. **HTTPS Certificates включены** в admin.tailscale.com → DNS → "HTTPS Certificates" ON (one-time toggle, действует на весь tailnet)
4. **Funnel grant** в policy file `nodeAttrs` (см. [[cascade-tailscale-acl]] — обычно `autogroup:member` имеет grant по умолчанию)
5. **Per-device Funnel toggle** в admin.tailscale.com → Machines → click device → "Funnel" toggle ON (или через ACL `nodeAttrs`)
6. **Сервис слушает локально** на 127.0.0.1 (или 0.0.0.0 если другая стратегия) на одном из portов 443 / 8443 / 10000

## Funnel CLI

```bash
# Включить foreground (для теста, держит терминал):
tailscale.exe funnel 8767

# Включить background (рекомендуется):
tailscale.exe funnel --bg 8767

# Проверить статус:
tailscale.exe funnel status
# Ожидаемое:
#   Funnel on:
#       https://<hostname>.tail80c5d4.ts.net
#           |-- / proxy http://127.0.0.1:8767

# Выключить (для конкретного порта):
tailscale.exe funnel 8767 off

# Сбросить ВСЕ Funnel конфиги на ноде:
tailscale.exe funnel reset
```

## Cascade-специфичные правки

### 1. WSL → Windows port-forward (только если сервер живёт в WSL1)

WSL1 шарит loopback с Windows — `netsh portproxy` НЕ нужен на WSL1.

WSL2 шарит loopback только если включён `networkingMode=mirrored` в `.wslconfig`. Если этого нет:

📋 PowerShell **admin**:

```
netsh interface portproxy add v4tov4 listenport=8767 listenaddress=0.0.0.0 connectport=8767 connectaddress=127.0.0.1
```

Проверить правила:

```
netsh interface portproxy show v4tov4
```

### 2. TransportSecuritySettings.allowed_hosts в server.py (защита от DNS rebinding)

После старта Funnel — внутрь приходит Host header `<hostname>.tail80c5d4.ts.net`. Если он НЕ в `allowed_hosts` — сервер вернёт 421.

В `cascade-browser/mcp-server/src/server.py`:

```python
ALLOWED_HOSTS = [
    '127.0.0.1', f'127.0.0.1:{MCP_PORT}',
    'localhost', f'localhost:{MCP_PORT}',
    'desktop-4sl95n4.tail80c5d4.ts.net', 'desktop-4sl95n4.tail80c5d4.ts.net:8767',  # MSI
    'ser10-tha-1.tail80c5d4.ts.net', 'ser10-tha-1.tail80c5d4.ts.net:8767',          # SER10
    # add new hostnames here when adding peers
]

mcp = FastMCP('cascade-browser',
              host=MCP_HOST, port=MCP_PORT,
              transport_security=TransportSecuritySettings(
                  enable_dns_rebinding_protection=True,
                  allowed_hosts=ALLOWED_HOSTS,
              ))
```

После правки — restart сервиса (`sudo systemctl restart cascade-browser.service` или `pkill -f run-server.sh && nohup ./run-server.sh > /tmp/cascade-browser.log 2>&1 &`).

### 3. Bearer auth (ОБЯЗАТЕЛЕН поверх Funnel)

Funnel = публичный URL. Без auth любой может вызвать tools. См. `cascade-browser/mcp-server/src/auth.py` — `BearerAuthMiddleware` уже стандарт, генерит токен в `~/.cascade-browser/bearer.txt` (chmod 600) при первом старте.

## Конфиг по умолчанию для Cascade-сервисов

| Сервис | Host | Port | Bearer | Allowed hosts включают |
|---|---|---|---|---|
| cascade-browser (SER10) | `ser10-tha-1.tail80c5d4.ts.net` | 8767 | yes (`~/.cascade-browser/bearer.txt`) | `127.0.0.1`, `ser10-tha-1...`, иногда `desktop-4sl95n4...` (для backup) |
| cascade-browser (MSI) | `desktop-4sl95n4.tail80c5d4.ts.net` | 8767 | yes | `127.0.0.1`, `desktop-4sl95n4...` |
| cascade-mcp state (opus) | `opus-cwr-bkk.tail80c5d4.ts.net` | (см. /opt/cascade-mcp/server.py) | yes | `127.0.0.1`, `opus-cwr-bkk...` |

## Стоп-условия (escalate)

- `Funnel on:` не появляется в `tailscale.exe funnel status` за 60+ секунд → возможно cert provisioning стоит. Проверить admin.tailscale.com → HTTPS Certificates ON; toggle Funnel per-device ON. Если давно был провизионинг — Let's Encrypt может rate-limit (34 ч на ту же ноду).
- `421 Invalid Host header` на запросе — `allowed_hosts` не содержит этот hostname.
- `502 Bad Gateway` — локальный сервис на :8767 не слушает. `systemctl status cascade-browser.service`.
- `Funnel relay servers` появляются в `tailscale.exe status` как peers — это нормально, не пугайся.

## Cleanup на удалённой ноде

```bash
tailscale.exe funnel reset     # снять все Funnel конфиги на ноде
tailscale.exe funnel status    # должно быть пусто
```

## Bearer token rotation (важно — отсутствовало в v1.0)

### Когда менять токен

| Триггер | Срочность |
|---|---|
| Telegram message с токеном случайно forward'нут | 🔴 немедленно |
| Подозрение что токен попал в browser history / clipboard manager / dev tools | 🔴 немедленно |
| Передача ноды другому человеку / продажа железа | 🔴 перед передачей |
| Регулярная ротация раз в квартал (best practice) | 🟢 раз в Q |
| После увольнения сотрудника с доступом (если будет применимо) | 🔴 немедленно |
| Bug bounty / external pentest начат | 🟡 в начале программы |

### Rotation script (recommended ~/bin/cascade-bearer-rotate)

```bash
#!/bin/bash
# ~/bin/cascade-bearer-rotate — generate new Bearer + restart server + tg-notify
set -e
NEW=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
BAK=~/.cascade-browser/bearer.txt.bak.$(date +%s)
[ -f ~/.cascade-browser/bearer.txt ] && mv ~/.cascade-browser/bearer.txt "$BAK"
echo "$NEW" > ~/.cascade-browser/bearer.txt
chmod 600 ~/.cascade-browser/bearer.txt

# Restart cascade-browser service (или nohup-форму)
if systemctl --user --quiet is-active cascade-browser.service 2>/dev/null; then
    sudo systemctl restart cascade-browser.service
elif pgrep -f run-server.sh >/dev/null; then
    pkill -f "python3 src/server.py" || true; sleep 1
    cd ~/projects/cascade-browser/mcp-server && nohup ./run-server.sh > /tmp/cascade-browser.log 2>&1 &
fi
sleep 2

# Test new token
TOKEN="$NEW"
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8767/mcp \
       -H "Authorization: Bearer $TOKEN" \
       -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
       -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"r","version":"0"}}}')
[ "$code" = "200" ] || { echo "FATAL: new token not accepted ($code). Rollback: cp $BAK ~/.cascade-browser/bearer.txt"; exit 1; }

# Notify Telegram (только превью токена — full отправляем отдельно по запросу)
tg-send-text "cascade-browser Bearer ROTATED $(date +%Y-%m-%d_%H:%M): ${NEW:0:6}...${NEW: -4} (len=${#NEW}). Use 'tg-saved-search rotation' для full token if needed."
echo "Rotation done. Backup: $BAK. New: ${NEW:0:6}...${NEW: -4}"
```

### Post-rotation tasks

1. Обновить claude.ai → Settings → Connectors → cascade-browser entry: paste new Bearer
2. Если SER10 + MSI оба активны как backup peers — оба токена нужно менять (они разные)
3. Backup-файл `bearer.txt.bak.*` удалить через 24-48 часов (когда уверен что новый OK)

### NEVER

- Не commit'ить Bearer в git
- Не отправлять в Telegram **на чужие** контакты (только Saved Messages)
- Не показывать в screen-share / public terminal recording
- Не хранить в `state/*.md` файлах
