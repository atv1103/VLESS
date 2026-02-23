#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/settings.env"
source "$SCRIPT_DIR/_logger.sh"

safe_sed() {
    local pattern="$1"
    local file="$2"

    if sed "$pattern" "$file" > "${file}.tmp" 2>/dev/null; then
        cat "${file}.tmp" > "$file"
        rm "${file}.tmp"
        return 0
    else
        rm -f "${file}.tmp"
        return 1
    fi
}

detect_server_ip() {
    local ip=""

    # log_info "Detecting server IP address..."
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ipecho.net/plain"
    )

    for service in "${services[@]}"; do
        ip=$(curl -s --max-time 5 "$service" 2>/dev/null || true)

        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            if [[ ! "$ip" =~ ^10\. ]] && \
               [[ ! "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && \
               [[ ! "$ip" =~ ^192\.168\. ]] && \
               [[ ! "$ip" =~ ^127\. ]]; then
                # log_info "Detected public IP: $ip"
                echo "$ip"
                return 0
            fi
        fi
    done

    log_error "Failed to detect public server IP"
    exit 1
}

# Определяем IP если не задан
if [[ -z "${SERVER_IP:-}" ]]; then
    SERVER_IP=$(detect_server_ip)

    safe_sed "s|^SERVER_IP=.*|SERVER_IP=\"$SERVER_IP\"|" "$ROOT_DIR/settings.env"

    log_info "SERVER_IP $SERVER_IP saved to settings.env"
fi

generate_reality_keys() {
    if [[ -z "$REALITY_PRIVATE_KEY" ]] || [[ -z "$REALITY_PUBLIC_KEY" ]]; then
        log_info "Generating Reality keys..."
        local keys_output
        keys_output=$(xray x25519)
        echo "$keys_output" > "$ROOT_DIR/configs/xray_keys.txt"

        REALITY_PRIVATE_KEY=$(echo "$keys_output" | awk '/PrivateKey:/ {print $2}')
        REALITY_PUBLIC_KEY=$(echo "$keys_output" | awk '/Password:/ {print $2}')

        # Обновляем settings.env
        safe_sed "s|^REALITY_PRIVATE_KEY=.*|REALITY_PRIVATE_KEY=\"$REALITY_PRIVATE_KEY\"|" "$ROOT_DIR/settings.env"
        safe_sed "s|^REALITY_PUBLIC_KEY=.*|REALITY_PUBLIC_KEY=\"$REALITY_PUBLIC_KEY\"|" "$ROOT_DIR/settings.env"

        log_info "Reality keys generated and saved to settings.env"
    else
        log_info "Using existing Reality keys from settings.env"
    fi
}

create_directories() {
    mkdir -p configs/reality
    mkdir -p configs/shadowsocks2022
    mkdir -p configs/splithttp
    log_info "Directories created"
}

generate_reality_configs() {
    log_info "Generating Reality configurations..."

    local reality_clients_json="["
    local reality_short_ids='[""]'

    for i in $(seq 1 "$CLIENTS_QTY"); do
        local uuid
        uuid=$(xray uuid)
        local email="user$i"

        local short_id
        short_id=$(openssl rand -hex 4)

        reality_short_ids=${reality_short_ids%]},"\"$short_id\""]

        # Добавляем объект клиента в JSON
        if [ "$i" -lt "$CLIENTS_QTY" ]; then
            reality_clients_json+="
        {\"id\": \"$uuid\", \"email\": \"$email\", \"flow\": \"xtls-rprx-vision\"},"
        else
            reality_clients_json+="
        {\"id\": \"$uuid\", \"email\": \"$email\", \"flow\": \"xtls-rprx-vision\"}"
        fi

        # Генерация vless:// ссылки
        local vless_link="vless://${uuid}@${SERVER_IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${short_id}&type=tcp#Reality_${email}"

        # Сохранение ссылки
        mkdir -p configs/reality/${email}
        echo "$vless_link" > "configs/reality/${email}/${email}.txt"

        # Генерация QR-кода
        qrencode -t PNG -o "configs/reality/${email}/${email}.png" -s 10 "$vless_link"

        log_info "Generated Reality config for $email (UUID: ${uuid:0:8}...)"
    done

    reality_clients_json+="
    ]"
    safe_sed "s|^REALITY_SHORT_IDS=.*|REALITY_SHORT_IDS='$reality_short_ids'|" "$ROOT_DIR/settings.env"

    echo "$reality_clients_json" > configs/reality_clients.json
}

