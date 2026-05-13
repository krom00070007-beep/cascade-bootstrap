---
name: cascade-browser-overview
description: Карта применения cascade-browser MCP-server (Claude → MCP → TCP → Native Host → Chrome MV3 extension → user's real Chrome profile). Dispatch для sub-skills (mcp-chrome architecture, tools, auth-funnel, safety, troubleshooting). Активируется при вопросах про MCP↔Chrome bridge в Cascade, browser tools, Bearer Funnel для browser, debugging extension bridge.
---

# cascade-browser — обзор

_Версия 1.0 от 2026-05-14. После BR-104 step 3 (Bearer+Funnel) + BR-105 Phase 3 (6 write tools)._

## Когда применять

Любая работа с cascade-browser:
- Использовать MCP tools (navigate, click, type, read_active_tab, screenshot, etc.)
- Debug extension bridge (chrome → native → tcp → mcp)
- Setup новой ноды с cascade-browser (SER10 deployment)
- Patch server.py / extension / native-host

Если запрос про **общий** browser automation (не cascade) — использовать `browser-automation` или Playwright skills вместо.

## Какой sub-skill вызывать

| Запрос | Использовать | Что внутри |
|---|---|---|
| Архитектура layer-by-layer (Claude→MCP→TCP→NH→ext→Chrome) | [[cascade-browser-mcp-chrome]] | Reference 10-layer flow, MV3 specifics, PyInstaller details (написан до BR-104/105) |
| "Какие tools доступны? Как вызвать `browser_X`?" | [[cascade-browser-tools]] | 10 MCP tools (4 read + 6 write) с примерами, parameters, response schemas |
| Bearer / Funnel / claude.ai connector / Host whitelist | [[cascade-browser-auth-funnel]] | BR-104 step 3 — auth, FastMCP transport_security, Tailscale Funnel + Win portproxy, connector URL |
| Safety: password fields, close_tab whitelist, URL scheme | [[cascade-browser-safety]] | Все guardrails: input[type=password] reject, claude.ai protect, http/https only, text masking |
| Sites не работают, SW dies, 421/401/502 | [[cascade-browser-troubleshooting]] | Specific cascade-browser symptoms (extension SW lifecycle, native host, DDoS-Guard, host header) |

## Stack overview (на 2026-05-14)

```
claude.ai / Claude Code / opus
    ↓ HTTPS + Bearer (Tailscale Funnel)
    ↓ desktop-4sl95n4.tail80c5d4.ts.net (MSI) / ser10-tha-1.tail80c5d4.ts.net (SER10 после 15.05)
    ↓ Win netsh portproxy 8767 → loopback (WSL1 shares loopback, WSL2 needs mirrored mode)
    ↓ FastMCP Streamable HTTP :8767 + BearerAuthMiddleware + TransportSecuritySettings.allowed_hosts
    ↓ asyncio bridge_listener.py TCP :8768
    ↓ Native Host cascade_browser_host.exe (PyInstaller, %LOCALAPPDATA%\cascade-browser\)
    ↓ Chrome Native Messaging (4-byte LE length prefix + UTF-8 JSON)
    ↓ Extension MV3 service-worker.js (dispatch by msg.type)
    ↓ chrome.tabs / chrome.scripting / chrome.bookmarks API
    ↓ user's real Chrome profile (all logins intact)
```

10-layer flow. 8 ms RTT при идеальной cell. См. [[cascade-browser-mcp-chrome]] для deep dive.

## Tools на 2026-05-14 (10 total)

### Read (4)

| Tool | Что делает |
|---|---|
| `browser_ping(msg)` | Echo-back round-trip с `latency_ms`, `tab_count`, `active_tab_url`. Phase 2: ts/echo chain. |
| `browser_read_active_tab(mode)` | DOM активной вкладки. `mode='text'/'html'/'both'`. |
| `browser_read_all_tabs(max_chars_per_tab)` | innerText всех вкладок в одном вызове. Skip chrome://, etc. |
| `browser_bookmarks_delete_old(days)` | chrome.bookmarks.remove(...) старше N дней. Sync-aware. |

### Write (6 — BR-105 Phase 3)

| Tool | Что делает | Safety |
|---|---|---|
| `browser_navigate(url, tab_id)` | chrome.tabs.update/create. tab_id=None/int/"new". | http/https only |
| `browser_click(selector, tab_id, wait_ms)` | polling 100ms + el.click() | timeout returns selector_not_found |
| `browser_type(selector, text, tab_id, submit, wait_ms)` | el.value=text + input/change events + opt Enter | input[type=password] REJECT |
| `browser_screenshot(tab_id, format, quality, full_page)` | captureVisibleTab base64. Default jpeg q=80. | full_page=true → not_implemented |
| `browser_scroll(direction, amount, tab_id)` | scrollTo/scrollBy. up/down/top/bottom × page/half/px=N | — |
| `browser_close_tab(tab_id, force)` | chrome.tabs.remove | claude.ai/github.com/anthropic docs → reject unless force=true |

Полный API + examples → [[cascade-browser-tools]].

## Live endpoints

| Где | URL | Bearer |
|---|---|---|
| MSI (preview) | `https://desktop-4sl95n4.tail80c5d4.ts.net/mcp` | `~/.cascade-browser/bearer.txt` (MSI) |
| SER10 (post-15.05) | `https://ser10-tha-1.tail80c5d4.ts.net/mcp` | `~/.cascade-browser/bearer.txt` (SER10, новый отдельный) |
| Local from inside Cascade fleet | `http://127.0.0.1:8767/mcp` (если на той же ноде) | тот же Bearer что у Funnel |

## Hard rules (must not violate)

- **Bearer mandatory.** Funnel = public, без auth любой может вызвать tools.
- **Host header whitelist mandatory.** `TransportSecuritySettings(allowed_hosts=[...])` — защита от DNS rebinding.
- **Password fields НИКОГДА** — even with force flag. `browser_type` reject.
- **URL scheme http/https only** в browser_navigate — `file://`, `chrome://`, `data:`, `javascript:` rejected (Python + SW double-check).
- **claude.ai / github.com / docs.anthropic.com / console.anthropic.com** в `browser_close_tab` — protected без `force=true`.

## Sources

- BR-104 step 3 commit `27b6e94` (Bearer + Host whitelist + browser_ping latency)
- BR-105 Phase 3 commit `924a3ac` (6 write tools)
- `cascade-browser/mcp-server/src/` — server.py, auth.py, bridge_listener.py, tools/*
- `cascade-browser/extension/background/service-worker.js`
- `cascade-browser/native-host/src/cascade_browser_host.py`
- handoffs/2026-05-14-cascade-full-session.md
