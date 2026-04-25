#!/usr/bin/env bash
# Bedolaga one-command installer (bot + cabinet)
# Compatible with: curl -fsSL <url> | bash

set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_VERSION="3.0.0"
BOT_REPO_DEFAULT="https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git"
CABINET_REPO_DEFAULT="https://github.com/BEDOLAGA-DEV/bedolaga-cabinet.git"
BOT_DIR_DEFAULT="$HOME/bedolaga-bot"
CABINET_DIR_DEFAULT="$HOME/bedolaga-cabinet"
STATIC_ROOT_DEFAULT="/srv/cabinet"

# Config (can be pre-set via env for zero questions)
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
INSTALL_BOT="${INSTALL_BOT:-true}"
INSTALL_CABINET="${INSTALL_CABINET:-true}"
CONFIGURE_NGINX="${CONFIGURE_NGINX:-true}"
ENABLE_SSL="${ENABLE_SSL:-true}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
CABINET_DOMAIN="${CABINET_DOMAIN:-}"

BOT_REPO="${BOT_REPO:-$BOT_REPO_DEFAULT}"
BOT_DIR="${BOT_DIR:-$BOT_DIR_DEFAULT}"
CABINET_REPO="${CABINET_REPO:-$CABINET_REPO_DEFAULT}"
CABINET_DIR="${CABINET_DIR:-$CABINET_DIR_DEFAULT}"
STATIC_ROOT="${STATIC_ROOT:-$STATIC_ROOT_DEFAULT}"

BOT_TOKEN="${BOT_TOKEN:-}"
ADMIN_IDS="${ADMIN_IDS:-}"
SUPPORT_USERNAME="${SUPPORT_USERNAME:-@support}"
TELEGRAM_BOT_USERNAME="${TELEGRAM_BOT_USERNAME:-}"

REMNAWAVE_API_URL="${REMNAWAVE_API_URL:-}"
REMNAWAVE_API_KEY="${REMNAWAVE_API_KEY:-}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

# SMTP Configuration
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
SMTP_FROM_NAME="${SMTP_FROM_NAME:-Bedolaga Cabinet}"
SMTP_FROM_EMAIL="${SMTP_FROM_EMAIL:-}"
SMTP_USE_TLS="${SMTP_USE_TLS:-true}"

PRICE_30_DAYS="${PRICE_30_DAYS:-1000}"
PRICE_90_DAYS="${PRICE_90_DAYS:-36900}"
PRICE_180_DAYS="${PRICE_180_DAYS:-69900}"

CRYPTOBOT_API_TOKEN="${CRYPTOBOT_API_TOKEN:-}"
YOOKASSA_SHOP_ID="${YOOKASSA_SHOP_ID:-}"
YOOKASSA_SECRET_KEY="${YOOKASSA_SECRET_KEY:-}"

VITE_APP_NAME="${VITE_APP_NAME:-Cabinet}"
VITE_APP_LOGO="${VITE_APP_LOGO:-V}"
BOT_API_PORT="${BOT_API_PORT:-8080}"
CABINET_DEPLOY_MODE="${CABINET_DEPLOY_MODE:-image}" # image|source|auto

SUDO=""

header() {
  echo -e "${BLUE}====================================================${NC}"
  echo -e "${BLUE}      Установщик Bedolaga v${SCRIPT_VERSION}${NC}"
  echo -e "${BLUE}      (Bot + Cabinet для Remnawave)${NC}"
  echo -e "${BLUE}====================================================${NC}"
}
log_i() { echo -e "${BLUE}[ИНФО]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_w() { echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $*"; }
log_e() { echo -e "${RED}[ОШИБКА]${NC} $*"; }

on_error() {
  local line="$1"
  log_e "Ошибка в установщике на строке ${line}."
}
trap 'on_error $LINENO' ERR

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || {
    log_e "Этот установщик поддерживает только Linux."
    exit 1
  }
}

setup_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=""
  elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    log_e "Запустите от имени root или установите sudo."
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log_e "Отсутствует необходимая команда: $1"
    exit 1
  }
}

is_true() {
  [[ "${1,,}" =~ ^(1|true|yes|y)$ ]]
}

show_menu() {
  local choice=""
  echo
  echo "Выберите действие:"
  echo "  1) Установить/Обновить Бот + Кабинет (рекомендуется)"
  echo "  2) Установить/Обновить только Бот"
  echo "  3) Установить/Обновить только Кабинет"
  echo "  4) Только настройка Nginx/SSL (для готовых файлов)"
  echo "  5) Удалить только Бот"
  echo "  6) Удалить только Кабинет"
  echo "  7) Полное удаление (Бот + Кабинет)"
  echo "  8) Выход"
  if [[ -t 0 ]]; then
    read -r -p "Введите выбор [1-8]: " choice
  else
    read -r -p "Введите выбор [1-8]: " choice </dev/tty
  fi
  case "$choice" in
    1) INSTALL_BOT="true"; INSTALL_CABINET="true"; CONFIGURE_NGINX="true" ;;
    2) INSTALL_BOT="true"; INSTALL_CABINET="false" ;;
    3) INSTALL_BOT="false"; INSTALL_CABINET="true"; CONFIGURE_NGINX="true" ;;
    4) INSTALL_BOT="false"; INSTALL_CABINET="false"; CONFIGURE_NGINX="true" ;;
    5) ACTION="remove_bot" ;;
    6) ACTION="remove_cabinet" ;;
    7) ACTION="remove_all" ;;
    8) log_i "Выход."; exit 0 ;;
    *) log_w "Неверный выбор, используем вариант 1."; INSTALL_BOT="true"; INSTALL_CABINET="true"; CONFIGURE_NGINX="true" ;;
  esac
}

