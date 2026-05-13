---
name: cascade-tailscale-acl
description: ACL / policy file конфигурация для tailnet Cascade. Tags для классификации (cascade-primary/cascade-server/cascade-exit/cascade-emergency), forbidden nodes (gl-mt6000-1, gl-mt6000-Thai, glkvm, beget-*), грант funnel attribute, exit node policy для bkk-exit/vultr-amsterdam, запрет Tailscale SSH на уровне политики. JSON-шаблоны и команды для применения через admin UI или API.
---

# Cascade × Tailscale ACL

## Зачем

ACL делает три вещи в Cascade:
1. **Сегментация** — разные классы нод не получают универсальный доступ (PRIMARY → exit OK, exit → PRIMARY NO)
2. **Funnel grant** — node attribute `funnel` для нод что публикуют MCP
3. **Защита forbidden nodes** — gl-mt6000-Thai / glkvm не должны принимать чужой трафик из tailnet без явного разрешения

## Открыть ACL editor

https://admin.tailscale.com/acls — JSON editor. Save применяет ACL ко всему tailnet моментально.

## Полный шаблон ACL для Cascade (стартовая точка)

```json
{
  "tagOwners": {
    "tag:cascade-primary":   ["krom00070007@gmail.com"],
    "tag:cascade-backup":    ["krom00070007@gmail.com"],
    "tag:cascade-server":    ["krom00070007@gmail.com"],
    "tag:cascade-exit":      ["krom00070007@gmail.com"],
    "tag:cascade-emergency": ["krom00070007@gmail.com"],
    "tag:cascade-mobile":    ["krom00070007@gmail.com"]
  },

  "groups": {
    "group:admins": ["krom00070007@gmail.com"]
  },

  "hosts": {
    "opus":     "100.70.212.16",
    "bkk-exit": "100.125.240.18",
    "msk-vps":  "100.103.182.81"
  },

  "acls": [
    /* 1. Admins всегда полный доступ к нашим нодам */
    {
      "action": "accept",
      "src":    ["group:admins"],
      "dst":    ["tag:cascade-primary:*", "tag:cascade-backup:*",
                 "tag:cascade-server:*", "tag:cascade-mobile:*"]
    },

    /* 2. PRIMARY → exit ноды (для outbound exit-node use) */
    {
      "action": "accept",
      "src":    ["tag:cascade-primary", "tag:cascade-backup", "tag:cascade-mobile"],
      "dst":    ["tag:cascade-exit:*"]
    },

    /* 3. PRIMARY ↔ server (state mirror push, cascade-state-push) */
    {
      "action": "accept",
      "src":    ["tag:cascade-primary", "tag:cascade-backup"],
      "dst":    ["tag:cascade-server:22", "tag:cascade-server:443"]
    },

    /* 4. emergency ноды (glkvm, gl-mt6000-Thai) НЕ ПРИНИМАЮТ входящий трафик от Cascade-классов;
          специально оставлено без accept-правила для них — default deny tailscale-acl сработает.
          Доступ к ним только из admin отдельной командой по необходимости. */

    /* 5. Внешние exit-trampolines (vultr, bkk-exit) принимают только exit-traffic */
    {
      "action": "accept",
      "src":    ["tag:cascade-mobile", "tag:cascade-primary"],
      "dst":    ["tag:cascade-exit:*"]
    }
  ],

  /* 6. Funnel grant — какие ноды могут публиковать в интернет */
  "nodeAttrs": [
    {
      "target": ["tag:cascade-primary", "tag:cascade-backup", "tag:cascade-server"],
      "attr":   ["funnel"]
    }
  ],

  /* 7. Tailscale SSH ЗАПРЕЩЕН везде. Этот блок ssh не объявлен (deny by default). */

  /* 8. autoApprovers - чтобы новая нода не висела с pending key approval */
  "autoApprovers": {
    "routes": {
      "10.20.0.0/24": ["tag:cascade-exit"]  /* AmneziaWG range через MSK-VPS */
    }
  }
}
```

## Tagging нод

Когда добавляешь нову ноду:

```bash
# при первом tailscale up:
tailscale.exe up --hostname=ser10-tha-1 --advertise-tags=tag:cascade-primary --accept-routes --accept-dns=false --ssh=false
```

Затем в admin.tailscale.com → Machines → выбрать ноду → Edit tags. Только владелец tag (см. `tagOwners`) может назначать tag.

## Cascade fleet → tag map

| Node | Tag |
|---|---|
| SER10 Pattaya-1 | `tag:cascade-primary` (с 2026-05-15) |
| MSI | `tag:cascade-backup` (после 2026-05-15) |
| opus-cwr-bkk | `tag:cascade-server` |
| bkk-exit | `tag:cascade-exit` |
| vultr-amsterdam | `tag:cascade-exit` |
| stockholm | `tag:cascade-exit` |
| MSK-VPS | `tag:cascade-exit` |
| timeweb-cascade-in | `tag:cascade-server` |
| S25 Ultra (Stanislav mobile) | `tag:cascade-mobile` |
| **gl-mt6000-1** | **БЕЗ TAG** (forbidden, в default deny) |
| **gl-mt6000 Thai** | **БЕЗ TAG** (forbidden) |
| **glkvm** | **БЕЗ TAG** (emergency) |
| **beget-***  | **БЕЗ TAG** (containers) |

## Запрет Tailscale SSH на уровне политики (defense-in-depth)

Помимо `--ssh=false` при `tailscale up`, можно гарантировать через **отсутствие** `ssh` блока в policy file. Если `ssh` блок не объявлен — Tailscale SSH запрещён независимо от клиентского флага.

```json
/* Этот блок НЕ должен появляться в policy file: */
/* "ssh": [
     { "action": "accept", "src": ["group:admins"], "dst": ["autogroup:self"], "users": ["root"] }
   ] */
```

## Применение через API (для автоматизации)

Tailscale API key (PAT) выпускается в admin → Settings → Keys.

```bash
TAILNET="tail80c5d4.ts.net"
TS_TOKEN="tskey-api-XXX"
curl -sS -H "Authorization: Bearer $TS_TOKEN" \
     -H "Content-Type: application/json" \
     -X POST "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/acl" \
     --data-binary @policy.hujson
```

(на 2026-05-14 — API не используется автоматически в Cascade; правки руками через admin UI)

## Стоп-условия

- ACL save в admin показывает синтаксическую ошибку — НЕ примет, твоя предыдущая версия остаётся активной (safe)
- После tag rename — нода может временно потерять доступы. Сначала добавить новый tag, потом снять старый.
- Изменения в `funnel` attribute срабатывают за ~10 секунд, не моментально.
