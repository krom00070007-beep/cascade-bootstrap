---
name: cascade-tailscale-acl
description: ACL / policy file конфигурация для tailnet Cascade — это АРХИТЕКТУРНЫЙ ПЛАН, не задеплоенная реальность (на 2026-05-14). Шаблоны tagOwners, acls, nodeAttrs funnel grant, autoApprovers, runbook постепенного rollout (snapshot → tagOwners → tag node → acls). Tags для классификации (cascade-primary/cascade-server/cascade-exit/cascade-emergency), forbidden nodes (gl-mt6000-1, gl-mt6000-Thai, glkvm, beget-*), запрет Tailscale SSH через отсутствие ssh-блока (defense-in-depth + --ssh=false flag).
---

# Cascade × Tailscale ACL

⚠️ **СТАТУС НА 2026-05-14: АРХИТЕКТУРНЫЙ ПЛАН, НЕ ЗАДЕПЛОЕНО.**

Реальный tailnet работает на permissive defaults:
- `tagOwners` содержит только `tag:vpn-bridge` (на `msk-vps-bridge`)
- MSI, opus-cwr-bkk, bkk-exit и остальные ноды — **untagged**
- Cascade-специфичные `cascade-*` теги — **не определены**
- Текущий `acls` блок не проверен (требует admin OAuth)

См. `docs/audits/cascade-tailscale-compliance-2026-05-14.md` (GAP №1) и `docs/audits/cascade-architecture-errors-2026-05-14.md` (Section 1).

## Зачем

ACL даст три вещи в Cascade (когда задеплоим):
1. **Сегментация** — разные классы нод не получают универсальный доступ (PRIMARY → exit OK, exit → PRIMARY NO)
2. **Funnel grant** — node attribute `funnel` для нод что публикуют MCP
3. **Защита forbidden nodes** — gl-mt6000-Thai / glkvm не должны принимать чужой трафик из tailnet без явного разрешения

**До deploy:** защита forbidden nodes только **документальная** (упоминание в `state/current.md`, `nodes.md`, exclusion list в `10-ssh-distribute.sh`). Достаточно для текущего solo-operator scenario, но недостаточно при росте команды или multi-machine скриптов.

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

## Постепенный rollout (low-risk, рекомендуется)

⚠️ **Все этапы — отдельные сессии**, не делать в один заход с другими high-risk операциями (Phase 3 deploy, MIG-001).

### Stage 0 — Snapshot текущего policy (always first)

1. admin.tailscale.com → Access controls → Edit (Open JSON editor)
2. Скопировать всю текущую `policy.hujson` в clipboard
3. Сохранить локально: `~/.cache/tailscale-acl-backup-$(date +%Y%m%d-%H%M%S).hujson`
4. Запушить через `tg-send-file` копию в Telegram Saved для cross-device backup

### Stage 1 — Добавить tagOwners (zero-impact)

Только определения tagOwners, без acls правил. Это zero-impact: peers продолжают работать как раньше.

В admin → ACL editor → patch:

```json
{
  "tagOwners": {
    "tag:cascade-primary":   ["krom00070007@gmail.com"],
    "tag:cascade-backup":    ["krom00070007@gmail.com"],
    "tag:cascade-server":    ["krom00070007@gmail.com"],
    "tag:cascade-exit":      ["krom00070007@gmail.com"],
    "tag:cascade-emergency": ["krom00070007@gmail.com"],
    "tag:cascade-mobile":    ["krom00070007@gmail.com"],
    "tag:vpn-bridge":        ["krom00070007@gmail.com"]   // существующий, не трогаем
  },
  // existing acls, groups, hosts остаются как были
}
```

Save → ничего не меняется в connectivity. Tags доступны для assignment.

### Stage 2 — Tag двух pilot-нод (MSI + opus)

В admin → Machines → desktop-4sl95n4 (MSI) → Edit tags → `tag:cascade-backup`. Save.
В admin → Machines → opus-cwr-bkk → Edit tags → `tag:cascade-server`. Save.

Verify через `tailscale.exe debug prefs` на MSI: `AdvertiseTags` должен показать `[tag:cascade-backup]`.

