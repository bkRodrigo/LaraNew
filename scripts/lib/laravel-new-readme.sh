#!/usr/bin/env bash

# laravel-new-readme.sh
# README generation helpers for laravel-new.sh. This file is sourced by the main script.

# Write a project README that matches the selected services.
#
# Arguments:
#   $1  Project directory (where README.md will be written).
#   $2  App name (used as the README title).
#   $3  DB key: none | mysql | pgsql.
#   $4  Cache enabled: true | false.
#   $5  Mail enabled: true | false.
write_project_readme() {
  local project_dir="$1"
  local app_name="$2"
  local db_key="$3"
  local cache_enabled="$4"
  local mail_enabled="$5"

  # Build a short services description line for the intro.
  local services_desc="nginx + php-fpm"
  if [[ "$db_key" == "mysql" ]]; then
    services_desc+=" + MySQL"
  elif [[ "$db_key" == "pgsql" ]]; then
    services_desc+=" + PostgreSQL"
  fi
  if [[ "$cache_enabled" == "true" ]]; then
    services_desc+=" + Redis"
  fi
  if [[ "$mail_enabled" == "true" ]]; then
    services_desc+=" + Mailpit"
  fi

  # Select the DB alias line and DB section based on the chosen DB.
  local db_alias_line="# No DB service enabled (SQLite by default)."
  local db_section=""
  if [[ "$db_key" == "mysql" ]]; then
    db_alias_line="alias dc-db='docker compose exec mysql'"
    db_section=$(cat <<'EOF'

## Database (MySQL)
Service name: `mysql`

Example import:
```bash
dc-db mysql -u root -p < /path/to/dump.sql
```
EOF
)
  elif [[ "$db_key" == "pgsql" ]]; then
    db_alias_line="alias dc-db='docker compose exec pgsql'"
    db_section=$(cat <<'EOF'

## Database (PostgreSQL)
Service name: `pgsql`

Example import:
```bash
dc-db psql -U postgres -d laravel < /path/to/dump.sql
```
EOF
)
  else
    db_section=$(cat <<'EOF'

## Database (SQLite)
SQLite is enabled by default using `database/database.sqlite`.
EOF
)
  fi

  # Add a Redis section only when cache is enabled.
  local redis_section=""
  if [[ "$cache_enabled" == "true" ]]; then
    redis_section=$(cat <<'EOF'

## Redis
Redis runs on:

```bash
localhost:6379
```
EOF
)
  fi

  # Add a Mailpit section only when mail is enabled.
  local mail_section=""
  if [[ "$mail_enabled" == "true" ]]; then
    mail_section=$(cat <<'EOF'

## Mailpit
Mailpit UI:

```bash
http://localhost:8025
```
EOF
)
  fi

  # Tailor the Quick Start section depending on whether a DB is enabled.
  local quick_start_db=""
  if [[ "$db_key" == "none" ]]; then
    quick_start_db=$(cat <<'EOF'
SQLite is enabled by default; the database file lives at:

```bash
database/database.sqlite
```
EOF
)
  else
    quick_start_db=$(cat <<'EOF'
Then run migrations:

```bash
docker compose exec fpm php artisan migrate
```
EOF
)
  fi

  # Write the README with the assembled sections.
  # Remove the default Laravel README first to ensure a full overwrite.
  rm -f "${project_dir}/README.md"
  cat <<EOF >"${project_dir}/README.md"
# ${app_name}

Minimal Laravel app with Docker (${services_desc}).

## Requirements
- Docker
- Docker Compose

## Quick Start
```bash
cp .env.example .env
docker compose up -d
```

Then generate the application key:

```bash
docker compose exec fpm php artisan key:generate
```

${quick_start_db}

## Useful Aliases (bash/zsh)
Add to your `~/.bashrc` or `~/.zshrc`:

```bash
alias dc='docker compose'
alias dc-exec='docker compose exec fpm'
alias app='docker compose exec fpm php'
${db_alias_line}
# Optional: alias weave='docker compose exec fpm php'
```

Reload your shell:

```bash
source ~/.bashrc
```

## Common Commands
```bash
# Laravel commands
app artisan migrate
app artisan tinker
app artisan test

# Composer (inside fpm container)
dc-exec composer install
dc-exec composer update

# Enter the PHP container
dc-exec /bin/sh
```
${db_section}${redis_section}${mail_section}

## Inspiration
> "Make it work, make it right, make it fast." -- Kent Beck
EOF
}
