---
name: cascade-browser-safety
description: Систематизированные safety guardrails cascade-browser — все защитные механизмы на уровнях MCP (Python) + extension (JS) + Native Host. Покрывает password field rejection, URL scheme whitelist (http/https only), close_tab host suffix whitelist (claude.ai/github.com/anthropic), text masking в логах, screenshot dataURI privacy, Bearer + Host header whitelist (см. auth-funnel), AGL обзорная карта. Применяется при review кода, при добавлении новых tools, при auditing.
---

# cascade-browser — Safety guarantees

_Версия 1.0 от 2026-05-14. После BR-105 Phase 3._

## Layers of defense

```
       Layer                          What it blocks
─────────────────────────────────────────────────────────────────────
1. Tailscale Funnel                   TLS encryption; no plaintext
2. BearerAuthMiddleware (HTTP)        Random tools/call to anonymous
3. TransportSecuritySettings (HTTP)   DNS rebinding (spoofed Host)
4. MCP tool validation (Python)       Bad URL scheme, empty selector, bad format
5. Extension SW guard (JS)            input[type=password], close_tab protected hosts
6. chrome.* API permissions           File system access (only with explicit perm)
7. user's Chrome profile              SOP, CSP, cookies scoped — usual browser security
```

7 layers. Атакующий должен пройти все 7 чтобы дотянуться к данным.

## Per-tool safety matrix

