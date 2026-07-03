#!/usr/bin/env bash

# laravel-new.sh
# Create a minimal Laravel project using the official Docker-based installer,
# then remove Laravel Sail artifacts for a non-Sail workflow.
# This script must be executable (e.g. `chmod +x scripts/laravel-new.sh`).
#
# Usage:
#   laravel-new <AppName> [-d <MySQL|PostgreSQL>] [-c] [-m] [-n <version>] [--db-host-port <port>]
#
# Parameters:
#   AppName  Project directory name to create.
#
# Options:
#   -d, -database, --database  Database engine: MySQL or PostgreSQL.
#   -c, -cache, --cache        Include Redis.
#   -m, -mail, --mail          Include Mailpit.
#   -n, --node, --node-version Optional Node version to write into .nvmrc.
#   --db-host-port <port>      Host port for the DB service (default: 3306/5432).
#
# Examples:
#   laravel-new my-app
#   laravel-new my-app -d PostgreSQL
#   laravel-new my-app -d PostgreSQL --db-host-port 5433
#   laravel-new my-app -d MySQL -c -m

# This script changes shell options and working directories; sourcing it would leak
# those changes into the user's interactive shell.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "Error: run this script directly; do not source it." >&2
  return 1 2>/dev/null || exit 1
fi

# Exit on errors, treat unset vars as errors, and fail pipelines if any command fails.
set -euo pipefail

restore_terminal() {
  if [[ -t 0 ]]; then
    stty sane >/dev/null 2>&1 || true
  fi
}

trap restore_terminal EXIT
trap 'restore_terminal; exit 130' INT
trap 'restore_terminal; exit 129' HUP
trap 'restore_terminal; exit 143' TERM

# Resolve the real directory this script lives in for template lookups, including
# when invoked through a symlink on PATH.
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="${SOURCE_DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# Load argument parsing helpers.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-args.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-args.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-args.sh"

# Load logging helpers for terse, readable output.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-log.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-log.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-log.sh"

# Load reusable interactive prompt helpers.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-prompt.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-prompt.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-prompt.sh"

# Load interactive service selection helpers.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-interactive.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-interactive.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-interactive.sh"

# Load README helpers for per-project documentation.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-readme.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-readme.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-readme.sh"

# Load cleanup helpers.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-cleanup.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-cleanup.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-cleanup.sh"

# Load Docker preflight checks.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-docker-preflight.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-docker-preflight.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-docker-preflight.sh"

# Load host port resolution helpers.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-host-ports.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-host-ports.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-host-ports.sh"

# Load Node version helpers (optional .nvmrc).
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-node.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-node.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-node.sh"

# Print usage help for the script.
usage() {
  cat <<'EOF'
Usage: laravel-new <AppName> [-d <MySQL|PostgreSQL>] [-c] [-m] [-n <version>] [--db-host-port <port>]

Creates a new Laravel app via laravel.build (Docker-based) with the requested
options, removes Sail, and writes a minimal Docker setup (nginx + fpm + optional
DB/Redis/Mailpit).

Preflight checks:
  - Ensure the target project directory does not already exist.
  - Ensure Docker has at least DOCKER_MIN_FREE_GB (default 5GB) free in its data root.
  - Resolve available host ports for HTTP, DB, Redis, and Mailpit.

Options:
  -d, -database, --database  Database engine: MySQL or PostgreSQL.
  -c, -cache, --cache        Include Redis.
  -m, -mail, --mail          Include Mailpit.
  -n, --node, --node-version Optional Node version to write into .nvmrc.
  --db-host-port <port>      Host port for the DB service (default: 3306/5432).
EOF
}

ensure_privilege_prompt_visible() {
  local privilege_cmd=""

  if command -v doas >/dev/null 2>&1; then
    privilege_cmd="doas"
  elif command -v sudo >/dev/null 2>&1; then
    privilege_cmd="sudo"
  else
    echo "Error: laravel.build requires sudo or doas to adjust generated file ownership." >&2
    return 1
  fi

  if "$privilege_cmd" -n true >/dev/null 2>&1; then
    return 0
  fi

  echo "The Laravel installer may need ${privilege_cmd} to fix generated file ownership."
  echo "Please authenticate now so no password prompt is hidden in the install log."

  if [[ "$privilege_cmd" == "sudo" ]]; then
    "$privilege_cmd" -v
  else
    "$privilege_cmd" true
  fi
}

