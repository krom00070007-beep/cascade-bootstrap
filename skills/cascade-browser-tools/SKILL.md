---
name: cascade-browser-tools
description: API reference + usage examples для 10 MCP-tools cascade-browser (4 read + 6 write). Каждый tool — signature, parameters, response schema, examples curl + Python MCP client, common usage patterns (scrape Gmail / fill form / take screenshot / batch read tabs / cleanup bookmarks). Активируется когда нужно вызвать конкретный tool, debug response, написать code что использует cascade-browser MCP.
---

# cascade-browser tools — API reference

_Версия 1.0 от 2026-05-14. 10 MCP tools (4 read + 6 write) после BR-104 step 3 + BR-105 Phase 3._

## Boilerplate: получить MCP session

Все tools вызываются через MCP Streamable HTTP. Сначала initialize + initialized, потом tools/call.

```bash
TOKEN=$(cat ~/.cascade-browser/bearer.txt)
URL="https://desktop-4sl95n4.tail80c5d4.ts.net/mcp"   # или http://127.0.0.1:8767/mcp локально

# initialize
curl -s -D /tmp/h.txt -o /tmp/init.txt -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{
    "protocolVersion":"2025-03-26","capabilities":{},
    "clientInfo":{"name":"my-client","version":"0.1"}}}'

SID=$(grep -i "^mcp-session-id:" /tmp/h.txt | awk '{print $2}' | tr -d '\r\n')

# initialized notification
curl -s -o /dev/null -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -H "mcp-session-id: $SID" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}'
```

Затем `tools/call` с тем же `mcp-session-id`:

```bash
curl -s -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -H "mcp-session-id: $SID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
    "name":"<tool_name>","arguments":{...}}}'
```

## READ tools

### `browser_ping(msg)`

**Назначение:** Liveness + latency check через всю цепочку. Используй периодически как health-check.

**Parameters:**
- `msg: str` (default `""`)

**Response:**
```json
{
  "ok": true,
  "req_id": "<uuid4>",
  "latency_ms": 9,
  "chain": "chrome→native→tcp→mcp",
  "ts_sent": 1778685956042,
  "ts_echo": 1778685956042,
  "ts_pong": 1778685956050,
  "ts_received": 1778685956051,
  "pong": "hello-from-mcp-e2e",
  "tab_count": 4,
  "active_tab_url": "https://example.com",
  "extension_version": "0.1.0",
  "server_version": "0.1.0-step2"
}
```

**Failure response:**
```json
{"ok": false, "error": "timeout", "broke_at": "mcp→...→extension (no pong within 10s)", "chain": "chrome→native→tcp→mcp"}
```

`broke_at` указывает где звено цепи отвалилось.

### `browser_read_active_tab(mode)`

**Назначение:** Получить DOM активной вкладки. Не требует navigate — читает что юзер сейчас видит.

**Parameters:**
- `mode: "text" | "html" | "both"` (default `"text"`)

**Response:**
```json
{
  "ok": true, "req_id": "...",
  "url": "https://gmail.com/...",
  "title": "Inbox - krom00070007@gmail.com",
  "tab_id": 2006799670,
  "text": "<innerText>",
  "html": null,
  "text_truncated": false,
  "html_truncated": false,
  "text_length": 12345,
  "html_length": 0
}
```

**Use case:** scrape Gmail после ручного логина (юзер уже на странице, нужно прочесть).

### `browser_read_all_tabs(max_chars_per_tab)`

**Назначение:** Прочесть innerText КАЖДОЙ открытой вкладки одним вызовом. Скипает chrome://, edge://, devtools://.

**Parameters:**
- `max_chars_per_tab: int` (default 50000)

**Response:**
```json
{
  "ok": true, "req_id": "...",
  "total_tabs": 12,
  "scraped": 8,
  "skipped": 4,
  "results": [
    {"tab_id": 1, "url": "...", "title": "...", "text_length": 4200, "text": "...", "truncated": false},
    {"tab_id": 2, "error": "..."}
  ]
}
```

**Use case:** multi-provider scrape (одновременно biling страницы Vultr+TimeWeb+Beget+LightNode open в Chrome → один call).

### `browser_bookmarks_delete_old(days)`

**Назначение:** Удалить bookmarks старше N дней через `chrome.bookmarks.remove()` API. Sync-aware (Google Sync propagates deletion).

**Parameters:**
- `days: int` (default 180)

**Response:**
```json
{
  "ok": true, "req_id": "...",
  "days": 180,
  "threshold_iso": "2026-11-15T...",
  "targeted": 425,
  "deleted_count": 420,
  "error_count": 5,
  "deleted_sample": [/* first 20 */],
  "errors": [/* first 10 */]
}
```

**Use case:** cleanup закладок (один раз в Q).

## WRITE tools (BR-105)

### `browser_navigate(url, tab_id)`

**Назначение:** Перейти по URL.

**Parameters:**
- `url: str` (http or https only — file/chrome/data/javascript REJECTED)
- `tab_id: None | int | "new"` (default `None` = active tab)

**Response on success:**
```json
{"ok": true, "req_id": "...", "tab_id": 2006799670, "url": "...", "title": "", "status": "loading"}
```

**Common usage:**
```bash
# Open URL in new tab:
... '{"name":"browser_navigate","arguments":{"url":"https://github.com","tab_id":"new"}}'

# Replace current tab:
... '{"name":"browser_navigate","arguments":{"url":"https://gmail.com"}}'

# Specific tab:
... '{"name":"browser_navigate","arguments":{"url":"https://reddit.com","tab_id":42}}'
```

### `browser_click(selector, tab_id, wait_ms)`