| Tool | Python layer (server.py / tools/*.py) | SW layer (service-worker.js) |
|---|---|---|
| `browser_ping` | — | — |
| `browser_read_active_tab` | mode = 'text'/'html'/'both' | — |
| `browser_read_all_tabs` | max_chars_per_tab cap | skip chrome:// / chrome-extension:// / edge:// / about: / devtools:// |
| `browser_bookmarks_delete_old` | days = positive int | — |
| `browser_navigate` | `urlparse(url).scheme in {'http','https'}` else `invalid_url` | `new URL(url).protocol` re-check; reject scheme |
| `browser_click` | selector non-empty string | poll 100ms, timeout `wait_ms`, return `selector_not_found` |
| `browser_type` | selector + text validation; **log only text_len, NOT raw text** | **`if (el.type==='password') return password_field_forbidden`**; check tagName input/textarea/contentEditable |
| `browser_screenshot` | format in {jpeg, png}; quality 1..100; full_page → `not_implemented` | dataURI not logged (только size_bytes + dimensions) |
| `browser_scroll` | direction in 4 values; amount regex `^(page\|half\|px=\d+)$` | — |
| `browser_close_tab` | tab_id required, force bool | `host = new URL(tab.url).host`; suffix-match `claude.ai`/`github.com`/`docs.anthropic.com`/`console.anthropic.com`; reject unless `force=true` |

## Detailed guards (с кодом)

### Guard 1: `browser_navigate` URL scheme

**Python (`tools/browser_navigate.py`):**

```python
from urllib.parse import urlparse

ALLOWED_SCHEMES = {'http', 'https'}

def _validate_url(url: str) -> tuple[bool, str]:
    parsed = urlparse(url)
    if parsed.scheme not in ALLOWED_SCHEMES:
        return False, f'scheme {parsed.scheme!r} not in {sorted(ALLOWED_SCHEMES)}'
    if not parsed.netloc:
        return False, 'missing host (netloc)'
    return True, ''

async def execute_browser_navigate(url, tab_id, bridge):
    ok, reason = _validate_url(url)
    if not ok:
        return {'ok': False, 'error': 'invalid_url', 'message': reason}
    ...
```

**SW (`service-worker.js`):**

```javascript
function validateNavUrl(url) {
  try {
    const u = new URL(url);
    if (!['http:', 'https:'].includes(u.protocol)) {
      return { ok: false, reason: `scheme ${u.protocol} not allowed` };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: `URL parse error: ${e.message}` };
  }
}
```

**Защищает от:**
- `file:///etc/passwd` — local file access
- `chrome://settings` — Chrome internals  
- `data:text/html,<script>...</script>` — local XSS
- `javascript:alert(1)` — direct script execution

### Guard 2: `browser_type` password fields

**SW (`handleBrowserType`):**

```javascript
if (el.type === 'password') {
  resolve({ found: true, password_field: true });
  return;
}
```

В Python — пропускает на extension; extension reject. Это **defence-in-depth** — даже если Python validation сломается, SW не пропустит.

**Также — text masking:**

Python `browser_type.py`:

```python
# MASKED log — do not print raw text
log.info(f'browser_type(selector={selector!r}, tab_id={tab_id!r}, text_len={len(text)}, '
         f'submit={submit}, wait_ms={wait_ms}) req_id={req_id}')
```

Response field — `value_len_after` (длина), не raw value:

```python
return {
    'ok': True, 'req_id': req_id,
    'typed': True,
    'value_len_after': payload.get('value_len_after'),
    'submit_dispatched': payload.get('submit_dispatched'),
}
```

**Защищает от:**
- Случайного логирования паролей в `/tmp/cascade-browser.log`
- Чтения через chrome devtools если кто-то получил screenshot
- Возврата raw value через MCP response (юзер мог автоматизировать, и значение появилось бы в logs)

### Guard 3: `browser_close_tab` host whitelist

**Python (`tools/browser_close_tab.py`):**

```python
PROTECTED_HOST_SUFFIXES = (
    'claude.ai',
    'github.com',
    'docs.anthropic.com',
    'console.anthropic.com',
)

request = {
    'type': 'browser_close_tab',
    'req_id': req_id,
    'payload': {
        'tab_id': tab_id,
        'force': bool(force),
        'protected_host_suffixes': list(PROTECTED_HOST_SUFFIXES),
    },
}
```

**SW (`handleBrowserCloseTab`):**

```javascript
const tab = await chrome.tabs.get(tab_id);
let host = '';
try { host = new URL(tab.url || '').host; } catch {}
const matchedSuffix = suffixes.find(s => host === s || host.endsWith('.' + s));
if (matchedSuffix && !force) {
    port.postMessage({
        type: 'browser_close_tab_response', req_id: reqId,
        payload: {
            closed: false, was_protected: true,
            protect_reason: `host ${host} matches protected suffix ${matchedSuffix} — pass force=true to override`,
            host,
        },
    });
    return;
}
```

**Защищает от:**
- Случайного `force=true` в скрипте автоматизации → ребро потерять claude.ai сессию посередине workflow
- Drive-by закрытия github / docs.anthropic.com где Stanislav работает

**Note:** `force=true` всё ещё работает — это **не** absolute block, а **friction** (требует осознанного override).

### Guard 4: HTTP layer — Bearer + Host whitelist

См. [[cascade-browser-auth-funnel]] для полного content.

```python
mcp = FastMCP(
    ...
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=ALLOWED_HOSTS,
    ),
)

app = mcp.streamable_http_app()
app.add_middleware(BearerAuthMiddleware, token=bearer_token)
```

- Bearer middleware — constant-time compare (`secrets.compare_digest`)
- TransportSecuritySettings — Host header whitelist (DNS rebinding)

## Threat model

| Угроза | Защита | Layer |
|---|---|---|
| Anonymous internet user calls `tools/call` | BearerAuthMiddleware → 401 | HTTP |
| Attacker brute-forces Bearer (43 chars random) | impossible (44^43 entropy) | Math |
| DNS rebinding (`evil.com` → 127.0.0.1) | TransportSecuritySettings → 421 | HTTP |
| Local malware reads `~/.cascade-browser/bearer.txt` | chmod 600 + owner-only | FS |
| MITM на public Wi-Fi | Tailscale Funnel HTTPS edge cert | TLS |
| Script tries to type into password field | SW rejects `password_field_forbidden` | Extension |
| Script tries to `file:///` exfil | URL scheme reject | Python + SW |
| Script accidentally closes claude.ai chat | host whitelist → was_protected | SW |
| Bearer leaked via Telegram forward | rotation procedure (see funnel skill) | Process |

## What is NOT protected

- **Юзер сам в Chrome скачивает malicious extension** — chrome.* API access to all user data. Out of cascade-browser scope.
- **Native Host скомпрометирован** — local攻擊er может перехватить весь MCP traffic. Mitigation: PyInstaller signed binary (TBD), `%LOCALAPPDATA%` ACL.
- **Юзер логинится в фишинг-сайт** — cascade-browser не блокирует phishing. Use email security / 2FA.
- **Cookies / session tokens читаются через `browser_read_active_tab` / `_all_tabs`** — это **намеренно** (workflows что нуждаются в logged-in state). Не злоупотреблять — не логировать responses содержащие токены.

## Audit checklist (для нового tool)

При добавлении нового tool (e.g. `browser_form_fill` в Phase 4):

- [ ] Python validation parameters (type, range, allowed values)
- [ ] SW double-check валидация (defense-in-depth)
- [ ] Если read sensitive data — `log.info` BEZ raw value (только length / hash / placeholder)
- [ ] Если write-side — должны ли быть protected URLs / fields?
- [ ] Unit-тесты mock-bridge на каждом safety path
- [ ] Update `cascade-browser-safety/SKILL.md` (этот файл) с новой строчкой в matrix
- [ ] Update `cascade-browser-tools/SKILL.md` с API reference

См. `cascade-browser/mcp-server/tests/test_navigation_tools.py` для шаблона тестов.

## Cross-refs

- [[cascade-browser-overview]] — общая карта
- [[cascade-browser-tools]] — usage examples каждого tool
- [[cascade-browser-auth-funnel]] — Bearer + Host whitelist details
- [[cascade-tailscale-hard-rules]] — общие hard rules tailnet
