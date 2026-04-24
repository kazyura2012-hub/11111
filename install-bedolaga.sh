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
  echo -e "${BLUE} Bedolaga Installer v${SCRIPT_VERSION}${NC}"
  echo -e "${BLUE}====================================================${NC}"
}
log_i() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_w() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_e() { echo -e "${RED}[ERROR]${NC} $*"; }

on_error() {
  local line="$1"
  log_e "Installer failed at line ${line}."
}
trap 'on_error $LINENO' ERR

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || {
    log_e "This installer supports Linux only."
    exit 1
  }
}

setup_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=""
  elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    log_e "Run as root or install sudo."
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log_e "Missing required command: $1"
    exit 1
  }
}

is_true() {
  [[ "${1,,}" =~ ^(1|true|yes|y)$ ]]
}

show_menu() {
  local choice=""
  echo
  echo "Select action:"
  echo "  1) Install/Update Bot + Cabinet (recommended)"
  echo "  2) Install/Update Bot only"
  echo "  3) Install/Update Cabinet only"
  echo "  4) Configure Nginx/SSL only (for existing cabinet static files)"
  echo "  5) Remove Bot only"
  echo "  6) Remove Cabinet only"
  echo "  7) Remove Bot + Cabinet"
  echo "  8) Exit"
  if [[ -t 0 ]]; then
    read -r -p "Enter choice [1-8]: " choice
  else
    read -r -p "Enter choice [1-8]: " choice </dev/tty
  fi
  case "$choice" in
    1) INSTALL_BOT="true"; INSTALL_CABINET="true"; CONFIGURE_NGINX="true" ;;
    2) INSTALL_BOT="true"; INSTALL_CABINET="false" ;;
    3) INSTALL_BOT="false"; INSTALL_CABINET="true"; CONFIGURE_NGINX="true" ;;
    4) INSTALL_BOT="false"; INSTALL_CABINET="false"; CONFIGURE_NGINX="true" ;;
    5) ACTION="remove_bot" ;;
    6) ACTION="remove_cabinet" ;;
    7) ACTION="remove_all" ;;
    8) log_i "Exit by user choice."; exit 0 ;;
    *) log_w "Invalid choice, using default: option 1."; INSTALL_BOT="true"; INSTALL_CABINET="true"; CONFIGURE_NGINX="true" ;;
  esac
}

ask() {
  local var_name="$1"
  local prompt="$2"
  local default="${3:-}"
  local current="${!var_name:-}"
  local value

  if [[ -n "$current" ]]; then
    return 0
  fi
  if is_true "$NON_INTERACTIVE"; then
    if [[ -n "$default" ]]; then
      printf -v "$var_name" '%s' "$default"
      return 0
    fi
    log_e "Required variable is missing in NON_INTERACTIVE mode: $var_name"
    exit 1
  fi

  if [[ -n "$default" ]]; then
    if [[ -t 0 ]]; then
      read -r -p "$prompt [$default]: " value
    elif [[ -r /dev/tty ]]; then
      read -r -p "$prompt [$default]: " value </dev/tty
    else
      log_e "No interactive TTY available. Set NON_INTERACTIVE=true and pass env vars."
      exit 1
    fi
    value="${value:-$default}"
  else
    if [[ -t 0 ]]; then
      read -r -p "$prompt: " value
    elif [[ -r /dev/tty ]]; then
      read -r -p "$prompt: " value </dev/tty
    else
      log_e "No interactive TTY available. Set NON_INTERACTIVE=true and pass env vars."
      exit 1
    fi
  fi
  printf -v "$var_name" '%s' "$value"
}

ask_secret() {
  local var_name="$1"
  local prompt="$2"
  local current="${!var_name:-}"
  local value

  if [[ -n "$current" ]]; then
    return 0
  fi
  if is_true "$NON_INTERACTIVE"; then
    log_e "Required secret variable is missing in NON_INTERACTIVE mode: $var_name"
    exit 1
  fi
  if [[ -t 0 ]]; then
    read -r -s -p "$prompt: " value
  elif [[ -r /dev/tty ]]; then
    read -r -s -p "$prompt: " value </dev/tty
  else
    log_e "No interactive TTY available. Set NON_INTERACTIVE=true and pass env vars."
    exit 1
  fi
  echo
  printf -v "$var_name" '%s' "$value"
}

