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

auto_public_ip() {
  curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null || true
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
    ca-certificates curl wget git jq openssl nginx certbot python3-certbot-nginx
  log_ok "Dependencies installed."
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
  for ep in "$url/health" "$url/api/health" "$url"; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 \
      -H "Authorization: Bearer ${key}" \
      -H "X-API-KEY: ${key}" "$ep" || true)"
    [[ "$code" =~ ^2[0-9][0-9]$ || "$code" == "401" || "$code" == "403" ]] && {
      log_ok "Remnawave responded at ${ep} (${code})."
      return 0
    }
  done
  log_w "Remnawave check failed (last code: ${code:-n/a}). Continuing anyway."
}

configure_bot_env() {
  local env_file="$1" cabinet_origin="$2"

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

  env_set "$env_file" "ADMIN_REPORTS_TOPIC_ID" "0"
  env_set "$env_file" "MULENPAY_SHOP_ID" "0"
  env_set "$env_file" "FREEKASSA_SHOP_ID" "0"
  env_set "$env_file" "FREEKASSA_PAYMENT_SYSTEM_ID" "0"
  env_set "$env_file" "KASSA_AI_SHOP_ID" "0"
  env_set "$env_file" "SEVERPAY_MID" "0"
  env_set "$env_file" "LOG_ROTATION_TOPIC_ID" "0"
  env_set "$env_file" "BACKUP_AUTO_ENABLED" "false"
  env_set "$env_file" "BACKUP_SEND_ENABLED" "false"

  env_set "$env_file" "CRYPTOBOT_ENABLED" "$([[ -n "$CRYPTOBOT_API_TOKEN" ]] && echo "true" || echo "false")"
  env_set "$env_file" "CRYPTOBOT_API_TOKEN" "$CRYPTOBOT_API_TOKEN"
  env_set "$env_file" "YOOKASSA_ENABLED" "$([[ -n "$YOOKASSA_SHOP_ID" ]] && echo "true" || echo "false")"
  env_set "$env_file" "YOOKASSA_SHOP_ID" "$YOOKASSA_SHOP_ID"
  env_set "$env_file" "YOOKASSA_SECRET_KEY" "$YOOKASSA_SECRET_KEY"

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

  env_set "$env_file" "TZ" "Europe/Moscow"
  env_set "$env_file" "DEFAULT_LANGUAGE" "ru"
  env_set "$env_file" "ENABLE_LOGO_MODE" "true"
  env_set "$env_file" "LOG_LEVEL" "INFO"
  env_set "$env_file" "DEBUG" "false"
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
  compose "$BOT_DIR" ps || true
  log_ok "Bedolaga Bot deployed."
}

build_cabinet_static() {
  local env_file="$CABINET_DIR/.env"
  ensure_env "$CABINET_DIR"
  env_set "$env_file" "VITE_API_URL" "/api"
  env_set "$env_file" "VITE_TELEGRAM_BOT_USERNAME" "$TELEGRAM_BOT_USERNAME"
  env_set "$env_file" "VITE_APP_NAME" "$VITE_APP_NAME"
  env_set "$env_file" "VITE_APP_LOGO" "$VITE_APP_LOGO"

  log_i "Building Bedolaga Cabinet static files..."
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
  log_ok "Cabinet static files prepared at $STATIC_ROOT."
}

write_nginx_conf() {
  local conf="/etc/nginx/sites-available/bedolaga-cabinet.conf"
  local enabled="/etc/nginx/sites-enabled/bedolaga-cabinet.conf"
  local upstream="http://127.0.0.1:${BOT_API_PORT}"

  $SUDO tee "$conf" >/dev/null <<EOF
server {
    listen 80;
    server_name ${CABINET_DOMAIN};

    root ${STATIC_ROOT};
    index index.html;

    location /api/ {
        rewrite ^/api/(.*) /\$1 break;
        proxy_pass ${upstream};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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
  $SUDO systemctl enable --now nginx
  $SUDO nginx -t
  $SUDO systemctl reload nginx
  log_ok "Nginx reverse proxy configured."
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

collect_inputs() {
  local detected_ip
  detected_ip="$(auto_public_ip)"

  ask BOT_TOKEN "BOT_TOKEN from @BotFather"
  ask ADMIN_IDS "ADMIN_IDS (comma-separated Telegram IDs)"
  ask TELEGRAM_BOT_USERNAME "Telegram bot username without @" ""
  ask REMNAWAVE_API_URL "REMNAWAVE_API_URL (https://...)" ""
  ask_secret REMNAWAVE_API_KEY "REMNAWAVE_API_KEY"
  ask_secret POSTGRES_PASSWORD "POSTGRES_PASSWORD"

  ask SUPPORT_USERNAME "SUPPORT_USERNAME" "$SUPPORT_USERNAME"
  ask PRICE_30_DAYS "PRICE_30_DAYS in kopeks" "$PRICE_30_DAYS"
  ask PRICE_90_DAYS "PRICE_90_DAYS in kopeks" "$PRICE_90_DAYS"
  ask PRICE_180_DAYS "PRICE_180_DAYS in kopeks" "$PRICE_180_DAYS"

  if [[ -z "$CABINET_DOMAIN" ]]; then
    if [[ -n "$detected_ip" ]]; then
      CABINET_DOMAIN="$detected_ip"
    elif is_true "$NON_INTERACTIVE"; then
      CABINET_DOMAIN="localhost"
    else
      ask CABINET_DOMAIN "Cabinet domain (or server IP)" "localhost"
    fi
  fi
}

print_summary() {
  echo
  log_ok "Installation completed."
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
}

main() {
  header
  require_linux
  setup_sudo

  need_cmd curl
  need_cmd git

  ensure_packages
  ensure_docker
  collect_inputs
  check_remnawave "$REMNAWAVE_API_URL" "$REMNAWAVE_API_KEY"

  if is_true "$INSTALL_BOT"; then
    install_bot
  else
    log_w "INSTALL_BOT=false, bot deployment skipped."
  fi

  if is_true "$INSTALL_CABINET"; then
    install_cabinet
  else
    log_w "INSTALL_CABINET=false, cabinet deployment skipped."
  fi

  print_summary
}

main "$@"
