#!/usr/bin/env bash

# laravel-new.sh
# Create a minimal Laravel project using the official Docker-based installer,
# then remove Laravel Sail artifacts for a non-Sail workflow.
# This script must be executable (e.g. `chmod +x scripts/laravel-new.sh`).
#
# Usage:
#   laravel-new <AppName> [-d <MySQL|PostgreSQL>] [-c] [-m]
#
# Parameters:
#   AppName  Project directory name to create.
#
# Options:
#   -d, -database, --database  Database engine: MySQL or PostgreSQL.
#   -c, -cache, --cache        Include Redis.
#   -m, -mail, --mail          Include Mailpit.
#
# Examples:
#   laravel-new my-app
#   laravel-new my-app -d PostgreSQL
#   laravel-new my-app -d MySQL -c -m

# Exit on errors, treat unset vars as errors, and fail pipelines if any command fails.
set -euo pipefail

# Resolve the directory this script lives in for template lookups.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Load README helpers for per-project documentation.
if [[ ! -f "${SCRIPT_DIR}/lib/laravel-new-readme.sh" ]]; then
  echo "Error: missing scripts/lib/laravel-new-readme.sh" >&2
  exit 1
fi
source "${SCRIPT_DIR}/lib/laravel-new-readme.sh"

# Print usage help for the script.
usage() {
  cat <<'EOF'
Usage: laravel-new <AppName> [-d <MySQL|PostgreSQL>] [-c] [-m]

Creates a new Laravel app via laravel.build (Docker-based) with the requested
options, removes Sail, and writes a minimal Docker setup (nginx + fpm + optional
DB/Redis/Mailpit).

Options:
  -d, -database, --database  Database engine: MySQL or PostgreSQL.
  -c, -cache, --cache        Include Redis.
  -m, -mail, --mail          Include Mailpit.
EOF
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

# Normalize the DB parameter into internal settings (only if DB was requested).
DB_KEY="none"
DB_WITH=""
DB_LABEL="No database"
DB_CONNECTION=""
DB_HOST=""
DB_PORT=""
FPM_BASE_TEMPLATE="${SCRIPT_DIR}/../templates/laravel/docker/fpm/Dockerfile.base"
FPM_VARIANT_TEMPLATE=""
RENDER_DOCKERFILE_SCRIPT="${SCRIPT_DIR}/render-dockerfile.sh"

if [[ "$DB_ENABLED" == "true" ]]; then
  case "${DB_TYPE_RAW,,}" in
    mysql)
      DB_KEY="mysql"
      DB_LABEL="MySQL"
      DB_WITH="mysql"
      DB_CONNECTION="mysql"
      DB_HOST="mysql"
      DB_PORT="3306"
      FPM_VARIANT_TEMPLATE="${SCRIPT_DIR}/../templates/laravel/docker/fpm/Dockerfile.mysql"
      ;;
    postgres|postgresql|pgsql)
      DB_KEY="pgsql"
      DB_LABEL="PostgreSQL"
      DB_WITH="pgsql"
      DB_CONNECTION="pgsql"
      DB_HOST="pgsql"
      DB_PORT="5432"
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

# Ensure the template files exist before continuing.
if [[ ! -f "$COMPOSE_TEMPLATE" || ! -f "$FPM_BASE_TEMPLATE" || ! -f "$NGINX_TEMPLATE" || ! -f "$RENDER_DOCKERFILE_SCRIPT" ]]; then
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

# Prevent overwriting existing files or directories.
if [[ -e "$APP_NAME" ]]; then
  echo "Error: path already exists: $APP_NAME" >&2
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

# Build the laravel.build URL (DB only; cache/mail are handled locally).
LARAVEL_BUILD_URL="https://laravel.build/${APP_NAME}"
if [[ -n "$DB_WITH" ]]; then
  LARAVEL_BUILD_URL="${LARAVEL_BUILD_URL}?with=${DB_WITH}"
fi

# Run the official Laravel build script with the requested options.
echo "[1/6] Installing Laravel (laravel.build)..."
if ! run_logged "Install Laravel" "curl -s \"$LARAVEL_BUILD_URL\" | bash"; then
  exit 1
fi
echo "      ✓ Project created: $APP_NAME"

# Move into the new project directory for cleanup work.
cd "$APP_NAME"

