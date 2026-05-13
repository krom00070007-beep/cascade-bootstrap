#!/bin/bash
# 09-local-doctor — local self-monitoring (без зависимости на MSI cascade-doctor)
#
# Создаёт:
#   /usr/local/bin/cascade-local-doctor      — health-check script
#   /etc/systemd/system/cascade-local-doctor.service
#   /etc/systemd/system/cascade-local-doctor.timer   — daily 12:00 локально
#   /var/log/cascade-local-doctor/             — log directory
#
# Self-doctor проверяет local параметры (без SSH к другим нодам) и шлёт
# отчёт в Telegram (если bot configured) или в stdout/file.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cascade-server-setup.conf"

# ============================================================
# 1) Create the actual local-doctor script
# ============================================================

cat > /usr/local/bin/cascade-local-doctor <<DOCTOR
#!/bin/bash
# cascade-local-doctor — local self-health-check
# Installed by cascade-server-setup. Runs via systemd timer (daily).

set -uo pipefail

CONFIG=/etc/cascade-local-doctor.conf
if [ -f "\$CONFIG" ]; then source "\$CONFIG"; fi

LOG_DIR=/var/log/cascade-local-doctor
mkdir -p "\$LOG_DIR"

DATE=\$(date +%Y-%m-%d)
NOW=\$(date '+%Y-%m-%d %H:%M:%S %Z')
REPORT="\$LOG_DIR/\$DATE.md"
HOST=\$(hostname)
TG_TOKEN="\${TELEGRAM_BOT_TOKEN:-}"
TG_CHAT="\${TELEGRAM_CHAT_ID:-}"
QUIET="\${TELEGRAM_QUIET:-false}"

CRITICAL=0
WARNS=0
NOTES=()

note() { NOTES+=("\$1"); }

cat > "\$REPORT" <<R
# Local Doctor — \$HOST \$DATE

_Generated \$NOW by cascade-local-doctor._

## System
- Uptime: \$(uptime -p)
- Kernel: \$(uname -r)
- Disk /: \$(df -h / | tail -1 | awk '{print \$5,\$3"/"\$2}')
- RAM: \$(free -h | head -2 | tail -1 | awk '{print \$3"/"\$2}')
- Swap: \$(free -h | grep ^Swap | awk '{print \$3"/"\$2}')
- Load: \$(uptime | awk -F'load average: ' '{print \$2}')

## Checks
R

# CHECK 1: apt upgradable
APT=\$(apt list --upgradable 2>/dev/null | grep -v ^Listing | wc -l)
if [ "\$APT" -gt 20 ]; then
    CRITICAL=\$((CRITICAL+1)); note "🔴 \$APT apt upgradable (>20)"
elif [ "\$APT" -gt 5 ]; then
    WARNS=\$((WARNS+1)); note "🟡 \$APT apt upgradable"
fi
echo "- apt upgradable: \$APT" >> "\$REPORT"

# CHECK 2: sshd config
SSHD_PR=\$(sshd -T 2>/dev/null | grep ^permitrootlogin | awk '{print \$2}')
SSHD_PA=\$(sshd -T 2>/dev/null | grep ^passwordauthentication | awk '{print \$2}')
SSHD_X11=\$(sshd -T 2>/dev/null | grep ^x11forwarding | awk '{print \$2}')
[ "\$SSHD_PR" = "yes" ] && { CRITICAL=\$((CRITICAL+1)); note "🔴 sshd PermitRootLogin yes"; }
[ "\$SSHD_PA" = "yes" ] && { CRITICAL=\$((CRITICAL+1)); note "🔴 sshd PasswordAuth yes"; }
[ "\$SSHD_X11" = "yes" ] && { WARNS=\$((WARNS+1)); note "🟡 sshd X11Forwarding yes"; }
echo "- sshd: permitroot=\$SSHD_PR, passauth=\$SSHD_PA, x11=\$SSHD_X11" >> "\$REPORT"

# CHECK 3: fail2ban
F2B=\$(systemctl is-active fail2ban 2>&1)
F2B_ENA=\$(systemctl is-enabled fail2ban 2>&1)
if [ "\$F2B" != "active" ]; then
    CRITICAL=\$((CRITICAL+1)); note "🔴 fail2ban not active (\$F2B)"
elif [ "\$F2B_ENA" != "enabled" ]; then
    WARNS=\$((WARNS+1)); note "🟡 fail2ban not enabled (auto-start)"
fi
echo "- fail2ban: \$F2B / \$F2B_ENA" >> "\$REPORT"

