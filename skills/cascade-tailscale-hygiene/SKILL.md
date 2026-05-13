---
name: cascade-tailscale-hygiene
description: Регулярная гигиена tailnet Cascade — quarterly cleanup orphan/offline нод, identify unknown peers, regenerate state/tailscale-tailnet.md через cascade-browser MCP scraping admin UI, audit key expiry, periodic Bearer rotation. Применяется когда видишь stale inventory, отдалённый "Last seen", unknown ноду в `tailscale.exe status`, или планируешь quarterly hygiene pass.
---

# Cascade × Tailscale — Hygiene (regular cleanup)

_Версия 1.0 от 2026-05-14. Создан после architecture-errors audit Sections 5+9+10._

## Когда применять

- **Quarterly** (раз в Q): полный pass через всё ниже
- **Ad-hoc**: видишь unknown peer в `tailscale.exe status`, кто-то спрашивает "что это за устройство?"
- **Before MIG / новые ноды**: clean-up перед добавлением (чтобы inventory не разрастался)
- **После увольнения / продажи устройства**: scope-cleanup конкретной ноды

## Главные регулярные задачи

| Задача | Частота | Когда триггер |
|---|---|---|
| Identify orphan / unknown nodes | Quarterly | Видишь имя hostname как hash (`812b992185f8`) или unknown owner |
| Remove offline > 90 days | Quarterly | `tailscale.exe status` показывает "offline, last seen 90d+" |
| Regen `state/tailscale-tailnet.md` | After cleanup | Doc drift с admin → state file out-of-date |
| Audit key expiry на control-points | Monthly | Случайно re-OAuth был запрошен |
| Bearer token rotation | Quarterly (или on suspicion) | См. [[cascade-tailscale-funnel]] Token rotation |
| Check forbidden nodes are still excluded | Quarterly | Особенно перед deploy новых скриптов |

## Procedure A — Identify orphan/unknown nodes

### Шаг 1: список kondidates

📋 в WSL (или PowerShell — `cmd.exe /c "tailscale.exe status"`):

```bash
cmd.exe /c "tailscale.exe status" 2>&1 | /bin/grep -E "(offline|krom00070007@)" | sort
```

Compare с inventory в `state/tailscale-tailnet.md` (32 девайса) и `state/nodes.md`. Узлы что встречаются в `tailscale.exe status` но не в state — kondidates на cleanup.

### Шаг 2: для каждого orphan — research

1. Open admin.tailscale.com → Machines → filter by hostname
2. Если hostname как hash (`812b992185f8`, `spb-3-vm-1jn8`) — посмотри "Last seen", "OS", "Tags". Часто это:
   - Старый Docker/CI auth, забытый
   - VPS, который удалили без logoff
   - Чей-то shared device (если работали с командой)
3. Если **не помнишь** что это — это candidate на **delete**.

### Шаг 3: action

- **Delete:** admin → Machines → выбрать → Delete (требует confirm)
- **Keep + document:** admin → Edit → добавить description в "Notes" + в `state/tailscale-tailnet.md` секция "Inventory"
- **Tag emergency:** если узел нужен но "не наш" (типа `tag:cascade-emergency`) — изолировать через ACL когда деплоим

## Procedure B — Remove offline > 90 days

### Reasoning

Offline > 90 days = либо устройство потеряно/продано/выкинуто, либо forgotten. В любом случае tailnet token на нём остаётся валидным (пока не expired в admin) → security risk если устройство попало в third-party hands.

### Шаги

1. admin → Machines → Filter "Last seen" descending
2. Найти все с last seen > 90d:
   ```
   25-f-1 (Android, last seen 41d) → BORDERLINE, ask Stanislav
   spb-3-vm-1jn8 (Linux, 13d) → too recent yet
   ```
3. Для каждого — confirm с Stanislav (если есть сомнение)
4. Delete from admin

⚠️ **Не удалять без явного OK** для devices с tag `cascade-mobile` (мобильник Stanislav может уйти offline на отпуск 30+ дней)

## Procedure C — Regen `state/tailscale-tailnet.md`

### Подход 1: cascade-browser MCP (если cascade-browser работает)

```bash
# Через MCP `browser_navigate` → admin.tailscale.com/admin/machines
# Затем `browser_read_active_tab(mode='text')` → save в state file
```

В реальности — нужен Claude Code session с активным cascade-browser MCP connector. На MSI это работает.

### Подход 2: ручной copy-paste

1. Open admin.tailscale.com/admin/machines в Chrome
2. Select all rows (Ctrl+A в таблице)
3. Copy
4. Paste в новый `state/tailscale-tailnet.md` под header "## Live inventory snapshot $(date)"
5. Clean up форматирование

### Подход 3: Tailscale API (если PAT настроен)

```bash
TAILNET="tail80c5d4.ts.net"
TS_TOKEN="tskey-api-XXX"
curl -sS -H "Authorization: Bearer $TS_TOKEN" \
     "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/devices" \
     | jq '.devices[] | {hostname:.hostname, id:.id, addresses:.addresses, lastSeen:.lastSeen, tags:.tags}' \
     > /tmp/tailscale-devices.json
```

Затем conversion JSON → markdown table.

⚠️ Tailscale API key — secret. Не commit'ить. Сделать read-only role если можно.

## Procedure D — Audit key expiry на control-points

Все Cascade control-points (`tag:cascade-primary`, `tag:cascade-backup`, `tag:cascade-server`, `tag:cascade-exit`) **должны** иметь Key expiry DISABLED.

### Шаги

1. admin → Machines → filter Type "Linux + Funnel" / "Windows + Exit"
2. Для каждой — Edit → "Disable key expiry" ON
3. Verify в state file отметить

## Procedure E — Bearer token rotation

См. [[cascade-tailscale-funnel]] секция "Bearer token rotation".

Quarterly recommendation: rotate (preventive) даже если нет признаков compromise.

## Procedure F — Verify forbidden nodes exclusion

После любого нового automation скрипта — `grep` на forbidden nodes:

```bash
cd ~/projects/cascade-state
for ip in 100.109.97.16 100.76.55.53 100.76.24.102; do
    /bin/grep -rn "$ip" scripts/ docs/ skills/ | /bin/grep -v "forbidden\|never touch\|DO NOT\|FORBIDDEN\|⛔"
done
```

Любые матчи без явного forbidden-комментария = bug, нужно пометить.

## Календарь регулярных task (предложение)

| Месяц | Действие |
|---|---|
| Каждый 1-й quarter | Full pass A+B+C+E |
| Каждый месяц | D + spot-check forbidden nodes |
| После любого MIG (новые ноды) | A + C |
| После любого инцидента | E (rotation immediately if suspicion) |

## Стоп-условия

- Если delete'ишь активную ноду (например iphone-15-pro-max используется ежедневно но "не виден" в админке потому что Bluetooth disabled) → urgent restore через re-OAuth
- Если cascade-browser MCP сломан (Procedure C) → используй ручной copy-paste
- Если admin API token leaked (Procedure C способ 3) → revoke + regen в admin.tailscale.com → Settings → Keys

## Audit log convention

После каждого hygiene pass — добавить entry в `state/current.md` секция "Recently closed":

```markdown
- **2026-08-15 hygiene Q3**: deleted 3 offline nodes (`25-f-1`, `spb-3-vm-1jn8`, `iphone-15-pro-max`).
  Regen-нул `tailscale-tailnet.md` через cascade-browser MCP. Bearer rotated.
  Verified forbidden nodes excluded in 4 automation scripts.
```

Это даёт audit trail и предотвращает повторный delete тех же нод (если кто-то спутает).
