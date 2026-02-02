#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$ROOT_DIR/scripts/docker-check.sh"
"$ROOT_DIR/scripts/update-speed.sh"
# "$ROOT_DIR/scripts/ssh-user-create.sh" #есть смысл настраивать только на иностранной vps, порт ssh надо изменить с 22 на другой, ссылка ssh://proxyclient:пароль@IP_адрес_сервера:порт#MySshServer
