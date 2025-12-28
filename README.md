# Pi-hole DNS Server

Локальный DNS-сервер с блокировкой рекламы и автоматическим SSL.

## Быстрый старт

```bash
cp .env.example .env
nano .env

sudo docker compose up -d
```

> **SSL сертификаты** выдаются автоматически, если указан `PIHOLE_DOMAIN` в `.env`

---

## Настройка DNS на хосте (опционально)

> **Примечание:** Эта настройка нужна только если вы хотите чтобы **сам сервер** использовал Pi-hole для DNS.

---

## DNS для Docker контейнеров (3x-ui, Xray и др.)

### Если контейнер использует `network_mode: host` (рекомендуется)

Контейнеры с `network_mode: host` видят сеть хоста напрямую.

**В настройках DNS указывайте:**
```json
"dns": {
  "servers": [
    {
      "address": "localhost",
      "port": 53
    }
  ]
}
```

> [!TIP]
> Проверить режим сети: `docker inspect CONTAINER --format '{{.HostConfig.NetworkMode}}'`

---

### Если контейнер НЕ использует `network_mode: host`

Обычные Docker контейнеры изолированы от хоста. `localhost:53` внутри контейнера — это DNS самого контейнера, а не Pi-hole.

**Решение — использовать Docker bridge IP:**

```bash
# Узнать Docker bridge IP
sudo docker network inspect bridge | grep Gateway
# Обычно: 172.17.0.1
```

**В настройках DNS указывайте:**
```json
"dns": {
  "servers": [
    {
      "address": "172.17.0.1",  // ← ваш Docker bridge IP
      "port": 53
    }
  ]
}
```

> [!WARNING]
> При этом нужно добавить binding в `docker-compose.yml`:
> ```yaml
> - "172.17.0.1:53:53/tcp"
> - "172.17.0.1:53:53/udp"
> ```

### Проверка DNS из контейнера

```bash
# Для network_mode: host
sudo docker exec 3xui_app nslookup google.com localhost

# Для обычных контейнеров
sudo docker exec CONTAINER nslookup google.com 172.17.0.1
```

### Устранение неполадок

```bash
# 1. Проверить что Pi-hole запущен
sudo docker ps | grep pihole

# 2. Проверить режим сети контейнера
sudo docker inspect 3xui_app --format '{{.HostConfig.NetworkMode}}'

# 3. Перезапустить Pi-hole
sudo docker compose down && sudo docker compose up -d

# 4. После изменения DNS в 3x-ui — перезапустить
sudo docker restart 3xui_app
```


### Включение (systemd-resolved → Pi-hole)

```bash
# 1. Создать конфигурацию
sudo mkdir -p /etc/systemd/resolved.conf.d/
sudo tee /etc/systemd/resolved.conf.d/pihole.conf << 'EOF'
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF

# 2. Применить
sudo systemctl restart systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
```

### Отключение (откат к systemd-resolved)

```bash
sudo rm /etc/systemd/resolved.conf.d/pihole.conf
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
```

### Проверка

```bash
cat /etc/resolv.conf | grep nameserver
dig google.com @127.0.0.1
```

### Ошибка "unable to resolve host"

Если после отключения `DNSStubListener` появляется ошибка:
```
sudo: unable to resolve host HOSTNAME: Name or service not known
```

Добавьте hostname в `/etc/hosts`:
```bash
grep -q "$(hostname)" /etc/hosts || echo "127.0.0.1 $(hostname)" | sudo tee -a /etc/hosts
```

---

## Конфигурация (.env)

### Основные параметры

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `TZ` | `Europe/Moscow` | Часовой пояс |
| `FTLCONF_webserver_api_password` | `admin123` | Пароль панели |

### Сетевые настройки

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `DNS_BIND_IP` | `127.0.0.1` | IP для DNS |
| `DNS_PORT` | `53` | Порт DNS |
| `WEB_BIND_IP` | `127.0.0.1` | IP для веб-панели |
| `WEB_HTTP_PORT` | `8080` | HTTP порт панели |
| `WEB_HTTPS_PORT` | `8443` | HTTPS порт панели |

### DNS настройки

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `FTLCONF_dns_listeningMode` | `ALL` | Режим: LOCAL, SINGLE, BIND, ALL |
| `FTLCONF_dns_dnssec` | `false` | Проверка DNSSEC |
| `FTLCONF_dns_cache_size` | `10000` | Размер кэша |
| `FTLCONF_dns_blockTTL` | `2` | TTL для блокировок |

