#!/bin/bash
# Скрипт установки Xray Manager
clear

set -e

XRAY_BIN="/usr/local/bin/xray"
MANAGER_BIN="/usr/local/bin/xray-manager.sh"
CONFIG_DIR="/usr/local/etc/xray"
CLIENT_DIR="$CONFIG_DIR/clients"
XRAY_LOG_DIR="/var/log/xray"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error_exit() {
    echo -e "${RED}✗ $1${NC}"
	read -r -p "Нажмите Enter для продолжения..." _
	echo "";	
	exit 1
}
error_message() {
    echo -e "${RED}✗ $1${NC}"
    echo "";	
}
success_message() {
    echo -e "${GREEN}✓ $1${NC}"	
	echo "";	
}
pause() {
    echo ""
    read -r -p "Нажмите Enter для продолжения..." _
}
echo "Установка Xray Manager ";
echo ""
echo "=== Проверка и установка зависимостей ==="
echo ""


echo "=== Проверим, присутствует ли xray в системе ==="
if  command -v "$XRAY_BIN" >/dev/null 2>&1; then
     success_message "Xray установлен."
else
    echo "=== Установка xray ==="
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
	
	if  command -v "$XRAY_BIN" >/dev/null 2>&1; then
		 success_message "Xray установлен."
	else
		error_exit "Xray не найден. Установите Xray в $XRAY_BIN"
		exit 1 
	fi
	
fi


echo "=== Проверим, присутствует ли jq в системе ==="
if  command -v jq >/dev/null 2>&1; then
     success_message "jq установлен."
else
    echo "=== Установка jq ==="
    sudo dnf install -y jq
	
	if  command -v jq >/dev/null 2>&1; then
		 success_message "jq установлен."
	else
		error_exit "jq не найден. Установите jq"
		exit 1 
	fi
	
fi

echo "=== Проверим, присутствует ли qrencode в системе ==="
if  command -v qrencode >/dev/null 2>&1; then
     success_message "qrencode установлен."
else
    echo "=== Установка qrencode ==="
    sudo dnf install -y qrencode
	
	if  command -v qrencode >/dev/null 2>&1; then
		 success_message "qrencode установлен."
	else
		error_exit "qrencode не найден. Установите qrencode"
		exit 1 
	fi
	
fi

echo "=== Проверим, присутствует ли curl в системе ==="
if  command -v curl >/dev/null 2>&1; then
     success_message "curl установлен."
else
    echo "=== Установка curl ==="
    sudo dnf install -y curl
	
	if  command -v curl >/dev/null 2>&1; then
		 success_message "curl установлен."
	else
		error_exit "curl не найден. Установите curl"
		exit 1 
	fi
	
fi


# =========================
# Проверка и создание директорий
# =========================
echo "=== Проверка директорий ==="

for dir in "$CONFIG_DIR" "$CLIENT_DIR" "$XRAY_LOG_DIR"; do
    if [ -d "$dir" ]; then
        echo "✓ Директория существует: $dir"
    else
        echo "Создаём директорию: $dir"
        sudo mkdir -p "$dir"
        if [ -d "$dir" ]; then
            success_message "Директория создана: $dir"
        else
            error_exit "Не удалось создать директорию: $dir"           
        fi
    fi
done
echo ""

# =========================
# Проверка и копирование менеджера
# =========================
echo "=== Проверка xray-manager.sh ==="

if [ -f "$MANAGER_BIN" ]; then
    echo "✓ Менеджер уже скопирован: $MANAGER_BIN"
else
    echo "Копируем менеджер в $MANAGER_BIN"
    sudo cp xray-manager.sh "$MANAGER_BIN"
    sudo chmod +x "$MANAGER_BIN"

    if [ -f "$MANAGER_BIN" ] && [ -x "$MANAGER_BIN" ]; then
        success_message "Менеджер успешно скопирован и доступен для запуска"
    else
        error_exit "Ошибка копирования менеджера!"        
    fi
fi 
echo ""

echo -e ""
echo -e "✅ Установка завершена!"
echo -e "\nДля управления аккаунтами пользователей запустите:\n$ $MANAGER_BIN или xray-manager.sh"