sed_in_place() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

insert_after_first_match() {
  local file="$1"
  local pattern="$2"
  local inserted_line="$3"
  local tmp=""
  local current_line=""
  local inserted="false"

  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  while IFS= read -r current_line || [[ -n "$current_line" ]]; do
    printf '%s\n' "$current_line" >>"$tmp"
    if [[ "$inserted" == "false" && "$current_line" =~ $pattern ]]; then
      printf '%s\n' "$inserted_line" >>"$tmp"
      inserted="true"
    fi
  done <"$file"

  mv "$tmp" "$file"
}

insert_after_first_line() {
  local file="$1"
  local inserted_line="$2"
  local tmp=""
  local current_line=""
  local line_number=0

  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  while IFS= read -r current_line || [[ -n "$current_line" ]]; do
    line_number=$((line_number + 1))
    printf '%s\n' "$current_line" >>"$tmp"
    if (( line_number == 1 )); then
      printf '%s\n' "$inserted_line" >>"$tmp"
    fi
  done <"$file"

  mv "$tmp" "$file"
}

# Parse the CLI arguments into well-named globals.
if ! parse_args "$@"; then
  echo "Error: $PARSE_ERROR" >&2
  usage
  exit 1
fi

# Show help and exit successfully.
if [[ "$SHOW_HELP" == "true" ]]; then
  usage
  exit 0
fi

if ! prompt_for_optional_services; then
  exit 1
fi

# Normalize the DB parameter into internal settings (only if DB was requested).
DB_KEY="none"
DB_WITH=""
DB_LABEL="No database"
DB_CONNECTION=""
DB_HOST=""
DB_PORT=""
DB_HOST_PORT=""
DB_HOST_PORT_CANDIDATE_START=""
HTTP_HOST_PORT="80"
REDIS_HOST_PORT="6379"
MAILPIT_SMTP_HOST_PORT="1025"
MAILPIT_DASHBOARD_HOST_PORT="8025"
FPM_BASE_TEMPLATE="${SCRIPT_DIR}/../templates/laravel/docker/fpm/Dockerfile.base"
FPM_VARIANT_TEMPLATE=""
RENDER_DOCKERFILE_SCRIPT="${SCRIPT_DIR}/render-dockerfile.sh"

if [[ "$DB_ENABLED" == "true" ]]; then
  DB_TYPE_NORMALIZED="$(printf '%s' "$DB_TYPE_RAW" | tr '[:upper:]' '[:lower:]')"

  case "$DB_TYPE_NORMALIZED" in
    mysql)
      DB_KEY="mysql"
      DB_LABEL="MySQL"
      DB_WITH="mysql"
      DB_CONNECTION="mysql"
      DB_HOST="mysql"
      DB_PORT="3306"
      DB_HOST_PORT="$DB_PORT"
      DB_HOST_PORT_CANDIDATE_START="3307"
      FPM_VARIANT_TEMPLATE="${SCRIPT_DIR}/../templates/laravel/docker/fpm/Dockerfile.mysql"
      ;;
    postgres|postgresql|pgsql)
      DB_KEY="pgsql"
      DB_LABEL="PostgreSQL"
      DB_WITH="pgsql"
      DB_CONNECTION="pgsql"
      DB_HOST="pgsql"
      DB_PORT="5432"
      DB_HOST_PORT="$DB_PORT"
      DB_HOST_PORT_CANDIDATE_START="5433"
      FPM_VARIANT_TEMPLATE="${SCRIPT_DIR}/../templates/laravel/docker/fpm/Dockerfile.pgsql"
      ;;
    *)
      echo "Error: DB must be MySQL or PostgreSQL." >&2
      usage
      exit 1
      ;;
  esac
fi

