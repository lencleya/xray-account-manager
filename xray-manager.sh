#!/bin/bash

VERSION="0.52"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG="/usr/local/etc/xray/config.json"
KEY_FILE="/usr/local/etc/xray/reality.key"
XRAY_BIN="/usr/local/bin/xray"
SERVICE="xray"
CLIENT_DIR="/usr/local/etc/xray/clients"

TELEGRAM_CONFIG="/usr/local/etc/xray/telegram.conf"

PORT=443

SNI_LIST=(
		"api.avito.ru"
		"apple.com"
		"eh.vk.com"
		"github.com"
		"m.vk.ru"
		"microsoft.com"
		"ozon.ru"
		"wb.ru"
		"www.twitch.tv"
		"www.vk.com"
		"ya.ru"
		"sun6-21.userapi.com"
		"cloudcdn-m9-12.cdn.yandex.net"		
)

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =========================
# Utils
# =========================


error_exit() {
    echo -e "${RED}✗ $1${NC}"
	pause
	exit 1
}

error_message() {
    echo -e "${RED}✗ $1${NC}"
	pause    
}

pause() {
    echo ""
    read -r -p "Нажмите Enter для продолжения..." _
}
success_message() {
    echo -e "${GREEN}✓ $1${NC}"	
	echo "";	
}

clear_if_interactive() {
    if [ -t 1 ]; then
        clear
    fi
}

require_cmd() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "$cmd" ]; then
        return 0
    fi
    error_exit "Команда '$cmd' не найдена"
}

