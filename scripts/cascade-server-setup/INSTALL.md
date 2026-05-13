# INSTALL.md — cascade-server-setup пошаговая инструкция запуска

_Detailed step-by-step deployment guide. Версия 1.0._

Для общего обзора что делает скрипт — см. `README.md`.
Этот документ — **детальная инструкция оператора** с примерами вывода и checkpoint'ами после каждого шага.

---

## Предварительные требования (Pre-flight)

### ✅ Что должно быть готово ДО запуска

Прежде чем запускать `00-bootstrap.sh`:

1. **Свежий Ubuntu 24.04 LTS server** — clean install, root доступ или sudo
2. **Минимум 1 GB RAM** (рекомендуется 2+ GB)
3. **Минимум 10 GB disk** (скрипт использует ~2 GB; swap 1 GB; буфер для logs)
4. **Internet доступ** для apt + Tailscale apt repo + GitHub keys
5. **Tailscale auth key** (см. Step 0.1 ниже)
6. **(Опционально) Telegram bot token + chat ID** (см. Step 0.2 ниже)
7. **SSH доступ открыт** для admin (но мы его hardenим в процессе)

### ⚠️ Важные предупреждения

- **Скрипт меняет sshd config** — убедись что у тебя есть **резервный канал** (KVM / console / другая SSH session) на случай если первая SSH сессия закроется
- **Не запускай скрипт без `cascade-server-setup.conf`** — упадёт сразу
- Скрипт **idempotent** — можно перезапустить если что-то упало; пропустит уже-сделанные шаги
- **Не commit'ить `cascade-server-setup.conf`** — содержит секреты (Tailscale auth key, Telegram token)

---

## Step 0 — Pre-flight setup (5-10 минут)

### Step 0.1 — Создание Tailscale auth key

📋 В браузере на админ-машине:

1. Открыть https://login.tailscale.com/admin/settings/keys
2. Click **"Generate auth key"**
3. Настройки:
   - ✅ **Reusable** = ON (можно использовать несколько раз если будут перезапуски)
   - ❌ **Ephemeral** = OFF (нужен permanent device record)
   - ✅ **Pre-approved** = ON (skip manual approval в admin)
   - ✅ **Tags** = `tag:cascade-exit` (или другой нужный tag)
     - ⚠️ Если этого tag ещё нет в `tagOwners` policy file — добавь сначала (см. cascade-tailscale-acl skill)
4. Click **"Generate key"**
5. Скопируй ключ (формат `tskey-auth-XXXXXX...`) — это **secret**, не commit'ить

**Запомни этот ключ** — пригодится в Step 1.

### Step 0.2 — (Опционально) Telegram bot для self-doctor

📋 В Telegram на телефоне или desktop:

1. **Найти @BotFather** → start
2. Команда **`/newbot`**
3. Имя бота — например `cascade_doctor_<servername>_bot` (должен быть unique)
4. Получишь `BOT_TOKEN` формата `1234567890:ABCdefGHIjklMNOpqrSTUvwxYZ`
5. Скопируй ✅

6. Найти **@userinfobot** → start → получишь свой `chat_id` (число вида `123456789`)
7. **Activate** новый bot: найди его в Telegram, нажми **Start** или отправь любое сообщение (иначе bot не сможет тебе отвечать)

**Запомни `BOT_TOKEN` и `CHAT_ID`** — пригодятся в Step 1.

Если Telegram не нужен — пропусти этот шаг, оставь поля пустыми в config.

### Step 0.3 — Решить chained routing setup

cascade-server-setup поддерживает chained exit-node:

```
Client → THIS server (cascade-exit) → ANOTHER peer → Internet
```

Кого использовать как "другой peer"? Зависит от цели:

| Цель | Use exit-node = |
|---|---|
| Trafffic из РФ через NL/EU | `vultr-amsterdam` (100.78.149.108) |
| Через TH/Asia | `bkk-exit` (100.125.240.18) |
| Через RU (для тестирования RU sites) | `russia-vps-exit` (100.71.74.25) |
| Без chain (direct internet с этого сервера) | пустое |

⚠️ Эту нode нужно знать **до запуска** (для config файла). Можно изменить позже через `tailscale set --exit-node=...`.

---

## Step 1 — Download + config (3-5 минут)

### Step 1.1 — Connect к серверу по SSH

📋 На admin-машине:

```bash
ssh root@<NEW_SERVER_IP>
```

Если запросит пароль — введи. Скоро мы это поменяем на key-only.

### Step 1.2 — Download скриптов

📋 На сервере (как root):

```bash
mkdir -p /opt/cascade-server-setup
cd /opt/cascade-server-setup

# Скачать все 12 файлов из public cascade-bootstrap repo
for f in 00-bootstrap.sh 01-system-prep.sh 02-sshd-harden.sh 03-firewall.sh \
         04-swap.sh 05-sysctl-tuning.sh 06-tailscale-install.sh 07-tailscale-up.sh \
         08-tailscale-exit-config.sh 09-local-doctor.sh \
         cascade-server-setup.conf.sample README.md INSTALL.md; do
    echo "Downloading $f..."
    curl -fsSL "https://raw.githubusercontent.com/krom00070007-beep/cascade-bootstrap/main/scripts/cascade-server-setup/$f" -o "$f"
done

# Сделать .sh executable
chmod +x *.sh

# Проверить что всё скачалось
ls -la
```

**Expected output:**

```
total 56
-rwxr-xr-x 1 root root 5972 May 14 03:41 00-bootstrap.sh
-rwxr-xr-x 1 root root 2909 May 14 03:42 01-system-prep.sh
-rwxr-xr-x 1 root root 2027 May 14 03:42 02-sshd-harden.sh
... etc
```

**Если curl упал:**

```bash
curl --version  # есть ли curl?
ping -c 1 raw.githubusercontent.com  # сетка работает?
```

Если curl не установлен:

```bash
apt update && apt install -y curl
```

### Step 1.3 — Создать config файл

📋 На сервере:

```bash
cp cascade-server-setup.conf.sample cascade-server-setup.conf
nano cascade-server-setup.conf
```

(или `vim` / `vi` если nano нет: `apt install -y nano`)

**Заполни обязательно:**

```bash
# Identity
HOSTNAME="ser-thailand-exit-1"      # уникальный имя в tailnet (без точек, lowercase, до 63 chars)
ADMIN_USER="usersstas"               # admin пользователь (создастся)
TZ="Asia/Bangkok"                    # часовой пояс

# Tailscale (CRITICAL)
TAILSCALE_AUTHKEY="tskey-auth-XXX..."  # из Step 0.1
TAILSCALE_TAGS="tag:cascade-exit"
TAILSCALE_ADVERTISE_EXIT_NODE=true

# Chained routing — кого использовать как outbound exit
USE_EXIT_NODE_HOSTNAME="vultr-amsterdam"

# Admin SSH key — откуда тянуть pubkey'и
ADMIN_SSH_PUBKEY_SOURCE="github:krom00070007-beep"

# Telegram (опционально, из Step 0.2)
TELEGRAM_BOT_TOKEN="1234567890:ABC..."   # пустое если не нужно
TELEGRAM_CHAT_ID="123456789"
```

Сохрани (Ctrl+O Enter, Ctrl+X в nano).

**Protect config от прочтения:**

```bash
chmod 600 cascade-server-setup.conf
```

### Step 1.4 — Verify config

📋 На сервере:

```bash
# Проверить что нет пустых обязательных полей
grep -E "^(HOSTNAME|ADMIN_USER|TAILSCALE_AUTHKEY)" cascade-server-setup.conf

# Должно быть 3 непустых строки, например:
# HOSTNAME="ser-thailand-exit-1"
# ADMIN_USER="usersstas"
# TAILSCALE_AUTHKEY="tskey-auth-..."
```