# Build the compose template name based on enabled services.
COMPOSE_SUFFIX=""
if [[ "$CACHE_ENABLED" == "true" && "$MAIL_ENABLED" == "true" ]]; then
  COMPOSE_SUFFIX=".cache-mail"
elif [[ "$CACHE_ENABLED" == "true" ]]; then
  COMPOSE_SUFFIX=".cache"
elif [[ "$MAIL_ENABLED" == "true" ]]; then
  COMPOSE_SUFFIX=".mail"
fi

COMPOSE_TEMPLATE="${SCRIPT_DIR}/../templates/laravel/compose/docker-compose.${DB_KEY}${COMPOSE_SUFFIX}.yml"
NGINX_TEMPLATE="${SCRIPT_DIR}/../templates/laravel/docker/nginx/default.conf"
DUMP_SERVER_TEMPLATE="${SCRIPT_DIR}/../templates/laravel/app/Console/Commands/DevDumpServerCommand.php"

# Ensure the template files exist before continuing.
if [[ ! -f "$COMPOSE_TEMPLATE" || ! -f "$FPM_BASE_TEMPLATE" || ! -f "$NGINX_TEMPLATE" || ! -f "$RENDER_DOCKERFILE_SCRIPT" || ! -f "$DUMP_SERVER_TEMPLATE" ]]; then
  echo "Error: missing template files under templates/laravel." >&2
  exit 1
fi
if [[ -n "$FPM_VARIANT_TEMPLATE" && ! -f "$FPM_VARIANT_TEMPLATE" ]]; then
  echo "Error: missing Dockerfile variant template: $FPM_VARIANT_TEMPLATE" >&2
  exit 1
fi

# Initialize the log file before any network-heavy work.
ROOT_DIR="$PWD"
init_log "$ROOT_DIR" "$APP_NAME"

# Summarize the selected options before continuing.
echo "Selected options:"
echo "  AppName:        $APP_NAME"
echo "  Database:       $DB_LABEL"
echo "  Redis cache:    $(if [[ "$CACHE_ENABLED" == "true" ]]; then echo "enabled"; else echo "disabled"; fi)"
echo "  Mailpit:        $(if [[ "$MAIL_ENABLED" == "true" ]]; then echo "enabled"; else echo "disabled"; fi)"
echo "  Compose file:   $(basename "$COMPOSE_TEMPLATE")"
echo "  FPM template:   $(basename "$FPM_BASE_TEMPLATE")"
if [[ -n "$FPM_VARIANT_TEMPLATE" ]]; then
  echo "  FPM variant:    $(basename "$FPM_VARIANT_TEMPLATE")"
else
  echo "  FPM variant:    none"
fi
echo ""
if ! confirm_selected_options; then
  exit 1
fi
echo ""

# Prevent overwriting existing files or directories.
if ! check_project_dir_available "$APP_NAME"; then
  exit 1
fi

# Ensure required host tools are available.
if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required." >&2
  exit 1
fi

# Ensure Docker is available because the installer and Composer run in containers.
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker is not running." >&2
  echo "      Start Docker Desktop, wait until it finishes starting, then run laravel-new again." >&2
  exit 1
fi
reset_host_port_reservations
if ! resolve_host_port "HTTP" "FORWARD_HTTP_PORT" "80" "8080"; then
  exit 1
fi
HTTP_HOST_PORT="$RESOLVED_HOST_PORT"

if [[ "$DB_ENABLED" == "true" ]]; then
  if ! resolve_host_port "$DB_LABEL" "FORWARD_DB_PORT" "$DB_PORT" "$DB_HOST_PORT_CANDIDATE_START" "$DB_HOST_PORT_RAW"; then
    exit 1
  fi
  DB_HOST_PORT="$RESOLVED_HOST_PORT"
fi
if [[ "$CACHE_ENABLED" == "true" ]]; then
  if ! resolve_host_port "Redis" "FORWARD_REDIS_PORT" "6379" "6380"; then
    exit 1
  fi
  REDIS_HOST_PORT="$RESOLVED_HOST_PORT"
