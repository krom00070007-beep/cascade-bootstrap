---
name: cascade-browser-troubleshooting
description: Decision tree для типичных проблем cascade-browser — MCP HTTP codes (401/421/406/502), bridge timeout, extension SW lifecycle (dies after 30s idle), Native Host respawn, JS-rendered DOM не видится через WebFetch, DDoS-Guard блокирует Mozilla UA, Chrome Native Messaging registry path issues. Применяется при любых отказах cascade-browser, перед эскалацией к Stanislav, при debug bridge handshake.
---

# cascade-browser — Troubleshooting

_Версия 1.0 от 2026-05-14. На основе BR-104 step 3 + BR-105 Phase 3 опыта._

## Quick decision tree

```
cascade-browser tool вернул ошибку?
├── HTTP status?
│   ├── 401 → [[cascade-browser-auth-funnel]] — Bearer не совпадает
│   ├── 421 → Host whitelist; добавить hostname в ALLOWED_HOSTS
│   ├── 406 → curl нет `Accept: application/json, text/event-stream` header (Streamable HTTP требует)
│   ├── 502 → локальный :8767 не слушает (systemctl status cascade-browser.service)
│   └── 200 + JSON-RPC ошибка → MCP layer, см. ниже
├── tool вернул `ok: false`?
│   ├── error="bridge_unavailable" → Native Host не подключён к TCP:8768
│   ├── error="timeout" → запрос дошёл до SW но SW не ответил за 10s
│   ├── error="selector_not_found" → CSS selector неверен / element ещё не отрендерился
│   ├── error="invalid_url" → http/https only
│   ├── error="password_field_forbidden" → input[type=password], blocked by design
│   ├── error="invalid_format" → screenshot format ≠ jpeg/png
│   └── error="handler_error" → SW caught exception, см. extension DevTools
└── Не вижу ответа вообще → curl hangs?
    └── См. секцию "Bridge handshake failures"
```

## Symptom: 401 Authorization required

**Текст:** `{"ok": false, "error": "auth_required", "message": "Missing Authorization header"}`

**Причина:** нет `Authorization: Bearer <token>` header.

**Fix:**

```bash
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
curl ... -H "Authorization: Bearer $TOKEN" ...
```

Если уже передаёшь — `error="auth_invalid"` означает токен не совпадает с тем что в `~/.cascade-browser/bearer.txt`. Возможно server был перезапущен с новым токеном.

## Symptom: 421 Invalid Host header

**Текст:** `Invalid Host header`

**Причина:** `TransportSecuritySettings.allowed_hosts` не содержит этот hostname.

**Fix:**

1. Найди какой hostname в Host header:
   ```bash
   curl -v ... 2>&1 | /bin/grep -i "> host:"
   ```
2. Добавь в `ALLOWED_HOSTS` в `server.py`:
   ```python
   ALLOWED_HOSTS = [
       ...,
       '<new-hostname>.tail80c5d4.ts.net',
       '<new-hostname>.tail80c5d4.ts.net:8767',
   ]
   ```
3. Restart service:
   ```bash
   sudo systemctl restart cascade-browser.service
   # or: pkill -f run-server.sh && nohup ./run-server.sh > /tmp/cascade-browser.log 2>&1 &
   ```

## Symptom: 406 Not Acceptable

**Причина:** Streamable HTTP transport требует `Accept: application/json, text/event-stream` header. Default curl даёт `Accept: */*` — не подходит.

**Fix:** добавить header в curl:

```bash
curl ... -H "Accept: application/json, text/event-stream" ...
```

## Symptom: 502 Bad Gateway / curl hangs

**Причина:** локальный сервис на :8767 не слушает.

**Diagnose:**

```bash
# Process check
pgrep -af "python3 src/server.py"
systemctl status cascade-browser.service

# Port check
ss -tlnp 2>/dev/null | /bin/grep -E ':876[78]'

# Log check
tail -20 /tmp/cascade-browser.log  # nohup-форма
journalctl -u cascade-browser -n 30 --no-pager  # systemd-форма
```