Если HOSTNAME / ADMIN_USER / TAILSCALE_AUTHKEY пустые — заполни ещё раз.

---

## Step 2 — Запуск bootstrap (5-10 минут)

### Step 2.1 — Опционально tmux

Чтобы скрипт не упал если SSH разорвётся (он на 5-10 минут):

📋 На сервере:

```bash
apt install -y tmux 2>/dev/null
tmux new -s setup
```

Внутри tmux запускай скрипт. Если SSH разорвётся — заново подключись и `tmux attach -t setup`.

### Step 2.2 — Запустить

📋 На сервере:

```bash
cd /opt/cascade-server-setup
sudo ./00-bootstrap.sh
```

**Что произойдёт (типичный flow ~5-10 минут):**

```
[2026-05-15 12:00:00] ==== cascade-server-setup start ====
[2026-05-15 12:00:00] Hostname: ser-thailand-exit-1, Admin: usersstas, TZ: Asia/Bangkok
[2026-05-15 12:00:00] --- Phase 1: 01-system-prep.sh ---
... (1-3 минуты: apt update + upgrade + install базовых пакетов)
[01] system prep done

[2026-05-15 12:03:00] --- Phase 2: 02-sshd-harden.sh ---
[02] sshd hardened + reloaded

[2026-05-15 12:03:05] --- Phase 3: 03-firewall.sh ---
Status: active
... (fail2ban + ufw enabled)
[03] firewall configured

[2026-05-15 12:03:15] --- Phase 4: 04-swap.sh (size=1024MB) ---
[04] swap configured: /swap.img (1024 MB), swappiness=10

[2026-05-15 12:03:30] --- Phase 5: 05-sysctl-tuning.sh ---
[05] sysctl tuning applied:
  ip_forward: 1
  congestion control: bbr
  default qdisc: fq
  rmem_max: 16777216

[2026-05-15 12:03:40] --- Phase 6: 06-tailscale-install.sh ---
... (1-2 минуты — apt install tailscale)
[06] tailscale installed

[2026-05-15 12:05:00] --- Phase 7: 07-tailscale-up.sh ---
[07] Using pre-auth key
... (10 sec — tailscale up)
[07] tailscale joined. tailnet IP: 100.x.y.z

[2026-05-15 12:05:15] --- Phase 8: 08-tailscale-exit-config.sh ---
[08] Configuring chain: this server → vultr-amsterdam → internet
[08] Found vultr-amsterdam at 100.78.149.108
[08] Chained exit-node configured

[2026-05-15 12:05:30] --- Phase 9: 09-local-doctor.sh ---
[09] local-doctor installed

[2026-05-15 12:05:45] ==== cascade-server-setup DONE ====
...
```

### Step 2.3 — Если что-то упало

**Phase 1 — apt errors:**

```
E: Could not get lock /var/lib/dpkg/lock-frontend
```
→ Другой apt процесс работает. Подожди или `sudo killall apt apt-get`.

**Phase 2 — sshd test failed:**

```
ERROR: sshd config test failed. Restoring backup.
```
→ Проверь `/etc/ssh/sshd_config` руками, найди syntax error, fix. Запусти `02-sshd-harden.sh` отдельно.

**Phase 6/7 — Tailscale недоступен:**

```
E: Unable to locate package tailscale
```
→ Проверь интернет: `curl -I https://pkgs.tailscale.com`. Возможно DNS issue: `cat /etc/resolv.conf`, замени на `nameserver 1.1.1.1` если нет.

**Phase 7 — auth key invalid:**

```
tailscale: failed to start daemon: auth key is invalid
```
→ Сгенерируй новый auth key в admin (см. Step 0.1). Проверь что в config нет пробелов / лишних кавычек.