get_server_ip() {
    local ip
    ip=$(curl -s ifconfig.me 2>/dev/null || true)
    if [ -z "$ip" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    echo "$ip"
}

format_bytes() {
    local bytes="$1"
    local unit="B"
    local value="$bytes"
    if [ -z "$bytes" ]; then
        echo "0 B"
        return
    fi
    if [ "$bytes" -ge 1099511627776 ] 2>/dev/null; then
        value=$((bytes / 1099511627776))
        unit="TB"
    elif [ "$bytes" -ge 1073741824 ] 2>/dev/null; then
        value=$((bytes / 1073741824))
        unit="GB"
    elif [ "$bytes" -ge 1048576 ] 2>/dev/null; then
        value=$((bytes / 1048576))
        unit="MB"
    elif [ "$bytes" -ge 1024 ] 2>/dev/null; then
        value=$((bytes / 1024))
        unit="KB"
    fi
    echo "${value} ${unit}"
}
user_online() {
    local NAME="$1"
    local ips=$(awk -v since="$(date -d '15 minutes ago' '+%Y/%m/%d %H:%M:%S')" '$1 " " $2 >= since && $0 ~ /'"$NAME"'/ && /accepted/ {match($0, /from ([0-9.]+):/, a); print a[1]}' /var/log/xray/access.log | sort | uniq)

    if [ -n "$ips" ]; then
        local count=$(echo "$ips" | wc -l)
        if [ "$count" -eq 1 ]; then
            echo -e "${GREEN}✅ $ips${NC}"  # один IP
        else
            local ip_list=$(echo "$ips" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
            echo -e "${GREEN}✅ $ip_list${NC}"
        fi
    fi
}


restart_xray() {
    systemctl restart "$SERVICE" || error_exit "Не удалось перезапустить xray"

    if ! systemctl is-active --quiet "$SERVICE"; then
        echo "Логи:"
        journalctl -u "$SERVICE" -n 20 --no-pager
        error_exit "Xray не запустился"
    fi

    echo -e "${GREEN}✓ Xray работает${NC}"
}

check_keys() {
    if [ ! -f "$KEY_FILE" ]; then
        error_exit "Файл ключей не найден. Запустите init"		
    fi

    source "$KEY_FILE"

    if [ -z "${PRIVATE_KEY:-}" ] || [ -z "${PUBLIC_KEY:-}" ]; then
        error_exit "Некорректный файл ключей"
    fi
}

check_config() {
    if [ ! -f "$CONFIG" ]; then
        error_exit "Конфиг не найден. Запустите init"		
    fi

    require_cmd jq

    local pk
    pk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$CONFIG" 2>/dev/null)
    if [ -z "$pk" ]; then
        error_exit "В конфиге не найден privateKey"
    fi
}

# =========================
# Init / Keys
# =========================

gen_keys_and_config() {
    require_cmd "$XRAY_BIN"
	
	

    #if [ -f "$CONFIG" ] || [ -f "$KEY_FILE" ]; then
	if [ -f "$KEY_FILE" ]; then
        echo -e "${RED}xray уже инициализирован, файл конфигурации и файл ключей расположен ${CONFIG_DIR}${NC}"
        echo -e "${YELLOW}Для повторной инициализации, удалите файлы:${NC}"
        echo "$CONFIG"
        echo "$KEY_FILE"
        return 1
    fi

    #mkdir -p "$CLIENT_DIR" "$CONFIG_DIR"
	
	clear_if_interactive
	
	echo -e "${YELLOW}========== XRAY ${VERSION} MENU ==========${NC}"
	echo ""
    echo -e "${YELLOW}🔐 Генерация Reality ключей...${NC}"
     
   
    local output
    output=$($XRAY_BIN x25519)

    PRIVATE_KEY=$(echo "$output" | awk -F': ' '/Private/{print $2; exit}')
    PUBLIC_KEY=$(echo "$output" | awk -F': ' '/Public/{print $2; exit}')
	
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        error_exit "Не удалось сгенерировать ключи"
    fi
	
	# случайный выбор
    #SNI=${SNI_LIST[$RANDOM % ${#SNI_LIST[@]}]}
	
	echo ""
	echo "Выберите SNI для Reality:"
	COLUMNS=1
	PS3="Выберите домен: "
	select SNI in "${SNI_LIST[@]}"; do
		if [[ -n "$SNI" ]]; then
			echo "Выбрано: $SNI"
			break
		else
			echo "Неверный выбор, попробуйте снова"
		fi
	done
	
    SHORT_ID=$(openssl rand -hex 4)

    cat > "$KEY_FILE" <<EOF
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SNI=$SNI
SHORT_ID=$SHORT_ID
EOF

     touch "$KEY_FILE"
 
    chmod 644 "$KEY_FILE"
    echo -e "${GREEN}✓ Ключи сохранены: $KEY_FILE${NC}"

    echo -e "${YELLOW}📄 Генерация дефолтного конфига: $CONFIG${NC}"

    cat > "$CONFIG" <<EOF
{
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8", "8.8.4.4"]
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "stats": {},
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:${PORT}",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "tag": "vless-in"
    },
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" },
      "tag": "api"
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {}, "tag": "direct" },
    { "protocol": "freedom", "tag": "api" }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      }
    ]
  },
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning",
    "dnsLog": false,
    "maskAddress": ""
  }
}
EOF
    restart_xray
    
	chmod 644 "$CONFIG"
    echo -e "${GREEN}✓ Конфиг сохранён: $CONFIG${NC}"
}
 
# =========================
# Clients
# =========================

client_exists_by_name() {
    local name="$1"
    jq -e --arg name "$name" '.inbounds[0].settings.clients[]? | select(.email == $name)' "$CONFIG" >/dev/null 2>&1
}

get_name_by_uuid() {
    local uuid="$1"
    jq -r --arg id "$uuid" '.inbounds[0].settings.clients[]? | select(.id==$id) | .email' "$CONFIG"
}

get_uuid_by_name() {
    local name="$1"
    jq -r --arg name "$name" '.inbounds[0].settings.clients[]? | select(.email==$name) | .id' "$CONFIG"
}

list_clients() {
    jq -r '.inbounds[0].settings.clients[]? | "\(.email)\t\(.id)"' "$CONFIG"
}