ask() {
  local var_name="$1"
  local prompt="$2"
  local default="${3:-${!var_name}}"
  local value

  if is_true "$NON_INTERACTIVE"; then
    if [[ -n "${!var_name}" ]]; then
      return 0
    fi
    if [[ -n "$default" ]]; then
      printf -v "$var_name" '%s' "$default"
      return 0
    fi
    log_e "Отсутствует обязательная переменная в неинтерактивном режиме: $var_name"
    exit 1
  fi

  local p_msg="$prompt"
  [[ -n "$default" ]] && p_msg="$prompt [$default]"

  if [[ -t 0 ]]; then
    read -r -p "$p_msg: " value
  elif [[ -r /dev/tty ]]; then
    read -r -p "$p_msg: " value </dev/tty
  else
    log_e "Интерактивный ввод недоступен. Используйте NON_INTERACTIVE=true."
    exit 1
  fi

  value="${value:-$default}"
  printf -v "$var_name" '%s' "$value"
}

ask_secret() {
  local var_name="$1"
  local prompt="$2"
  local value

  if [[ -n "${!var_name}" ]]; then
    return 0
  fi
  if is_true "$NON_INTERACTIVE"; then
    log_e "Отсутствует секретная переменная в неинтерактивном режиме: $var_name"
    exit 1
  fi

  if [[ -t 0 ]]; then
    read -r -s -p "$prompt: " value
  elif [[ -r /dev/tty ]]; then
    read -r -s -p "$prompt: " value </dev/tty
  else
    log_e "Интерактивный ввод недоступен."
    exit 1
  fi
  echo
  printf -v "$var_name" '%s' "$value"
}

validate_bot_token() {
  local token="$1"
  if [[ ! "$token" =~ ^[0-9]{8,12}:[a-zA-Z0-9_-]{35}$ ]]; then
    log_w "Внимание: Формат BOT_TOKEN выглядит необычно. Должно быть что-то вроде 12345678:ABCDEF..."
    return 1
  fi
  return 0
}

