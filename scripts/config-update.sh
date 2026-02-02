#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/_logger.sh"

# Пути к файлам
CONFIG_FILE="$ROOT_DIR/config.json"
REALITY_CLIENTS_FILE="$ROOT_DIR/configs/reality_clients.json"
SPLITHTTP_CLIENTS_FILE="$ROOT_DIR/configs/splithttp_clients.json"
GRPC_CLIENTS_FILE="$ROOT_DIR/configs/grpc_clients.json"
SS_CLIENTS_FILE="$ROOT_DIR/configs/shadowsocks_clients.json"
SETTINGS_FILE="$ROOT_DIR/settings.env"

# Проверка существования файлов
check_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        exit 1
    fi
}

log_info "Checking files..."
check_file "$CONFIG_FILE"
check_file "$REALITY_CLIENTS_FILE"
check_file "$SETTINGS_FILE"

log_info "Loading settings from settings.env..."
source "$SETTINGS_FILE"

validate_settings() {
    local required_vars=(
        "REALITY_PORT"
        "REALITY_DEST"
        "REALITY_SERVER_NAME"
        "REALITY_PRIVATE_KEY"
        "REALITY_PUBLIC_KEY"
        "REALITY_SHORT_IDS"
        "SS_PORT"
        "SS_METHOD"
        "SS_SERVER_PASSWORD"
        "SPLITHTTP_PORT"
        "SPLITHTTP_HOST"
        "SPLITHTTP_PATH"
        "GRPC_PORT"
        "GRPC_SERVICENAME"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var is not set in settings.env"
            exit 1
        fi
    done
}

validate_settings

# Создаем бэкап конфига
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
log_info "Backup created: $BACKUP_FILE"

# Читаем массивы клиентов
log_info "Reading client data..."
REALITY_CLIENTS=$(cat "$REALITY_CLIENTS_FILE")
SPLITHTTP_CLIENTS=$(cat "$SPLITHTTP_CLIENTS_FILE" 2>/dev/null || echo "[]")
GRPC_CLIENTS=$(cat "$GRPC_CLIENTS_FILE" 2>/dev/null || echo "[]")
SS_CLIENTS=$(cat "$SS_CLIENTS_FILE" 2>/dev/null || echo "[]")

log_info "Reality clients: $(echo "$REALITY_CLIENTS" | jq 'length') users"
log_info "SplitHTTP clients: $(echo "$SPLITHTTP_CLIENTS" | jq 'length') users"
log_info "grpc clients: $(echo "$GRPC_CLIENTS" | jq 'length') users"
log_info "Shadowsocks clients: $(echo "$SS_CLIENTS" | jq 'length') users"

# Обновляем конфиг с помощью jq
log_info "Updating config.json..."

jq --argjson reality_clients "$REALITY_CLIENTS" \
    --argjson splithttp_clients "$SPLITHTTP_CLIENTS" \
    --argjson grpc_clients "$GRPC_CLIENTS" \
    --argjson ss_clients "$SS_CLIENTS" \
    --arg reality_port "$REALITY_PORT" \
    --arg reality_dest "$REALITY_DEST" \
    --arg reality_server_name "$REALITY_SERVER_NAME" \
    --arg reality_private_key "$REALITY_PRIVATE_KEY" \
    --arg reality_public_key "$REALITY_PUBLIC_KEY" \
    --argjson reality_short_ids "$REALITY_SHORT_IDS" \
    --arg ss_port "$SS_PORT" \
    --arg ss_method "$SS_METHOD" \
    --arg ss_password "$SS_SERVER_PASSWORD" \
    --arg splithttp_port "$SPLITHTTP_PORT" \
    --arg splithttp_host "$SPLITHTTP_HOST" \
    --arg splithttp_path "$SPLITHTTP_PATH" \
    --arg grpc_port "$GRPC_PORT" \
    --arg grpc_serviceName "$GRPC_SERVICENAME" \
    '
    # Обновляем Reality (TCP) clients
    (.inbounds[] | select(.tag == "reality-in") | .settings.clients) = $reality_clients |

    (.inbounds[] | select(.tag == "reality-in") | .port) = ($reality_port | tonumber) |
    (.inbounds[] | select(.tag == "reality-in") | .streamSettings.realitySettings.dest) = $reality_dest |
    (.inbounds[] | select(.tag == "reality-in") | .streamSettings.realitySettings.serverNames) = [$reality_server_name] |
    (.inbounds[] | select(.tag == "reality-in") | .streamSettings.realitySettings.privateKey) = $reality_private_key |
    (.inbounds[] | select(.tag == "reality-in") | .streamSettings.realitySettings.shortIds) = $reality_short_ids |

    # Обновляем SplitHTTP clients
    (.inbounds[] | select(.tag == "splithttp-in") | .settings.clients) = $splithttp_clients |

    # Обновляем SplitHTTP настройки (тот же публичный ключ что и для Reality)
    (.inbounds[] | select(.tag == "splithttp-in") | .port) = ($splithttp_port | tonumber) |
    (.inbounds[] | select(.tag == "splithttp-in") | .streamSettings.splithttpSettings.host) = $splithttp_host |
    (.inbounds[] | select(.tag == "splithttp-in") | .streamSettings.splithttpSettings.path) = $splithttp_path |

    # Обновляем grpc clients
    (.inbounds[] | select(.tag == "grpc-in") | .settings.clients) = $grpc_clients |

    # Обновляем grpc настройки (тот же публичный ключ что и для Reality)
    (.inbounds[] | select(.tag == "grpc-in") | .port) = ($grpc_port | tonumber) |
    (.inbounds[] | select(.tag == "grpc-in") | .streamSettings.grpcSettings.serviceName) = $grpc_serviceName |

    # Обновляем Shadowsocks clients
    (.inbounds[] | select(.tag == "ss-in") | .settings.clients) = $ss_clients |

    # Обновляем Shadowsocks настройки
    (.inbounds[] | select(.tag == "ss-in") | .port) = ($ss_port | tonumber) |
    (.inbounds[] | select(.tag == "ss-in") | .settings.method) = $ss_method |
    (.inbounds[] | select(.tag == "ss-in") | .settings.password) = $ss_password
' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"

# Проверяем валидность JSON
if jq empty "${CONFIG_FILE}.tmp" 2>/dev/null; then
    cat "${CONFIG_FILE}.tmp" > "$CONFIG_FILE"
    rm -f "${CONFIG_FILE}.tmp"

    log_info "✅ Config updated successfully!"
else
    log_error "Invalid JSON generated. Restoring from backup..."
    cat "$BACKUP_FILE" > "$CONFIG_FILE"
    rm -f "${CONFIG_FILE}.tmp"
    exit 1
fi

# Показываем diff
log_info "Changes made:"
echo ""
echo "Reality clients:"
jq '.inbounds[] | select(.tag == "reality-in") | .settings.clients | length' "$CONFIG_FILE"

echo ""
echo "SplitHTTP clients:"
jq '.inbounds[] | select(.tag == "splithttp-in") | .settings.clients | length' "$CONFIG_FILE"

echo ""
echo "grpc clients:"
jq '.inbounds[] | select(.tag == "grpc-in") | .settings.clients | length' "$CONFIG_FILE"

echo ""
echo "Shadowsocks clients:"
jq '.inbounds[] | select(.tag == "ss-in") | .settings.clients | length' "$CONFIG_FILE"

echo ""
log_info "Backup saved as: $BACKUP_FILE"
log_info "Done!"
