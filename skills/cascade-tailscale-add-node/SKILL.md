---
name: cascade-tailscale-add-node
description: Пошаговое добавление новой ноды в Cascade tailnet — флаги tailscale up (--hostname/--accept-routes/--accept-dns/--ssh=false/--advertise-tags), OAuth flow (через какой email авторизоваться), regustration tag в admin, проверка MagicDNS, опциональное включение HTTPS Certificates+Funnel per-device. Шаблоны команд для Win-side (tailscale.exe), WSL (через tailscale.exe wrapper), Linux peers (apt install tailscale + tailscale up). Применяется когда: запуск SER10, добавление мобильного S25, добавление новой ноды exit, регистрация Lenovo как secondary control point.
---

# Cascade × Tailscale: добавление новой ноды

## Перед началом

Определи tag, который получит нода:

| Тип ноды | Tag | Где |
|---|---|---|
| Новый control-point (как SER10) | `tag:cascade-primary` или `tag:cascade-backup` | Win11 + WSL2 |
| Сервер 24/7 для MCP | `tag:cascade-server` | Linux VDS |
| Exit node (Thailand / NL / RU) | `tag:cascade-exit` | Linux VDS |
| Мобильник | `tag:cascade-mobile` | iOS/Android |
| Emergency-only | **БЕЗ TAG** (forbidden) | gl-mt6000-* / glkvm |

См. [[cascade-tailscale-acl]] для полного `tagOwners` списка.

## Шаги (Win11 + WSL — сценарий SER10)

### 1. Install Tailscale на Windows

📋 PowerShell **admin**:

```
winget install --id=tailscale.tailscale -e --silent --accept-package-agreements
```

или MSI:

```
msiexec /i https://tailscale.com/download/windows ALLUSERS=1 /qn
```

### 2. tailscale up с правильными флагами

📋 PowerShell **admin**:

```
tailscale.exe up --hostname=ser10-tha-1 --advertise-tags=tag:cascade-primary --accept-routes=true --accept-dns=false --ssh=false
```

Объяснение:
- `--hostname=ser10-tha-1` — DNS имя в tailnet (без точек, lowercase, до 63 chars)
- `--advertise-tags=tag:cascade-primary` — pre-tag. Owner tag (см. ACL `tagOwners`) должен авторизовать ноду как tagged peer
- `--accept-routes=true` — принимать subnet routes от других нод (AmneziaWG 10.20.0.0/24 через MSK-VPS и т.д.)
- `--accept-dns=false` — НЕ перехватывать DNS. Если включить — рискуем сломать GoogleDNS / AdGuard разрешение
- `--ssh=false` — **ОБЯЗАТЕЛЬНО, никогда не включать**, см. [[cascade-tailscale-hard-rules]]

Откроется браузер для OAuth. Выбор аккаунта: **krom00070007@gmail.com** (см. карту сред [[cascade-collaboration]]).

### 3. Verify status

```
tailscale.exe status
tailscale.exe ip -4
```

`ip -4` напечатает новый tailnet IP (100.x.y.z) — сохрани в `C:\Cascade\logs\tailnet-ip.txt` для записи в state.

### 4. Per-device toggles в admin.tailscale.com

Открой https://admin.tailscale.com/machines, найди новую ноду:

| Toggle | Что | Когда нужно |
|---|---|---|
| **Key expiry — disable** | Не истечь через 180 дней без re-auth | Для всех Cascade-нод |
| **Funnel** | Per-device включение Funnel | Только если эта нода будет публиковать MCP (как SER10) |
| **Subnet router approval** | Принять routes от ноды | Если нода имеет subnet (exit node типа MSK-VPS с AmneziaWG) |

### 5. (Опционально) MagicDNS sanity

```
nslookup ser10-tha-1.tail80c5d4.ts.net
# (с любой другой Cascade-ноды; должен вернуть 100.x.y.z)
```

Если не резолвит:
- admin.tailscale.com → DNS → "Use MagicDNS" должно быть ON
- ноды должны быть в одном tailnet (`tail80c5d4.ts.net`)

### 6. Linux / WSL — установка Tailscale внутри WSL (НЕ обязательно для cascade-browser; нужно если хочешь WSL быть отдельным peer)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=ser10-tha-1-wsl --advertise-tags=tag:cascade-backup --accept-routes=true --accept-dns=false --ssh=false
```

Обычно WSL пайн использовать **через Win-side tailscale.exe** (WSL шарит loopback с Win) — это проще и нет двойной авторизации.

### 7. Записать в cascade-state

После успешного join + tag, обновить `~/projects/cascade-state/state/nodes.md`:

```markdown
- **<hostname>** (TS <ip>, <description>)
  - Account: krom00070007@gmail.com
  - Tag: tag:cascade-primary
  - Tailscale SSH: DISABLED
  - Funnel: <yes/no, URL>
  - Subnet routes: <none / 10.20.0.0/24 / ...>
```

Commit + push (post-commit hook опуса auto-push'нёт).

## Сценарий iOS/Android (mobile)

1. App Store / Google Play → Tailscale
2. Sign in → krom00070007@gmail.com
3. В админке machines: найти ноду, set tag `tag:cascade-mobile`
4. Disable key expiry (mobile теряет re-auth особенно болезненно)

## Стоп-условия

- OAuth flow открывает другой аккаунт (Gmail backup или work) → отказаться, повторно
- Tag rejected: "the device user is not in tagOwners" → проверить `tagOwners` в ACL; добавить email
- MagicDNS не резолвит после 10 минут → admin DNS / MagicDNS toggle ON, refresh
- `tailscale up` зависает на "Waiting for authorization" → admin → Machines → найти pending, approve

## Не забудь после

- Обновить `cascade-browser/mcp-server/src/server.py` `ALLOWED_HOSTS` если эта нода будет публиковать через Funnel ([[cascade-tailscale-funnel]] section 2)
- Распространить SSH pubkey на ALLOWED Cascade-ноды (НЕ на forbidden — см. cascade-state `scripts/migration/10-ssh-distribute.sh` для шаблона)
- Если нода — control-point (Claude Code на ней): запустить `cascade-state-push` или настроить `post-commit` hook (см. `scripts/migration/06-repos-clone.sh`)