# Remove Sail files (compose config, Sail script, and Sail docker assets).
echo "[2/6] Removing Sail..."
log_note "Remove Sail artifacts"
rm -f compose.yaml docker-compose.yml vendor/bin/sail
rm -rf docker
echo "      ✓ Sail files removed"

# If Sail is listed as a dev dependency, remove it using Composer in a container.
if grep -q '"laravel/sail"' composer.json; then
  log_note "Remove laravel/sail dependency"
  if ! run_logged "Remove laravel/sail" "docker run --rm -u \"$(id -u):$(id -g)\" -v \"$PWD\":/app -w /app composer:2 composer remove laravel/sail --dev"; then
    exit 1
  fi
  echo "      ✓ laravel/sail removed from composer.json"
else
  # Some templates may not include Sail; in that case nothing to remove.
  echo "      ✓ laravel/sail not present"
fi

# Update a key in an env file or append it if missing.
update_env_value() {
  local env_file="$1"
  local env_key="$2"
  local env_value="$3"

  if [[ ! -f "$env_file" ]]; then
    return 0
  fi

  if grep -q "^${env_key}=" "$env_file"; then
    sed -i "s/^${env_key}=.*/${env_key}=${env_value}/" "$env_file"
  else
    echo "${env_key}=${env_value}" >> "$env_file"
  fi
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

# Copy minimal Docker files for nginx + php-fpm + chosen services.
echo "[3/6] Writing Docker setup..."
log_note "Copy minimal Docker files"
mkdir -p docker/nginx docker/fpm
cp "$NGINX_TEMPLATE" docker/nginx/default.conf
"$RENDER_DOCKERFILE_SCRIPT" "$FPM_BASE_TEMPLATE" "$FPM_VARIANT_TEMPLATE" "docker/fpm/Dockerfile"
cp "$COMPOSE_TEMPLATE" docker-compose.yml
echo "      ✓ docker-compose.yml + docker/ files copied"

# Align .env and .env.example with the selected DB service name and port.
echo "[4/6] Updating .env files..."
log_note "Update environment files"
if [[ "$DB_ENABLED" == "true" ]]; then
  DB_DEFAULT_NAME="$(sanitize_db_name "$APP_NAME")"
  update_env_value ".env" "DB_CONNECTION" "$DB_CONNECTION"
  update_env_value ".env" "DB_HOST" "$DB_HOST"
  update_env_value ".env" "DB_PORT" "$DB_PORT"
  update_env_value ".env" "DB_DATABASE" "$DB_DEFAULT_NAME"
  update_env_value ".env" "DB_USERNAME" "$DB_DEFAULT_NAME"
  update_env_value ".env" "DB_PASSWORD" "secret"
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
  update_env_value ".env" "CACHE_STORE" "redis"
  update_env_value ".env" "REDIS_HOST" "redis"
  update_env_value ".env" "REDIS_PORT" "6379"
  update_env_value ".env.example" "CACHE_STORE" "redis"
  update_env_value ".env.example" "REDIS_HOST" "redis"
  update_env_value ".env.example" "REDIS_PORT" "6379"
fi

# Align .env and .env.example with Mailpit when mail is enabled.
if [[ "$MAIL_ENABLED" == "true" ]]; then
  update_env_value ".env" "MAIL_MAILER" "smtp"
  update_env_value ".env" "MAIL_HOST" "mailpit"
  update_env_value ".env" "MAIL_PORT" "1025"
  update_env_value ".env" "MAIL_ENCRYPTION" "null"
  update_env_value ".env.example" "MAIL_MAILER" "smtp"
  update_env_value ".env.example" "MAIL_HOST" "mailpit"
  update_env_value ".env.example" "MAIL_PORT" "1025"
  update_env_value ".env.example" "MAIL_ENCRYPTION" "null"
fi
echo "      ✓ DB/Redis/Mail settings applied"

# Write a README tailored to the selected options.
echo "[5/6] Writing README..."
log_note "Write project README"
if ! write_project_readme "$PWD" "$APP_NAME" "$DB_KEY" "$CACHE_ENABLED" "$MAIL_ENABLED"; then
  echo "      ✗ README.md generation failed"
  LOG_KEEP="true"
  finalize_log
  exit 1
fi
echo "      ✓ README.md generated"

# Final confirmation and log cleanup.
echo "[6/6] Done"
echo "      Project ready at: $PWD"
finalize_log