list_clients_table() {
    check_config
    require_cmd jq
	
	
	clear_if_interactive
	
	echo -e "${YELLOW}========== XRAY ${VERSION} MENU ==========${NC}"
	echo ""
    echo "Список пользователей"
    echo ""    


    local clients
    clients=$(list_clients)

    if [ -z "$clients" ]; then
        echo -e "${YELLOW}Список пользователей пуст${NC}"
        return 0
    fi

    local index=0
    local max_name=4
    local max_uuid=4
    local names=()
    local uuids=()

    while IFS=$'\t' read -r name uuid; do
        [ -z "$name" ] && continue
        index=$((index + 1))
        names+=("$name")
        uuids+=("$uuid")

        local name_len=${#name}
        local uuid_len=${#uuid}
        if [ "$name_len" -gt "$max_name" ]; then
            max_name=$name_len
        fi
        if [ "$uuid_len" -gt "$max_uuid" ]; then
            max_uuid=$uuid_len
        fi
    done <<< "$clients"

    printf "%-4s  %-*s  %-*s\n" "ID" "$max_name" "Name" "$max_uuid" "UUID"
    printf "%-4s  %-*s  %-*s\n" "----" "$max_name" "----" "$max_uuid" "----"
    local i
    for ((i=0; i<index; i++)); do
        local num=$((i + 1))
        printf "%-4s  %-*s  %-*s\n" "${num}." "$max_name" "${names[$i]}" "$max_uuid" "${uuids[$i]}"
    done
}
select_user_menu() {
    check_config
    require_cmd jq

    local show_uuid="${1:-yes}"
    local clients
    clients=$(list_clients)

    if [ -z "$clients" ]; then
        echo -e "${YELLOW}Список пользователей пуст${NC}" >&2
        return 1
    fi

    local index=0
    local names=()
    local uuids=()
    local max_name=4
    local max_uuid=4

    while IFS=$'\t' read -r name uuid; do
        name=$(echo "$name" | xargs)
        uuid=$(echo "$uuid" | xargs)
        [ -z "$name" ] && continue
        index=$((index + 1))
        names+=("$name")
        uuids+=("$uuid")
        local name_len=${#name}
        local uuid_len=${#uuid}
        if [ "$name_len" -gt "$max_name" ]; then
            max_name=$name_len
        fi
        if [ "$uuid_len" -gt "$max_uuid" ]; then
            max_uuid=$uuid_len
        fi
    done <<< "$clients"

    if [ "$show_uuid" = "yes" ]; then
        printf "%-4s  %-*s  %-*s\n" "ID" "$max_name" "Name" "$max_uuid" "UUID" >&2
        printf "%-4s  %-*s  %-*s\n" "----" "$max_name" "----" "$max_uuid" "----" >&2
        local i
        for ((i=0; i<index; i++)); do
            local num=$((i + 1))
            printf "%-4s  %-*s  %-*s\n" "${num}." "$max_name" "${names[$i]}" "$max_uuid" "${uuids[$i]}" >&2
        done
    else
        printf "%-4s  %-*s\n" "ID" "$max_name" "Name" >&2
        printf "%-4s  %-*s\n" "----" "$max_name" "----" >&2
        local i
        for ((i=0; i<index; i++)); do
            local num=$((i + 1))
            printf "%-4s  %-*s\n" "${num}." "$max_name" "${names[$i]}" >&2
        done
    fi

    echo "" >&2
    echo -n "Введите номер (B - назад): " >&2
    read -r choice

    case "$choice" in
        [Bb]) return 2 ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$index" ]; then
                local idx=$((choice - 1))
                echo "${names[$idx]}|${uuids[$idx]}"
                return 0
            fi
            echo -e "${RED}Неверный выбор${NC}" >&2
            return 1
            ;;
    esac
}

add_client() {
    check_keys
    check_config
    require_cmd jq
	
	clear_if_interactive
	
	echo -e "${YELLOW}========== XRAY ${VERSION} MENU ==========${NC}"
	echo ""
    echo "Создание нового пользователя:"
    echo ""    

    local name="$1"
    if [ -z "$name" ]; then
        read -r -p "Введите имя пользователя: " name
    fi

    if [ -z "$name" ]; then
        error_exit "Имя не может быть пустым"
    fi

    if client_exists_by_name "$name"; then
        error_exit "Пользователь '$name' уже существует"
    fi

    local uuid
    uuid=$($XRAY_BIN uuid)

    local tmp
    tmp=$(mktemp)

    jq --arg id "$uuid" --arg name "$name" \
        '.inbounds[0].settings.clients += [{"id": $id, "flow": "xtls-rprx-vision", "email": $name}]' \
        "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"

    chmod 644 "$CONFIG"

    echo -e "${GREEN}✓ Пользователь добавлен${NC}"
    echo "Имя: $name"
    echo "UUID: $uuid"
    echo ""

    generate_client_config "$uuid" "$name"
    restart_xray

    echo ""
    generate_link "$uuid" "$name"

   
	# Загружаем Telegram настройки если файл существует
	if [ -f "$TELEGRAM_CONFIG" ]; then
		source "$TELEGRAM_CONFIG"
	fi
	
	if [[ -n "${TELEGRAM_TOKEN:-}" && -n "${TELEGRAM_CHAT:-}" ]]; then
		echo ""
		echo "Отправка файла конфигурации в Telegram бота..."
		send_config_to_telegram "$name"

	else
		echo ""
		success_message "Конфиг с настроенными маршрутами и правилами сохранён в: $CLIENT_DIR/${name}.json"
		echo "Скопируйте содержимое и вставьте в VPN клиент HAPP или аналогичные."
		echo ""
		echo "Чтобы включить отправку в Telegram, настройте бота через меню (пункт 9)"
		echo ""
	fi
}

remove_client_by_uuid() {
    check_config
    require_cmd jq
	
	clear_if_interactive
	
	echo -e "${YELLOW}========== XRAY ${VERSION} MENU ==========${NC}"
	echo ""
    echo "Удаление пользователя:"
    echo ""    


    local selected
    selected=$(select_user_menu "yes") || {
        [ $? -eq 2 ] && return 0
        return 1
    }

    local email
    local uuid
    email=$(echo "$selected" | awk -F'|' '{print $1}')
    uuid=$(echo "$selected" | awk -F'|' '{print $2}')

    if [ -z "$email" ] || [ -z "$uuid" ]; then
        echo -e "${YELLOW}⚠ Пользователь не найден${NC}"
        return 1
    fi

    local tmp
    tmp=$(mktemp)

    jq --arg id "$uuid" \
       '.inbounds[0].settings.clients |= map(select(.id != $id))' \
       "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"

    if [ -d "$CLIENT_DIR" ]; then
        local file="$CLIENT_DIR/${email}.json"
        [ -f "$file" ] && rm -f "$file"
    fi

    chmod 644 "$CONFIG"
    restart_xray

    echo -e "${GREEN}✓ Пользователь удалён: $email${NC}"
}

# =========================
# Link / QR / Config
# =========================

generate_qr() {
    local link="$1"
    if ! command -v qrencode >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ qrencode не установлен${NC}"
        return
    fi

    echo ""
    qrencode -t ANSIUTF8 "$link"
    echo ""
}

generate_link() {
    check_keys
	
    local uuid="$1"
    local name="$2"

    local server_ip
    server_ip=$(get_server_ip)

    local link
    link="vless://${uuid}@${server_ip}:${PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${name}"

    generate_qr "$link"

    echo "Ссылка для подключения без правил роутинга (все подключения идут через vpn):"
    echo "$link"
}

qr_link_menu() {
    check_keys
    check_config
	
	
	clear_if_interactive
	
	echo -e "${YELLOW}========== XRAY ${VERSION} MENU ==========${NC}"
	echo ""
    echo "Сгенерировать QR-код и ссылку для подключения:"
    echo ""    


    local selected
    selected=$(select_user_menu "no") || {
        [ $? -eq 2 ] && return 0
        return 1
    }

    local name
    local uuid
    name=$(echo "$selected" | awk -F'|' '{print $1}')
    uuid=$(echo "$selected" | awk -F'|' '{print $2}')

    if [ -z "$name" ] || [ -z "$uuid" ]; then
        echo -e "${YELLOW}⚠ Пользователь не найден${NC}"
        return 1
    fi

    generate_link "$uuid" "$name"
}

show_user_config() {
    local name="$1"

    if [ -z "$name" ]; then
        read -r -p "Введите имя пользователя: " name
    fi

    if [ -z "$name" ]; then
        echo -e "${YELLOW}⚠ Имя не введено${NC}"
        return 1
    fi

    local file="$CLIENT_DIR/${name}.json"
    if [ ! -f "$file" ]; then
        echo -e "${YELLOW}⚠ Конфиг пользователя не найден: $file${NC}"
        return 1
    fi

    clear_if_interactive
    cat "$file"
}

send_config_to_telegram() {
    local name="$1"
	
	
	#clear_if_interactive
	
	echo -e "${YELLOW}========== XRAY ${VERSION} MENU ==========${NC}"
	echo ""
    echo "Отправка конфига в телеграм-бота:"
    echo ""    


    if [ -z "$name" ]; then
        local selected
        selected=$(select_user_menu "no") || {
            [ $? -eq 2 ] && return 0
            return 1
        }

        name=$(echo "$selected" | awk -F'|' '{print $1}')
    fi

    if [ -z "$name" ]; then
        echo -e "${YELLOW}⚠ Пользователь не найден${NC}"
        return 1
    fi

    local file="$CLIENT_DIR/${name}.json"
    if [ ! -f "$file" ]; then
        echo -e "${YELLOW}⚠ Конфиг не найден: $file${NC}"
        return 1
    fi

    send_telegram_file "$file" "xray-config-${name}.json" && \
        echo -e "${GREEN}✓ Конфиг отправлен в Telegram${NC}" || {
        echo -e "${YELLOW}⚠ Не удалось отправить конфиг${NC}"
        return 1
    }
}

# =========================
# Client Config Generator
# =========================

generate_client_config() {
    check_keys

    local uuid="$1"
    local name="$2"

    local server_ip
    server_ip=$(get_server_ip)

    local file="$CLIENT_DIR/${name}.json"

    cat > "$file" <<EOF
{
  "log": { "loglevel": "warning" },
  "dns": {
    "queryStrategy": "UseIPv4",
    "servers": ["1.1.1.1", "8.8.8.8"]
  },
  "inbounds": [
    {
      "protocol": "socks",
      "listen": "127.0.0.1",
      "port": 10808,
      "settings": {
        "auth": "noauth",
        "udp": true,
        "userLevel": 8
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${server_ip}",
            "port": ${PORT},
            "users": [
              {
                "id": "${uuid}",
                "flow": "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "${SNI}",
          "publicKey": "${PUBLIC_KEY}",
          "shortId": "${SHORT_ID}"
        }
      },
      "tag": "proxy"
    },
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "remarks": "${name}",
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "domain": [
                    "domain:2ip.io",
                    "domain:speedtest.net",
					"cloudflare.com",
					
                    "domain:cdninstagram.com",
                    "domain:chatgpt.com",
                    "domain:fbcdn.net",
                    "domain:ggpht.com",
                    "domain:googlevideo.com",
                    "domain:gvt1.com",
                    "domain:ig.me",
                    "domain:instagram.com",
                    "domain:openai.com",
					
                    "domain:remotedesktop.google.com",
					"domain:googleapis.com",
					"domain:gstatic.com",
					"domain:chromoting.com",
                    
                    "domain:tiktok.com",
                    "domain:tiktokcdn.com",
                    "domain:tiktokv.com",
                    "domain:tiktokcdn-us.com",
                    "domain:byteoversea.com",
                    "domain:tiktokcdn-in.com",
                    "domain:tlivecdn.com",
                    "domain:ttlivecdn.com",
                    "domain:muscdn.com",
                    "domain:tik-tokapi.com",
                    "domain:ttoversea.net",
                    "domain:ttoverseaus.net",
                    "domain:ibytedtos.com",
                    "domain:ipstatp.com",
                    "domain:musical.ly",
                    "domain:tiktokcdn-eu.com",
                    "domain:tiktokd.net",
                    "domain:tiktokd.org",
                    "domain:tiktokv.us",
                    "domain:tiktokw.us",
                    "domain:ttwstatic.com",
                    "domain:tiktokv.eu",
                    "domain:soundcloud.com",
                    "domain:soundcloud.cloud",
                    "domain:wa.me",
                    "domain:whatsapp.com",
                    "domain:whatsapp.net",
                    "domain:wide-youtube.l.google.com",
                    "domain:youtu.be",
                    "domain:youtube-nocookie.com",
                    "domain:youtube-ui.l.google.com",
                    "domain:youtube.com",
                    "domain:yt-video-upload.l.google.com",
                    "domain:yt.be",
                    "domain:ytimg.com",

					"domain:t.me",
					"domain:tg.dev",
					"domain:tg.org",
					"domain:tx.me",
					"domain:teleg.xyz",
					"domain:telegram.ai",
					"domain:telegram.asia",
					"domain:telegram.biz",
					"domain:telegram.cloud",
					"domain:telegram.cn",
					"domain:telegram.co",
					"domain:telegram.com",
					"domain:telegram.de",
					"domain:telegram.dev",
					"domain:telegram.dog",
					"domain:telegram.eu",
					"domain:telegram.fr",
					"domain:telegram.host",
					"domain:telegram.in",
					"domain:telegram.info",
					"domain:telegram.io",
					"domain:telegram.jp",
					"domain:telegram.me",
					"domain:telegram.net",
					"domain:telegram.org",
					"domain:telegram.qa",
					"domain:telegram.ru",
					"domain:telegram.services",
					"domain:telegram.solutions",
					"domain:telegram.space",
					"domain:telegram.team",
					"domain:telegram.tech",
					"domain:telegram.uk",
					"domain:telegram.us",
					"domain:telegram.website",
					"domain:telegram.xyz",
					"domain:telegramapp.org",
					"domain:telegra.ph",
					"domain:telesco.pe",
					"domain:nicegram.app",
					"domain:telegramdownload.com",
					"domain:cdn-telegram.org",
					"domain:comments.app",
					"domain:contest.com",
					"domain:fragment.com",
					"domain:graph.org",
					"domain:quiz.directory",
					"domain:tdesktop.com",
					"domain:telega.one",
					"domain:telegram-cdn.org",
					"domain:usercontent.dev",
					"domain:tgram.org",
					"domain:torg.org",
					
					"domain:imo.im", 
					"domain:imoim.net",
					"domain:kzhi.tech",
					
					"domain:aistudio.google.com",
                    "domain:gemini.google.com"
                    
        ],
        "outboundTag": "proxy"
      },
	  {
				"type": "field",
				"ip": [
					"91.108.4.0/22",
					"91.108.8.0/22",
					"91.108.12.0/22",
					"91.108.16.0/22",
					"91.108.20.0/22",
					"91.108.56.0/22",
					"149.154.160.0/20",
					
					"192.12.31.0/24", 
					
					"192.178.0.0/15",
					"142.250.0.0/15",
					"142.251.0.0/16",
					"172.217.0.0/19",
					"172.217.32.0/20",
					"172.217.48.0/21",
					"172.217.64.0/18",
					"172.217.128.0/17",
					"216.58.192.0/19",
					"74.125.0.0/16",
					"216.239.32.0/20",
					"216.239.48.0/21",
					"216.239.56.0/22",
					"216.239.61.0/24",
					"216.239.62.0/23",
					"108.170.192.0/18",
					"108.177.0.0/17",
					"64.233.160.0/19",
					"209.85.128.0/17"
			
				],
				"outboundTag": "proxy"
	  },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

    echo -e "${GREEN}✓ Конфиг клиента сохранён: $file${NC}"
}

# =========================
# Telegram
# =========================
load_telegram_config() {
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        echo -e "${YELLOW}⚠ Telegram не настроен (файл не найден)${NC}"
        return 1
    fi

    source "$TELEGRAM_CONFIG"

    if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT:-}" ]]; then
        echo -e "${YELLOW}⚠ TELEGRAM_TOKEN или TELEGRAM_CHAT пустые${NC}"
        return 1
    fi

    return 0
}

send_telegram_message() {
    local text="$1"

    if [ -z "$text" ]; then
        echo -e "${YELLOW}⚠ Пустое сообщение${NC}"
        return 1
    fi

    load_telegram_config || return 1
    require_cmd curl

    curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT}" \
        --data-urlencode "text=${text}" >/dev/null

    return 0
}
send_telegram_file() {
    local file_path="$1"
    local caption="$2"
    
	if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
        echo -e "${YELLOW}⚠ Файл не найден: $file_path${NC}"
        return 1
    fi

    load_telegram_config || return 1
    require_cmd curl
	
    if [ -n "$caption" ]; then
        curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT}" \
            -F "document=@${file_path}" \
            -F "caption=${caption}" >/dev/null
    else
        curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT}" \
            -F "document=@${file_path}" >/dev/null
    fi

    return 0
}

# =========================
# Stats
# =========================

get_all_stats() {
    

    $XRAY_BIN api statsquery --server=127.0.0.1:10085 2>/dev/null | \
    jq -r '
        [ .stat[]
          | select(.name|startswith("user>>>"))
          | {user:(.name|split(">>>")[1]), dir:(.name|split(">>>")[3]), value:.value}
        ]
        | group_by(.user)[]
        | (.[0].user) as $u
        | (map(select(.dir=="uplink")|.value)|add // 0) as $up
        | (map(select(.dir=="downlink")|.value)|add // 0) as $down
        | [$u, $up, $down]
        | @tsv
    '
}

stats_menu() {
    check_config

    require_cmd "$XRAY_BIN"

    while true; do
        clear_if_interactive
        echo -e "${YELLOW}========== XRAY STATS ==========${NC}"
        echo "Пользователи:"
        echo ""

        local clients
        clients=$(list_clients)

        if [ -z "$clients" ]; then
            echo -e "${YELLOW}Список пользователей пуст${NC}"
            echo ""
            read -r -p "B - назад: " _
            return
        fi

        declare -A uplink
        declare -A downlink
        while IFS=$'\t' read -r user up down; do
            [ -z "$user" ] && continue
            uplink["$user"]="$up"
            downlink["$user"]="$down"
        done < <(get_all_stats)

        local index=0
        local names=()
        local uuids=()
        local max_name=4

        while IFS=$'\t' read -r name uuid; do
            [ -z "$name" ] && continue
            index=$((index + 1))
            names+=("$name")
            uuids+=("$uuid")

            local up=${uplink[$name]:-0}
            local down=${downlink[$name]:-0}
            local name_len=${#name}
            if [ "$name_len" -gt "$max_name" ]; then
                max_name=$name_len
            fi
        done <<< "$clients"
         
        if [ "$index" -gt 0 ]; then
            printf "%-4s  %-*s  %-12s  %-12s %-12s\n" "" "$max_name" "Name" "Download" "Upload" "Online"
            printf "%-4s  %-*s  %-12s  %-12s %-12s\n" "" "$max_name" "----" "--------" "------" "------"
            local i
            for ((i=0; i<index; i++)); do
                local name="${names[$i]}"
                local up=${uplink[$name]:-0}
                local down=${downlink[$name]:-0}
                local num=$((i + 1))
				local online=$(user_online "$name")
                printf "%-4s  %-*s  %-12s  %-12s %-12s\n" "${num})" "$max_name" "$name" "$(format_bytes "$down")" "$(format_bytes "$up")" "$online"
            done
        fi

        echo ""
        read -r -p "Введите номер (B - назад, R - обновить): " choice

        case "$choice" in
            [Bb]) return ;;
            [Rr]) continue ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$index" ]; then
                    local idx=$((choice - 1))
                    local name="${names[$idx]}"
                    local uuid="${uuids[$idx]}"
                    show_user_stats "$name" "$uuid"
                else
                    echo -e "${RED}Неверный выбор${NC}"
                    pause
                fi
                ;;
        esac
    done
}

show_user_stats() {
    local name="$1"
    local uuid="$2"

    while true; do
        clear_if_interactive
        echo -e "${YELLOW}========== STATS: ${name} ==========${NC}"
        echo "UUID: $uuid"
        echo ""

        local line
        line=$($XRAY_BIN api statsquery --server=127.0.0.1:10085 2>/dev/null | \
            jq -r --arg u "$name" '
                [ .stat[]
                  | select(.name|startswith("user>>>"))
                  | {user:(.name|split(">>>")[1]), dir:(.name|split(">>>")[3]), value:.value}
                ]
                | map(select(.user==$u))
                | (map(select(.dir=="uplink")|.value)|add // 0) as $up
                | (map(select(.dir=="downlink")|.value)|add // 0) as $down
                | [$u, $up, $down]
                | @tsv
            ')

        if [ -z "$line" ]; then
            echo -e "${YELLOW}Статистика не найдена (возможно, пользователь ещё не подключался)${NC}"
        else
            local up
            local down
            IFS=$'\t' read -r _ up down <<< "$line"
            echo "Uplink:   $(format_bytes "$up")"
            echo "Downlink: $(format_bytes "$down")"
            echo "Всего:    $(format_bytes $((up + down)))"
        fi

        echo ""
        read -r -p "B - назад, R - обновить: " action
        case "$action" in
            [Bb]) return ;;
            [Rr]) continue ;;
            *)
                echo -e "${RED}Неверный выбор${NC}"
                pause
                ;;
        esac
    done
}
add_telegram_tokens() {
    clear_if_interactive

    echo -e "${YELLOW}========== XRAY ${VERSION} MENU ==========${NC}"
    echo ""
    echo "Настройка Telegram бота:"
    echo ""

    read -r -p "Введите Telegram Bot Token: " token
    read -r -p "Введите ваш Telegram Chat ID: " chat_id

    # Проверка
    if [[ -z "$token" || -z "$chat_id" ]]; then
        error_message "Токен и Chat ID не могут быть пустыми!"
        pause
        return
    fi

    # Создаем файл если нет
    #mkdir -p "$(dirname "$TELEGRAM_CONFIG")"
	touch $TELEGRAM_CONFIG

# Сохраняем
bash -c "cat > $TELEGRAM_CONFIG" <<EOF
TELEGRAM_TOKEN="$token"
TELEGRAM_CHAT="$chat_id"
EOF

    chmod 644 "$TELEGRAM_CONFIG"

    success_message "Данные Telegram успешно сохранены в $TELEGRAM_CONFIG"    
}

# =========================
# Menu
# =========================

show_menu() {
    while true; do
        clear_if_interactive
		echo -e "${YELLOW}========== XRAY ${VERSION} MENU ==========${NC}"
		echo ""
        echo "1) Добавить пользователя"
        echo "2) Удалить пользователя"
        echo "3) Список пользователей"
        echo "4) Статистика"
        echo "5) Отправить конфиг в телеграм-бота"
		echo "6) Сгенерировать QR для подключения"
		echo "7) Перезапустить xray"
		echo "8) Инициализация (первый запуск)"
		echo "9) Прописать telegram token и userid"
        echo "0) Exit"
        echo ""
        read -r -p "Выберите действие: " choice

        case "$choice" in
            1) add_client ; pause ;;
            2) remove_client_by_uuid ; pause ;;
            3) list_clients_table ; pause ;;
            4) stats_menu ;;            
            5) send_config_to_telegram ; pause ;;
			6) qr_link_menu ; pause ;;
			7) restart_xray ; pause ;;
			8) gen_keys_and_config ; pause ;;
			9) add_telegram_tokens ; pause ;;
            0) exit 0 ;;
            *) echo -e "${RED}Неверный пункт меню${NC}" ; pause ;;
        esac
    done
}

# =========================
# CLI
# =========================

case "${1:-}" in
    init)
        gen_keys_and_config
        ;;
    add)
        add_client "${2:-}"
        ;;
    list)
        list_clients_table
        ;;
    remove)
        remove_client_by_uuid "${2:-}"
        ;;
    link)
        generate_link "${2:-}" "${3:-}"
        ;;
    qr-link)
        qr_link_menu
        ;;
    config)
        show_user_config "${2:-}"
        ;;
    send-telegram)
        send_config_to_telegram "${2:-}"
        ;;
    restart)
        restart_xray
        ;;
    stat)
        stats_menu
        ;;
    "")
        show_menu
        ;;
    *)
        echo "Использование: $0 [init|add <name>|list|remove <uuid>|link <uuid> <name>|qr-link|config <name>|send-telegram <name>|restart|stat]"
        ;;
esac
