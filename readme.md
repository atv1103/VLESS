## Инструкция для запуска
1. `cd VLESS && nano settings.env` - Изменяем настройки файла **settings.env**, удали блокировку торрентов при необходимости из config.json
2. `bash prepare-system.sh` - доп настройки сервера
3. Создаем пользовательские конфиги VLESS:

`docker compose --profile setup run --rm config-builder && docker compose --profile setup down --rmi local`

1. `cp ./examples/wg0.conf ./wg/config/wg0.conf && nano ./wg/config/wg0.conf` - редактируем конфиг Wireguard
2. `docker compose up -d` - запускаем контейнер с VLESS и WG
3. `bash add-iptables-rules.sh` - добавляем правила iptables

4. `docker exec wg-client curl -s ifconfig.me` - проверяем IP Wireguard
5. `curl ifconfig.me` - проверяем IP хоста (должен остаться ваш VPS IP)
6. `docker logs xray -f` - логи xray контейнера (выйти через ctrl+c)

Готово, конфиги наших клиентов хранятся в директории **/configs/*прокси-протокол*/userНОМЕР/**, можем скопировать файл конфигурации клиента **userНОМЕР.txt** с сервера с помощью WinSCP или другим удобным для вас способом или вывести QR код прямо в терминале командой

`docker exec -it xray /etc/xray/show-reality userНОМЕР`

`docker exec -it xray /etc/xray/show-splithttp userНОМЕР`

`docker exec -it xray /etc/xray/show-grpc userНОМЕР`

`docker exec -it xray /etc/xray/show-ss userНОМЕР` - **DEPRECATED!**

## Рекомендуемые доп настройки
**Внимание: временами билдер багует и не записывает IP в файл settings.env, чинится удалением билдера, образов и имаджей. Команда для полной очистки докер файлов (`docker stop $(docker ps -aq) 2>/dev/null; docker rm -f $(docker ps -aq) 2>/dev/null; docker rmi -f $(docker images -aq) 2>/dev/null; docker volume rm -f $(docker volume ls -q) 2>/dev/null; docker network prune -f; docker buildx prune -af; docker builder prune -af; docker system prune -af --volumes`)** О баге известно, будет исправлен при возможности

1. Можно настроить SSH прокси. SSH-сервер нужно перевесить на нестандартный порт (не 22).

   `sudo nano /etc/ssh/sshd_config` - #Port 22 закомментирован, раскомментируй и замени на нужный тебе, или добавь дополнительную строку ниже (например Port 1234), тогда будет два порта SSH.

   `sudo sshd -t` - проверить конфиг

   `sudo systemctl restart ssh` - перезапустить SSH

   Доступ к серверу `ssh *user*@*IP* -p *port*`

   Больше никаких особых действий не требуется, но рекомендуется создать на сервере отдельного системного пользователя для SSH-прокси *(настроено в ssh-user-create.sh)*, ограничив его в правах, чтобы подключаясь к серверу логином-паролем клиент не мог выполнять никаких команд в системе.

Важно: в некоторых дистрибутивах по умолчанию SSHd не разрешает туннелирование трафика.

Проверь коммандой `sshd -T | grep allowtcpforwarding`

Чтобы разрешить, нужно на сервере в файле /etc/ssh/sshd_config добавить/заменить параметр AllowTcpForwarding yes.

Для создания пользователя и туннелирования:
раскомментируй строку **8** в **prepare-system.sh** или запусти `sudo bash ./scripts/ssh-user-create.sh`

Ссылка может быть такой:
ssh://proxyclient:пароль@IP_адрес_сервера:порт#MySshServer
такую ссылку понимает только Streisand и больше никто.

2. *(Настроено в update-speed.sh)* Можно настроить на сервере Bottleneck Bandwidth и Round-trip propagation time (BBR) congestion control algorithm. В файл /etc/sysctl.conf вписать

net.core.default_qdisc=fq

net.ipv4.tcp_congestion_control=bbr

и потом выполнить команду sysctl -p

## Инструкции при изменении конфигов
1. `docker compose restart xray` - при изменении конфига Xray (inbounds/outbounds)
2. `docker compose restart wireguard && docker compose restart xray` - при изменении конфига WireGuard

3. `docker exec xray curl ifconfig.me` - проверить IP Xray (должен быть IP WireGuard)
4. `curl ifconfig.me` - проверить IP хоста (должен остаться ваш VPS IP)

## Описание settings.env файла
**CLIENTS_QTY** - количество клиентов

**SERVER_IP** - ip сервера, в случае пустого значения сгенерирует IPv4 адрес вашего сервера

**REALITY_PORT** - порт reality, 443

**REALITY_DEST** - ваш_маскировочный_домен:443

**REALITY_SERVER_NAME** - ваш_маскировочный_домен

**REALITY_PRIVATE_KEY** - приватный reality ключ, будет сгенерирован автоматически

**REALITY_PUBLIC_KEY** - публичный reality ключ, будет сгенерирован автоматически

**REALITY_SHORT_IDS** - идентификатор клиента reality, будет сгенерирован автоматически

**SS_PORT** - порт shadowsocks, необходимо изменить

**SS_METHOD** - shadowsocks кодировка

**SS_SERVER_PASSWORD** - произвольный ключ shadowsocks, будет сгенерирован автоматически

**SPLITHTTP_PORT** - необходимо изменить номер порта на нестандартный

**SPLITHTTP_HOST** - доменное имя, которое будет использоваться в HTTP заголовке host

**SPLITHTTP_PATH** - URI путь для соединения

**GRPC_PORT** - рекомендовано 2053

**GRPC_SERVICENAME** - необходимо изменить номер порта на нестандартный

## Config.json
Чтобы не блокировался торрент, в **outbounds** необходимо удалить объект

    {
    "type": "field",
    "protocol": "bittorrent",
    "outboundTag": "block"
    }

# Описание скриптов
1. _logger.sh - подсветка вывода терминала
2. config-generate.sh - генерация клиентов (ссылки, qr), определение ip, заполнение settings.env
3. config-update.sh - заполнение config.json информацией из settings.env
4. docker-check.sh - проверка наличия докера и установка в случае отсутствия
5. ssh-user-create.sh - создание нового ssh пользователя с ограниченными правами, открытие туннелирования
6. update-speed.sh - настройка Bottleneck Bandwidth и Round-trip propagation time (BBR) congestion control algorithm
7. wg-generate.sh - генерация клиентского конфига wireguard
8. add-iptables-rules.sh - запись iptables правил на сервер, добавление правил в /etc/rc.local для работы после перезагрузки

# Клиенты
Windows / Linux - v2rayN, Nekobox/Nekoray, Hiddify‑Next, InvisibleMan
Android - v2rayNG, NekoboxForAndroid, Hiddify‑Next
iOS / macOS - Shadowrocket, Streisand, FoXray, v2raytun

Подробнее в статье https://habr.com/ru/articles/799751/
