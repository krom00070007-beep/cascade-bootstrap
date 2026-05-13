#!/bin/bash
# 05-sysctl-tuning — BBR + buffers + ip_forward (для tailnet routing)

set -euo pipefail

cat > /etc/sysctl.d/99-cascade-tuning.conf <<'EOF'
# IP forwarding (на случай если станет exit-node)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Fast Open
net.ipv4.tcp_fastopen = 3

# Socket buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Connection tracking
net.netfilter.nf_conntrack_max = 524288

# FD limits
fs.file-max = 1000000
EOF

sysctl -p /etc/sysctl.d/99-cascade-tuning.conf >/dev/null 2>&1 || true

cat > /etc/security/limits.d/99-cascade.conf <<'EOF'
*               soft    nofile          524288
*               hard    nofile          1048576
EOF

echo "[05] sysctl applied"
