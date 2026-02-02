#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="/etc/iptables-docker-nat.rules"
RC_LOCAL="/etc/rc.local"

source "$ROOT_DIR/settings.env"

REALITY_FAKE_IP=$(nslookup "$REALITY_SERVER_NAME" | awk '/^Address: / { print $2 }' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
# у майкрософта выводит 23.197.162.102

if [ -z "$REALITY_SERVER_NAME" ] || [ -z "$REALITY_FAKE_IP" ]; then
    echo "Ошибка: не удалось получить IP для $REALITY_SERVER_NAME"
    exit 1
fi
echo "[+] Получен REALITY FAKE IP: $REALITY_FAKE_IP"

RULES=$(cat <<EOF
iptables -t nat -A PREROUTING -p tcp --dport ${SPLITHTTP_PORT} -j DNAT --to-destination 172.18.0.2:${SPLITHTTP_PORT}
iptables -t nat -A PREROUTING -p tcp --dport ${REALITY_PORT}  -j DNAT --to-destination 172.18.0.2:${REALITY_PORT}
iptables -t nat -A PREROUTING -p tcp --dport ${SS_PORT} -j DNAT --to-destination 172.18.0.2:${SS_PORT}
iptables -t nat -A PREROUTING -p tcp --dport ${GRPC_PORT} -j DNAT --to-destination 172.18.0.2:${GRPC_PORT}
iptables -t nat -A POSTROUTING -d 172.18.0.2 -j MASQUERADE

iptables -t nat -A PREROUTING -i eth0 -p udp --dport ${REALITY_PORT} -j DNAT --to-destination ${REALITY_FAKE_IP}:${REALITY_PORT}
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination ${REALITY_FAKE_IP}:80
EOF
)

echo "[+] Применение правил iptables"
echo "$RULES" | while read -r rule; do
  [ -z "$rule" ] && continue
  eval "$rule"
done

echo "[+] Сохраняем правила в файл $RULES_FILE"
echo "# Docker NAT rules" > "$RULES_FILE"
echo "$RULES" >> "$RULES_FILE"

echo "[+] Создание /etc/rc.local"
if [ ! -f "$RC_LOCAL" ]; then
  cat <<'EOF' > "$RC_LOCAL"
#!/bin/bash
exit 0
EOF
  chmod +x "$RC_LOCAL"
fi

echo "[+] Регистрация правил в rc.local"
if ! grep -q "$RULES_FILE" "$RC_LOCAL"; then
  sed -i '/^exit 0/i # Восстановление Docker NAT rules\
if [ -f /etc/iptables-docker-nat.rules ]; then\
  while read -r rule; do\
    [ -z "$rule" ] && continue\
    [[ "$rule" =~ ^# ]] && continue\
    eval "$rule"\
  done < /etc/iptables-docker-nat.rules\
fi' "$RC_LOCAL"
fi

echo "[✓] Завершено. Правила применены и будут существовать после перезапуска."


