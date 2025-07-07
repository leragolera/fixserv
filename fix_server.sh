#!/bin/bash

# Скрипт восстановления сервера BlackHat Mail
# Автор: AI Assistant
# Дата: 2025-01-07

echo "=== Скрипт восстановления сервера BlackHat Mail ==="
echo "Начинаем диагностику и восстановление..."

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода статуса
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка root прав
if [[ $EUID -ne 0 ]]; then
   print_error "Скрипт должен запускаться с правами root"
   exit 1
fi

print_status "Проверка системы..."

# 1. Проверка и настройка сети
print_status "1. Настройка сетевых интерфейсов..."

# Получить основной интерфейс
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
    print_warning "Не найден основной интерфейс, используем eth0"
fi

print_status "Основной интерфейс: $INTERFACE"

# Поднять интерфейс
ip link set $INTERFACE up

# Проверить есть ли IP адрес
IP_EXISTS=$(ip addr show $INTERFACE | grep "inet " | wc -l)
if [ $IP_EXISTS -eq 0 ]; then
    print_warning "IP адрес не настроен, настраиваем..."
    ip addr add 91.90.192.36/24 dev $INTERFACE
    ip route add default via 91.90.192.1 2>/dev/null
fi

# Настроить DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

# Проверить подключение
print_status "Проверка подключения к интернету..."
if ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    print_status "Интернет работает"
else
    print_error "Нет подключения к интернету"
    exit 1
fi

# 2. Восстановление пакетов
print_status "2. Восстановление системных пакетов..."

# Обновить списки пакетов
apt update -y

# Исправить поврежденные пакеты
apt -f install -y

# Переустановить критические пакеты
apt install --reinstall -y systemd
apt install --reinstall -y network-manager
apt install --reinstall -y openssh-server
apt install --reinstall -y nginx

# Установить недостающие пакеты
apt install -y curl wget git nodejs npm sqlite3

# 3. Восстановление сетевых сервисов
print_status "3. Восстановление сетевых сервисов..."

# Включить и запустить NetworkManager
systemctl unmask NetworkManager 2>/dev/null
systemctl enable NetworkManager
systemctl start NetworkManager

# Включить и запустить SSH
systemctl enable ssh
systemctl start ssh

# 4. Восстановление почтового сервера
print_status "4. Восстановление почтового сервера..."

# Проверить существует ли проект
if [ -d "/var/www/mail" ]; then
    cd /var/www/mail
    
    # Проверить backend
    if [ -f "backend/server.js" ]; then
        print_status "Восстановление backend..."
        cd backend
        npm install
        cd ..
        
        # Запустить backend сервис
        systemctl enable blackhat-mail
        systemctl start blackhat-mail
    fi
    
    # Проверить frontend
    if [ -f "frontend/package.json" ]; then
        print_status "Сборка frontend..."
        cd frontend
        
        # Исправить проблему с иконкой Sync
        if [ -f "src/components/EmailView.js" ]; then
            sed -i 's/Sync, /RotateCcw, /g' src/components/EmailView.js
            sed -i 's/<Sync /<RotateCcw /g' src/components/EmailView.js
        fi
        
        npm install
        npm run build
        
        # Установить права
        chown -R www-data:www-data build/
        cd ..
    fi
    
    # Установить права на проект
    chown -R www-data:www-data /var/www/mail/
fi

# 5. Восстановление веб-сервера
print_status "5. Восстановление веб-сервера..."

# Проверить конфигурацию nginx
nginx -t

# Удалить дублирующие конфигурации
if [ -L "/etc/nginx/sites-enabled/mail.blackhatteam.cc" ]; then
    rm /etc/nginx/sites-enabled/mail.blackhatteam.cc
    print_status "Удалена дублирующая конфигурация nginx"
fi

# Перезапустить nginx
systemctl enable nginx
systemctl restart nginx

# 6. Восстановление почтовых сервисов
print_status "6. Восстановление почтовых сервисов..."

# Postfix
systemctl enable postfix
systemctl start postfix

# Dovecot
systemctl enable dovecot
systemctl start dovecot

# 7. Проверка всех сервисов
print_status "7. Проверка состояния сервисов..."

# Функция проверки сервиса
check_service() {
    local service=$1
    if systemctl is-active --quiet $service; then
        print_status "$service: РАБОТАЕТ"
    else
        print_error "$service: НЕ РАБОТАЕТ"
        systemctl status $service --no-pager -l
    fi
}

check_service "nginx"
check_service "blackhat-mail"
check_service "postfix"
check_service "dovecot"
check_service "ssh"

# 8. Проверка портов
print_status "8. Проверка портов..."
netstat -tlnp | grep -E '(80|443|3001|25|993|995)' || true

# 9. Проверка доступности
print_status "9. Проверка доступности сервисов..."

# Проверить backend
if curl -f http://localhost:3001/api/domains > /dev/null 2>&1; then
    print_status "Backend API доступен"
else
    print_warning "Backend API недоступен"
fi

# Проверить frontend
if [ -f "/var/www/mail/frontend/build/index.html" ]; then
    print_status "Frontend собран"
else
    print_warning "Frontend не собран"
fi

# 10. Очистка и финализация
print_status "10. Финализация..."

# Очистить кеш пакетов
apt autoremove -y
apt autoclean

# Обновить локальную база данных пакетов
updatedb 2>/dev/null || true

print_status "=== Восстановление завершено! ==="
print_status "Попробуйте подключиться к серверу по SSH и проверить работу сайта"
print_status "SSH: ssh root@91.90.192.36"
print_status "Сайт: http://mail.blackhat-team.cc"

# Показать краткий статус
echo ""
echo "=== КРАТКИЙ СТАТУС ==="
echo "Сеть: $(ping -c 1 8.8.8.8 > /dev/null 2>&1 && echo 'OK' || echo 'FAIL')"
echo "SSH: $(systemctl is-active ssh)"
echo "Nginx: $(systemctl is-active nginx)"
echo "Backend: $(systemctl is-active blackhat-mail)"
echo "Postfix: $(systemctl is-active postfix)"
echo "Dovecot: $(systemctl is-active dovecot)"