fi
if [[ "$MAIL_ENABLED" == "true" ]]; then
  if ! resolve_host_port "Mailpit SMTP" "FORWARD_MAILPIT_SMTP_PORT" "1025" "1026"; then
    exit 1
  fi
  MAILPIT_SMTP_HOST_PORT="$RESOLVED_HOST_PORT"
  if ! resolve_host_port "Mailpit dashboard" "FORWARD_MAILPIT_DASHBOARD_PORT" "8025" "8026"; then
    exit 1
  fi
  MAILPIT_DASHBOARD_HOST_PORT="$RESOLVED_HOST_PORT"
fi

REQUIRED_HOST_PORTS=("$HTTP_HOST_PORT")
if [[ "$DB_ENABLED" == "true" ]]; then
  REQUIRED_HOST_PORTS+=("$DB_HOST_PORT")
fi
if [[ "$CACHE_ENABLED" == "true" ]]; then
  REQUIRED_HOST_PORTS+=("$REDIS_HOST_PORT")
fi
if [[ "$MAIL_ENABLED" == "true" ]]; then
  REQUIRED_HOST_PORTS+=("$MAILPIT_SMTP_HOST_PORT" "$MAILPIT_DASHBOARD_HOST_PORT")
fi
if ! check_ports_available "${REQUIRED_HOST_PORTS[@]}"; then
  exit 1
fi

# Build the laravel.build URL (DB only; cache/mail are handled locally).
LARAVEL_BUILD_URL="https://laravel.build/${APP_NAME}"
if [[ -n "$DB_WITH" ]]; then
  LARAVEL_BUILD_URL="${LARAVEL_BUILD_URL}?with=${DB_WITH}"
fi

# Run the official Laravel build script with the requested options.
if ! ensure_privilege_prompt_visible; then
  exit 1
fi
echo "[1/10] Installing Laravel (laravel.build)..."
if ! run_logged "Install Laravel" "curl -s \"$LARAVEL_BUILD_URL\" | bash"; then
  exit 1
fi
echo "      ✓ Project created: $APP_NAME"

# Move into the new project directory for cleanup work.
cd "$APP_NAME"

# Remove Sail files (compose config, Sail script, and Sail docker assets).
echo "[2/10] Removing Sail..."
log_note "Remove Sail artifacts"
rm -f compose.yaml docker-compose.yml vendor/bin/sail
rm -rf docker
echo "      ✓ Sail files removed"

# If Sail is listed as a dev dependency, remove it using Composer in a container.
if grep -q '"laravel/sail"' composer.json; then
  log_note "Remove laravel/sail dependency"
  if ! run_logged_retry "Remove laravel/sail" "docker run --rm -u \"$(id -u):$(id -g)\" -v \"$PWD\":/app -w /app composer:2 composer remove laravel/sail --dev" 2; then
    exit 1
  fi
  echo "      ✓ laravel/sail removed from composer.json"
else
  # Some templates may not include Sail; in that case nothing to remove.
  echo "      ✓ laravel/sail not present"
fi

# Install Envy for managing .env.example.
echo "[3/10] Installing Envy..."
log_note "Install worksome/envy"
if ! run_logged_retry "Install Envy" "docker run --rm -u \"$(id -u):$(id -g)\" -v \"$PWD\":/app -w /app composer:2 composer require worksome/envy --dev" 2; then
  exit 1
fi
if ! run_logged "Publish Envy config" "docker run --rm -u \"$(id -u):$(id -g)\" -v \"$PWD\":/app -w /app composer:2 php artisan envy:install"; then
  exit 1
fi
log_note "Configure Envy helpers"
if [[ -f "config/envy.php" ]]; then
  sed_in_place \
    -e "s/'display_comments' => [a-z]*/'display_comments' => true/" \
    -e "s/'display_location_hints' => [a-z]*/'display_location_hints' => true/" \
    config/envy.php
fi
echo "      ✓ worksome/envy installed"

