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
Address = 10.100.0.2/32 # <SERVER [INTERFACE] ADDRESS>/32
PrivateKey = <SERVER_PRIVATE_KEY>
MTU = 1380
DNS = 1.1.1.1, 8.8.8.8
# Таблица маршрутизации - не изменяет default route! задаем маршрут при запуске композа
Table = off

PostUp = ip route add <SERVER_IP>/32 via 172.20.0.1 dev eth0 || true
PostUp = ip route del default via 172.20.0.1 dev eth0 || true
PostUp = ip route add default dev wg0
PostDown = ip route del default dev wg0 || true
PostDown = ip route add default via 172.20.0.1 dev eth0 || true

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <SERVER_PRESHARED_KEY>
Endpoint = <SERVER_IP>:51820
AllowedIPs = 0.0.0.0/0
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
