# INSTALL.md — cascade-bastion-setup пошаговая инструкция

_Detailed step-by-step guide для bastion server (krom7.ru → Cascade tailnet → Beelink RDP)._

См. `README.md` для overview архитектуры.

---

## Pre-flight requirements

### ✅ Что должно быть готово ДО запуска

1. **Ubuntu 24.04 VDS** (fresh install, минимум 2 GB RAM / 20 GB disk)
   - Recommended providers: TimeWeb, Vultr, LightNode, DigitalOcean
   - Public IP с открытым 22, 80, 443
2. **Домен** `krom7.ru` (или другой) с DNS A record → VDS public IP
   - Propagation должна быть готова: `dig +short krom7.ru` возвращает VDS IP
3. **Tailscale account** + auth key
4. **PC Beelink** с:
   - Tailscale установленным, joined в cascade tailnet
   - RDP enabled (Windows: Settings → System → Remote Desktop ON)
   - В tailnet с hostname (рекомендую `beelink-ser10` или `beelink-pattaya`)
5. **Tailnet ACL** позволяет `tag:cascade-bastion` достучаться к Beelink:3389
6. **Email** для Let's Encrypt notifications

---

## Step 0 — Pre-flight (15 минут)

### Step 0.1 — DNS

📋 У registrar (Reg.ru, GoDaddy, и т.д.):

1. Создать **A record:** `krom7.ru → <VDS_PUBLIC_IP>`
2. (Optional) `www.krom7.ru → <VDS_PUBLIC_IP>` если хочешь www-redirect
3. Подождать propagation (1-30 мин)
4. Verify: `nslookup krom7.ru 8.8.8.8` или `dig +short krom7.ru`

⚠️ **Без DNS Let's Encrypt не выдаст cert** — будет HTTP-01 challenge fail.

### Step 0.2 — Tailscale auth key

📋 https://login.tailscale.com/admin/settings/keys

1. **Generate auth key**
2. Settings:
   - ✅ Reusable, ❌ Ephemeral, ✅ Pre-approved
   - Tags: `tag:cascade-bastion`
3. **Copy** ключ
4. Verify `tag:cascade-bastion` в `tagOwners` policy file (если нет — добавить)

### Step 0.3 — Beelink в tailnet

📋 На Beelink (Windows):

1. Download Tailscale: https://tailscale.com/download/windows → install
2. Login → join cascade tailnet (account `krom00070007@gmail.com`)
3. **Hostname:** в admin → Machines → Edit → `beelink-ser10` (или другой descriptive)
4. **Tags:** в admin → Edit → `tag:cascade-primary` или `tag:cascade-backup`
5. **Verify RDP:**
   ```powershell
   # PowerShell admin на Beelink:
   (Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name fDenyTSConnections).fDenyTSConnections
   # должно быть 0 (RDP enabled)

   # Если 1 (disabled):
   Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name fDenyTSConnections -value 0
   Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
   ```

6. **Verify tailnet IP:**
   ```powershell
   tailscale.exe ip -4
   # e.g. 100.X.Y.Z — запиши, потребуется в config
   ```

### Step 0.4 — Tailnet ACL (если ACL deploy'нут)

В admin policy file:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:cascade-bastion"],
      "dst": ["tag:cascade-primary:3389", "tag:cascade-backup:3389"]
    }
  ]
}
```

Если ACL **не deploy'нут** (текущее состояние на 2026-05-14, см. cascade-tailscale-acl skill) — `cascade-bastion` сможет достучаться к Beelink по умолчанию (default-allow).

---

## Step 1 — Connect + download (5 минут)

### Step 1.1 — SSH

```bash
ssh root@<VDS_IP>
```

### Step 1.2 — Download

```bash
mkdir -p /opt/cascade-bastion
cd /opt/cascade-bastion

for f in 00-bootstrap.sh 01-system-prep.sh 02-sshd-harden.sh 03-firewall.sh \
         04-swap.sh 05-sysctl-tuning.sh 06-docker-install.sh 07-guacamole-deploy.sh \
         08-nginx-install.sh 09-letsencrypt.sh 10-tailscale-install.sh \
         11-tailscale-up.sh 12-add-beelink-connection.sh 13-validate.sh \
         cascade-bastion-setup.conf.sample README.md INSTALL.md; do
    curl -fsSL "https://raw.githubusercontent.com/krom00070007-beep/cascade-bootstrap/main/scripts/cascade-bastion-setup/$f" -o "$f"
done
chmod +x *.sh
ls -la
```

### Step 1.3 — Config

```bash
cp cascade-bastion-setup.conf.sample cascade-bastion-setup.conf
nano cascade-bastion-setup.conf
```

**Обязательно заполнить:**

```bash
HOSTNAME="cascade-bastion-krom7"
ADMIN_USER="usersstas"
TZ="Asia/Bangkok"

DOMAIN="krom7.ru"
LETSENCRYPT_EMAIL="krom00070007@gmail.com"

TAILSCALE_AUTHKEY="tskey-auth-XXX..."
TAILSCALE_TAGS="tag:cascade-bastion"
USE_EXIT_NODE_HOSTNAME="bkk-exit"  # chained outbound