# Install Symfony VarDumper and add dev:dump-server command.
echo "[4/10] Installing VarDumper + dev:dump-server..."
log_note "Install symfony/var-dumper"
if ! grep -q '"symfony/var-dumper"' composer.json; then
  if ! run_logged_retry "Install symfony/var-dumper" "docker run --rm -u \"$(id -u):$(id -g)\" -v \"$PWD\":/app -w /app composer:2 composer require symfony/var-dumper --dev" 2; then
    exit 1
  fi
fi
log_note "Add dev:dump-server command"
mkdir -p app/Console/Commands
cp "$DUMP_SERVER_TEMPLATE" app/Console/Commands/DevDumpServerCommand.php
if [[ -f "routes/console.php" ]]; then
  if ! grep -q "DevDumpServerCommand" routes/console.php; then
    if grep -q "^use Illuminate\\\\Support\\\\Facades\\\\Artisan;" routes/console.php; then
      insert_after_first_match routes/console.php '^use Illuminate\\Support\\Facades\\Artisan;$' 'use App\Console\Commands\DevDumpServerCommand;'
    else
      insert_after_first_line routes/console.php 'use App\Console\Commands\DevDumpServerCommand;'
    fi
  fi
  if ! grep -q "DevDumpServerCommand::class" routes/console.php; then
    if grep -q "DevDumpServerCommand;" routes/console.php; then
      insert_after_first_match routes/console.php 'DevDumpServerCommand;$' 'Artisan::addCommands([DevDumpServerCommand::class]);'
    else
      insert_after_first_line routes/console.php 'Artisan::addCommands([\App\Console\Commands\DevDumpServerCommand::class]);'
    fi
  fi
fi
echo "      ✓ dev:dump-server command ready"

# Update a key in an env file or append it if missing.
update_env_value() {
  local env_file="$1"
  local env_key="$2"
  local env_value="$3"
  local safe_value

  if [[ ! -f "$env_file" ]]; then
    return 0
  fi

  safe_value="$(printf '%s' "$env_value" | sed -e 's/[&|]/\\&/g')"

  if grep -q "^${env_key}=" "$env_file"; then
    sed_in_place "s|^${env_key}=.*|${env_key}=${safe_value}|" "$env_file"
  else
    echo "${env_key}=${env_value}" >> "$env_file"
  fi
}

ensure_blank_line() {
  local env_file="$1"

  if [[ ! -f "$env_file" ]]; then
    return 0
  fi

  if [[ -n "$(tail -n 1 "$env_file")" ]]; then
    echo "" >> "$env_file"
  fi
}

write_minimal_env_files() {
  local app_name="$1"
  local app_key="$2"

  cat <<'EOF' > .env.example
APP_NAME="__APP_NAME__"
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=http://localhost

EOF

  cp .env.example .env

  update_env_value ".env" "APP_NAME" "\"$app_name\""
  update_env_value ".env.example" "APP_NAME" "\"$app_name\""
  update_env_value ".env" "APP_KEY" "$app_key"
}

sanitize_db_name() {
  local raw="$1"
  local cleaned

  cleaned="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  if [[ -z "$cleaned" ]]; then
    cleaned="app"
  fi

  printf '%s' "$cleaned"
}

format_localhost_url() {
  local port="$1"

  if [[ "$port" == "80" ]]; then
    printf '%s' "http://localhost"
  else
    printf 'http://localhost:%s' "$port"
  fi
}

# Copy minimal Docker files for nginx + php-fpm + chosen services.
echo "[5/10] Writing Docker setup..."
log_note "Copy minimal Docker files"
mkdir -p docker/nginx docker/fpm
cp "$NGINX_TEMPLATE" docker/nginx/default.conf
"$RENDER_DOCKERFILE_SCRIPT" "$FPM_BASE_TEMPLATE" "$FPM_VARIANT_TEMPLATE" "docker/fpm/Dockerfile"
cp "$COMPOSE_TEMPLATE" docker-compose.yml
echo "      ✓ docker-compose.yml + docker/ files copied"

# Optionally write NVM config for Node usage.
echo "[6/10] Resolving Node version..."
log_note "Resolve Node version"
if ! resolve_node_version "$NODE_VERSION_RAW"; then
  cleanup_failed_setup "$PWD" "Invalid Node version"
  exit 1