**Назначение:** Клик по CSS selector с ожиданием появления.

**Parameters:**
- `selector: str` (CSS selector, e.g. `"button#submit"`, `"a[href*=foo]"`)
- `tab_id: None | int` (default None = active)
- `wait_ms: int` (default 5000, polling 100ms)

**Response on success:**
```json
{"ok": true, "req_id": "...", "clicked": true, "element": {"tag": "button", "text": "Submit", "visible": true}}
```

**Common usage:**
```
'{"name":"browser_click","arguments":{"selector":"button[type=submit]"}}'
'{"name":"browser_click","arguments":{"selector":"a.dropdown-toggle","wait_ms":10000}}'
```

### `browser_type(selector, text, tab_id, submit, wait_ms)`

**Назначение:** Ввод текста в `<input>` / `<textarea>` / `contentEditable`.

**Parameters:**
- `selector: str`
- `text: str` (НЕ логируется в plain — только length)
- `tab_id: None | int`
- `submit: bool` (default False; True → dispatch keydown Enter после ввода)
- `wait_ms: int` (default 5000)

**Response on success:**
```json
{"ok": true, "req_id": "...", "typed": true, "value_len_after": 11, "submit_dispatched": false}
```

**Safety failures:**
```json
{"ok": false, "error": "password_field_forbidden",
 "message": "typing into input[type=password] is not allowed"}
```

**Use case:** заполнение search form, message box, контактные формы. **Не для паролей** (используй password manager).

### `browser_screenshot(tab_id, format, quality, full_page)`

**Назначение:** Captura viewport как base64-encoded image.

**Parameters:**
- `tab_id: None | int`
- `format: "jpeg" | "png"` (default `"jpeg"`)
- `quality: int 1..100` (default 80, только для JPEG)
- `full_page: bool` (default False — `True` → `not_implemented` в v1)

**Response on success:**
```json
{"ok": true, "req_id": "...", "format": "jpeg",
 "data_base64": "BASE64STRING",
 "width": 1920, "height": 1080, "size_bytes": 41640}
```

**Sizing reference (FullHD viewport):**
- JPEG q=80: ~200-500 KB base64 (рекомендуется)
- PNG: ~2-5 MB base64 (lossless, тяжелее)

**Use case:** визуально сравнить рендер, отчёт «как страница выглядит сейчас», audit chart screenshots.

### `browser_scroll(direction, amount, tab_id)`

**Назначение:** Прокрутить страницу.

**Parameters:**
- `direction: "up" | "down" | "top" | "bottom"`
- `amount: "page" | "half" | "px=NNN"` (игнорируется для top/bottom)
- `tab_id: None | int`

**Response:**
```json
{"ok": true, "req_id": "...", "scrolled_to_y": 156, "page_height": 3817, "view_height": 156}
```

**Use case:** lazy-load content (infinite scroll), reach footer to click "Load more", scroll-capture-multiple для full-page screenshot manually.

### `browser_close_tab(tab_id, force)`

**Назначение:** Закрыть вкладку.

**Parameters:**
- `tab_id: int` (required — no default)
- `force: bool` (default False — `True` обходит protected list)

**Response on success:**
```json
{"ok": true, "req_id": "...", "closed": true, "was_protected": false,
 "protect_reason": null, "host": "example.com"}
```

**Protected (success but not closed):**
```json
{"ok": true, "closed": false, "was_protected": true,
 "protect_reason": "host claude.ai matches protected suffix claude.ai — pass force=true to override",
 "host": "claude.ai"}
```

Protected suffixes (host suffix-match): `claude.ai`, `github.com`, `docs.anthropic.com`, `console.anthropic.com`.

**Use case:** cleanup открытых tabs / автоматизация workflow (после submit формы — закрыть tab).

## Common patterns

### Pattern 1: Open + scrape

```bash
# 1. Navigate to new tab
NAV=$(curl ... browser_navigate '{"url":"https://wordstat.yandex.ru/...","tab_id":"new"}')
TAB=$(jq -r '.result.content[0].text | fromjson | .tab_id' <<<"$NAV")
sleep 2  # wait for page load

# 2. Read content
READ=$(curl ... browser_read_active_tab '{"mode":"text"}')
echo "$READ" | jq -r '.result.content[0].text | fromjson | .text' | head -50
```

### Pattern 2: Form fill + submit

```bash
# Wait for form
curl ... browser_click '{"selector":"#username"}'         # focus
curl ... browser_type '{"selector":"#username","text":"alice"}'
curl ... browser_type '{"selector":"#password","text":"..."}' \
    # → error: password_field_forbidden (по дизайну)
# Use a password manager extension instead
curl ... browser_click '{"selector":"button#submit"}'
```

### Pattern 3: Multi-tab snapshot

```bash
# Snapshot 8 hosting billing pages
curl ... browser_read_all_tabs '{"max_chars_per_tab":80000}' \
    | jq -r '.result.content[0].text | fromjson | .results[] | "\(.url): \(.text_length) chars"'
```

## Tool selection cheat-sheet

| Хочу | Tool |
|---|---|
| Понять что юзер видит сейчас | `browser_read_active_tab` |
| Snapshot multiple tabs | `browser_read_all_tabs` |
| Перейти куда-то | `browser_navigate` |
| Нажать кнопку | `browser_click` |
| Заполнить поле | `browser_type` |
| Скриншот | `browser_screenshot` |
| Прокрутить | `browser_scroll` |
| Health-check | `browser_ping` |
| Удалить старые закладки | `browser_bookmarks_delete_old` |
| Закрыть вкладку | `browser_close_tab` (НЕ закроет protected URLs без force) |

См. [[cascade-browser-safety]] для полного safety overview.
