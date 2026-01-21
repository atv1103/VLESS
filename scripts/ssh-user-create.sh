#!/bin/bash
set -e

USER_NAME="proxyclient"
SSHD_CONFIG="/etc/ssh/sshd_config"

# --- Создание пользователя ---
if id "$USER_NAME" &>/dev/null; then
    echo "User '$USER_NAME' already exists"
    exit 0
fi

adduser --no-create-home --shell /bin/true "$USER_NAME"

echo "User '$USER_NAME' created successfully"

# --- Разрешаем TCP Forwarding в SSH ---
if grep -q -E '^AllowTcpForwarding\s+yes' "$SSHD_CONFIG"; then
    echo "AllowTcpForwarding already enabled in $SSHD_CONFIG"
else
    echo "Enabling AllowTcpForwarding in $SSHD_CONFIG..."

    # Если строка с AllowTcpForwarding есть, заменяем на yes
    if grep -q '^AllowTcpForwarding' "$SSHD_CONFIG"; then
        sed -i 's/^AllowTcpForwarding.*/AllowTcpForwarding yes/' "$SSHD_CONFIG"
    else
        # Иначе добавляем в конец файла
        echo "AllowTcpForwarding yes" >> "$SSHD_CONFIG"
    fi

    # Перезапуск SSH сервиса
    if systemctl is-active ssh >/dev/null 2>&1; then
        systemctl restart ssh
        echo "SSH service restarted"
    elif systemctl is-active sshd >/dev/null 2>&1; then
        systemctl restart sshd
        echo "SSHD service restarted"
    else
        echo "⚠️ Не удалось определить сервис SSH для перезапуска. Перезапустите вручную."
    fi
fi

# Ссылка может быть такой:
# ssh://proxyclient:пароль@IP_адрес_сервера:порт#MySshServer
# такую ссылку понимает только Streisand.
