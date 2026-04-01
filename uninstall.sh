#!/bin/bash
clear

XRAY_BIN="/usr/local/bin/xray"
MANAGER_BIN="/usr/local/bin/xray-manager"
CONFIG_DIR="/usr/local/etc/xray"
XRAY_LOG_DIR="/var/log/xray"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите скрипт от root (sudo)"
    exit 1
fi

echo "=== Удаление Xray Manager ==="

read -p "Вы уверены? Это удалит все конфиги и пользователей! (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Отмена"
    exit 0
fi

echo "Остановка Xray..."
systemctl stop xray 2>/dev/null

echo "Удаление сервиса Xray..."
systemctl disable xray 2>/dev/null


bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove


echo "Удаление файлов..."

rm -f "$MANAGER_BIN"
rm -rf "$CONFIG_DIR"
rm -rf "$XRAY_LOG_DIR"

echo "Удаление Xray бинарника..."
rm -f "$XRAY_BIN"

echo -e "${GREEN}✓ Удаление завершено${NC}"