fi
if [[ -n "$NODE_VERSION" ]]; then
  write_nvmrc "$NODE_VERSION"
  echo "      ✓ .nvmrc written"
else
  echo "      ✓ .nvmrc skipped"
fi

# Align .env and .env.example with the selected DB service name and port.
echo "[7/10] Updating .env files..."
log_note "Update environment files"
APP_KEY_VALUE=""
if [[ -f ".env" ]]; then
  APP_KEY_VALUE="$(grep -m1 '^APP_KEY=' .env | cut -d= -f2- || true)"
fi
write_minimal_env_files "$APP_NAME" "$APP_KEY_VALUE"
APP_URL_VALUE="$(format_localhost_url "$HTTP_HOST_PORT")"
update_env_value ".env" "APP_URL" "$APP_URL_VALUE"
ensure_blank_line ".env"
update_env_value ".env" "FORWARD_HTTP_PORT" "$HTTP_HOST_PORT"
if [[ "$DB_ENABLED" == "true" ]]; then
  DB_DEFAULT_NAME="$(sanitize_db_name "$APP_NAME")"
  ensure_blank_line ".env"
  ensure_blank_line ".env.example"
  update_env_value ".env" "DB_CONNECTION" "$DB_CONNECTION"
  update_env_value ".env" "DB_HOST" "$DB_HOST"
  update_env_value ".env" "DB_PORT" "$DB_PORT"
  update_env_value ".env" "DB_DATABASE" "$DB_DEFAULT_NAME"
  update_env_value ".env" "DB_USERNAME" "$DB_DEFAULT_NAME"
  update_env_value ".env" "DB_PASSWORD" "secret"
  update_env_value ".env" "FORWARD_DB_PORT" "$DB_HOST_PORT"
  update_env_value ".env.example" "DB_CONNECTION" "$DB_CONNECTION"
  update_env_value ".env.example" "DB_HOST" "$DB_HOST"
  update_env_value ".env.example" "DB_PORT" "$DB_PORT"
  update_env_value ".env.example" "DB_DATABASE" "$DB_DEFAULT_NAME"
  update_env_value ".env.example" "DB_USERNAME" "$DB_DEFAULT_NAME"
  update_env_value ".env.example" "DB_PASSWORD" "secret"
else
  update_env_value ".env" "DB_CONNECTION" "sqlite"
  update_env_value ".env" "DB_DATABASE" "database/database.sqlite"
  update_env_value ".env.example" "DB_CONNECTION" "sqlite"
  update_env_value ".env.example" "DB_DATABASE" "database/database.sqlite"
  touch database/database.sqlite
fi

# Align .env and .env.example with Redis when cache is enabled.
if [[ "$CACHE_ENABLED" == "true" ]]; then
  ensure_blank_line ".env"
  ensure_blank_line ".env.example"
  update_env_value ".env" "CACHE_STORE" "redis"
  update_env_value ".env" "REDIS_HOST" "redis"
  update_env_value ".env" "REDIS_PORT" "6379"
  update_env_value ".env" "FORWARD_REDIS_PORT" "$REDIS_HOST_PORT"
  update_env_value ".env.example" "CACHE_STORE" "redis"
  update_env_value ".env.example" "REDIS_HOST" "redis"
  update_env_value ".env.example" "REDIS_PORT" "6379"
fi

# Align .env and .env.example with Mailpit when mail is enabled.
if [[ "$MAIL_ENABLED" == "true" ]]; then
  ensure_blank_line ".env"
  ensure_blank_line ".env.example"
  update_env_value ".env" "MAIL_MAILER" "smtp"
  update_env_value ".env" "MAIL_HOST" "mailpit"
  update_env_value ".env" "MAIL_PORT" "1025"
  update_env_value ".env" "MAIL_ENCRYPTION" "null"
  update_env_value ".env" "FORWARD_MAILPIT_SMTP_PORT" "$MAILPIT_SMTP_HOST_PORT"
  update_env_value ".env" "FORWARD_MAILPIT_DASHBOARD_PORT" "$MAILPIT_DASHBOARD_HOST_PORT"
  update_env_value ".env.example" "MAIL_MAILER" "smtp"
  update_env_value ".env.example" "MAIL_HOST" "mailpit"
  update_env_value ".env.example" "MAIL_PORT" "1025"
  update_env_value ".env.example" "MAIL_ENCRYPTION" "null"