**Fix:**

```bash
# Если nohup-форма:
cd ~/projects/cascade-browser/mcp-server
nohup ./run-server.sh > /tmp/cascade-browser.log 2>&1 &

# Если systemd:
sudo systemctl restart cascade-browser.service
sudo systemctl status cascade-browser.service
```

## Symptom: tool returns `bridge_unavailable`

**Текст:** `{"ok": false, "error": "bridge_unavailable", "broke_at": "mcp→tcp", "message": "No Native Host connected — cannot send request"}`

**Причина:** Native Host (Windows-side `.exe`) НЕ подключён к TCP:8768.

**Diagnose:**

1. На WSL: проверь bridge log:
   ```bash
   /bin/grep -E "Native Host (connected|disconnected)" /tmp/cascade-browser.log | tail -10
   ```
   Должны быть recent `Native Host connected from 127.0.0.1:NNNNN`. Если только `disconnected (EOF)` — ext умер.

2. Chrome side: открой chrome://extensions/ → cascade-browser → click **service worker** → DevTools console.
   Ищи:
   - `[SW-diag] DIAGNOSTIC START`
   - `[SW-diag] hello-from-sw posted successfully`
   - `[SW-diag] MSG from host: {"type":"handshake_ack",...}`

   Если последняя строка не `handshake_ack` — bridge не работает.

3. Windows side: открой `%LOCALAPPDATA%\cascade-browser\host.log`:
   - "Connection refused on 127.0.0.1:8768" → MCP server не запущен
   - "TCP connected to MCP server" + no further activity → bridge OK, проблема в SW

**Fix attempts (в порядке):**

1. Chrome → chrome://extensions/ → cascade-browser → **Reload** button (revive SW)
2. Если SW не оживает — close Chrome полностью + reopen
3. Если Native Host не respawn — restart Chrome полностью
4. Если всё ещё нет — проверь registry: `reg query "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.cascade.browser"` (should return `(Default) REG_SZ "C:\Users\krom0\AppData\Local\cascade-browser\com.cascade.browser.json"`)

## Symptom: tool returns `timeout`

**Текст:** `{"ok": false, "error": "timeout", "broke_at": "mcp→...→extension"}`

**Причина:** MCP отправил frame Native Host → TCP → но SW не вернул response за 10s.

**Possible causes:**

1. SW крашнулся посередине handler'а — см. chrome://extensions/ → service worker → DevTools для exception
2. Tab requested не существует (`tab_id` invalid) — handler могут зависнуть на `chrome.tabs.get(invalid_id)`
3. JS injection blocked — `chrome.scripting.executeScript` на `chrome://` / `chrome-extension://` / некоторых sites блокируется
4. `wait_ms` timeout слишком короткий — element не успевает появиться

**Fix:**

- Увеличь `wait_ms` для click/type (10000ms вместо 5000)
- Проверь selector через manual DevTools `document.querySelector("<selector>")` на target page
- Если page имеет CSP `script-src` strict — chrome.scripting может failed

## Symptom: SW dies after ~30 seconds idle

**Причина:** MV3 ограничение — service worker завершается после idle. Native Messaging port умирает с ним.

**Fix:** **offscreen document** удерживает persistent port (см. `extension/offscreen/`). Default наша implementation использует SW-side с auto-respawn через `setTimeout`.

Это **известное ограничение** MV3, не баг. Когда tool вызывается — SW reactivates (~ 50-100 ms), Native Host respawnится Chrome'ом, handshake → response. RTT в этом случае ~500-1500 ms (vs 8-50 ms когда port жив).

## Symptom: DDoS-Guard / Cloudflare блокирует curl Mozilla UA

**Текст:** `<title>403</title>` или JS challenge page вместо контента.