validate_admin_ids() {
  local ids="$1"
  if [[ ! "$ids" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    log_e "Ошибка: ADMIN_IDS должны быть числами через запятую (например: 12345678,98765432)"
    return 1
  fi
  return 0
}

validate_url() {
  local url="$1"
  if [[ ! "$url" =~ ^https?:// ]]; then
    log_e "Ошибка: URL должен начинаться с http:// или https://"
    return 1
  fi
  return 0
}

auto_public_ip() {
  curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null || true
}

resolve_ipv4() {
  local host="$1"
  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | head -n1
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2}' | tail -n1
  else
    echo ""
  fi
}

normalize_origin() {
  local v="$1"
  if [[ -z "$v" ]]; then
    echo ""
  elif [[ "$v" =~ ^https?:// ]]; then
    echo "${v%/}"
  else
    # For domains/IPs, we allow both http and https for CORS safety
    echo "https://${v%/},http://${v%/}"
  fi
}

apt_update() {
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "$@"
}

ensure_packages() {
  log_i "Установка системных зависимостей..."
  apt_update
  apt_install \
    ca-certificates curl wget git jq openssl nginx certbot python3-certbot-nginx ufw
  log_ok "Зависимости установлены."
}

ensure_swap() {
  local ram_kb
  ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  if [[ "$ram_kb" -lt 1900000 ]]; then
    log_w "Обнаружено мало ОЗУ ($((ram_kb / 1024)) MB)."
    if [[ -f /swapfile ]]; then
      log_i "Swap-файл уже существует."
      return 0
    fi
    
    if is_true "$NON_INTERACTIVE"; then
      log_i "Автоматическое создание 2GB swap..."
    else
      local answer=""
      read -r -p "Создать 2GB swap-файл для стабильной сборки? (y/n): " answer </dev/tty
      [[ "$answer" =~ ^(y|Y|yes|YES)$ ]] || return 0
    fi
    
    log_i "Создание swap..."
    $SUDO fallocate -l 2G /swapfile
    $SUDO chmod 600 /swapfile
    $SUDO mkswap /swapfile
    $SUDO swapon /swapfile
    echo '/swapfile none swap sw 0 0' | $SUDO tee -a /etc/fstab
    log_ok "Swap-файл создан."
  fi
}

setup_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then return 0; fi
  
  if is_true "$NON_INTERACTIVE"; then return 0; fi

  local answer=""
  echo -e "\n${BLUE}--- Безопасность ---${NC}"
  read -r -p "Настроить фаервол UFW? (разрешит SSH, 80, 443) (y/n): " answer </dev/tty
  if [[ "$answer" =~ ^(y|Y|yes|YES)$ ]]; then
    log_i "Настройка фаервола..."
    $SUDO ufw allow 22/tcp
    $SUDO ufw allow 80/tcp
    $SUDO ufw allow 443/tcp
    $SUDO ufw --force enable
    log_ok "Фаервол включен."
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_i "Установка Docker..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi
  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    apt_install docker-compose-plugin || true
  fi
  docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 || {
    log_e "docker compose недоступен."
    exit 1
  }
  if [[ -n "$SUDO" ]]; then
    $SUDO usermod -aG docker "$USER" 2>/dev/null || true
  fi
  log_ok "Docker готов."
}

compose_file() {
  local dir="$1"
  local f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [[ -f "$dir/$f" ]] && { echo "$dir/$f"; return 0; }
  done
  return 1
}

compose() {
  local dir="$1"
  shift
  local f
  f="$(compose_file "$dir" || true)"
  (
    cd "$dir"
    if docker compose version >/dev/null 2>&1; then
      if [[ -n "$f" ]]; then
        docker compose -f "$f" "$@"
      else
        docker compose "$@"
      fi
    else
      if [[ -n "$f" ]]; then
        docker-compose -f "$f" "$@"
      else
        docker-compose "$@"
      fi
    fi
  )
}

clone_or_update() {
  local repo="$1"
  local dir="$2"
  local title="$3"
  mkdir -p "$dir"
  if [[ -d "$dir/.git" ]]; then
    log_i "$title: updating repository..."
    git -C "$dir" fetch --all --prune
    git -C "$dir" pull --ff-only
  else
    log_i "$title: cloning repository..."
    rm -rf "$dir"
    git clone "$repo" "$dir"
  fi
}

ensure_env() {
  local dir="$1"
  if [[ ! -f "$dir/.env" ]]; then
    if [[ -f "$dir/.env.example" ]]; then
      cp "$dir/.env.example" "$dir/.env"
    else
      : > "$dir/.env"
    fi
  fi
}

env_set() {
  local file="$1" key="$2" val="$3" esc
  esc="$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')"
  if grep -q "^${key}=" "$file"; then
    sed -i "s/^${key}=.*/${key}=${esc}/" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

env_set_if_missing() {
  local file="$1" key="$2" val="$3"
  grep -q "^${key}=" "$file" || printf '%s=%s\n' "$key" "$val" >> "$file"
}

check_remnawave() {
  local url="$1" key="$2" code="" ep
  log_i "Проверка доступности Remnawave API..."
  
  # Remove trailing slash if any
  url="${url%/}"

  for ep in "$url/health" "$url/api/health" "$url"; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
      -H "Authorization: Bearer ${key}" \
      -H "X-API-KEY: ${key}" "$ep" || true)"
    [[ "$code" =~ ^2[0-9][0-9]$ || "$code" == "401" || "$code" == "403" ]] && {
      log_ok "Remnawave ответил по адресу ${ep} (код: ${code})."
      return 0
    }
  done
  
  log_w "Проверка Remnawave не удалась (код: ${code:-n/a})."
  log_w "Это может означать неверный URL, ключ API или панель выключена."
  
  if ! is_true "$NON_INTERACTIVE"; then
    local answer=""
    read -r -p "Все равно продолжить установку? (y/n): " answer </dev/tty
    if [[ ! "$answer" =~ ^(y|Y|yes|YES)$ ]]; then
      log_e "Установка прервана пользователем."
      exit 1
    fi
  fi
}

configure_bot_env() {
  local env_file="$1" cabinet_origin="$2"

  log_i "Configuring .env for Bot..."
  env_set "$env_file" "BOT_TOKEN" "$BOT_TOKEN"
  env_set "$env_file" "ADMIN_IDS" "$ADMIN_IDS"
  env_set "$env_file" "SUPPORT_USERNAME" "$SUPPORT_USERNAME"
  env_set "$env_file" "REMNAWAVE_API_URL" "$REMNAWAVE_API_URL"
  env_set "$env_file" "REMNAWAVE_API_KEY" "$REMNAWAVE_API_KEY"
  env_set "$env_file" "REMNAWAVE_AUTH_TYPE" "api_key"
  env_set "$env_file" "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
  env_set_if_missing "$env_file" "POSTGRES_HOST" "db"
  env_set_if_missing "$env_file" "POSTGRES_PORT" "5432"
  env_set_if_missing "$env_file" "POSTGRES_USER" "remnawave_user"
  env_set_if_missing "$env_file" "POSTGRES_DB" "remnawave_bot"
  env_set "$env_file" "SALES_MODE" "tariffs"
  env_set "$env_file" "PRICE_30_DAYS" "$PRICE_30_DAYS"
  env_set "$env_file" "PRICE_90_DAYS" "$PRICE_90_DAYS"
  env_set "$env_file" "PRICE_180_DAYS" "$PRICE_180_DAYS"

  # SMTP settings
  env_set "$env_file" "SMTP_HOST" "$SMTP_HOST"
  env_set "$env_file" "SMTP_PORT" "$SMTP_PORT"
  env_set "$env_file" "SMTP_USER" "$SMTP_USER"
  env_set "$env_file" "SMTP_PASSWORD" "$SMTP_PASSWORD"
  env_set "$env_file" "SMTP_FROM_NAME" "$SMTP_FROM_NAME"
  env_set "$env_file" "SMTP_FROM_EMAIL" "$SMTP_FROM_EMAIL"
  env_set "$env_file" "SMTP_USE_TLS" "$SMTP_USE_TLS"

  # Payment settings
  env_set "$env_file" "CRYPTOBOT_ENABLED" "$([[ -n "$CRYPTOBOT_API_TOKEN" ]] && echo "true" || echo "false")"
  env_set "$env_file" "CRYPTOBOT_API_TOKEN" "$CRYPTOBOT_API_TOKEN"
  env_set "$env_file" "YOOKASSA_ENABLED" "$([[ -n "$YOOKASSA_SHOP_ID" ]] && echo "true" || echo "false")"
  env_set "$env_file" "YOOKASSA_SHOP_ID" "$YOOKASSA_SHOP_ID"
  env_set "$env_file" "YOOKASSA_SECRET_KEY" "$YOOKASSA_SECRET_KEY"

  # API & Cabinet integration
  env_set "$env_file" "WEB_API_ENABLED" "true"
  env_set "$env_file" "WEB_API_PORT" "$BOT_API_PORT"
  env_set "$env_file" "CABINET_ENABLED" "true"
  env_set_if_missing "$env_file" "CABINET_JWT_SECRET" "$(openssl rand -hex 32)"

  if [[ -n "$cabinet_origin" ]]; then
    env_set "$env_file" "CABINET_ALLOWED_ORIGINS" "$cabinet_origin"
    env_set "$env_file" "WEB_API_ALLOWED_ORIGINS" "$cabinet_origin"
  fi
  if [[ -n "$TELEGRAM_BOT_USERNAME" ]]; then
    env_set "$env_file" "CABINET_TELEGRAM_BOT_USERNAME" "$TELEGRAM_BOT_USERNAME"
  fi

  # Branding (synced with Cabinet if possible)
  env_set "$env_file" "APP_NAME" "$VITE_APP_NAME"

  # Defaults
  env_set "$env_file" "TZ" "Europe/Moscow"
  env_set "$env_file" "DEFAULT_LANGUAGE" "ru"
  env_set "$env_file" "ENABLE_LOGO_MODE" "true"
  env_set "$env_file" "LOG_LEVEL" "INFO"
  env_set "$env_file" "DEBUG" "false"

  # Fix common Pydantic validation errors for integer fields (ensure they are 0 if invalid/placeholder)
  # This list covers fields that must be integers in the bot's Pydantic models
  local int_fields=(
    "ADMIN_REPORTS_TOPIC_ID" 
    "LOG_ROTATION_TOPIC_ID" 
    "MULENPAY_SHOP_ID" 
    "FREEKASSA_SHOP_ID" 
    "FREEKASSA_PAYMENT_SYSTEM_ID" 
    "KASSA_AI_SHOP_ID" 
    "SEVERPAY_MID"
    "LOG_ROTATION_DAYS"
    "BACKUP_ROTATION_DAYS"
  )
  for key in "${int_fields[@]}"; do
    local current_val
    # Get current value, removing quotes if any
    current_val=$(grep "^${key}=" "$env_file" | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    # If empty or not a pure number, set to 0
    if [[ -z "$current_val" || ! "$current_val" =~ ^[0-9]+$ ]]; then
      env_set "$env_file" "$key" "0"
    fi
  done
}

install_bot() {
  log_i "Installing Bedolaga Bot..."
  clone_or_update "$BOT_REPO" "$BOT_DIR" "Bedolaga Bot"
  ensure_env "$BOT_DIR"
  configure_bot_env "$BOT_DIR/.env" "$(normalize_origin "$CABINET_DOMAIN")"

  mkdir -p "$BOT_DIR/data/backups" "$BOT_DIR/data/referral_qr" "$BOT_DIR/logs" "$BOT_DIR/locales"
  $SUDO chown -R 1000:1000 "$BOT_DIR/data" "$BOT_DIR/logs" "$BOT_DIR/locales" 2>/dev/null || true

  compose "$BOT_DIR" down -t 10 || true
  compose "$BOT_DIR" up -d --build
  fix_bot_db_auth_if_needed
  compose "$BOT_DIR" ps || true
  log_ok "Bedolaga Bot deployed."
}

fix_bot_db_auth_if_needed() {
  log_i "Checking bot startup status..."
  sleep 6
  local bot_logs
  bot_logs="$(compose "$BOT_DIR" logs --tail 200 bot 2>/dev/null || true)"

  if [[ "$bot_logs" == *"InvalidPasswordError"* || "$bot_logs" == *"password authentication failed for user"* ]]; then
    log_w "Detected PostgreSQL password mismatch (old DB volume + new password)."
    log_w "Fix requires DB volume reset for bot stack."
    if is_true "$NON_INTERACTIVE"; then
      log_w "NON_INTERACTIVE mode: skipping destructive auto-fix."
      log_w "Run manually if needed: cd $BOT_DIR && docker compose down -v && docker compose up -d --build"
      return 0
    fi

    local answer=""
    if [[ -t 0 ]]; then
      read -r -p "Reset bot DB volume now? This deletes bot database data. (type YES): " answer
    else
      read -r -p "Reset bot DB volume now? This deletes bot database data. (type YES): " answer </dev/tty
    fi

    if [[ "$answer" == "YES" ]]; then
      log_i "Resetting bot stack volumes and restarting..."
      compose "$BOT_DIR" down -v --remove-orphans || true
      compose "$BOT_DIR" up -d --build
      sleep 6
      log_ok "Bot stack restarted with fresh DB volume."
    else
      log_w "Skipped DB volume reset by user."
    fi
  fi
}

build_cabinet_static() {
  local mode="${CABINET_DEPLOY_MODE,,}"
  if [[ "$mode" != "image" && "$mode" != "source" && "$mode" != "auto" ]]; then
    log_w "Unknown CABINET_DEPLOY_MODE='${CABINET_DEPLOY_MODE}', using 'image'."
    mode="image"
  fi
  if [[ "$mode" == "auto" || "$mode" == "image" ]]; then
    if build_cabinet_static_from_image; then
      return 0
    fi
    if [[ "$mode" == "image" ]]; then
      log_e "Cabinet image mode failed. Set CABINET_DEPLOY_MODE=source to force source build."
      exit 1
    fi
    log_w "Falling back to source build due to image failure."
  fi
  build_cabinet_static_from_source
}

build_cabinet_static_from_image() {
  local image="ghcr.io/bedolaga-dev/bedolaga-cabinet:latest"
  local temp_name="tmp_bedolaga_cabinet_$$"
  log_i "Using prebuilt cabinet image (low RAM mode): $image"
  if ! $SUDO docker pull "$image"; then
    log_w "Cannot pull image from GHCR."
    return 1
  fi
  $SUDO docker create --name "$temp_name" "$image" >/dev/null
  $SUDO mkdir -p "$STATIC_ROOT"
  $SUDO rm -rf "${STATIC_ROOT:?}/"*
  $SUDO docker cp "${temp_name}:/usr/share/nginx/html/." "$STATIC_ROOT/"
  $SUDO docker rm -f "$temp_name" >/dev/null 2>&1 || true
  log_ok "Cabinet static files copied from prebuilt image."
  return 0
}

build_cabinet_static_from_source() {
  local env_file="$CABINET_DIR/.env"
  ensure_env "$CABINET_DIR"
  
  log_i "Configuring .env for Cabinet build..."
  env_set "$env_file" "VITE_API_URL" "/api"
  env_set "$env_file" "VITE_TELEGRAM_BOT_USERNAME" "$TELEGRAM_BOT_USERNAME"
  env_set "$env_file" "VITE_APP_NAME" "$VITE_APP_NAME"
  env_set "$env_file" "VITE_APP_LOGO" "$VITE_APP_LOGO"

  log_i "Building Bedolaga Cabinet static files from source..."
  log_w "This may take several minutes and requires at least 2GB RAM."
  
  # Pass env vars to docker compose build if needed, though .env should be picked up
  compose "$CABINET_DIR" build cabinet-frontend
  compose "$CABINET_DIR" create cabinet-frontend
  
  local cid
  cid="$(compose "$CABINET_DIR" ps -q cabinet-frontend | tr -d '\r\n')"
  [[ -n "$cid" ]] || {
    log_e "Cannot detect cabinet-frontend container."
    exit 1
  }
  
  $SUDO mkdir -p "$STATIC_ROOT"
  $SUDO rm -rf "${STATIC_ROOT:?}/"*
  $SUDO docker cp "${cid}:/usr/share/nginx/html/." "$STATIC_ROOT/"
  compose "$CABINET_DIR" rm -sf cabinet-frontend || true
  
  $SUDO chown -R www-data:www-data "$STATIC_ROOT" || true
  log_ok "Cabinet static files prepared at $STATIC_ROOT."
}

write_nginx_conf() {
  local conf="/etc/nginx/sites-available/bedolaga-cabinet.conf"
  local enabled="/etc/nginx/sites-enabled/bedolaga-cabinet.conf"
  local upstream="http://127.0.0.1:${BOT_API_PORT}"

  log_i "Configuring Nginx for ${CABINET_DOMAIN}..."
  $SUDO mkdir -p "$STATIC_ROOT"
  $SUDO chown -R www-data:www-data "$STATIC_ROOT" || true
  $SUDO chmod -R 755 "$STATIC_ROOT" || true

  $SUDO tee "$conf" >/dev/null <<EOF
server {
    listen 80;
    server_name ${CABINET_DOMAIN};

    root ${STATIC_ROOT};
    index index.html;

    client_max_body_size 10M;

    location /api/ {
        rewrite ^/api/(.*) /\$1 break;
        proxy_pass ${upstream};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
    }

    location ~* \.(?:js|css|woff2?|ttf|ico|png|jpe?g|svg|webp|gif)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location / {
        try_files \$uri /index.html;
        add_header Cache-Control "no-cache, must-revalidate";
    }
}
EOF

  [[ -L "$enabled" ]] || $SUDO ln -s "$conf" "$enabled"
  $SUDO rm -f /etc/nginx/sites-enabled/default
  
  if $SUDO nginx -t; then
    $SUDO systemctl enable --now nginx
    $SUDO systemctl reload nginx
    log_ok "Nginx reverse proxy configured for ${CABINET_DOMAIN}."
  else
    log_e "Nginx configuration test failed. Please check $conf"
    exit 1
  fi
}

setup_ssl() {
  if ! is_true "$ENABLE_SSL"; then
    log_w "SSL отключен в конфигурации (ENABLE_SSL=false)."
    return 0
  fi
  if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
    log_w "LETSENCRYPT_EMAIL не заполнен. SSL пропущен."
    return 0
  fi
  if [[ "$CABINET_DOMAIN" == "localhost" || "$CABINET_DOMAIN" == "127.0.0.1" ]]; then
    log_w "Пропуск SSL для localhost."
    return 0
  fi
  log_i "Запрос сертификата Let's Encrypt..."
  if $SUDO certbot --nginx -d "$CABINET_DOMAIN" --non-interactive --agree-tos -m "$LETSENCRYPT_EMAIL" --redirect; then
    log_ok "SSL включен: https://${CABINET_DOMAIN}"
  else
    log_w "Ошибка Certbot. Проверьте DNS запись A и открыты ли порты 80/443."
  fi
}

validate_dns_for_domain() {
  local public_ip="$1"
  local dns_ip=""
  local host="${CABINET_DOMAIN}"

  [[ -n "$host" ]] || return 0
  [[ "$host" == "localhost" || "$host" == "127.0.0.1" ]] && return 0
  [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 0

  dns_ip="$(resolve_ipv4 "$host" || true)"
  if [[ -z "$dns_ip" ]]; then
    log_w "Не удалось разрешить DNS запись A для ${host}."
    return 0
  fi
  if [[ -n "$public_ip" && "$dns_ip" != "$public_ip" ]]; then
    log_w "Несоответствие DNS A: ${host} -> ${dns_ip}, IP сервера ${public_ip}."
    log_w "SSL может не настроиться, пока DNS не указывает на этот сервер."
  else
    log_ok "DNS запись A корректна: ${host} -> ${dns_ip}"
  fi
}

install_cabinet() {
  log_i "Установка Кабинета Bedolaga..."
  clone_or_update "$CABINET_REPO" "$CABINET_DIR" "Bedolaga Cabinet"
  build_cabinet_static
  if is_true "$CONFIGURE_NGINX"; then
    write_nginx_conf
    setup_ssl
  else
    log_w "Настройка Nginx пропущена (CONFIGURE_NGINX=false)."
  fi
  log_ok "Кабинет Bedolaga развернут."
}

confirm_destructive() {
  local msg="$1"
  local answer=""
  if is_true "$NON_INTERACTIVE"; then
    return 0
  fi
  if [[ -t 0 ]]; then
    read -r -p "$msg (введите YES для подтверждения): " answer
  else
    read -r -p "$msg (введите YES для подтверждения): " answer </dev/tty
  fi
  [[ "$answer" == "YES" ]] || {
    log_w "Отменено."
    exit 0
  }
}

remove_bot() {
  confirm_destructive "Это удалит контейнеры, тома и файлы Бота Bedolaga. Продолжить?"
  if [[ -d "$BOT_DIR" ]]; then
    compose "$BOT_DIR" down -v --remove-orphans || true
  fi
  $SUDO rm -rf "$BOT_DIR"
  log_ok "Бот удален."
}

remove_cabinet() {
  confirm_destructive "Это удалит файлы кабинета и конфигурацию nginx. Продолжить?"
  if [[ -d "$CABINET_DIR" ]]; then
    compose "$CABINET_DIR" down -v --remove-orphans || true
  fi
  $SUDO rm -rf "$CABINET_DIR"
  $SUDO rm -rf "$STATIC_ROOT"
  $SUDO rm -f /etc/nginx/sites-enabled/bedolaga-cabinet.conf
  $SUDO rm -f /etc/nginx/sites-available/bedolaga-cabinet.conf
  $SUDO nginx -t >/dev/null 2>&1 && $SUDO systemctl reload nginx || true
  log_ok "Кабинет удален."
}

handle_remove_action() {
  case "${ACTION:-}" in
    remove_bot)
      remove_bot
      exit 0
      ;;
    remove_cabinet)
      remove_cabinet
      exit 0
      ;;
    remove_all)
      confirm_destructive "Это полностью удалит И бот, И кабинет. Продолжить?"
      remove_bot
      remove_cabinet
      exit 0
      ;;
  esac
}

collect_inputs() {
  local detected_ip
  detected_ip="$(auto_public_ip)"

  if ! is_true "$NON_INTERACTIVE"; then
    show_menu
  fi
  handle_remove_action

  # 1. Base Domain / Nginx setup
  echo -e "\n${BLUE}--- Общая конфигурация ---${NC}"
  if [[ -z "$CABINET_DOMAIN" ]]; then
    ask CABINET_DOMAIN "Домен или IP сервера для кабинета (например: bedolaga.com или 1.2.3.4)" "${detected_ip:-localhost}"
  fi

  if ! is_true "$INSTALL_BOT" && ! is_true "$INSTALL_CABINET" && is_true "$CONFIGURE_NGINX"; then
    if is_true "$ENABLE_SSL" && [[ -z "$LETSENCRYPT_EMAIL" ]]; then
      ask LETSENCRYPT_EMAIL "Email для Let's Encrypt SSL (для уведомлений)" ""
    fi
    validate_dns_for_domain "$detected_ip"
    return 0
  fi

  # 2. Bot Configuration
  if is_true "$INSTALL_BOT"; then
    echo -e "\n${BLUE}--- Конфигурация Бота ---${NC}"
    while true; do
      ask BOT_TOKEN "BOT_TOKEN от @BotFather"
      validate_bot_token "$BOT_TOKEN" && break || {
        if ! is_true "$NON_INTERACTIVE"; then BOT_TOKEN=""; continue; else break; fi
      }
    done

    while true; do
      ask ADMIN_IDS "ADMIN_IDS (ID администраторов через запятую)"
      validate_admin_ids "$ADMIN_IDS" && break || {
        if ! is_true "$NON_INTERACTIVE"; then ADMIN_IDS=""; continue; else break; fi
      }
    done

    ask TELEGRAM_BOT_USERNAME "Username бота без @" ""

    while true; do
      ask REMNAWAVE_API_URL "REMNAWAVE_API_URL (например: https://panel.example.com)" ""
      validate_url "$REMNAWAVE_API_URL" && break || {
        if ! is_true "$NON_INTERACTIVE"; then REMNAWAVE_API_URL=""; continue; else break; fi
      }
    done

    ask_secret REMNAWAVE_API_KEY "REMNAWAVE_API_KEY"
    ask_secret POSTGRES_PASSWORD "POSTGRES_PASSWORD (пароль для базы данных бота)"

    echo -e "\n${BLUE}--- Настройка Почты (SMTP) ---${NC}"
    echo -e "${YELLOW}Необходимо для регистрации пользователей в кабинете.${NC}"
    ask SMTP_HOST "SMTP Хост (например: smtp.yandex.ru или smtp.gmail.com)" "$SMTP_HOST"
    if [[ -n "$SMTP_HOST" ]]; then
      ask SMTP_PORT "SMTP Порт (обычно 465 или 587)" "$SMTP_PORT"
      ask SMTP_USER "SMTP Пользователь (обычно ваш email)" "$SMTP_USER"
      ask_secret SMTP_PASSWORD "SMTP Пароль (для Yandex/Gmail нужен 'Пароль приложения')"
      ask SMTP_FROM_EMAIL "Email отправителя (тот же что и пользователь)" "${SMTP_USER}"
      ask SMTP_FROM_NAME "Имя отправителя" "$SMTP_FROM_NAME"
      ask SMTP_USE_TLS "Использовать TLS/SSL? (true/false)" "$SMTP_USE_TLS"
    else
      log_w "SMTP не настроен. Регистрация в кабинете может не работать!"
    fi

    echo -e "\n${BLUE}--- Поддержка и Цены ---${NC}"
    ask SUPPORT_USERNAME "Username поддержки в Telegram (например: @support_bot)" "$SUPPORT_USERNAME"
    ask PRICE_30_DAYS "Цена за 30 дней (в копейках, например: 10000 = 100 руб)" "$PRICE_30_DAYS"
    ask PRICE_90_DAYS "Цена за 90 дней (в копейках)" "$PRICE_90_DAYS"
    ask PRICE_180_DAYS "Цена за 180 дней (в копейках)" "$PRICE_180_DAYS"

    echo -e "\n${BLUE}--- Платежные системы (Опционально) ---${NC}"
    echo -e "${YELLOW}Подсказка: Можно пропустить сейчас и добавить позже в .env${NC}"
    ask CRYPTOBOT_API_TOKEN "CryptoBot API Token (нажмите ENTER чтобы пропустить)" ""
    ask YOOKASSA_SHOP_ID "YooKassa Shop ID (нажмите ENTER чтобы пропустить)" ""
    if [[ -n "$YOOKASSA_SHOP_ID" ]]; then
      ask_secret YOOKASSA_SECRET_KEY "YooKassa Secret Key"
    fi

    ask BOT_API_PORT "Внутренний порт API бота (для связи с кабинетом)" "$BOT_API_PORT"
  fi

  # 3. Cabinet Configuration
  if is_true "$INSTALL_CABINET" || is_true "$CONFIGURE_NGINX"; then
    echo -e "\n${BLUE}--- Конфигурация Кабинета ---${NC}"
    
    if is_true "$INSTALL_CABINET"; then
      ask VITE_APP_NAME "Название приложения в кабинете" "$VITE_APP_NAME"
      ask VITE_APP_LOGO "Текст логотипа (обычно 1 буква)" "$VITE_APP_LOGO"
      
      if [[ -z "$TELEGRAM_BOT_USERNAME" ]]; then
        ask TELEGRAM_BOT_USERNAME "Username бота без @ (для входа в кабинет)" ""
      fi

      if ! is_true "$NON_INTERACTIVE"; then
        echo -e "\nВыберите способ развертывания кабинета:"
        echo "  image)  Использовать готовый Docker образ (рекомендуется, быстро)"
        echo "  source) Собрать из исходников (нужно 2ГБ+ ОЗУ, очень медленно)"
        ask CABINET_DEPLOY_MODE "Режим" "$CABINET_DEPLOY_MODE"
      fi
    fi

    if is_true "$ENABLE_SSL" && [[ -z "$LETSENCRYPT_EMAIL" ]] && ! is_true "$NON_INTERACTIVE"; then
      echo -e ""
      ask LETSENCRYPT_EMAIL "Email для Let's Encrypt SSL (для уведомлений)" ""
    fi
  fi

  validate_dns_for_domain "$detected_ip"
}

print_summary() {
  echo
  log_ok "Установка завершена."
  
  if is_true "$INSTALL_BOT" || is_true "$INSTALL_CABINET"; then
    echo -e "\n${BLUE}--- Проверка состояния ---${NC}"
    if is_true "$INSTALL_BOT"; then
      if curl -s "http://127.0.0.1:${BOT_API_PORT}/health" >/dev/null 2>&1 || curl -s "http://127.0.0.1:${BOT_API_PORT}" >/dev/null 2>&1; then
        log_ok "API Бота: Запущено"
      else
        log_w "API Бота: Не отвечает (возможно, запуск еще идет)"
      fi
    fi
    if [[ -n "$CABINET_DOMAIN" ]]; then
      if curl -s -I "http://${CABINET_DOMAIN}" | grep -q "200 OK\|301 Moved\|302 Found" >/dev/null 2>&1; then
        log_ok "URL Кабинета: Доступен"
      else
        log_w "URL Кабинета: Недоступен с этого сервера (проверьте DNS/Фаервол)"
      fi
    fi
  fi

  echo -e "\n${BLUE}--- Пути и Ссылки ---${NC}"
  echo "Путь бота:      $BOT_DIR"
  echo "Путь кабинета:  $CABINET_DIR"
  echo "Статика:        $STATIC_ROOT"
  echo "URL Кабинета:   http://${CABINET_DOMAIN}"
  if is_true "$ENABLE_SSL" && [[ -n "$LETSENCRYPT_EMAIL" ]] && [[ "$CABINET_DOMAIN" != "localhost" && "$CABINET_DOMAIN" != "127.0.0.1" ]]; then
    echo "URL Кабинета:   https://${CABINET_DOMAIN}"
  fi
  echo
  echo "Полезные команды:"
  echo "  Логи бота: cd $BOT_DIR && docker compose logs -f --tail 100"
  echo "  Проверка Nginx: sudo nginx -t && sudo systemctl reload nginx"
  echo
  echo "Как обновить Bedolaga:"
  echo "  Бот:     cd $BOT_DIR && git pull && docker compose up -d --build"
  echo "  Кабинет: Запустите этот скрипт снова и выберите 'Установить только Кабинет'"
  echo
  echo "Как добавить платежи позже:"
  echo "  1. Редактировать файл: nano $BOT_DIR/.env"
  echo "  2. Перезапустить бота: cd $BOT_DIR && docker compose up -d"
  echo
  echo "Авторизация в кабинете:"
  echo "  Логин/пароль по умолчанию не используются."
  echo "  Вход выполняется через Telegram в веб-интерфейсе."
  echo "  Доступ администратора управляется через ADMIN_IDS в .env бота."
}

main() {
  header
  require_linux
  setup_sudo

  need_cmd curl

  ensure_packages
  ensure_swap
  need_cmd git
  ensure_docker
  
  collect_inputs
  setup_firewall
  
  if is_true "$INSTALL_BOT"; then
    check_remnawave "$REMNAWAVE_API_URL" "$REMNAWAVE_API_KEY"
  fi

  if is_true "$INSTALL_BOT"; then
    install_bot
  else
    log_w "INSTALL_BOT=false, bot deployment skipped."
  fi

  if is_true "$INSTALL_CABINET"; then
    install_cabinet
  elif is_true "$CONFIGURE_NGINX"; then
    write_nginx_conf
    setup_ssl
  else
    log_w "INSTALL_CABINET=false, cabinet deployment skipped."
  fi

  print_summary
}

main "$@"