generate_shadowsocks_configs() {
    log_info "Generating Shadowsocks 2022 configurations..."

    local ss_clients_json="["

    local SERVER_PASSWORD
    while :; do
        SERVER_PASSWORD=$(openssl rand -base64 16)
        [[ "$SERVER_PASSWORD" != *"/"* ]] && break
    done
    safe_sed "s|^SS_SERVER_PASSWORD=.*|SS_SERVER_PASSWORD=\"$SERVER_PASSWORD\"|" "$ROOT_DIR/settings.env"

    for i in $(seq 1 "$CLIENTS_QTY"); do
        local client_password
        while :; do
            client_password=$(openssl rand -base64 16)
            [[ "$client_password" != *"/"* ]] && break
        done
        local email="user$i"

        if [ "$i" -lt "$CLIENTS_QTY" ]; then
            ss_clients_json+="
        {\"password\": \"$client_password\", \"email\": \"$email\"},"
        else
            ss_clients_json+="
        {\"password\": \"$client_password\", \"email\": \"$email\"}"
        fi

        local full_password="${SERVER_PASSWORD}:${client_password}"

        local bodylink=$(echo -n "${SS_METHOD}:${full_password}@${SERVER_IP}:${SS_PORT}" | base64 -w0)
        local ss_link="ss://${bodylink}#SS2022_${email}"

        mkdir -p configs/shadowsocks2022/${email}
        echo "$ss_link" > "configs/shadowsocks2022/${email}/${email}.txt"
        qrencode -t PNG -o "configs/shadowsocks2022/${email}/${email}.png" -s 10 "$ss_link"

        log_info "Generated Shadowsocks config for $email"
    done

    ss_clients_json+="
    ]"

    echo "$ss_clients_json" > configs/shadowsocks_clients.json
}

generate_splithttp_configs() {
    log_info "Generating splithttp configurations..."

    local clients_data_file="configs/reality_clients.json"

    if [[ ! -f "$clients_data_file" ]]; then
        log_error "Client data file not found. Run Reality generation first."
        return 1
    fi

    local splithttp_clients_json="["
    local first=true

    while IFS= read -r line; do
        # Извлекаем поля из JSON объекта
        local uuid=$(echo "$line" | jq -r '.id')
        local email=$(echo "$line" | jq -r '.email')

        # Добавляем в JSON
        if [ "$first" = true ]; then
            splithttp_clients_json+="
        {\"id\": \"$uuid\", \"email\": \"$email\"}"
            first=false
        else
            splithttp_clients_json+=",
        {\"id\": \"$uuid\", \"email\": \"$email\"}"
        fi

        # Генерация vless:// ссылки для splithttp
        local splithttp_link="vless://${uuid}@${SERVER_IP}:${SPLITHTTP_PORT:-443}?type=splithttp&encryption=none&security=none&path=${SPLITHTTP_PATH}&host=${SPLITHTTP_HOST}#SplitHTTP_${email}"

        # Сохранение
        mkdir -p configs/splithttp/${email}
        echo "$splithttp_link" > "configs/splithttp/${email}/${email}.txt"
        qrencode -t PNG -o "configs/splithttp/${email}/${email}.png" -s 10 "$splithttp_link"

        log_info "Generated splithttp config for $email"

    done < <(jq -c '.[]' "$clients_data_file")

    splithttp_clients_json+="
    ]"

    echo "$splithttp_clients_json" > configs/splithttp_clients.json

    log_info "splithttp configurations generated"
}

generate_grpc_configs() {
    log_info "Generating grpc configurations..."

    local clients_data_file="configs/reality_clients.json"

    if [[ ! -f "$clients_data_file" ]]; then
        log_error "Client data file not found. Run Reality generation first."
        return 1
    fi

    local grpc_clients_json="["
    local first=true

    while IFS= read -r line; do
        # Извлекаем поля из JSON объекта
        local uuid=$(echo "$line" | jq -r '.id')
        local email=$(echo "$line" | jq -r '.email')

        # Добавляем в JSON
        if [ "$first" = true ]; then
            grpc_clients_json+="
        {\"id\": \"$uuid\", \"email\": \"$email\"}"
            first=false
        else
            grpc_clients_json+=",
        {\"id\": \"$uuid\", \"email\": \"$email\"}"
        fi

        # Генерация vless:// ссылки для grpc
        local grpc_link="vless://${uuid}@${SERVER_IP}:${GRPC_PORT:-443}?type=grpc&encryption=none&security=none&serviceName=${GRPC_SERVICENAME}#grpc_${email}"

        # Сохранение
        mkdir -p configs/grpc/${email}
        echo "$grpc_link" > "configs/grpc/${email}/${email}.txt"
        qrencode -t PNG -o "configs/grpc/${email}/${email}.png" -s 10 "$grpc_link"

        log_info "Generated grpc config for $email"

    done < <(jq -c '.[]' "$clients_data_file")

    grpc_clients_json+="
    ]"

    echo "$grpc_clients_json" > configs/grpc_clients.json

    log_info "grpc configurations generated"
}

update_dockercompose_ports() {
  local COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
  source "$ROOT_DIR/settings.env"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "❌ docker-compose.yml не найден"
    return 1
  fi

  # Проверки переменных
  for var in REALITY_PORT SS_PORT SPLITHTTP_PORT GRPC_PORT; do
    if [[ -z "${!var}" ]]; then
      echo "❌ Переменная $var не задана в settings.env"
      return 1
    fi
  done

  echo "[+] Обновляем порты в docker-compose.yml"

  awk -v REALITY_PORT="$REALITY_PORT" \
    -v SS_PORT="$SS_PORT" \
    -v SPLITHTTP_PORT="$SPLITHTTP_PORT" \
    -v GRPC_PORT="$GRPC_PORT" '
  {
    print_line = 1
    if ($0 ~ /^[[:space:]]*ports:/) {
      # запоминаем количество пробелов в отступе
      match($0, /^([[:space:]]*)/, m)
      indent = m[1]
      print indent "ports:"
      print indent "  - \"" REALITY_PORT ":" REALITY_PORT "\""
      print indent "  - \"" SS_PORT ":" SS_PORT "/tcp\""
      print indent "  - \"" SS_PORT ":" SS_PORT "/udp\""
      print indent "  - \"" SPLITHTTP_PORT ":" SPLITHTTP_PORT "\""
      print indent "  - \"" GRPC_PORT ":" GRPC_PORT "\""
      in_ports = 1
      print_line = 0
      next
    }
    if (in_ports) {
      # проверяем, что строка имеет больший отступ чем блок ports
      match($0, /^([[:space:]]*)/, m)
      current_indent = m[1]
      if (length(current_indent) <= length(indent) && $0 !~ /^[[:space:]]*$/) {
        in_ports = 0
      } else {
        # пропускаем старую строку порта
        print_line = 0
        next
      }
    }
    if (print_line) print
  }
  ' "$COMPOSE_FILE" > "$COMPOSE_FILE.tmp"

  cat "$COMPOSE_FILE.tmp" > "$COMPOSE_FILE"
  rm -f "$COMPOSE_FILE.tmp"

  echo "✅ Порты успешно обновлены"
}


main() {
    log_info "Starting configuration generation..."

    generate_reality_keys
    create_directories
    generate_reality_configs
    generate_shadowsocks_configs
    generate_splithttp_configs
    generate_grpc_configs
    update_dockercompose_ports

    log_info "Configuration generation completed!"
}

main "$@"