BEELINK_TAILSCALE_HOST="beelink-ser10"
BEELINK_PROTOCOL="rdp"
BEELINK_PORT="3389"
BEELINK_USERNAME="krom0"

GUACAMOLE_ADMIN_USER="guacadmin"
GUACAMOLE_ADMIN_PASS="changeme-strong-pass-here"   # ⚠️ ИЗМЕНИ обязательно

POSTGRES_PASSWORD="changeme-postgres-strong"
```

Save (Ctrl+O, Ctrl+X), `chmod 600 cascade-bastion-setup.conf`.

---

## Step 2 — Запуск (15-25 минут)

```bash
sudo ./00-bootstrap.sh
```

### Expected timeline:

| Phase | Что делает | Время |
|---|---|---|
| 1 — system-prep | apt + admin user + unattended-upgrades | 2-3 мин |
| 2 — sshd-harden | key-only sshd | 5 сек |
| 3 — firewall | fail2ban + ufw | 10 сек |
| 4 — swap | 2 GB swapfile | 5 сек |
| 5 — sysctl | BBR + buffers + ip_forward | 5 сек |
| 6 — docker | install Docker CE | 1-2 мин |
| 7 — guacamole | docker compose pull + up (большая часть time) | 3-5 мин |
| 8 — nginx | install + initial config | 30 сек |
| 9 — Let's Encrypt | certbot --nginx -d krom7.ru | 30-60 сек |
| 10 — tailscale install | apt | 30 сек |
| 11 — tailscale up | join + chained exit set | 10 сек |
| 12 — beelink connection | SQL insert | 5 сек |
| 13 — validate | 13 checks | 5 сек |

**Expected final output:**

```
==== cascade-bastion-setup validation ====
  ✓ nginx active
  ✓ docker active
  ✓ Guacamole container healthy
  ✓ guacd container healthy
  ✓ postgres container healthy
  ✓ Guacamole port 8080 listening
  ✓ nginx 443 listening (SSL)
  ✓ Let's Encrypt cert exists
  ✓ tailscale joined
  ✓ Tailscale RunSSH=false
  ✓ ufw active
  ✓ fail2ban active
  ✓ https://krom7.ru returns 200/302