fi
if ! run_logged "Prune .env.example with Envy" "docker run --rm -u \"$(id -u):$(id -g)\" -v \"$PWD\":/app -w /app composer:2 php artisan envy:prune --force"; then
  exit 1
fi
ensure_blank_line ".env.example"
update_env_value ".env.example" "FORWARD_HTTP_PORT" "80"
if [[ "$DB_ENABLED" == "true" ]]; then
  update_env_value ".env.example" "FORWARD_DB_PORT" "$DB_PORT"
fi
if [[ "$CACHE_ENABLED" == "true" ]]; then
  update_env_value ".env.example" "FORWARD_REDIS_PORT" "6379"
fi
if [[ "$MAIL_ENABLED" == "true" ]]; then
  update_env_value ".env.example" "FORWARD_MAILPIT_SMTP_PORT" "1025"
  update_env_value ".env.example" "FORWARD_MAILPIT_DASHBOARD_PORT" "8025"
fi
echo "      ✓ DB/Redis/Mail settings applied"

# Start Docker and run migrations (idempotent).
echo "[8/10] Starting Docker and running migrations..."
log_note "Compose down"
if ! run_logged "Compose down" "docker compose down -v"; then
  exit 1
fi
log_note "Compose up"
HOST_PORTS=("$HTTP_HOST_PORT")
if [[ "$DB_ENABLED" == "true" ]]; then
  HOST_PORTS+=("$DB_HOST_PORT")
fi
if [[ "$CACHE_ENABLED" == "true" ]]; then
  HOST_PORTS+=("$REDIS_HOST_PORT")
fi
if [[ "$MAIL_ENABLED" == "true" ]]; then
  HOST_PORTS+=("$MAILPIT_SMTP_HOST_PORT" "$MAILPIT_DASHBOARD_HOST_PORT")
fi
if ! check_ports_available "${HOST_PORTS[@]}"; then
  cleanup_failed_setup "$PWD" "Required ports are in use"
  exit 1
fi
if ! check_docker_disk_space; then
  cleanup_failed_setup "$PWD" "Insufficient Docker disk space"
  exit 1
fi
if ! run_logged "Compose up" "docker compose up -d --build"; then
  exit 1
fi
log_note "Run migrations"
MIGRATION_ATTEMPTS=12
MIGRATION_DELAY=3
MIGRATION_DONE="false"
for attempt in $(seq 1 "$MIGRATION_ATTEMPTS"); do
  if docker compose exec -T fpm php artisan migrate --force >>"$LOG_TMP" 2>&1; then
    MIGRATION_DONE="true"
    break
  fi
  echo "      - Waiting for database (${attempt}/${MIGRATION_ATTEMPTS})..."
  sleep "$MIGRATION_DELAY"
done
if [[ "$MIGRATION_DONE" != "true" ]]; then
  echo "      ✗ Migrations failed"
  show_log_tail
  LOG_KEEP="true"
  finalize_log
  exit 1
fi
echo "      ✓ Migrations complete"

# Write a README tailored to the selected options.
echo "[9/10] Writing README..."
log_note "Write project README"
if ! write_project_readme "$PWD" "$APP_NAME" "$DB_KEY" "$CACHE_ENABLED" "$MAIL_ENABLED" "$DB_HOST_PORT" "$HTTP_HOST_PORT" "$REDIS_HOST_PORT" "$MAILPIT_SMTP_HOST_PORT" "$MAILPIT_DASHBOARD_HOST_PORT"; then
  echo "      ✗ README.md generation failed"
  LOG_KEEP="true"
  finalize_log
  exit 1
fi
echo "      ✓ README.md generated"

# Final confirmation and log cleanup.
echo "[10/10] Done"
echo "      Project ready at: $PWD"
finalize_log
