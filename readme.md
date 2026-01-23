## Инструкция для запуска
1. Изменяем настройки файла **settings.env**, удали блокировку торрентов при необходимости из config.json (инструкция ниже)
2. `cd VLESS & bash prepare-system.sh` - доп настройки сервера
3. Создаем пользовательские конфиги VLESS и клиентский конфиг Wireguard
`docker compose --profile setup run --rm config-builder && \
docker compose --profile setup run --rm wg-config-builder && \
docker compose --profile setup down --rmi local`

ENCODED=$(echo -n "2022-blake3-aes-128-gcm:${SS_PASS}@${HOST}:${SS_PORT}" | base64 -w0)

4. `cp ./examples/wg0.conf ./wg/config/wg0.conf` - копируем конфиг Wiregiard
1. `nano ./wg/config/wg0.conf` - редактируем конфиг Wireguard
2. `docker compose up -d` - запускаем контейнер с VLESS и WG

Готово, конфиги наших клиентов хранятся в директории **/configs/*прокси-протокол*/userНОМЕР/**, можем скопировать файл конфигурации клиента **userНОМЕР.txt** с сервера с помощью WinSCP или другим удобным для вас способом или вывести QR код прямо в терминале командой

`docker exec -it xray /etc/xray/show-reality userНОМЕР`

`docker exec -it xray /etc/xray/show-ss userНОМЕР` - **DEPRECATED!**

`docker exec -it xray /etc/xray/show-xhttp userНОМЕР`

## Рекомендуемые доп настройки
1. Сделайте проброс порта не только на 443/TCP-порт (его делает XTLS-Reality), а еще на 443/UDP и 80/TCP до сервера, под который вы маскируетесь. Например, если вы маскируетесь под www.microsoft.com, то отрезолвте его IP-адрес (с помощью nslookup, ping или какого-нибудь онлайн-сервиса), а потом добавьте правила iptables (можно засунуть в /etc/rc.local, если он у вас есть - см. инструкции для вашего Linux-дистрибутива):

```iptables -t nat -A PREROUTING -i eth0 -p udp --dport 443 -j DNAT --to-destination fake_site_ip:443```

```iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination fake_site_ip:80```

(вместо eth0 должен быть ваш сетевой интерфейс, иногда бывает ens3, например).

2. Можно настроить SSH прокси. SSH-сервер нужно перевесить на нестандартный порт (не 22). Больше никаких особых действий не требуется, но рекомендуется создать на сервере отдельного системного пользователя для SSH-прокси *(настроено в ssh-user-create.sh)*, ограничив его в правах, чтобы подключаясь к серверу логином-паролем клиент не мог выполнять никаких команд в системе.
Важно: в некоторых дистрибутивах по умолчанию SSHd не разрешает туннелирование трафика. Чтобы разрешить, нужно на сервере в файле /etc/ssh/sshd_config добавить/заменить параметр AllowTcpForwarding yes.

Для создания пользователя и туннелирования:
раскомментируй строку **8** в **prepare-system.sh** или запусти `sudo bash ./scripts/ssh-user-create.sh`

Ссылка может быть такой:
ssh://proxyclient:пароль@IP_адрес_сервера:порт#MySshServer
такую ссылку понимает только Streisand и больше никто.

3. *(Настроено в update-speed.sh)* Можно настроить на сервере Bottleneck Bandwidth и Round-trip propagation time (BBR) congestion control algorithm. В файл /etc/sysctl.conf вписать

net.core.default_qdisc=fq

net.ipv4.tcp_congestion_control=bbr

и потом выполнить команду sysctl -p

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

**xhttp_PORT** - необходимо изменить номер порта на нестандартный

**xhttp_HOST** - доменное имя, которое будет использоваться в HTTP заголовке host

**xhttp_PATH** - URI путь для соединения

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

# Клиенты
Windows / Linux - v2rayN, Nekobox/Nekoray, Hiddify‑Next, InvisibleMan
Android - v2rayNG, NekoboxForAndroid, Hiddify‑Next
iOS / macOS - Shadowrocket, Streisand, FoXray, v2raytun

Подробнее в статье https://habr.com/ru/articles/799751/
