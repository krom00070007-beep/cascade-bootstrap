---
name: cascade-tailscale-overview
description: Карта применения Tailscale в проекте Cascade и подсказка по выбору вложенного skill'а (funnel/serve/acl/add-node/troubleshooting/hygiene/hard-rules). Активируется при любом вопросе или задаче про Tailscale в контексте Cascade — настройка ноды, экспозиция MCP, диагностика сетевых проблем, правки ACL, добавление нового peer, regular cleanup.
---

# Cascade × Tailscale — обзор

_Версия 1.1 от 2026-05-14 (с учётом compliance audit и architecture-errors review)._

## Когда применять

Любая работа с Tailscale в контексте Cascade VPN / Tier 2 / cascade-browser / cascade-state / cascade-out. Если запрос не про Tailscale — этот skill не нужен.

## Source of truth для tailnet inventory

| Уровень | Источник | Что в нём |
|---|---|---|
| Canonical (живой) | **admin.tailscale.com → Machines** | Текущее состояние tailnet (32 устройств), tags, online/offline, key expiry |
| Generated mirror | **`state/tailscale-tailnet.md`** | Дамп админки через cascade-browser MCP (`browser_read_active_tab`); regen вручную, см. [[cascade-tailscale-hygiene]] |
| Roles + descriptions | **`state/nodes.md`** | Что делает каждая нода, recovery channels, SSH host-keys |
| Skill overview (этот файл) | Core fleet only (12 из 32) | Pattern reference, НЕ полный inventory |

⚠️ **Этот SKILL.md покрывает 12 core nodes**, остальные 20 (Android, iOS, orphan, mobile, offline) — в `state/tailscale-tailnet.md`. Не считай этот документ исчерпывающим inventory.

## Какой sub-skill вызывать

| Запрос содержит | Использовать | Что внутри |
|---|---|---|
| "Funnel", "опубликовать на интернет", "claude.ai connector URL", "raw.githubusercontent домен" | [[cascade-tailscale-funnel]] | Funnel CLI, HTTPS Certificates toggle, `allowed_hosts` patch для server.py, troubleshooting cert provisioning |
| "Serve", "только в tailnet", "внутренний MCP", "не публиковать" | [[cascade-tailscale-serve]] | `tailscale serve`, разница с Funnel, ACL для tagged серверов |
| "ACL", "tag", "права", "разрешить/запретить", "policy file" | [[cascade-tailscale-acl]] | JSON ACL для Cascade: tags `cascade-primary`/`cascade-server`/`cascade-emergency`/`cascade-exit`, forbidden nodes, грант funnel attribute |
| "Добавить новую ноду", "SER10", "tailscale up", "OAuth join" | [[cascade-tailscale-add-node]] | Шаги добавления (PowerShell+WSL), флаги, MagicDNS, регистрация в admin |
| "421 Invalid Host", "cert not provisioned", "MagicDNS не резолвит", "tailscale.exe из WSL" | [[cascade-tailscale-troubleshooting]] | Типичные ошибки + диагностика |
| Хочешь предотвратить новые ошибки в скриптах автоматизации | [[cascade-tailscale-hard-rules]] | АБСОЛЮТНЫЕ правила (--ssh=false, gl-mt6000-* not-touch) |
| Quarterly cleanup, identify orphan nodes, regen tailscale-tailnet.md, Bearer rotation | [[cascade-tailscale-hygiene]] | Регулярная гигиена: cleanup offline >90d, audit unknown peers, doc drift fix |

## Cascade fleet × Tailscale на 2026-05-14

| Node | TS IP | Hostname | Funnel? | Serve? | Role |
|---|---|---|---|---|---|
| **SER10 Pattaya-1** | TBD (15.05+) | `ser10-tha-1.tail80c5d4.ts.net` | да (`https://ser10-tha-1...ts.net/mcp` для cascade-browser) | — | PRIMARY (после 15.05) |
| **MSI** | 100.117.0.35 | `desktop-4sl95n4.tail80c5d4.ts.net` | да (cascade-browser preview) | — | BACKUP (после 15.05) |
| **opus-cwr-bkk** | 100.70.212.16 | `opus-cwr-bkk.tail80c5d4.ts.net` | да (`/mcp` для cascade-mcp state-tool) | — | 24/7 VDS, state mirror, MCP `get_cascade_state` |
| **bkk-exit** | 100.125.240.18 | `bkk-exit.tail80c5d4.ts.net` | — | — | Thailand exit node (mobile S25 + S7) |
| **vultr-amsterdam** | 100.78.149.108 | — | — | — | NL exit (VPN bridge через MSK-VPS) |
| **stockholm** | 100.70.187.116 | — | — | — | VPN-bridge backup |
| **MSK-VPS** | 100.103.182.81 (tailnet) | — | — | — | AmneziaWG terminator (RU) |
| **timeweb-cascade-in** | 100.102.240.52 | — | — | — | Beget container peer |
| **gl-mt6000-1** | 100.109.97.16 | — | — | — | ⛔ home router NEVER TOUCH |
| **gl-mt6000 Thai** | 100.76.55.53 | — | — | — | ⛔ recovery node NEVER TOUCH |
| **glkvm** | 100.76.24.102 | — | — | — | ⛔ emergency access NEVER TOUCH |
| **beget-cascade-in/out** | — | — | — | — | ⛔ containers SSH refused |

## Ключевые внешние ссылки

- Tailscale admin: https://admin.tailscale.com
- Tailscale Funnel docs: https://tailscale.com/kb/1223/funnel
- Tailscale Serve docs: https://tailscale.com/kb/1242/tailscale-serve
- Tailscale ACL docs: https://tailscale.com/kb/1018/acls
- Tailscale CLI reference: https://tailscale.com/kb/1080/cli

## Перекрёстные правила (обязательно соблюдать)

- **Tailscale SSH запрещён везде** (`--ssh=false`). См. [[cascade-tailscale-hard-rules]].
- Funnel требует HTTPS Certificates + Funnel toggled per-device в admin. См. [[cascade-tailscale-funnel]].
- Все Funnel-exposed серверы должны иметь Host-header whitelist (`TransportSecuritySettings.allowed_hosts` или middleware) — DNS rebinding защита.
- Bearer auth ОБЯЗАТЕЛЕН поверх Funnel (Tailscale не authenticates запросы — Funnel = публичный).