### Step 2.4 — Если TAILSCALE_AUTHKEY пустой (Manual OAuth path)

Если в Step 1.3 ты НЕ заполнил auth key — скрипт остановится после Phase 6 с message:

```
[07] No TAILSCALE_AUTHKEY in config — interactive OAuth required.
[07] Run на этом сервере (после exit script):
      tailscale up --hostname=ser-thailand-exit-1 --accept-routes=true --accept-dns=false --ssh=false --advertise-tags=tag:cascade-exit --advertise-exit-node
```

Тогда:

📋 Скопируй команду + запусти руками:

```bash
tailscale up --hostname=ser-thailand-exit-1 --accept-routes=true --accept-dns=false --ssh=false --advertise-tags=tag:cascade-exit --advertise-exit-node
```

Output:

```
To authenticate, visit:

	https://login.tailscale.com/a/abc123...
```

📋 Открой URL в браузере → OAuth → выбери account `krom00070007@gmail.com` → Authorize.

После успешной auth — выполни последние phases:

```bash
./08-tailscale-exit-config.sh
./09-local-doctor.sh  # если ENABLE_LOCAL_DOCTOR=true в config
```

---

## Step 3 — Verification (5 минут)

### Step 3.1 — Tailscale status

📋 На сервере:

```bash
tailscale status --self
```

**Expected:**
```
100.X.Y.Z   ser-thailand-exit-1     krom00070007@  linux     idle, tx 12K rx 8K
```

Если `offline` — `tailscale up` ещё раз.

📋 Проверить что мы advertise exit-node:

```bash
tailscale debug prefs | grep -E "(AdvertiseExitNode|ExitNode|RunSSH)"
```

**Expected:**

```
"AdvertiseExitNode": true,
"ExitNodeIP": "100.78.149.108",   ← chained, IP USE_EXIT_NODE_HOSTNAME
"RunSSH": false,
```

### Step 3.2 — Проверить sshd hardening

📋 На сервере:

```bash
sshd -T | grep -E "^(permitrootlogin|passwordauth|x11forwarding)"
```

**Expected:**

```
permitrootlogin prohibit-password
passwordauthentication no
x11forwarding no
```

⚠️ **DANGER**: до выхода из текущей SSH сессии — **открой новый terminal с другой машины** и попробуй залогиниться через SSH key. Если получится — sshd hardening работает. Если **нет** — НЕ закрывай текущую сессию, fix issues иначе lockout.

### Step 3.3 — Проверить fail2ban + ufw

```bash
systemctl status fail2ban | head -5
systemctl status ufw | head -3
ufw status verbose | head -15
```

**Expected:**

```
fail2ban.service - Fail2Ban Service
   Loaded: loaded; enabled
   Active: active (running)

ufw.service active
ufw status: active

Logging: on (low)
Default: deny (incoming), allow (outgoing)
22/tcp     ALLOW IN    Anywhere    # SSH
41641/udp  ALLOW IN    Anywhere    # Tailscale WireGuard
Anywhere   ALLOW IN    tailscale0  # Tailscale tailnet traffic
```

### Step 3.4 — Проверить sysctl tuning

```bash
sysctl net.ipv4.ip_forward net.core.default_qdisc net.ipv4.tcp_congestion_control
```

**Expected:**