==== RESULT: 13 passed / 0 failed ====
```

---

## Step 3 — Access verification (10 минут)

### Step 3.1 — Browser test

📋 В браузере:

1. Open `https://krom7.ru`
2. Должен открыться Guacamole login page (с Let's Encrypt valid cert padlock)
3. Login: `guacadmin` / `<password из config>`
4. **🚨 Change password immediately:**
   - Settings (top right gear) → Preferences → Update Password
   - Set strong password, **скопируй в password manager**
5. Должно быть видно connection: **Beelink-Pattaya**
6. Click → должен открыться RDP к Beelink
7. Login на Beelink через Windows credentials

**Expected:** Beelink desktop в браузере.

### Step 3.2 — Desktop client (alternative)

📋 На client device (другой PC / mobile / laptop):

1. Install Tailscale: https://tailscale.com/download
2. Login → join cascade tailnet
3. После join — Beelink доступен напрямую как `beelink-ser10.tail80c5d4.ts.net:3389`
4. Open Windows Remote Desktop (mstsc) или Microsoft Remote Desktop (Mac):
   - Computer: `beelink-ser10.tail80c5d4.ts.net`
   - Username: krom0 (or whoever)
5. Connect

---

## Step 4 — Tailnet config (5 минут)

### Step 4.1 — admin.tailscale.com

📋 https://login.tailscale.com/admin/machines

1. Find `cascade-bastion-krom7` → click
2. **Toggle:** "Disable key expiry" (для long-lived bastion)
3. (Опционально) "Allow this node as exit node" если хочешь bastion как exit для других peers

### Step 4.2 — Add to MSI cascade-doctor (опционально)

Чтобы daily monitor включал bastion server:

📋 На MSI:

```bash
cd ~/projects/cascade-state/scripts/cascade-doctor
nano cascade-doctor.sh
# Add to FULL_SSH_NODES:
#     "cascade-bastion-krom7|root@<tailnet IP>|bastion|guacamole_running"
git add cascade-doctor.sh
git commit -m "cascade-doctor: monitor cascade-bastion-krom7"
git push origin main
```

(Можно также добавить custom check `docker ps --filter name=guacamole`.)

---

## Step 5 — Daily operations

### Browser access (most common)

1. `https://krom7.ru`
2. Login
3. Click connection → connect

### Restart Guacamole

```bash
cd /opt/guacamole
docker compose restart
```

### Update Guacamole version

```bash
cd /opt/guacamole
# Edit docker-compose.yml — bump image versions (e.g. 1.5.4 → 1.6.0)
docker compose pull
docker compose up -d
```

### Backup Guacamole DB

```bash
docker exec guac-postgres pg_dump -U guacamole_user guacamole_db > /tmp/guac-backup-$(date +%Y%m%d).sql
# transfer куда-то safe
```

### Add more connections (другие peers)

Web UI: Settings → Connections → New Connection.

Или SQL через `12-add-beelink-connection.sh` template — modify за вторую ноду.

### Renew SSL (automatic)

`certbot.timer` runs every 12h, renews если cert expires < 30 дней. Verify:

```bash
systemctl list-timers certbot.timer
```

---

## Troubleshooting per phase

| Phase | Symptom | Решение |
|---|---|---|
| 7 (Guacamole) | container не starts | `docker compose logs guacamole` → обычно DB init issue. Try `docker compose down -v; docker compose up -d` (это **erase data** — только если ничего ценного) |
| 9 (Let's Encrypt) | `Failed authorization for $DOMAIN` | DNS не resolves → wait propagation. `dig +short $DOMAIN` должен возвращать твой VDS IP. |
| 11 (Tailscale) | `auth key invalid` | Regenerate в admin → update в config → re-run. |
| 12 (SQL insert) | `relation guacamole_connection does not exist` | DB schema не initialized. Restart compose: `docker compose down; docker compose up -d`. |
| nginx 502 Bad Gateway | Guacamole down | `docker ps; docker compose logs guacamole` |
| RDP connection fails | Beelink offline/firewall | `tailscale ping beelink-ser10` с bastion — должен pong. Если не pong → Beelink offline или Tailscale на нём не активен. |
| Slow RDP | Bandwidth | См. cascade-tailscale-troubleshooting (BBR tuning); попробуй уменьшить RDP color depth до 16-bit |

---

## Rollback

```bash
# Stop services
cd /opt/guacamole && docker compose down -v
systemctl stop nginx
tailscale logout
tailscale down
apt remove --purge -y nginx certbot docker-ce tailscale
ufw --force reset

# Cleanup
rm -rf /opt/guacamole /opt/cascade-bastion
rm /etc/nginx/sites-enabled/*
rm -rf /etc/letsencrypt
rm /etc/sysctl.d/99-cascade-*.conf
swapoff /swap.img; rm /swap.img
sed -i '/swap.img/d' /etc/fstab
sysctl --system
```

Затем удалить ноду в admin.tailscale.com → Machines → Delete.

---

## Security checklist

После deploy убедись:

- [ ] Guacamole default password сменён (`guacadmin/guacadmin` → strong)
- [ ] Postgres password в config был strong (не `changeme-...`)
- [ ] SSH работает только key (test from другой машины: `ssh -o PasswordAuthentication=no root@<VDS>` — должен accept)
- [ ] fail2ban active
- [ ] ufw active, только 22/80/443/41641 open
- [ ] Tailscale RunSSH=false
- [ ] HTTPS only (HTTP redirect to HTTPS)
- [ ] HSTS header в nginx response: `curl -I https://krom7.ru | grep -i strict`

---

## FAQ

**Q: Может работать без своего домена?**
A: Yes — используй `tailscale funnel` вместо Let's Encrypt + nginx (publish Guacamole на `<hostname>.tail80c5d4.ts.net`). Замени Phase 8-9 на `tailscale funnel --bg 443` через portproxy 8080→443. Pattern такой же как в cascade-msi-setup Phase 9.

**Q: Безопасно ли давать access всем по krom7.ru?**
A: Layers защиты:
1. Guacamole login (username/password)
2. Beelink Windows login (отдельный credentials)
3. fail2ban на failed Guacamole logins (можно настроить filter)
4. nginx может ограничить IP allowlist если хочется
5. (Опционально) Cloudflare front + WAF

**Q: Сколько concurrent users поддерживает Guacamole?**
A: На 2 GB VDS — 3-5 одновременных sessions комфортно. Больше — нужно scale VDS (4-8 GB) + горизонтальный scale (multiple guacd containers).

**Q: Можно проксить SSH к Beelink через Guacamole?**
A: Yes — Guacamole supports SSH/Telnet помимо RDP/VNC. В config укажи `BEELINK_PROTOCOL="ssh"`, `BEELINK_PORT="22"`.

**Q: Что если Tailscale на Beelink выключится?**
A: Beelink станет unreachable через tailnet. Web access через krom7.ru тоже сломается. Решение: на Beelink убедись `Tailscale → Settings → Start on boot ON`.

**Q: Альтернатива Guacamole?**
A: Apache Guacamole — самый mature open-source. Альтернативы: rustdesk (self-hosted, P2P), MeshCentral (full RMM suite), NoMachine (proprietary). Guacamole = baseline.

---

## Cross-refs

- `README.md` — overview архитектуры
- `cascade-bastion-setup.conf.sample` — config template
- `scripts/cascade-server-setup/` — generic Linux setup (без Guacamole)
- `scripts/cascade-msi-setup/` — Windows + WSL для MSI rebuild
- `docs/audits/cascade-architecture-errors-2026-05-14.md` — известные issues
- `skills/cascade-tailscale-funnel/SKILL.md` — Funnel alternative для Guacamole без своего домена
- `skills/cascade-browser-overview/SKILL.md` — общая cascade-browser картина (different use case)
