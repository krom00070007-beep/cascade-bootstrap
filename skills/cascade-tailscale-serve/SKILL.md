---
name: cascade-tailscale-serve
description: Tailscale Serve для внутренних Cascade-сервисов, доступных ТОЛЬКО внутри tailnet (без публикации в интернет). Когда выбирать Serve vs Funnel, CLI команды, отличие TLS терминации, ACL для tagged серверов. Применяется к не-публичным dashboards (Grafana, AdGuard UI, Webmin) и MCP-сервисам, доступным только peer'ам.
---

# Cascade × Tailscale Serve

## Когда применять (Serve vs Funnel)

| Критерий | Serve | Funnel |
|---|---|---|
| Доступ | Только tailnet peers | Любой в интернет |
| URL | `https://<hostname>.tail80c5d4.ts.net` | то же |
| Auth | Tailscale already authenticates peer | Нужен свой Bearer / OAuth (Tailscale не помогает) |
| HTTPS Cert | Авто | Авто |
| Порты | Любые | Только 443/8443/10000 |
| Когда выбирать | claude.ai НЕ должен видеть, только внутренние boards / SSH-only сервисы / cascade-doctor MCP | claude.ai web/mobile, GitHub raw downloads, любой external consumer |

**В Cascade сейчас Serve НЕ используется**, всё через Funnel. Но Serve уместен для:
- AdGuard UI на MSK-VPS (10.20.0.1:53 + admin :80)
- Будущий cascade-doctor MCP (только админ-доступ)
- Grafana / Prometheus / monitoring dashboards
- Tilda preview / personal git repos

## Serve CLI

```bash
# HTTPS на :443 → проксирует на локальный :3000:
tailscale.exe serve --bg --https=443 localhost:3000

# HTTP на :80 (без cert, для legacy):
tailscale.exe serve --bg --http=80 localhost:8080

# TCP forwarding (raw, без TLS terminate):
tailscale.exe serve --bg --tcp=5432 localhost:5432

# TLS-terminated TCP:
tailscale.exe serve --bg --tls-terminated-tcp=5432 tcp://localhost:5432

# Файлы / директорию (только на macOS open-source):
tailscale.exe serve --bg /path/to/files

# Static text response:
tailscale.exe serve --bg --https=443 text:"OK from cascade"

# Path-based routing:
tailscale.exe serve --bg --https=443 --set-path=/api localhost:3000
tailscale.exe serve --bg --https=443 --set-path=/admin localhost:9000

# Список:
tailscale.exe serve status
tailscale.exe serve status --json

# Сброс:
tailscale.exe serve reset

# Отключение конкретного:
tailscale.exe serve --https=443 / off
```

## Persistence

- `--bg` — конфиг сохраняется, авто-старт после reboot
- без `--bg` — нужен ручной рестарт после reboot

## TLS терминация

Serve **сам разворачивает TLS** через Let's Encrypt cert (тот же что Funnel использует). Локальный сервис может слушать на HTTP — Tailscale апскейлит до HTTPS на edge.

Если локальный сервис уже на HTTPS с self-signed cert:

```bash
tailscale.exe serve --bg --https=443 https+insecure://localhost:8443
```

## ACL для Serve

В отличие от Funnel, Serve **не требует** `funnel` node attribute. Достаточно стандартных ACL правил типа:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:cascade-admin"],
      "dst": ["tag:cascade-internal-services:*"]
    }
  ],
  "tagOwners": {
    "tag:cascade-admin": ["krom00070007@gmail.com"],
    "tag:cascade-internal-services": ["krom00070007@gmail.com"]
  }
}
```

Затем тег нодам:

```bash
# На MSK-VPS:
tailscale.exe up --advertise-tags=tag:cascade-internal-services
```

## Cascade-сценарий (planned, ещё не реализован)

Будущий cascade-doctor MCP на opus или ser10:

```bash
# на ser10-tha-1 (когда будет cascade-doctor):
tailscale.exe serve --bg --https=443 localhost:9876
```

→ `https://ser10-tha-1.tail80c5d4.ts.net/` доступно только peer'ам tailnet, доп. auth не нужен (peer уже verified by tailnet).

## Стоп-условия

- Serve и Funnel **не могут слушать один и тот же порт одновременно**. Решить сначала какой используешь.
- Если сервис должен быть и для claude.ai (Funnel), и для опуса (Serve) — Funnel достаточно: peers тоже могут к нему подключаться по тому же URL.
