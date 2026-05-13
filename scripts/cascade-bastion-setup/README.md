# cascade-bastion-setup — VDS bastion для remote desktop через krom7.ru

VDS на Ubuntu 24 как web-based remote desktop bridge к PC Beelink (Pattaya) через Cascade tailnet.

## Архитектура

```
┌──────────────┐
│   Browser    │ → https://krom7.ru → nginx (443) → Guacamole web UI
│  (любой PC)  │                                          ↓
└──────────────┘                                       guacd
                                                          ↓
┌──────────────┐                                       Tailscale tailnet
│Desktop client│ ──┐                                     ↓
│ (Tailscale) │   │                            ┌─────────────────────┐
└──────────────┘  │                            │  bkk-exit (Bangkok) │  (optional chain)
                  │                            └─────────────────────┘
                  │                                     ↓
                  │                            ┌─────────────────────┐
                  │                            │ opus-cwr-bkk (relay) │
                  │                            └─────────────────────┘
                  │                                     ↓
                  └─────────────────────────→ Beelink-SER10 (Pattaya home LAN)
                              RDP/VNC via tailnet IP        ↑
                                                        Beelink in same
                                                        LAN as MSI
```

**Два access patterns:**

1. **Browser (no setup на client):**
   - User → `https://krom7.ru` → login → Click "Beelink-Pattaya" → RDP в браузере
   - Trafffic: browser → krom7.ru:443 (HTTPS) → Guacamole web → guacd → Tailscale → Beelink

2. **Desktop client (Tailscale installed):**
   - User установил Tailscale → joined cascade tailnet
   - Любой RDP/VNC client → подключается к `beelink-ser10.tail80c5d4.ts.net:3389`
   - Trafffic: client → Tailscale tunnel → Beelink (direct, без bastion)

## Components

| Service | Role | Port |
|---|---|---|
| **nginx** | Reverse proxy + SSL termination | 80/443 |
| **certbot** | Let's Encrypt cert auto-renew | — |
| **guacamole** (Docker) | Web UI + connection manager | 8080 (localhost only) |
| **guacd** (Docker) | RDP/VNC/SSH protocol handler | internal |
| **postgres** (Docker) | Guacamole DB (users + connections) | internal |
| **tailscaled** | Tailscale daemon | 41641/udp |

## Файлы (15 total / 753 строки)

```
scripts/cascade-bastion-setup/
├── 00-bootstrap.sh                 # Main entry, 13 phases
├── 01-system-prep.sh               # apt + admin user + unattended-upgrades
├── 02-sshd-harden.sh               # key-only
├── 03-firewall.sh                  # ufw 22/80/443/41641udp + fail2ban
├── 04-swap.sh                      # 2 GB
├── 05-sysctl-tuning.sh             # BBR + buffers + ip_forward
├── 06-docker-install.sh            # Docker CE + compose
├── 07-guacamole-deploy.sh          # docker compose up (guacd + guacamole + postgres)
├── 08-nginx-install.sh             # Initial site config
├── 09-letsencrypt.sh               # certbot SSL для $DOMAIN
├── 10-tailscale-install.sh         # apt repo + install
├── 11-tailscale-up.sh              # tailscale up + chained exit к bkk-exit
├── 12-add-beelink-connection.sh    # SQL insert RDP connection
├── 13-validate.sh                  # E2E checks
├── cascade-bastion-setup.conf.sample
├── README.md (этот файл)
└── INSTALL.md (детальная инструкция)
```

## Quick start

```bash
# As root on fresh Ubuntu 24.04:
mkdir -p /opt/cascade-bastion && cd /opt/cascade-bastion
for f in 00-bootstrap.sh 01-system-prep.sh 02-sshd-harden.sh 03-firewall.sh \
         04-swap.sh 05-sysctl-tuning.sh 06-docker-install.sh 07-guacamole-deploy.sh \
         08-nginx-install.sh 09-letsencrypt.sh 10-tailscale-install.sh \
         11-tailscale-up.sh 12-add-beelink-connection.sh 13-validate.sh \
         cascade-bastion-setup.conf.sample README.md INSTALL.md; do
    curl -fsSL "https://raw.githubusercontent.com/krom00070007-beep/cascade-bootstrap/main/scripts/cascade-bastion-setup/$f" -o "$f"
done
chmod +x *.sh
cp cascade-bastion-setup.conf.sample cascade-bastion-setup.conf
nano cascade-bastion-setup.conf   # fill in TAILSCALE_AUTHKEY, BEELINK_TAILSCALE_HOST, etc.
sudo ./00-bootstrap.sh
```

Time: 15-25 минут (Docker pull + Let's Encrypt + apt).

## Pre-flight requirements

| Step | Что |
|---|---|
| **DNS** | A record `krom7.ru → <VDS public IP>` propagated |
| **Tailscale auth key** | reusable + tag:cascade-bastion (см. INSTALL.md) |
| **Beelink** | Tailscale установлен, RDP enabled, в tailnet с hostname `beelink-ser10` |
| **Tailnet ACL** | `tag:cascade-bastion` → can reach `tag:cascade-primary` / `tag:cascade-backup` (где Beelink) |

## Baked-in fixes из Cascade audits

| Issue | Fix |
|---|---|
| sshd permitrootlogin/passwordauth/x11 yes | 02-sshd-harden patches |
| fail2ban not installed (public-IP nodes) | 03-firewall installs + enables |
| ufw not configured | 03-firewall configures 22/80/443/41641-udp |
| 0 swap | 04-swap 2 GB default |
| Tailscale `--ssh=true` violation | 11-tailscale FORCED `--ssh=false` |
| ip_forward не set для exit-node | 05-sysctl enables |
| TCP BBR not enabled | 05-sysctl + fq qdisc |

## Performance expectations

| Hop | Latency | Bandwidth |
|---|---|---|
| Browser → krom7.ru (VDS) | depends on geo, ~50-200 ms | depends on VDS plan |
| krom7.ru → bkk-exit (chained) | +20-100 ms | 80-95% (с BBR tuning) |
| bkk-exit → Beelink (tailnet) | +20-100 ms | 80-95% |
| **Total RDP latency vs direct** | **+50-200 ms** | **70-85% direct** |

С BBR tuning latency очень приемлимая для RDP/VNC. Без — будет sluggish.

## Cross-refs

- `INSTALL.md` — step-by-step deployment guide
- `scripts/cascade-server-setup/` — generic Ubuntu setup (без Guacamole)
- `scripts/cascade-msi-setup/` — Windows + WSL setup (для MSI rebuild)
- `scripts/migration/` — MIG-001 for SER10
- `skills/cascade-tailscale-overview/SKILL.md` — общая карта tailnet
- `docs/audits/cascade-architecture-errors-2026-05-14.md` — known issues
