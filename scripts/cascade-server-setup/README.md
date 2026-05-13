# cascade-server-setup — bootstrap new Ubuntu 24.04 VDS

End-to-end setup script для нового Linux VDS, который должен:
1. **Tailscale exit-node** (advertise) — peers могут использовать этот сервер для outbound
2. **Chained outbound** — этот сервер сам использует ДРУГОЙ Tailscale peer как exit-node
3. **AutoDoctor локально** — daily self-check + Telegram self-report

## Baked-in fixes известных ошибок Cascade

(на основе `docs/audits/cascade-architecture-errors-2026-05-14.md` + `cascade-servers-revision-2026-05-14.md`)

| Issue (из audits) | Fix в setup |
|---|---|
| sshd permitrootlogin/passwordauth/x11 = yes (5/5 серверов) | 02-sshd-harden.sh patches к `prohibit-password / no / no` |
| fail2ban отсутствует (bkk-exit, msk-vps-bridge) | 03-firewall.sh installs + enables |
| ufw not installed (vultr.guest) | 03-firewall.sh installs + configures |
| 0 swap (3 серверов) | 04-swap.sh default 1 GB |
| apt upgradable security overdue | 01-system-prep `apt upgrade` + unattended-upgrades |
| Tailscale SSH (`--ssh=true`) — hard rule violation | 07-tailscale-up forces `--ssh=false` |
| ip_forward не setting для exit-node | 05-sysctl-tuning enables + persists |

## Hard rules enforced