# CHECK 4: ufw
if command -v ufw >/dev/null 2>&1; then
    UFW=\$(ufw status 2>/dev/null | head -1 | awk '{print \$2}')
    [ "\$UFW" != "active" ] && { WARNS=\$((WARNS+1)); note "🟡 ufw not active"; }
    echo "- ufw: \$UFW" >> "\$REPORT"
fi

# CHECK 5: Tailscale
TS_SSH=\$(tailscale debug prefs 2>/dev/null | grep RunSSH | tr -d ',"' | awk '{print \$2}')
[ "\$TS_SSH" = "true" ] && { CRITICAL=\$((CRITICAL+1)); note "🔴 Tailscale SSH=true (hard rule violation)"; }
TS_IP=\$(tailscale ip -4 2>/dev/null | head -1)
echo "- Tailscale IP: \$TS_IP, RunSSH=\$TS_SSH" >> "\$REPORT"

# CHECK 6: journalctl errors 24h
JERR=\$(journalctl -p err --since "24 hours ago" --no-pager 2>/dev/null | wc -l)
[ "\$JERR" -gt 50 ] && { WARNS=\$((WARNS+1)); note "🟡 journal errors 24h: \$JERR"; }
echo "- journal errors 24h: \$JERR" >> "\$REPORT"

# CHECK 7: ip_forward (для exit-node — должно быть 1)
IPFW=\$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
[ "\$IPFW" != "1" ] && { WARNS=\$((WARNS+1)); note "🟡 ip_forward=\$IPFW (should be 1 for exit-node)"; }
echo "- ip_forward: \$IPFW" >> "\$REPORT"

# Summary
echo "" >> "\$REPORT"
echo "## Summary" >> "\$REPORT"
echo "- Critical: \$CRITICAL" >> "\$REPORT"
echo "- Warnings: \$WARNS" >> "\$REPORT"
if [ \${#NOTES[@]} -gt 0 ]; then
    echo "" >> "\$REPORT"
    echo "### Notes" >> "\$REPORT"
    for n in "\${NOTES[@]}"; do echo "- \$n" >> "\$REPORT"; done
fi

# Telegram delivery
if [ -n "\$TG_TOKEN" ] && [ -n "\$TG_CHAT" ]; then
    SUMMARY="🩺 \$HOST local-doctor \$DATE: \$CRITICAL critical, \$WARNS warns"
    if [ \${#NOTES[@]} -gt 0 ]; then
        SUMMARY="\$SUMMARY"\$'\n\n'"\$(printf '%s\n' "\${NOTES[@]}")"
    fi
    if [ "\$CRITICAL" -gt 0 ] || [ "\$QUIET" != "true" ]; then
        curl -sS -X POST "https://api.telegram.org/bot\$TG_TOKEN/sendMessage" \\
            -d "chat_id=\$TG_CHAT" \\
            -d "text=\$SUMMARY" >/dev/null 2>&1 || true
    fi
fi

# Exit code
[ "\$CRITICAL" -gt 0 ] && exit 1 || exit 0
DOCTOR
chmod +x /usr/local/bin/cascade-local-doctor

# ============================================================
# 2) Save config (Telegram credentials)
# ============================================================

cat > /etc/cascade-local-doctor.conf <<EOF
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_QUIET="${TELEGRAM_QUIET:-false}"
EOF
chmod 600 /etc/cascade-local-doctor.conf

# ============================================================
# 3) systemd service + timer
# ============================================================

cat > /etc/systemd/system/cascade-local-doctor.service <<EOF
[Unit]
Description=Cascade Local Doctor (daily self health-check)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cascade-local-doctor
StandardOutput=append:/var/log/cascade-local-doctor/cron.log
StandardError=append:/var/log/cascade-local-doctor/cron.log
EOF

cat > /etc/systemd/system/cascade-local-doctor.timer <<EOF
[Unit]
Description=Cascade Local Doctor — daily timer

[Timer]
OnCalendar=*-*-* ${LOCAL_DOCTOR_HOUR:-12}:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cascade-local-doctor.timer

echo "[09] local-doctor installed."
echo "  Script: /usr/local/bin/cascade-local-doctor"
echo "  Timer: cascade-local-doctor.timer (daily ${LOCAL_DOCTOR_HOUR:-12}:00 local)"
echo "  Logs: /var/log/cascade-local-doctor/"
echo ""
echo "Manual test run:"
echo "  /usr/local/bin/cascade-local-doctor"
echo ""
echo "Verify timer:"
echo "  systemctl status cascade-local-doctor.timer"
echo "  systemctl list-timers cascade-local-doctor.timer"
