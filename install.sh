#!/bin/bash
# Скрипт установки Xray Manager
clear
set -e

XRAY_BIN="/usr/local/bin/xray"
MANAGER_BIN="/usr/local/bin/xray-manager"
CONFIG_DIR="/usr/local/etc/xray"
CLIENT_DIR="$CONFIG_DIR/clients"
XRAY_LOG_DIR="/var/log/xray"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите скрипт от root (sudo)"
    exit 1
fi

# =========================
# Определение ОС
# =========================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Не удалось определить ОС"
    exit 1
fi

echo "Обнаружена ОС: $OS"

# =========================
# Определение пакетного менеджера
# =========================
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    PKG_MANAGER="apt"
    INSTALL_CMD="apt update && apt install -y"
elif [[ "$OS" == "almalinux" || "$OS" == "centos" || "$OS" == "rocky" ]]; then
    PKG_MANAGER="dnf"
    INSTALL_CMD="dnf install -y"
else
    echo "❌ Неподдерживаемая ОС: $OS"
    exit 1
fi

echo "Используем пакетный менеджер: $PKG_MANAGER"

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

install_if_missing() {
    local pkg=$1
    
	echo "=== Проверим, присутствует ли $pkg в системе ==="
	
    if command -v "$pkg" >/dev/null 2>&1; then
        success_message "$pkg установлен."
        return
    fi

    echo -e "${YELLOW}=== Установка $pkg ===${NC}"

    if ! eval "$INSTALL_CMD $pkg"; then
        error_exit "Ошибка установки пакета: $pkg (возможно, пакет не существует)"
    fi

    if command -v "$pkg" >/dev/null 2>&1; then
        success_message "$pkg установлен."
    else
        error_exit "$pkg установлен, но команда не найдена"
    fi
}


echo "Установка Xray Manager ";
echo ""
echo "=== Проверка и установка зависимостей ==="
echo ""
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

install_if_missing jq
install_if_missing qrencode
install_if_missing curl


# =========================
# Проверка и создание директорий
# =========================
echo "=== Проверка директорий ==="

for dir in "$CONFIG_DIR" "$CLIENT_DIR" "$XRAY_LOG_DIR"; do
    if [ -d "$dir" ]; then
        echo "✓ Директория существует: $dir"
    else
        echo "Создаём директорию: $dir"
           mkdir -p "$dir"
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
echo "=== Проверка xray-manager ==="

if [ -f "$MANAGER_BIN" ]; then
    echo "✓ Менеджер уже скопирован: $MANAGER_BIN"
else
    echo "Копируем менеджер в $MANAGER_BIN"
        cp xray-manager.sh "$MANAGER_BIN"
        chmod +x "$MANAGER_BIN"

    if [ -f "$MANAGER_BIN" ] && [ -x "$MANAGER_BIN" ]; then
        success_message "Менеджер успешно скопирован и доступен для запуска"
    else
        error_exit "Ошибка копирования менеджера!"        
    fi
fi 
echo ""


success_message " Установка завершена!"

echo -e "Для управления аккаунтами пользователей выполните:\n$ $MANAGER_BIN или xray-manager"
echo -e "----------------------------------------------"
echo -e ""
echo -e "Для удаления сервиса xray и скрипта xray-manager выполните команду:"
echo -e './uninstall.sh'