**Причина:** target site (например iflora-spb.ru) защищён DDoS-Guard / Cloudflare → блокирует generic browsers.

**Fix для cascade-browser context:**

- НЕ относится к cascade-browser MCP (он использует наш реальный Chrome profile с правильным fingerprint)
- Если используешь curl / WebFetch на site с DDoS-Guard — используй YandexBot / Googlebot UA:
  ```bash
  curl -A "Mozilla/5.0 (compatible; YandexBot/3.0; +http://yandex.com/bots)" ...
  ```

DDoS-Guard whitelist'ит крупные поисковые боты, но не generic Mozilla.

## Symptom: extension показывает "Service Worker (inactive)"

**Причина:** SW спит (нормально для MV3 idle).

**Fix:** click "Service Worker" link в chrome://extensions → откроется DevTools → SW автоматически пробудится.

Если хочешь forcefully reload extension — click 🔄 Reload button на extension card.

## Symptom: Bridge handshake failures

**Sequence что должно произойти при working bridge:**

```
[SW-diag] DIAGNOSTIC START
[SW-diag] manifest permissions: [...]
[SW-diag] attempting connectNative from service worker
[SW-diag] port created: Object  
[SW-diag] hello-from-sw posted successfully
[SW-diag] MSG from host: {"type":"handshake_ack","server_version":"..."}    ← КРИТИЧНО
```

Если последней строки НЕТ — bridge не работает. Возможные причины:

1. **Native Host не запустился** — обычно из-за registry path / executable path mismatch
2. **MCP server не слушает на :8768** — `ss -tlnp | grep 8768`
3. **MCP server слушает но не отвечает на handshake** — проверь bridge_listener.py logic

**Diagnose:**

```bash
# Windows-side: log Native Host
type %LOCALAPPDATA%\cascade-browser\host.log

# WSL-side: log MCP server (recent)
tail -50 /tmp/cascade-browser.log | grep -E "Native Host|handshake"
```

## Symptom: JS-rendered DOM не виден через WebFetch

**Не cascade-browser problem.** WebFetch использует server-side render only. Tilda / SPA сайты с client-side render — пустые в WebFetch responses.

**Fix:** используй **cascade-browser MCP** (он использует реальный Chrome — видит JS-rendered DOM):

```bash
# Через MCP
... browser_navigate '{"url":"https://target.com","tab_id":"new"}'
sleep 2  # wait for JS render
... browser_read_active_tab '{"mode":"text"}'
```

## Symptom: Chrome Native Messaging Host not found

**Registry path:** `HKCU\Software\Google\Chrome\NativeMessagingHosts\com.cascade.browser` `(Default)`

**Fix:**

```powershell
reg add "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.cascade.browser" /ve `
    /t REG_SZ /d "$env:LOCALAPPDATA\cascade-browser\com.cascade.browser.json" /f
```

И проверь что `%LOCALAPPDATA%\cascade-browser\com.cascade.browser.json` существует и содержит правильный `path` к `.exe`.

## Cascade-specific escalation signs

| Symptom | Escalation level |
|---|---|
| `Funnel cert provisioning > 60s` | См. [[cascade-tailscale-troubleshooting]] |
| Bridge log shows `Native Host disconnected (EOF)` every 30s | SW lifecycle issue (см. выше) |
| `Permission denied` от Chrome native messaging | Manifest `allowed_origins` не содержит current Extension ID |
| Кривое `extension-key.pem` → ID меняется при reload | Reuse stable key file |
| `host.log` пустой / отсутствует | Native Host не запустился — registry path issue |

## Cross-refs

- [[cascade-browser-overview]] — общая карта layers
- [[cascade-browser-mcp-chrome]] — deep dive в архитектуру layer-by-layer
- [[cascade-tailscale-troubleshooting]] — WSL2 networking, MagicDNS, cert provisioning
- [[cascade-tailscale-funnel]] — Funnel CLI и prerequisites
