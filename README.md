# Pi-hole DNS Server

Локальный DNS-сервер с блокировкой рекламы и автоматическим SSL.

## Быстрый старт

```bash
# 1. Настройте конфигурацию
cp .env.example .env
nano .env

# 2. Запустите Pi-hole
sudo docker compose up -d
```

> **SSL сертификаты** выдаются автоматически, если указан `PIHOLE_DOMAIN` в `.env`

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
