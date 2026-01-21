#!/bin/bash
set -e

SYSCTL_FILE="/etc/sysctl.d/99-bbr.conf"

echo "🔍 Checking current TCP congestion control..."
CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control || echo "")

if [[ "$CURRENT_CC" == "bbr" ]]; then
    echo "✅ BBR is already enabled"
    exit 0
fi

echo "🚀 Enabling BBR congestion control..."

# Создаём конфиг
cat <<EOF > "$SYSCTL_FILE"
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

# Применяем настройки
sysctl --system >/dev/null

# Проверка
NEW_CC=$(sysctl -n net.ipv4.tcp_congestion_control)

if [[ "$NEW_CC" == "bbr" ]]; then
    echo "✅ BBR successfully enabled"
else
    echo "❌ Failed to enable BBR"
    exit 1
fi

echo "ℹ️ Current settings:"
sysctl net.core.default_qdisc
sysctl net.ipv4.tcp_congestion_control

echo "🎉 Done"
