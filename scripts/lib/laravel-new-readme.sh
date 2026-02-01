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
  local db_default_name=""
  local nvm_version=""
  local nvm_section=""
  if [[ -f "${project_dir}/.nvmrc" ]]; then
    nvm_version="$(cat "${project_dir}/.nvmrc" 2>/dev/null || true)"
  fi
  if [[ -n "$nvm_version" ]]; then
    nvm_section=$(cat <<EOF

## Node (NVM)
This project includes a \`.nvmrc\` pinned to Node ${nvm_version}. If you use
NVM, run:

\`\`\`bash
nvm install
nvm use
\`\`\`
EOF
)
  fi

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

  db_default_name="$(printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  if [[ -z "$db_default_name" ]]; then
    db_default_name="app"
  fi

  # Select the DB alias line and DB section based on the chosen DB.
  local db_alias_line="# No DB service enabled (SQLite by default)."
  local db_section=""
  if [[ "$db_key" == "mysql" ]]; then
    db_alias_line="alias dc-dbm='docker compose exec mysql'"
    db_section=$(cat <<EOF

## Database (MySQL)
Service name: \`mysql\`
Default credentials:
\`DB_DATABASE=${db_default_name}\`, \`DB_USERNAME=${db_default_name}\`, \`DB_PASSWORD=secret\`
(derived from the app name: lowercased and stripped to alphanumerics)

If you change DB credentials after the first boot, recreate the volume:
~~~bash
dc down -v
dc up -d
~~~

Example import:
~~~bash
dc-dbm mysql -u ${db_default_name} -p ${db_default_name} < /path/to/dump.sql
~~~

Interactive shell:
~~~bash
dc-dbm mysql -u ${db_default_name} -p ${db_default_name}
~~~

Useful commands (MySQL CLI):
~~~sql
SHOW DATABASES;
USE ${db_default_name};
SHOW TABLES;
DESCRIBE users;
SHOW INDEXES FROM users;
SELECT COUNT(*) FROM users;
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;
~~~
EOF
)
  elif [[ "$db_key" == "pgsql" ]]; then
    db_alias_line="alias dc-dbp='docker compose exec pgsql'"
    db_section=$(cat <<EOF

## Database (PostgreSQL)
Service name: \`pgsql\`
Default credentials:
\`DB_DATABASE=${db_default_name}\`, \`DB_USERNAME=${db_default_name}\`, \`DB_PASSWORD=secret\`
(derived from the app name: lowercased and stripped to alphanumerics)

If you change DB credentials after the first boot, recreate the volume:
~~~bash
dc down -v
dc up -d
~~~

Example import:
~~~bash
dc-dbp psql -U ${db_default_name} -d ${db_default_name} < /path/to/dump.sql
~~~

Interactive shell:
~~~bash
dc-dbp psql -U ${db_default_name} -d ${db_default_name}
~~~

Useful commands (psql):
~~~psql
\l           -- list databases
\c ${db_default_name}   -- connect
\dn          -- list schemas
\dt          -- list tables
\d users     -- describe table
\d+ users    -- describe table (detailed)
\di          -- list indexes
\conninfo    -- connection info
\q           -- quit
~~~

SQL examples (run after you connect to the database):
~~~sql
SELECT current_database();
SELECT COUNT(*) FROM users;
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;
~~~
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
Migrations run during setup. Re-run if needed (after setting the aliases below):

```bash
app artisan migrate
```
EOF
)
  fi

  # Write the README with the assembled sections.
  # Remove the default Laravel README first to ensure a full overwrite.
  local readme_path="${project_dir}/README.md"
  rm -f "$readme_path"

  {
    printf '# %s\n\n' "$app_name"
    printf 'Minimal Laravel app with Docker (%s).\n\n' "$services_desc"
    cat <<'EOF'
## Requirements
- Docker
- Docker Compose

## Quick Start
The project ships with a minimal `.env` created by the generator. Start
services with:

```bash
docker compose up -d
```

If `APP_KEY` is empty, generate it (after setting the aliases below):

```bash
app artisan key:generate
```

EOF
    printf '%s\n\n' "$quick_start_db"
    cat <<'EOF'
## Useful Aliases (bash/zsh)
Add to your ~/.bashrc or ~/.zshrc:

```bash
alias dc='docker compose'
alias dc-exec='docker compose exec fpm'
alias app='docker compose exec fpm php'
EOF
    printf '%s\n' "$db_alias_line"
    cat <<'EOF'
# Optional: alias weave='docker compose exec fpm php'
```

Reload your shell:

```bash
source ~/.bashrc
```

The commands below assume you have these aliases set.

## Environment Files (Envy)
This project ships with a minimal `.env`. To keep `.env.example` in sync with
your config files, use Envy:

```bash
# Add missing env keys based on config/env() usage
app artisan envy:sync

# Remove unused env keys from .env.example
app artisan envy:prune
```

If you regenerate `.env` from `.env.example`, make sure to preserve your
existing `APP_KEY` (or re-run `app artisan key:generate`).

EOF
    printf '%s\n' "$nvm_section"
    cat <<'EOF'
## Common Commands
```bash
# Laravel commands
app artisan migrate
app artisan tinker
app artisan test
app artisan dev:dump-server
app vendor/bin/phpunit

# Composer (inside fpm container)
app composer install
app composer update
app composer require vendor/package
app composer require --dev vendor/package

# Enter the PHP container
app /bin/sh
```

## Rebuild Images
```bash
# Rebuild the FPM image (pull latest base)
dc build --pull --no-cache fpm
dc up -d --force-recreate
```
EOF
    printf '%s' "$db_section"
    printf '%s' "$redis_section"
    printf '%s' "$mail_section"
    cat <<'EOF'

## Inspiration
> "Make it work, make it right, make it fast." -- Kent Beck
EOF
  } > "$readme_path"

  # Confirm the README was written successfully.
  if [[ ! -f "$readme_path" ]]; then
    return 1
  fi
}
