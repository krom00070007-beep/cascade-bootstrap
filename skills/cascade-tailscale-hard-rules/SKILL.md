---
name: cascade-tailscale-hard-rules
description: Абсолютные правила работы с Tailscale в Cascade, нарушение которых может разрушить сетевую связность или захардкодить инцидент. Включает запрет Tailscale SSH (--ssh=false везде), список forbidden nodes (gl-mt6000-1, gl-mt6000-Thai, glkvm, beget-*), правила key expiry для critical-нод, политику HTTPS Certificates + Funnel toggle. Активируется автоматически при любых правках ACL / tailscale up / систем сетевой топологии.
---

# Cascade × Tailscale — АБСОЛЮТНЫЕ ПРАВИЛА

Эти правила **нельзя** нарушать без явного и прямо записанного разрешения от Stanislav. Каждое сформулировано на основе инцидента / explicit instruction.

## 1. Tailscale SSH (`--ssh=true`) ЗАПРЕЩЁН везде

**Причина:** Два инцидента в прошлом — одно подключение по Tailscale SSH перезаписало authorization framework системного sshd, потребовалось ручное восстановление через console / KVM.

**Как соблюдать:**

- При `tailscale up` всегда `--ssh=false`
- В policy file нет `ssh` блока (default deny)
- SSH всё ещё работает — через стандартный системный sshd на :22 с ключами (см. `~/.ssh/id_ed25519`)

**Если кто-то предлагает `--ssh=true` "для удобства":** напомнить про инциденты и отказать.

## 2. Forbidden nodes (НЕ ТРОГАТЬ)

| Node | TS IP | Что нельзя делать |
|---|---|---|
| **gl-mt6000-1** | 100.109.97.16 | Home router в семейной квартире. **Любая ошибка → семья без интернета.** Не катать ключи, не reboot, не trafficshape, не firewall reload |
| **gl-mt6000 Thai** | 100.76.55.53 | Recovery node для Thailand. **Любая ошибка может его выключить — без него потеря Thailand доступа.** Forbidden: `fw reload`, `nft flush`, `tailscaled restart`, `iptables -F`, network restart, Tailscale SSH |
| **glkvm** | 100.76.24.102 | KVM emergency access (IP-KVM устройство). **Должно остаться независимым от Cascade.** Не катать ключи. Не trafficshape |
| **beget-cascade-in/out** | n/a | Container peers с Beget hosting, SSH refused by container architecture. Менять только через панель Beget |

**Признак:** если задача или скрипт упоминает один из этих узлов как target → STOP, эскалировать.

### Текущий уровень защиты (на 2026-05-14)

| Слой защиты | Состояние | Сила |
|---|---|---|
| Документация (state/current.md, nodes.md) | ✅ есть | 🟡 medium — зависит от внимательности оператора |
| Script exclusion list (`10-ssh-distribute.sh`) | ✅ есть | 🟢 high — for that one script |
| **ACL tag-based deny** | ❌ **НЕ задеплоено** | 🔴 — был бы network-уровень defense, но требует [[cascade-tailscale-acl]] rollout |
| Per-node SSH key absence (наш ключ не на gl-mt6000-1 admin) | ✅ для gl-mt6000-1 | 🟢 high — даже если скрипт случайно target'нет, нет authentication |

**Bottom line:** до ACL rollout — защита **документально-procedural**, достаточно для solo-operator scenario, недостаточно при multi-machine скриптах. См. [[cascade-tailscale-acl]] для plan.

## 3. Funnel — обязательные требования

- Funnel экспозит сервис на **публичный интернет**. Без auth = catastrophe.
- Каждый Funnel-сервис в Cascade ОБЯЗАН иметь **Bearer middleware** (или эквивалент). См. `cascade-browser/mcp-server/src/auth.py`.
- Bearer token хранится в `~/.cascade-browser/bearer.txt` (chmod 600), НИКОГДА в git, НИКОГДА в memory.
- `TransportSecuritySettings.allowed_hosts` ОБЯЗАН включать тот hostname, через который Funnel экспозит. Иначе **либо 421 для legitimate, либо нет защиты от DNS rebinding**.

## 4. ACL — никогда не убирать existing accept-правил без двойной проверки

- Перед `Save` в admin.tailscale.com — открыть текущий policy в VS Code, сравнить diff.
- Сохранить backup предыдущего policy.hujson локально (`~/.cache/tailscale-acl-backup-<date>.hujson`).
- НИКОГДА не save'ить с массивом `acls: []` (это deny-all).
- ACL syntax errors — admin не сохраняет (safe), но logical errors — да (НЕ safe). Тестировать с конкретных нод.

## 5. Key expiry для critical-нод — DISABLE

Все Cascade control points (PRIMARY/BACKUP/SERVER tag) должны иметь Key expiry DISABLED в admin.tailscale.com → Machines → device.

**Причины:**

- Re-auth требует OAuth flow → требует browser → MSK-VPS или opus headless не смогут авто-re-auth → нода offline → сервис недоступен.
- 90-180 дней цикл — не предсказуемый момент. Лучше явно отключить.

**Исключение:** S25 Ultra (mobile) — там можно оставить expiry, Stanislav re-auth'нится с устройства за 30 секунд.

## 6. HTTPS Certificates — toggle включён глобально, выключение запрещено без объявления

- admin.tailscale.com → DNS → "HTTPS Certificates" **должен быть ON** всегда (пока хоть один сервис в Funnel или Serve работает).
- Выключение этого toggle разорвёт ВСЕ Funnel/Serve endpoints (cert не доступен).
- Если кому-то нужно временно выключить (например, тестирование) — объявить в Telegram Saved + state/current.md.

## 7. MagicDNS — toggle включён глобально

- admin.tailscale.com → DNS → "Use MagicDNS" **должен быть ON**.
- Все Cascade конфиги (~/.ssh/config, allowed_hosts, scripts) полагаются на `<hostname>.tail80c5d4.ts.net` резолвинг.
- Выключение MagicDNS = ломаются все routings, потребует переписать конфиги на raw IPs.

## 8. Tags только из tagOwners

- Невозможно advertise tag, который тебе не принадлежит per `tagOwners` в policy. Это design feature, не баг.
- Если новый tag нужен — добавить в `tagOwners` FIRST, потом `tailscale up --advertise-tags=...`.

## 9. tailnet name — не менять без object backup

Текущий tailnet: `tail80c5d4.ts.net`. Все hostnames, allowed_hosts, scripts полагаются на этот suffix. Смена name (через admin.tailscale.com → Settings → Tailnet name) сломает всё одним кликом — последствия как у DB rename.

## 10. tailscale CLI на forbidden ноду

Если случайно `tailscale ssh <forbidden-node>` или `tailscale ping <forbidden-node>` — это OK (read-only, не вредит). Запрещены только **изменяющие** команды (`up`, `down`, `set`, `funnel`, `serve`) с targetом forbidden ноды (которая, впрочем, отсутствует в acls accept-блоках — default deny её защитит).

---

## Если правило нарушено — что делать

1. **Не паниковать**, проверить точечно что сломалось.
2. **Откатить через admin UI** ACL если правка была там (есть undo last save).
3. **Если нода стала недоступна** через Tailscale: zHe Tailscale daemon рестарт на ней через локальный SSH (если живой) или KVM (glkvm — только если она сама не задействована).
4. **Логировать инцидент** в `cascade-state/state/current.md` "Recently closed" с обоснованием.
