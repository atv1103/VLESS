#!/bin/bash
set -e

WG_CONF="/config/wg0.conf"

echo "[wg-config] Checking WireGuard config..."

if [ -f "$WG_CONF" ]; then
  echo "[wg-config] wg0.conf already exists, skipping generation"
  exit 0
fi

echo "[wg-config] Generating keys..."

umask 077

PRIVATE_KEY=$(wg genkey)

echo "[wg-config] Writing wg0.conf..."

cat > "$WG_CONF" <<EOF
[Interface]
Address = 10.100.0.2/32 # INTERNAL_SERVER_SUBNET/32 - но host ID уникальный! (<- .2)
PrivateKey = <SERVER_PRIVATE_KEY>
MTU = 1380
# Таблица маршрутизации - не изменяет default route! задаем маршрут при запуске композа
Table = off

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <SERVER_PRESHARED_KEY>
Endpoint = VPS_IP:51820
AllowedIPs = 0.0.0.0/1, 128.0.0.0/1
PersistentKeepalive = 25
EOF

echo "[wg-config] Done"


# if [ ! -f /config/wg0.conf ]; then
#       umask 077 &&
#       wg genkey | tee /config/privatekey | wg pubkey > /config/publickey
#       echo '
# [Interface]
# PrivateKey = '$(cat /config/privatekey)'
# Address = 10.100.0.2/32
# DNS = 1.1.1.1

# [Peer]
# PublicKey = SERVER_PUBLIC_KEY
# Endpoint = SERVER_IP:51820
# AllowedIPs = 0.0.0.0/0
# PersistentKeepalive = 25
#       ' > /config/wg0.conf
# fi