```
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

Если `bbr` не показано — kernel не поддерживает BBR (редкость на Ubuntu 24). Fallback CUBIC всё равно работает, но bandwidth penalty будет больше.

### Step 3.5 — Local-doctor verify

```bash
systemctl status cascade-local-doctor.timer
systemctl list-timers cascade-local-doctor.timer
```

**Expected (timer state):**

```
NEXT                          LEFT          LAST   PASSED        UNIT
Wed 2026-05-15 12:00:00 +07   2h 30min ago   n/a    n/a           cascade-local-doctor.timer
```

Запусти manually для теста:

```bash
/usr/local/bin/cascade-local-doctor
echo "Exit code: $?"
ls /var/log/cascade-local-doctor/
```

Должен сгенерить `/var/log/cascade-local-doctor/2026-05-15.md` + (если Telegram настроен) отправить summary в bot.

### Step 3.6 — Проверить chained outbound IP

С другой ноды tailnet (которая использует **этот** сервер как exit-node):

📋 На другом peer:

```bash
tailscale set --exit-node=ser-thailand-exit-1
curl -s ifconfig.me
```

**Expected:** должен показать IP **vultr-amsterdam** (NL), а не Singapore/Thailand сервера. Это значит chain работает: твой peer → ser-thailand-exit-1 → vultr-amsterdam → internet.

Если показывает другой IP — `tailscale debug prefs` на ser-thailand-exit-1 показать `ExitNodeIP`.

---

## Step 4 — Admin tasks (10 минут)

### Step 4.1 — В admin.tailscale.com

📋 https://login.tailscale.com/admin/machines

1. Find новую ноду (по hostname, например `ser-thailand-exit-1`)
2. Click на неё → детали
3. **Toggle ON**: "Allow this node as exit node"
4. **Disable key expiry** (для long-lived servers): "Machine settings" → "Disable key expiry"
5. Если subnet routes advertised — Approve

### Step 4.2 — Зарегистрировать в MSI cascade-doctor

На MSI (через SSH или localhost):

```bash
cd ~/projects/cascade-state/scripts/cascade-doctor
nano cascade-doctor.sh
```

Найти `FULL_SSH_NODES=(` и добавить новую строчку:

```bash
FULL_SSH_NODES=(
    "opus-cwr-bkk|root@100.70.212.16|core|cascade-mcp_active"
    ...
    "ser-thailand-exit-1|root@<NEW_TAILNET_IP>|exit-th-chained|"   # ← новая
)
```

Commit + push:

```bash
git add scripts/cascade-doctor/cascade-doctor.sh
git commit -m "cascade-doctor: add ser-thailand-exit-1 to FULL_SSH_NODES"
git push origin main
```

С следующего daily run (12:00 Bangkok) MSI doctor будет также мониторить эту ноду.

### Step 4.3 — Записать в state/nodes.md

```bash
nano ~/projects/cascade-state/state/nodes.md
```

Добавить новую строчку:

```markdown
| **ser-thailand-exit-1** | <PUBLIC_IP> | <TAILNET_IP> | Ubuntu 24.04 | Exit-node (chained через vultr-amsterdam). Setup via cascade-server-setup v1.0 (2026-05-15). |
```

Commit + push в cascade-state.

---

## Step 5 — Performance verification (опционально)

### Step 5.1 — Bandwidth test через chained routing

С другой ноды tailnet:

```bash
tailscale set --exit-node=ser-thailand-exit-1
# Speed test
curl -o /dev/null https://speed.cloudflare.com/__down?bytes=100000000
# или
wget -O /dev/null http://speedtest.tele2.net/100MB.zip
```

Сравни с direct (без exit-node):

```bash
tailscale set --exit-node=
wget -O /dev/null http://speedtest.tele2.net/100MB.zip
```

**Expected ratio:**

| Setup | Bandwidth penalty |
|---|---|
| Direct (no chain) | 0% baseline |
| Chained без BBR tuning | 50-70% loss |
| Chained с BBR + buffers (наш setup) | **5-15% loss** |

Если получаешь >30% loss с tuning — проверь:
- Bandwidth между peers (run `iperf3 -c <peer>`)
- MTU настройки (`ip link show tailscale0` — должно быть mtu 1280)
- CPU bottleneck на сервере (`top` — нагрузка `tailscaled`)

### Step 5.2 — Latency test

```bash
# С другой ноды:
tailscale ping --c 5 ser-thailand-exit-1   # round-trip к этой ноде
curl -w "@-" -o /dev/null -s https://google.com <<'EOF'
   time_connect: %{time_connect}\n
      time_total: %{time_total}\n
EOF
```

---

## Step 6 — Cleanup (после успешного setup)

### Step 6.1 — Сохранить config куда-то

⚠️ **НЕ commit'ить cascade-server-setup.conf** (он на сервере, и в нём secrets).

Если нужно сохранить:

```bash
# Encode token before saving (для безопасности)
cat > /tmp/cascade-config-backup.txt <<EOF
Created: $(date -Iseconds)
Host: $HOSTNAME (TS IP: $(tailscale ip -4))
Tailscale auth key (used once): tskey-auth-...
Telegram bot token: ...
Telegram chat ID: ...
EOF

# Send to Telegram Saved Messages
tg-send-text "$(cat /tmp/cascade-config-backup.txt)"   # if tg-send-text installed
# OR copy/paste manually to Telegram
rm /tmp/cascade-config-backup.txt
```

Это backup secrets для cross-device recovery.

### Step 6.2 — Logout root SSH

После того как admin user работает + key login проверен:

```bash
# Verify admin login from another terminal works first!
ssh usersstas@<server-ip> 'sudo whoami'  # должно вернуть "root"

# Только если работает — закрыть root session
exit
```

С этого момента — login только через `ssh usersstas@server` + sudo для admin tasks.

### Step 6.3 — Optional: lock root account

Если хочешь absolute lock'нуть root:

```bash
# Как admin user:
sudo passwd -l root
```

Можно отменить позже: `sudo passwd -u root`.

---

## Troubleshooting per phase

### Phase 1 (system-prep)

| Symptom | Решение |
|---|---|
| `E: Could not get lock /var/lib/dpkg/lock-frontend` | Подожди / `killall apt apt-get` |
| `Sub-process /usr/bin/dpkg returned an error code` | `dpkg --configure -a` + retry |
| `Failed to fetch http://archive.ubuntu.com/...` | DNS issue / network down. Check `/etc/resolv.conf`, ping 8.8.8.8 |
| `ADMIN_SSH_PUBKEY_SOURCE` curl fails | Verify URL: `curl https://github.com/krom00070007-beep.keys` |

### Phase 2 (sshd-harden)

| Symptom | Решение |
|---|---|
| `sshd: configuration test failed` | Backup был восстановлен. Check `/etc/ssh/sshd_config` manually для syntax error. Run `02-sshd-harden.sh` отдельно. |
| Cannot SSH after phase | LOCKOUT — нужен KVM / console access. Через console: `nano /etc/ssh/sshd_config`, set `PasswordAuthentication yes` обратно, `systemctl reload sshd`. |

### Phase 3 (firewall)

| Symptom | Решение |
|---|---|
| `ufw: command not found` | Phase 1 не закончился. Re-run `01-system-prep.sh`. |
| Locked out после ufw enable | KVM console → `ufw disable` → `systemctl stop ufw`. Fix rules. |
| `fail2ban refuses to start` | `journalctl -u fail2ban -n 30`, check `/etc/fail2ban/jail.local` syntax |

### Phase 6/7 (Tailscale)

| Symptom | Решение |
|---|---|
| `tailscale: Up failed: ...` | `journalctl -u tailscaled -n 30`. Часто — network connectivity или firewall блокирует UDP 41641. |
| `auth key invalid` | Сгенерируй новый ключ в admin. Old key может быть expired (default 90 days). |
| Browser OAuth не открывается | Headless server. Открыть printed URL в браузере на ДРУГОЙ машине вручную. |
| `the device user is not in tagOwners` | Добавь `tag:cascade-exit` в `tagOwners` в admin policy file (см. cascade-tailscale-acl skill). |

### Phase 8 (exit-config)

| Symptom | Решение |
|---|---|
| `WARN: cannot resolve USE_EXIT_NODE_HOSTNAME` | Peer не online или MagicDNS off в admin. `tailscale.exe status` проверить. |
| `exit-node IP not advertising` | На admin → Machines → target peer → "Allow this node as exit node" должен быть ON. |
| После chain — internet не работает с peer-client | Verify target exit-node functional (curl ifconfig.me on target peer). |

### Phase 9 (local-doctor)

| Symptom | Решение |
|---|---|
| `cascade-local-doctor.timer not active` | `systemctl status cascade-local-doctor.timer`, enable: `systemctl enable --now cascade-local-doctor.timer` |
| Telegram bot не отвечает | Check token + chat_id; verify `curl https://api.telegram.org/bot$TOKEN/sendMessage -d chat_id=$CHAT_ID -d text=test` |
| Report показывает 🔴 на проверках | Это OK — реальные issues которые надо fix manually. Script даст hints в notes. |

---

## Удаление / откат

Если что-то пошло не так и нужно начать с чистого листа:

⚠️ **Это удалит ноду из tailnet и сбросит большинство конфигов.**

```bash
# 1. Покинуть tailnet
tailscale logout
tailscale down

# 2. Удалить Tailscale
apt remove --purge -y tailscale

# 3. Удалить firewall rules
ufw --force reset

# 4. Удалить swap
swapoff /swap.img
rm /swap.img
sed -i '/swap.img/d' /etc/fstab

# 5. Удалить sysctl tuning
rm /etc/sysctl.d/99-cascade-tuning.conf
rm /etc/sysctl.d/99-cascade-swap.conf
sysctl --system

# 6. Удалить local-doctor
systemctl disable --now cascade-local-doctor.timer
rm /etc/systemd/system/cascade-local-doctor.{service,timer}
rm /usr/local/bin/cascade-local-doctor
rm /etc/cascade-local-doctor.conf
rm -rf /var/log/cascade-local-doctor/

# 7. Восстановить sshd config (backup из Phase 2)
ls /etc/ssh/sshd_config.bak-*
cp /etc/ssh/sshd_config.bak-<latest> /etc/ssh/sshd_config
systemctl reload sshd

# 8. Удалить admin user (опционально — если нужен fresh install)
# userdel -r usersstas
```

Затем удалить ноду в admin.tailscale.com → Machines → Delete.

---

## FAQ

**Q: Скрипт занимает много памяти/CPU?**
A: Нет. Runtime ~5-10 минут с пиком ~200 MB RAM (apt). Стабильное состояние — ~50 MB.

**Q: Что если ноут с админом сдохнет посередине Phase 7?**
A: Скрипт idempotent. Re-run `sudo ./00-bootstrap.sh` — пропустит готовые phases, продолжит с failed.

**Q: Можно ли сменить exit-node после deploy?**
A: Да: `sudo tailscale set --exit-node=<new-hostname>` или `--exit-node=` (без значения = direct без chain).

**Q: Безопасно ли использовать pre-auth key?**
A: Key одноразовый (если не reusable) или ограничен по тегу. Не commit'ить, держать в config с chmod 600.

**Q: Что если хочу 2 exit-node на одном сервере (failover)?**
A: Tailscale пока не поддерживает primary/secondary exit-node на одном host. Можно скриптом switch при alert.

**Q: Performance penalty acceptable для production?**
A: Зависит от use case. Для browsing + API calls (low bandwidth) — да. Для torrenting / video streaming — лучше direct.

---

## Cross-refs

- `README.md` — overview + список файлов
- `cascade-server-setup.conf.sample` — template config
- `docs/audits/cascade-servers-revision-2026-05-14.md` — baseline что мониторим
- `skills/cascade-tailscale-add-node/SKILL.md` — общий workflow добавления Tailscale node
- `skills/cascade-tailscale-acl/SKILL.md` — tagOwners prereq
- `scripts/cascade-doctor/README.md` — central monitoring c MSI