validate_bot_token() {
  local token="$1"
  if [[ ! "$token" =~ ^[0-9]{8,12}:[a-zA-Z0-9_-]{35}$ ]]; then
    log_w "Warning: BOT_TOKEN format looks unusual. Should be like 12345678:ABCDEF..."
    return 1
  fi
  return 0
}

validate_admin_ids() {
  local ids="$1"
  if [[ ! "$ids" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    log_e "Error: ADMIN_IDS must be comma-separated numbers (e.g. 12345678,98765432)"
    return 1
  fi
  return 0
}

validate_url() {
  local url="$1"
  if [[ ! "$url" =~ ^https?:// ]]; then
    log_e "Error: URL must start with http:// or https://"
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
    echo "$v"
  else
    echo "https://$v"
  fi
}

apt_update() {
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "$@"
}

ensure_packages() {
  log_i "Installing system dependencies..."
  apt_update
  apt_install \
    ca-certificates curl wget git jq openssl nginx certbot python3-certbot-nginx ufw
  log_ok "Dependencies installed."
}

ensure_swap() {
  local ram_kb
  ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  if [[ "$ram_kb" -lt 1900000 ]]; then
    log_w "Detected low RAM ($((ram_kb / 1024)) MB)."
    if [[ -f /swapfile ]]; then
      log_i "Swap already exists."
      return 0
    fi
    
    if is_true "$NON_INTERACTIVE"; then
      log_i "Creating 2GB swap file automatically..."
    else
      local answer=""
      read -r -p "Create 2GB swap file to prevent build failures? (y/n): " answer </dev/tty
      [[ "$answer" =~ ^(y|Y|yes|YES)$ ]] || return 0
    fi
    
    log_i "Creating swap..."
    $SUDO fallocate -l 2G /swapfile
    $SUDO chmod 600 /swapfile
    $SUDO mkswap /swapfile
    $SUDO swapon /swapfile
    echo '/swapfile none swap sw 0 0' | $SUDO tee -a /etc/fstab
    log_ok "Swap file created."
  fi
}

setup_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then return 0; fi
  
  if is_true "$NON_INTERACTIVE"; then return 0; fi

  local answer=""
  echo -e "\n${BLUE}--- Security ---${NC}"
  read -r -p "Configure UFW firewall? (allows SSH, 80, 443) (y/n): " answer </dev/tty
  if [[ "$answer" =~ ^(y|Y|yes|YES)$ ]]; then
    log_i "Configuring firewall..."
    $SUDO ufw allow 22/tcp
    $SUDO ufw allow 80/tcp
    $SUDO ufw allow 443/tcp
    $SUDO ufw --force enable
    log_ok "Firewall enabled."
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_i "Installing Docker..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi
  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    apt_install docker-compose-plugin || true
  fi
  docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 || {
    log_e "docker compose is unavailable."
    exit 1
  }
  if [[ -n "$SUDO" ]]; then
    $SUDO usermod -aG docker "$USER" 2>/dev/null || true
  fi
  log_ok "Docker is ready."
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
  log_i "Checking Remnawave API availability..."
  
  # Remove trailing slash if any
  url="${url%/}"

  for ep in "$url/health" "$url/api/health" "$url"; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
      -H "Authorization: Bearer ${key}" \
      -H "X-API-KEY: ${key}" "$ep" || true)"
    [[ "$code" =~ ^2[0-9][0-9]$ || "$code" == "401" || "$code" == "403" ]] && {
      log_ok "Remnawave responded at ${ep} (${code})."
      return 0
    }
  done
  
  log_w "Remnawave check failed (last code: ${code:-n/a})."
  log_w "This might mean the URL is wrong, the API Key is invalid, or the panel is down."
  
  if ! is_true "$NON_INTERACTIVE"; then
    local answer=""
    read -r -p "Do you want to continue anyway? (y/n): " answer </dev/tty
    if [[ ! "$answer" =~ ^(y|Y|yes|YES)$ ]]; then
      log_e "Installation aborted by user."
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
  env_set "$env_file" "SALES_MODE" "tariffs"
  env_set "$env_file" "PRICE_30_DAYS" "$PRICE_30_DAYS"
  env_set "$env_file" "PRICE_90_DAYS" "$PRICE_90_DAYS"
  env_set "$env_file" "PRICE_180_DAYS" "$PRICE_180_DAYS"

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
  
  # Topic IDs (default 0 for disabling)
  env_set_if_missing "$env_file" "ADMIN_REPORTS_TOPIC_ID" "0"
  env_set_if_missing "$env_file" "LOG_ROTATION_TOPIC_ID" "0"
}

install_bot() {
  log_i "Installing Bedolaga Bot..."
  clone_or_update "$BOT_REPO" "$BOT_DIR" "Bedolaga Bot"
  ensure_env "$BOT_DIR"
  configure_bot_env "$BOT_DIR/.env" "$(normalize_origin "$CABINET_DOMAIN")"

  mkdir -p "$BOT_DIR/data/backups" "$BOT_DIR/logs" "$BOT_DIR/locales"
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
    log_w "SSL disabled by configuration (ENABLE_SSL=false)."
    return 0
  fi
  if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
    log_w "LETSENCRYPT_EMAIL is empty. SSL skipped."
    return 0
  fi
  if [[ "$CABINET_DOMAIN" == "localhost" || "$CABINET_DOMAIN" == "127.0.0.1" ]]; then
    log_w "SSL skipped for localhost."
    return 0
  fi
  log_i "Requesting Let's Encrypt certificate..."
  if $SUDO certbot --nginx -d "$CABINET_DOMAIN" --non-interactive --agree-tos -m "$LETSENCRYPT_EMAIL" --redirect; then
    log_ok "SSL enabled: https://${CABINET_DOMAIN}"
  else
    log_w "Certbot failed. Verify DNS A record and open ports 80/443."
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
    log_w "Cannot resolve DNS A record for ${host} yet."
    return 0
  fi
  if [[ -n "$public_ip" && "$dns_ip" != "$public_ip" ]]; then
    log_w "DNS A mismatch: ${host} -> ${dns_ip}, server public IP is ${public_ip}."
    log_w "SSL may fail until DNS points to this server."
  else
    log_ok "DNS A record looks good: ${host} -> ${dns_ip}"
  fi
}

install_cabinet() {
  log_i "Installing Bedolaga Cabinet..."
  clone_or_update "$CABINET_REPO" "$CABINET_DIR" "Bedolaga Cabinet"
  build_cabinet_static
  if is_true "$CONFIGURE_NGINX"; then
    write_nginx_conf
    setup_ssl
  else
    log_w "Nginx setup skipped (CONFIGURE_NGINX=false)."
  fi
  log_ok "Bedolaga Cabinet deployed."
}

confirm_destructive() {
  local msg="$1"
  local answer=""
  if is_true "$NON_INTERACTIVE"; then
    return 0
  fi
  if [[ -t 0 ]]; then
    read -r -p "$msg (type YES): " answer
  else
    read -r -p "$msg (type YES): " answer </dev/tty
  fi
  [[ "$answer" == "YES" ]] || {
    log_w "Cancelled."
    exit 0
  }
}

remove_bot() {
  confirm_destructive "This will remove Bedolaga Bot containers, volumes and files. Continue?"
  if [[ -d "$BOT_DIR" ]]; then
    compose "$BOT_DIR" down -v --remove-orphans || true
  fi
  $SUDO rm -rf "$BOT_DIR"
  log_ok "Bot removed."
}

remove_cabinet() {
  confirm_destructive "This will remove Cabinet files and nginx config. Continue?"
  if [[ -d "$CABINET_DIR" ]]; then
    compose "$CABINET_DIR" down -v --remove-orphans || true
  fi
  $SUDO rm -rf "$CABINET_DIR"
  $SUDO rm -rf "$STATIC_ROOT"
  $SUDO rm -f /etc/nginx/sites-enabled/bedolaga-cabinet.conf
  $SUDO rm -f /etc/nginx/sites-available/bedolaga-cabinet.conf
  $SUDO nginx -t >/dev/null 2>&1 && $SUDO systemctl reload nginx || true
  log_ok "Cabinet removed."
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
      confirm_destructive "This will remove BOTH bot and cabinet. Continue?"
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
  echo -e "\n${BLUE}--- General Configuration ---${NC}"
  if [[ -z "$CABINET_DOMAIN" ]]; then
    ask CABINET_DOMAIN "Cabinet domain or server IP (e.g. bedolaga.com or 1.2.3.4)" "${detected_ip:-localhost}"
  fi

  if ! is_true "$INSTALL_BOT" && ! is_true "$INSTALL_CABINET" && is_true "$CONFIGURE_NGINX"; then
    if is_true "$ENABLE_SSL" && [[ -z "$LETSENCRYPT_EMAIL" ]]; then
      ask LETSENCRYPT_EMAIL "Email for Let's Encrypt SSL" ""
    fi
    validate_dns_for_domain "$detected_ip"
    return 0
  fi

  # 2. Bot Configuration
  if is_true "$INSTALL_BOT"; then
    echo -e "\n${BLUE}--- Bot Configuration ---${NC}"
    while true; do
      ask BOT_TOKEN "BOT_TOKEN from @BotFather"
      validate_bot_token "$BOT_TOKEN" && break || {
        if ! is_true "$NON_INTERACTIVE"; then BOT_TOKEN=""; continue; else break; fi
      }
    done

    while true; do
      ask ADMIN_IDS "ADMIN_IDS (comma-separated Telegram IDs)"
      validate_admin_ids "$ADMIN_IDS" && break || {
        if ! is_true "$NON_INTERACTIVE"; then ADMIN_IDS=""; continue; else break; fi
      }
    done

    ask TELEGRAM_BOT_USERNAME "Telegram bot username without @" ""

    while true; do
      ask REMNAWAVE_API_URL "REMNAWAVE_API_URL (e.g. https://panel.example.com)" ""
      validate_url "$REMNAWAVE_API_URL" && break || {
        if ! is_true "$NON_INTERACTIVE"; then REMNAWAVE_API_URL=""; continue; else break; fi
      }
    done

    ask_secret REMNAWAVE_API_KEY "REMNAWAVE_API_KEY"
    ask_secret POSTGRES_PASSWORD "POSTGRES_PASSWORD (for bot database)"

    echo -e "\n${BLUE}--- Support & Pricing ---${NC}"
    ask SUPPORT_USERNAME "Support Telegram username (e.g. @support_bot)" "$SUPPORT_USERNAME"
    ask PRICE_30_DAYS "Price for 30 days (in kopeks, e.g. 10000 = 100 rub)" "$PRICE_30_DAYS"
    ask PRICE_90_DAYS "Price for 90 days (in kopeks)" "$PRICE_90_DAYS"
    ask PRICE_180_DAYS "Price for 180 days (in kopeks)" "$PRICE_180_DAYS"

    echo -e "\n${BLUE}--- Payment Systems (Optional) ---${NC}"
    echo -e "${YELLOW}Hint: You can skip these now and add them later by editing .env file${NC}"
    ask CRYPTOBOT_API_TOKEN "CryptoBot API Token (press ENTER to skip)" ""
    ask YOOKASSA_SHOP_ID "YooKassa Shop ID (press ENTER to skip)" ""
    if [[ -n "$YOOKASSA_SHOP_ID" ]]; then
      ask_secret YOOKASSA_SECRET_KEY "YooKassa Secret Key"
    fi

    ask BOT_API_PORT "Internal Bot API Port (for cabinet connection)" "$BOT_API_PORT"
  fi

  # 3. Cabinet Configuration
  if is_true "$INSTALL_CABINET" || is_true "$CONFIGURE_NGINX"; then
    echo -e "\n${BLUE}--- Cabinet Configuration ---${NC}"
    
    if is_true "$INSTALL_CABINET"; then
      ask VITE_APP_NAME "Cabinet Application Name" "$VITE_APP_NAME"
      ask VITE_APP_LOGO "Cabinet Logo text (usually 1 letter)" "$VITE_APP_LOGO"
      
      if [[ -z "$TELEGRAM_BOT_USERNAME" ]]; then
        ask TELEGRAM_BOT_USERNAME "Telegram bot username without @ (for cabinet login)" ""
      fi

      if ! is_true "$NON_INTERACTIVE"; then
        echo "Select cabinet deployment method:"
        echo "  image) Use prebuilt Docker image (recommended, saves RAM/Time)"
        echo "  source) Build from source (requires 2GB+ RAM, slow)"
        ask CABINET_DEPLOY_MODE "Mode" "$CABINET_DEPLOY_MODE"
      fi
    fi

    if is_true "$ENABLE_SSL" && [[ -z "$LETSENCRYPT_EMAIL" ]] && ! is_true "$NON_INTERACTIVE"; then
      ask LETSENCRYPT_EMAIL "Email for Let's Encrypt SSL (required for SSL)" ""
    fi
  fi

  validate_dns_for_domain "$detected_ip"
}

print_summary() {
  echo
  log_ok "Installation completed."
  
  if is_true "$INSTALL_BOT" || is_true "$INSTALL_CABINET"; then
    echo -e "\n${BLUE}--- Health Check ---${NC}"
    if is_true "$INSTALL_BOT"; then
      if curl -s "http://127.0.0.1:${BOT_API_PORT}/health" >/dev/null 2>&1 || curl -s "http://127.0.0.1:${BOT_API_PORT}" >/dev/null 2>&1; then
        log_ok "Bot API: Running"
      else
        log_w "Bot API: Not responding yet (it might take a minute)"
      fi
    fi
    if [[ -n "$CABINET_DOMAIN" ]]; then
      if curl -s -I "http://${CABINET_DOMAIN}" | grep -q "200 OK\|301 Moved\|302 Found" >/dev/null 2>&1; then
        log_ok "Cabinet URL: Accessible"
      else
        log_w "Cabinet URL: Not accessible from this server yet (check DNS/Firewall)"
      fi
    fi
  fi

  echo -e "\n${BLUE}--- Paths ---${NC}"
  echo "Bot path:      $BOT_DIR"
  echo "Cabinet path:  $CABINET_DIR"
  echo "Static path:   $STATIC_ROOT"
  echo "Cabinet URL:   http://${CABINET_DOMAIN}"
  if is_true "$ENABLE_SSL" && [[ -n "$LETSENCRYPT_EMAIL" ]] && [[ "$CABINET_DOMAIN" != "localhost" && "$CABINET_DOMAIN" != "127.0.0.1" ]]; then
    echo "Cabinet URL:   https://${CABINET_DOMAIN}"
  fi
  echo
  echo "Useful commands:"
  echo "  cd $BOT_DIR && docker compose logs -f --tail 100"
  echo "  sudo nginx -t && sudo systemctl reload nginx"
  echo
  echo "To Update Bedolaga:"
  echo "  Bot:     cd $BOT_DIR && git pull && docker compose up -d --build"
  echo "  Cabinet: Re-run this script and choose 'Install Cabinet only'"
  echo
  echo "To add/change payments later:"
  echo "  1. Edit file: nano $BOT_DIR/.env"
  echo "  2. Restart bot: cd $BOT_DIR && docker compose up -d"
  echo
  echo "Cabinet authentication:"
  echo "  Login/password is not used by default."
  echo "  Sign in via Telegram in the web cabinet."
  echo "  Admin access is controlled by ADMIN_IDS in bot .env."
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
