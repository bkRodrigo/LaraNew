# Laravel New (Minimal, Non-Sail)

This repo provides a small helper script that scaffolds a new Laravel app using
the official Docker-based installer and then removes Laravel Sail. It also
copies in a minimal Docker setup (nginx + php-fpm + optional DB/Redis/Mailpit)
so you can run the app without Sail.

## Requirements

- Docker
- curl

## Install

Clone this repo and make the script executable:

```bash
git clone <your-repo-url>
cd brewkrafts
chmod +x scripts/laravel-new.sh
```

## Add an alias

Add this to your `~/.bashrc` (or `~/.bash_profile`):

```bash
alias laravel-new='/path/to/brewkrafts/scripts/laravel-new.sh'
```

Reload your shell:

```bash
source ~/.bashrc
```

## Usage

```bash
laravel-new <AppName> [-d <MySQL|PostgreSQL>] [-c] [-m]
```

Parameters:
- `AppName`: Project directory name to create.

Options:
- `-d`, `-database`, `--database`: Include a database (`MySQL` or `PostgreSQL`).
- `-c`, `-cache`, `--cache`: Include Redis.
- `-m`, `-mail`, `--mail`: Include Mailpit.

Examples:

```bash
laravel-new my-app
laravel-new my-app -d PostgreSQL
laravel-new my-app -d MySQL -c -m
```

## What it does

1. Uses `laravel.build` to create a fresh Laravel app (DB only if requested).
2. Removes Laravel Sail files (`compose.yaml`, `vendor/bin/sail`, `docker/`).
3. Copies in minimal Docker files from `templates/laravel/`.
4. If no DB is selected, sets SQLite defaults and creates `database/database.sqlite`.
5. Updates `.env` and `.env.example` with DB/Redis/Mailpit settings as needed.
6. Removes the `laravel/sail` dependency using Composer inside a Docker container.

## Debugging

If the installer fails, a full log is saved to `.laravel-new.log` inside the
project directory. On success, the log file is deleted.

## Templates

The minimal Docker files live in:

- `templates/laravel/compose/` (prebuilt docker-compose variants)
- `templates/laravel/docker/nginx/default.conf`
- `templates/laravel/docker/fpm/Dockerfile.base` (base template with placeholders)
- `templates/laravel/docker/fpm/Dockerfile.mysql` (MySQL variant values)
- `templates/laravel/docker/fpm/Dockerfile.pgsql` (PostgreSQL variant values)
- `scripts/render-dockerfile.sh` (renders the final Dockerfile)