- ❌ `--ssh=false` ВСЕГДА (Tailscale SSH forbidden)
- ❌ Никаких forbidden node IPs / hostnames (gl-mt6000-*, glkvm, beget-*) в этом скрипте — он для НОВОГО сервера, никаких операций на других нодах
- ❌ Никаких secrets / tokens в скрипте — только через `cascade-server-setup.conf` (gitignore'нут)

## Performance tuning (минимальная потеря скорости)

В `05-sysctl-tuning.sh`:
- **TCP BBR** congestion control (vs default CUBIC) — лучше для high-latency VPN paths
- **fq qdisc** для BBR fair queuing
- **TCP Fast Open** (3 = client+server)
- Большие socket buffers (16 MB max)
- `nf_conntrack_max=524288` (high-concurrency NAT exit)
- File descriptor limit 1M
- swappiness=10 (минимум swap usage)

Result (typical Ubuntu 24.04 VDS):
- Loss baseline без tuning: ~15-25% bandwidth penalty в chained-routing
- С tuning: ~3-8% penalty (BBR + buffers + fq)

## Files в этой папке

```
scripts/cascade-server-setup/
├── 00-bootstrap.sh                # ⚡ Entry point — calls phases 01-09
├── 01-system-prep.sh              # apt + admin user + SSH keys + unattended-upgrades
├── 02-sshd-harden.sh              # key-only + modern algorithms
├── 03-firewall.sh                 # fail2ban + ufw
├── 04-swap.sh                     # 1 GB swap по умолчанию
├── 05-sysctl-tuning.sh            # BBR + buffers + ip_forward + conntrack
├── 06-tailscale-install.sh        # official apt repo
├── 07-tailscale-up.sh             # join tailnet (pre-auth key или OAuth)
├── 08-tailscale-exit-config.sh    # advertise-exit-node + chained exit
├── 09-local-doctor.sh             # daily self-check + Telegram
├── cascade-server-setup.conf.sample
└── README.md (этот файл)
```

## Setup steps (на новом VDS, как root)

### Step 1 — download + config

```bash
# As root on fresh Ubuntu 24.04 box:
mkdir -p /opt/cascade-server-setup
cd /opt/cascade-server-setup

# Download (например через cascade-bootstrap public repo)
curl -fsSL https://raw.githubusercontent.com/krom00070007-beep/cascade-bootstrap/main/scripts/cascade-server-setup/00-bootstrap.sh -o 00-bootstrap.sh
# (или клонить весь репо если git installed)
# git clone https://github.com/krom00070007-beep/cascade-bootstrap.git .

# Скачать остальные scripts тем же образом, или:
for f in 01-system-prep.sh 02-sshd-harden.sh 03-firewall.sh 04-swap.sh \
         05-sysctl-tuning.sh 06-tailscale-install.sh 07-tailscale-up.sh \
         08-tailscale-exit-config.sh 09-local-doctor.sh \
         cascade-server-setup.conf.sample; do
    curl -fsSL "https://raw.githubusercontent.com/krom00070007-beep/cascade-bootstrap/main/scripts/cascade-server-setup/$f" -o "$f"
done
chmod +x *.sh

# Config
cp cascade-server-setup.conf.sample cascade-server-setup.conf
nano cascade-server-setup.conf   # заполни TAILSCALE_AUTHKEY, hostname, etc.
chmod 600 cascade-server-setup.conf
```

### Step 2 — pre-flight tasks в admin.tailscale.com

Перед запуском скрипта:

1. **Generate auth key:**
   - admin.tailscale.com → Settings → Keys → Generate auth key
   - Pre-approved + Reusable + Ephemeral=false
   - Pre-assigned tag `tag:cascade-exit` (если использовать tags)
2. **Tag в tagOwners** — `tag:cascade-exit` должен быть в `tagOwners` в policy file (см. cascade-tailscale-acl skill). Если нет — добавь:
   ```json
   "tagOwners": { "tag:cascade-exit": ["krom00070007@gmail.com"], ... }
   ```
3. **Paste auth key** в `cascade-server-setup.conf` → `TAILSCALE_AUTHKEY="tskey-auth-..."`

### Step 3 — Telegram bot setup (опционально, для self-doctor)

Для local-doctor self-reports:

1. @BotFather → создать нового бота `/newbot`, получить `BOT_TOKEN`
2. Найти chat_id (через @userinfobot или @get_id_bot — message от твоего юзера)
3. Заполнить в conf: `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID`

Если не нужно — оставить пустыми; отчёты будут только в `/var/log/cascade-local-doctor/`.

### Step 4 — run

```bash
sudo ./00-bootstrap.sh
```

Время: ~5-10 минут (зависит от apt + Tailscale auth).

Если `TAILSCALE_AUTHKEY` пустой — скрипт остановится на Phase 7 + распечатает interactive команду `tailscale up ...`. Тогда:
- Скопируй команду, запусти руками
- Open URL в браузере → OAuth → выбери account
- После join — запусти `./08-tailscale-exit-config.sh` чтобы завершить

### Step 5 — admin tasks (после bootstrap)

1. **admin.tailscale.com → Machines → этот host:**
   - ✅ Enable `Allow this node as exit node`
   - ✅ Approve subnet routes (если advertised)
   - ✅ Disable key expiry (для long-lived exit nodes)

2. **Verify chained exit works:**
   От другой ноды tailnet:
   ```bash
   tailscale set --exit-node=<new-server-hostname>
   curl -s ifconfig.me      # должен показать egress IP того ДРУГОГО peer (USE_EXIT_NODE_HOSTNAME)
   ```

3. **Add to MSI cascade-doctor:**
   В `~/projects/cascade-state/scripts/cascade-doctor/cascade-doctor.sh` добавить:
   ```bash
   FULL_SSH_NODES=(
       ...
       "<new-hostname>|root@<new-tailnet-ip>|exit|"
   )
   ```
   Commit + push. MSI doctor подхватит ноду в next daily run.

## Verification на новом сервере

```bash
# System
hostname
uptime
free -h
df -h /

# Tailscale
tailscale status --self
tailscale ip -4
tailscale debug prefs | grep -E "(RunSSH|ExitNode|AdvertiseExit|AdvertiseRoutes)"

# Performance
sysctl net.ipv4.ip_forward net.core.default_qdisc net.ipv4.tcp_congestion_control

# Security
sshd -T | grep -E "^(permitroot|password|x11)"
systemctl status fail2ban ufw

# Doctor
systemctl status cascade-local-doctor.timer
cascade-local-doctor              # manual test run
ls -la /var/log/cascade-local-doctor/
```

## Speed loss expectations

Chained routing client → THIS server → other-exit → internet:

| Hop | Approximate cost |
|---|---|
| Client → этот сервер | ~20-50 ms (Tailscale wireguard, geo-dependent) |
| Этот сервер → other-exit-peer | ~20-100 ms |
| **Total RTT increase vs direct internet** | **~50-150 ms** typical |
| **Bandwidth vs direct** | **80-95%** (с BBR + tuning) |

Worst case (no tuning, default CUBIC): bandwidth penalty 50-70%. Зачем нам tuning.

## Troubleshooting

| Symptom | Решение |
|---|---|
| Phase 7 "no IP yet" | Run `tailscale up` руками в interactive mode |
| `bash: tailscale: command not found` после 06 | Reboot или `source /etc/profile` для PATH refresh |
| sshd refuses key after 02 | Check `/var/log/auth.log`, verify `/home/$ADMIN_USER/.ssh/authorized_keys` — если пусто, скопируй вручную через `cat ~/key.pub >> ~/.ssh/authorized_keys` |
| `tailscale set --exit-node=$IP` fails | Verify $USE_EXIT_NODE_HOSTNAME peer is `Allow exit node` в admin |
| ufw blocks important traffic | Check `ufw status numbered`, add explicit allow rules для нужных портов |
| local-doctor timer не fire'тся | `systemctl list-timers --all`; if no `cascade-local-doctor.timer` — `systemctl enable --now cascade-local-doctor.timer` |
| Telegram bot не отвечает | Verify TOKEN + CHAT_ID right; test через `curl https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text=test` |

## Future enhancements

- v1.1 — IPv6 dual-stack
- v1.2 — Cloudflare WARP fallback (если Tailscale exit-peer down)
- v1.3 — Prometheus node_exporter для metric export
- v1.4 — DDoS protection (CrowdSec or fail2ban + iptables rules)

См. `docs/audits/cascade-doctor-future-tiers.md` для общего AutoDoctor roadmap.

## Cross-refs

- `docs/audits/cascade-architecture-errors-2026-05-14.md` — какие ошибки fix'нуты этим скриптом
- `docs/audits/cascade-servers-revision-2026-05-14.md` — per-server baseline что должно быть
- `skills/cascade-tailscale-add-node/SKILL.md` — общий workflow добавления Tailscale node
- `skills/cascade-tailscale-acl/SKILL.md` — tagOwners pre-req
- `scripts/cascade-doctor/cascade-doctor.sh` — MSI-side doctor куда добавить новую ноду