### SSL сертификаты

| Параметр | Описание |
|----------|----------|
| `PIHOLE_DOMAIN` | Домен для панели (для авто-SSL) |
| `PIHOLE_ADMIN_EMAIL` | Email для Let's Encrypt |

---

## Режимы доступа

### Вариант 1: Только localhost (безопасно)

```env
DNS_BIND_IP=127.0.0.1
WEB_BIND_IP=127.0.0.1
WEB_HTTP_PORT=8080
WEB_HTTPS_PORT=8443
```

Доступ к панели через SSH туннель:
```bash
ssh -L 8080:127.0.0.1:8080 user@server
# Открыть: http://localhost:8080/admin
```

### Вариант 2: Доступ по домену с SSL

```env
PIHOLE_DOMAIN=dns.yourdomain.com
PIHOLE_ADMIN_EMAIL=admin@yourdomain.com
WEB_BIND_IP=0.0.0.0
WEB_HTTP_PORT=80
WEB_HTTPS_PORT=443
```

Панель будет доступна по `https://dns.yourdomain.com/admin`

### Ограничение DNS по IP (iptables)

```bash
# Разрешить конкретный IP
sudo iptables -I INPUT -p udp --dport 53 -s YOUR_IP -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j DROP

# Сохранить
sudo apt install iptables-persistent -y
```

---

## SSL сертификаты

Сертификаты выдаются автоматически если указан домен в `.env`:

```env
PIHOLE_DOMAIN=dns.yourdomain.com
PIHOLE_ADMIN_EMAIL=admin@yourdomain.com
```

После запуска `docker compose up -d`:
1. Certbot проверит DNS запись домена
2. Автоматически выпустит сертификат
3. Будет обновлять его каждые 12 часов

---

## Команды управления

```bash
# Запуск
sudo docker compose up -d

# Остановка
sudo docker compose down

# Перезапуск
sudo docker compose restart
sudo docker compose down && sudo docker compose up -d



# Логи Pi-hole
sudo docker logs pihole

# Логи Certbot
sudo docker logs pihole_certbot

# Обновить blocklists (gravity)
sudo docker exec pihole pihole -g

# Добавить в whitelist
sudo docker exec pihole pihole allow domain.com

# Добавить в blacklist
sudo docker exec pihole pihole deny domain.com

# Статус Pi-hole
sudo docker exec pihole pihole status
```

---

## Блоклисты рекламы

### YouTube Ads Blocklist

Добавлен автоматически при наличии volumes:
```
https://raw.githubusercontent.com/kboghdady/youTube_ads_4_pi-hole/master/youtubelist.txt
```

### Добавить YouTube blocklist вручную:

```bash
sudo docker exec pihole pihole-FTL sqlite3 /etc/pihole/gravity.db \
  "INSERT OR IGNORE INTO adlist (address, enabled) VALUES 
  ('https://raw.githubusercontent.com/kboghdady/youTube_ads_4_pi-hole/master/youtubelist.txt', 1);"
sudo docker exec pihole pihole -g
```

### Добавить whitelist (чтобы видео работали):

```bash
sudo docker exec pihole pihole allow s.youtube.com
```

### Другие популярные списки:

| Список | URL |
|--------|-----|
| StevenBlack Hosts | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| AdGuard DNS | `https://v.firebog.net/hosts/AdguardDNS.txt` |
| EasyList | `https://easylist.to/easylist/easylist.txt` |

---

## Автообновление blocklists (cron)

Для автоматического обновления списков блокировки:

```bash
# Открыть crontab
sudo crontab -e

# Добавить строку (обновление каждый день в 3:00):
0 3 * * * docker exec pihole pihole -g > /dev/null 2>&1
```

Проверить текущие задачи:
```bash
sudo crontab -l
```

---

## Структура проекта

```
pi-hole/
├── docker-compose.yml    # Docker конфигурация
├── .env                  # Настройки (из .env.example)
├── .env.example          # Пример настроек с комментариями
├── certbot-init.sh       # Скрипт авто-выпуска SSL
├── etc-pihole/           # Данные Pi-hole (создаётся автоматически)
└── certbot-logs/         # Логи Certbot
```
