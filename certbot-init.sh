#!/bin/sh
# ============================================================================
# SSL Certificate Auto-setup для Pi-hole
# Автоматическая настройка SSL сертификатов Let's Encrypt
# Проверяет занятость порта 80 и останавливает конфликтующие сервисы
# ============================================================================

set -e

DOMAIN="${PIHOLE_DOMAIN:-}"
EMAIL="${PIHOLE_ADMIN_EMAIL:-admin@$DOMAIN}"

echo "🔐 Pi-hole SSL Auto-setup"
echo "   Домен: ${DOMAIN:-не указан}"

# Проверка занятости порта 80
check_port_80() {
    echo "🔍 Проверка порта 80..."
    
    if netstat -tlnp 2>/dev/null | grep -q ":80 " || ss -tlnp 2>/dev/null | grep -q ":80 "; then
        echo "⚠️  Порт 80 занят. Останавливаю конфликтующие сервисы..."
        
        # Пытаемся остановить известные сервисы
        systemctl stop nginx 2>/dev/null || true
        systemctl stop apache2 2>/dev/null || true
        systemctl stop httpd 2>/dev/null || true
        
        # Ждём освобождения порта
        sleep 3
        
        if netstat -tlnp 2>/dev/null | grep -q ":80 " || ss -tlnp 2>/dev/null | grep -q ":80 "; then
            echo "❌ Порт 80 всё ещё занят!"
            echo "   Освободите порт 80 для выпуска сертификата"
            return 1
        fi
        
        echo "✅ Порт 80 освобождён"
    else
        echo "✅ Порт 80 свободен"
    fi
    return 0
}

# Проверка DNS записи
check_dns() {
    domain=$1
    [ -z "$domain" ] || [ "$domain" = "localhost" ] && return 0
    
    echo "🔍 Проверка DNS для $domain..."
    
    VPS_IP=$(wget -4 -qO- --timeout=5 ifconfig.me 2>/dev/null || wget -4 -qO- --timeout=5 api.ipify.org 2>/dev/null || echo "")
    [ -z "$VPS_IP" ] && echo "⚠️  Не удалось определить IP сервера" && return 0
    
    DOMAIN_IP=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -1)
    [ -z "$DOMAIN_IP" ] && DOMAIN_IP=$(getent hosts "$domain" 2>/dev/null | awk '{print $1}' | head -1)
    
    if [ -z "$DOMAIN_IP" ]; then
        echo "❌ DNS не найден для $domain"
        echo "   Добавьте A запись: $domain -> $VPS_IP"
        return 1
    fi
    
    if [ "$DOMAIN_IP" = "$VPS_IP" ]; then
        echo "✅ DNS OK: $domain -> $VPS_IP"
        return 0
    else
        echo "❌ DNS не совпадает: $domain -> $DOMAIN_IP (сервер: $VPS_IP)"
        return 1
    fi
}

# Получение сертификата
get_cert() {
    domain=$1
    [ -z "$domain" ] || [ "$domain" = "localhost" ] && return 0
    
    cert_path="/etc/letsencrypt/live/$domain"
    
    if [ -d "$cert_path" ] && [ -f "$cert_path/fullchain.pem" ]; then
        echo "✅ Сертификат существует: $domain"
    else
        # Проверяем DNS
        check_dns "$domain" || { echo "⚠️  Пропускаем $domain (DNS не настроен)"; return 1; }
        
        # Проверяем порт 80
        check_port_80 || { echo "⚠️  Пропускаем $domain (порт 80 занят)"; return 1; }
        
        echo "📋 Запрос сертификата для $domain..."
        sleep 3
        
        certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            -d "$domain" \
            --preferred-challenges http \
            || echo "⚠️  Не удалось получить сертификат для $domain"
        
        [ -f "$cert_path/fullchain.pem" ] && echo "✅ Сертификат получен: $domain"
    fi
}

# Основная логика
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "localhost" ]; then
    echo "⚠️  PIHOLE_DOMAIN не указан"
    echo "   Режим только обновления сертификатов..."
else
    get_cert "$DOMAIN"
fi

# Цикл автообновления (каждые 12 часов)
echo "🔄 Запуск цикла обновления..."
trap exit TERM
while :; do
    certbot renew --standalone --quiet || true
    sleep 12h &
    wait
done