Communications должны работать как раньше (`tailscale.exe ping opus-cwr-bkk` → success), потому что acls ещё не ограничен.

### Stage 3 — Tag остальных core нод

После 24 часов наблюдения Stage 2 без проблем:
- bkk-exit → `tag:cascade-exit`
- vultr-amsterdam → `tag:cascade-exit`
- stockholm → `tag:cascade-exit`
- msk-vps-bridge → `tag:cascade-exit` + сохранить `tag:vpn-bridge`
- timeweb-* → `tag:cascade-server`
- gl-mt6000-1 → `tag:cascade-emergency`
- gl-mt6000 (Thai) → `tag:cascade-emergency`
- glkvm → `tag:cascade-emergency`
- s25-ultra-stanislav-3 → `tag:cascade-mobile`
- iphone-* → `tag:cascade-mobile`

Beget container ноды (refuse SSH) — без tag, либо `tag:cascade-emergency` (если хочется визуально маркировать).

### Stage 4 — Применить acls **в test mode сначала**

Tailscale поддерживает `tailscale.exe acl test` (если включён). Перед save:

```bash
# Сохранить candidate policy локально
cat > /tmp/candidate-acls.hujson <<'EOF'
{
  // ... весь policy file с новым acls блоком ...
}
EOF

# Test против известных peer pairs (run на любой ноде)
# Не уверен что это поддерживается на Free plan — проверить
```

Если `acl test` недоступен — использовать **strategy: open до явного deny**. Первая итерация acls:

```json
"acls": [
  /* Универсальный allow для всех владельцев, потом сужаем */
  { "action": "accept", "src": ["autogroup:owner"], "dst": ["*:*"] }
]
```

Это equivalent permissive-by-default — equivalent текущему состоянию, но в явной форме. Save и verify все работает.

### Stage 5 — Усиление acls по одному правилу

После Stage 4 → постепенно дробить:

1. Заменить `autogroup:owner` на конкретные tag-sources (`tag:cascade-primary, tag:cascade-backup, tag:cascade-mobile`)
2. После 24 часов — заменить `dst: ["*:*"]` на `dst: ["tag:cascade-server:*", "tag:cascade-exit:*"]`
3. После следующих 24 часов — удалить открытый универсальный rule
4. Forbidden nodes (`tag:cascade-emergency`) **не появляются** в `dst` ни одного accept-rule → default deny

### Stage 6 — Verify hard-rules

После полного rollout:

- `tailscale.exe ssh tag:cascade-emergency` → должно fail (нет ssh блока, deny)
- Любой peer → `tag:cascade-emergency` connect → должно fail
- `tag:cascade-mobile` (телефон) → `tag:cascade-server` :443 (Funnel) → success
- `tag:cascade-mobile` → `tag:cascade-exit` (exit node use) → success

### Stop conditions / rollback

- На любом stage если peer теряет доступ непредвиденно → **rollback из Stage 0 snapshot** немедленно (admin → ACL → paste старую policy.hujson → Save).
- Не оставлять deny-rules pending — каждый save должен быть **complete и valid**.
- Если admin показывает syntax error — он не save'нет (safe), но logical errors save'тся (Stage 5 dangerous part).

## Текущий тэг на нодах (на 2026-05-14)

| Node | Live tags | Должен быть после rollout |
|---|---|---|
| MSI | (none) | `tag:cascade-backup` (после 15.05; PRIMARY до этого) |
| SER10 Pattaya-1 | (offline) | `tag:cascade-primary` (после 15.05) |
| opus-cwr-bkk | (none) | `tag:cascade-server` |
| bkk-exit | (none) | `tag:cascade-exit` |
| vultr-amsterdam | (none) | `tag:cascade-exit` |
| stockholm | (none) | `tag:cascade-exit` |
| msk-vps-bridge | `tag:vpn-bridge` | `tag:vpn-bridge` + `tag:cascade-exit` |
| s25-ultra-stanislav-3 | (none) | `tag:cascade-mobile` |
| gl-mt6000-1 | (none) | `tag:cascade-emergency` |
| gl-mt6000 (Thai) | (none) | `tag:cascade-emergency` |
| glkvm | (none) | `tag:cascade-emergency` |
