---
name: cascade-tailscale-troubleshooting
description: Типичные ошибки и диагностика Tailscale в контексте Cascade. Покрывает: cert provisioning > 60s, 421 Invalid Host header (DNS rebinding защита и allowed_hosts), MagicDNS не резолвит, OAuth не открывается, tailscale.exe не виден из WSL, tailnet IP drift, Funnel relay servers spam в status, key expiry, ACL deny после tag rename. Применяется при любой сетевой / Funnel / Serve проблеме на любой Cascade-ноде.
---

# Cascade × Tailscale — диагностика

## Дерево решений

```
Проблема видна с какой стороны?
├── С Cascade ноды (curl → Funnel/Serve URL)
│   └── HTTP код?
│       ├── 401 → Bearer middleware reject — проверь токен → cascade-browser/auth.py
│       ├── 421 Invalid Host header → allowed_hosts missing → см. [[cascade-tailscale-funnel]] section 2
│       ├── 502 Bad Gateway → локальный сервис не слушает на upstream порту → systemctl status
│       ├── 503 → Tailscale Funnel сам не дотягивается → tailscale funnel status
│       └── timeout → нода offline или Funnel выключился → tailscale status
├── В админке admin.tailscale.com
│   ├── Key expired → re-auth: tailscale.exe up (открой OAuth)
│   ├── Pending approval → admin → Machines → approve
│   └── Tag rejected → tagOwners не включает текущий email → см. [[cascade-tailscale-acl]]
├── В DNS / MagicDNS
│   └── См. секцию ниже
└── В Funnel / Serve
    └── См. секцию ниже
```

## Funnel cert provisioning > 60s

**Симптом:** `tailscale funnel status` не показывает "Funnel on:" минутами.

**Возможные причины:**
1. HTTPS Certificates **не toggled** в admin.tailscale.com → DNS → "HTTPS Certificates" должен быть ON. Это **per-tailnet** toggle, не per-device.
2. Funnel **не toggled per-device** в admin → Machines → device → Funnel ON. Per-device.
3. ACL `nodeAttrs` не grant'ит funnel attribute этому tag/device. См. [[cascade-tailscale-acl]] section "Funnel grant".
4. Tailscale ≥ v1.38.3 не установлен. `tailscale --version`.
5. Let's Encrypt rate limit (если часто запрашивал cert — ждать 34 ч).

**Диагностика:**

📋 на ноде:

```
tailscale.exe debug daemon-logs | tail -50
```

или

```
tailscale.exe debug netcheck
```

## 421 Invalid Host header

**Симптом:** через Funnel URL получаем `421 Invalid Host header` (и обычно `Connection: close`).

**Причина:** `TransportSecuritySettings.allowed_hosts` в `server.py` не содержит этот hostname. Сервер защищает от DNS rebinding и блокирует любой Host header вне whitelist.

**Решение:**

```python
ALLOWED_HOSTS = [
    '127.0.0.1', '127.0.0.1:8767',
    'localhost', 'localhost:8767',
    '<this-device>.tail80c5d4.ts.net',
    '<this-device>.tail80c5d4.ts.net:8767',
    ...
]
```

Перезапустить сервис: `sudo systemctl restart cascade-browser.service` или `pkill -f run-server.sh && nohup ./run-server.sh > /tmp/cascade-browser.log 2>&1 &`.

**Sanity:** для тестирования pre-Funnel — `curl -H "Host: <hostname>.tail80c5d4.ts.net" http://127.0.0.1:8767/mcp` (с Bearer) — должно работать или вернуть 421 (если allowed_hosts кривой).

## MagicDNS не резолвит

**Симптом:** `nslookup ser10-tha-1.tail80c5d4.ts.net` возвращает `NXDOMAIN`.

**Причины + решения:**

1. **MagicDNS выключен в tailnet** — admin.tailscale.com → DNS → "Use MagicDNS" ON.
2. **Нода offline** — `tailscale.exe status` другого peer'а должен её видеть. Если показывает `offline` — peer не на сети.
3. **`--accept-dns=false` на запрашивающей ноде** — это нормально для Cascade (см. policy). Используй явный hostname или IP через `tailscale.exe ip -4 -d <peer>`.
4. **DNS propagation up to 10 min** для новых нод.

## OAuth login не открывается / browser не появляется

**Симптом:** `tailscale up` зависает на "Login: visit https://login.tailscale.com/...".

**Причины:**

1. **Headless Linux без браузера** — `tailscale up` печатает URL, открой на другом устройстве, авторизуйся, нода активируется автоматически.
2. **Зашитый OAuth callback** — на Win-стороне через `tailscale.exe` — IE отключён в Win11 → может не открыться. Решение: открой URL руками в Chrome / Edge.

## tailscale.exe не виден из WSL

**Симптом:** в WSL `tailscale --version` → command not found.

**Причина:** Tailscale daemon на Win-стороне, в WSL нет CLI binary.

**Решения:**

1. Использовать через `cmd.exe /c "tailscale.exe ..."`:

   ```bash
   cmd.exe /c "tailscale.exe status"
   cmd.exe /c "tailscale.exe funnel --bg 8767"
   ```

2. Создать обёртку в `~/bin/tailscale`:

   ```bash
   cat > ~/bin/tailscale <<'EOF'
   #!/bin/bash
   exec cmd.exe /c "tailscale.exe $@"
   EOF
   chmod +x ~/bin/tailscale
   ```

3. Установить отдельный Linux Tailscale внутри WSL (тогда WSL — отдельный peer):
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up --hostname=ser10-tha-1-wsl --advertise-tags=tag:cascade-backup --accept-routes --accept-dns=false --ssh=false
   ```

## tailnet IP drift

**Симптом:** после reboot ноды IP в tailnet поменялся.

**Причина:** редкая, но возможна — Tailscale может перевыделить IP при долгом offline.

**Защита:**

- Использовать **hostnames** (MagicDNS) во всех конфигах: `~/.ssh/config`, `allowed_hosts`, scripts.
- Если ID критичен — admin.tailscale.com → Machines → device → "Reserved IP" (не уверен поддерживается в free план).

## Funnel relay servers spam в `tailscale status`

**Симптом:** `tailscale status` показывает 5+ нод вида `funnel-ingress-1234`, не наших.

**Причина:** Tailscale relay servers подключены потому что у тебя Funnel включён хоть на одном устройстве. Это **нормально** и не вредит.

**Решение:** игнорировать. Можно фильтровать:

```bash
tailscale.exe status | /bin/grep -v "funnel-ingress"
```

## Key expiry

**Симптом:** через 90-180 дней нода offline без причины.

**Причина:** Tailscale по умолчанию требует re-OAuth каждые 90/180 дней.

**Решение:** admin → Machines → device → "Key expiry" → Disable.

## ACL deny после tag rename

**Симптом:** после tag rename нода теряет доступы.

**Безопасный workflow:**
1. Добавить **новый** tag (не убирая старый): admin → Edit machine → tags `tag:cascade-primary tag:cascade-primary-v2`.
2. Перечитать `acls` на работу с новым tag.
3. **После** проверки доступов — снять старый tag.

## Cascade-специфичные стоп-условия (эскалировать к Stanislav)

| Сигнал | Что не делать самому |
|---|---|
| Проблема с **gl-mt6000-Thai** (100.76.55.53) | ⛔ НЕ перезапускать tailscaled / fw reload — recovery node. Эскалируй |
| Проблема с **gl-mt6000-1** (100.109.97.16) | ⛔ Семейный роутер. НЕ трогать |
| Проблема с **glkvm** (100.76.24.102) | ⛔ Emergency access. НЕ катать ключи |
| Funnel ломается на opus → cascade-state MCP отвалился | ⚠️ Bridge с claude.ai сломан — приоритет, но сам restart, эскалируй если cert provisioning > 60s |
| Tailscale Funnel удалён в admin случайно | Восстановление через `tailscale funnel --bg <port>` на ноде |
