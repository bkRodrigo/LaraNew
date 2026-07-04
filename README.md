# Laravel New (Minimal, Non-Sail)

This repo provides a small helper script that scaffolds a new Laravel app using
the official Docker-based installer and then removes Laravel Sail. It also
copies in a minimal Docker setup (nginx + php-fpm + optional DB/Redis/Mailpit)
so you can run the app without Sail.

## Requirements

- Docker
- curl

On Windows, run the script from a WSL distro and make sure Docker is available
there, for example through Docker Desktop with WSL integration enabled.

For development or validation work, install ShellCheck so Bash scripts can be
linted consistently on Linux, macOS, and Windows with WSL.

Linux / WSL (Debian or Ubuntu):

```bash
sudo apt update
sudo apt install shellcheck
```

macOS with Homebrew:

```bash
brew install shellcheck
```

Other Linux distributions:

```bash
# Fedora
sudo dnf install ShellCheck

# Arch
sudo pacman -S shellcheck
```

## Install

Clone this repo and make the script executable:

```bash
git clone <your-repo-url>
cd LaraNew
chmod +x scripts/laravel-new.sh
```

You can run the script directly from the repository with
`./scripts/laravel-new.sh`, or use one of the reusable shell setup options below.

## Add an alias

Add this to your `~/.bashrc` (or `~/.bash_profile`):

```bash
alias laravel-new='/path/to/LaraNew/scripts/laravel-new.sh'
```

Reload your shell:

```bash
source ~/.bashrc
```

## Add a symlink on PATH

Alternatively, create a symlink named `laravel-new` in a directory on your
`PATH`:

```bash
mkdir -p ~/bin/executables
ln -s /path/to/LaraNew/scripts/laravel-new.sh ~/bin/executables/laravel-new
```

If needed, add that directory to your shell startup file:

```bash
export PATH="$HOME/bin/executables:$PATH"
```

## Usage

```bash
laravel-new <AppName> [-d <MySQL|PostgreSQL>] [-c] [-m] [-n <version>] [--db-host-port <port>]
```

Parameters:
- `AppName`: Project directory name to create.

Options:
- `-d`, `-database`, `--database`: Include a database (`MySQL` or `PostgreSQL`).
- `-c`, `-cache`, `--cache`: Include Redis.
- `-m`, `-mail`, `--mail`: Include Mailpit.
- `-n`, `--node`, `--node-version`: Optional Node version to write into `.nvmrc`.
- `--db-host-port`: Optional host port for the database service.

## Interactive Prompts

Interactive runs ask for omitted optional services before generating the project.
Passing a flag skips the corresponding prompt; non-interactive runs keep
defaults (`no database`, Redis disabled, Mailpit disabled).

For example, `laravel-new my-app` prompts for every optional service:

```text
Configure optional services:

Database
  1) None
  2) MySQL
  3) PostgreSQL
Choose Database [1]:
Enable Redis cache? [y/N]
Enable Mailpit? [y/N]

Selected options:
  AppName:        my-app
  Database:       No database
  Redis cache:    disabled
  Mailpit:        disabled
  Compose output: compose.yml
  Compose template: compose.none.yml
  FPM template:   Dockerfile.base
  FPM variant:    none

Continue? [Y/n]
```

Partial flags skip only the choices they specify. For example,
`laravel-new my-app -d MySQL` skips the database prompt but still asks whether
to enable Redis and Mailpit.

## Preflight Checks

Before doing any work, the script verifies:
- The target project directory does not already exist.
- Docker has enough free disk space (default 5GB). Override with `DOCKER_MIN_FREE_GB`.
- Required host ports are available for HTTP, DB, Redis, and Mailpit.
- If a default host port is busy, the script tries up to 50 reasonable alternatives before prompting.

## Host Ports

Generated projects keep container ports stable and publish host ports through
`.env` `FORWARD_*` values. The generator writes the selected local host ports to
`.env`, while `.env.example` documents the conventional defaults:

- `FORWARD_HTTP_PORT=80`
- `FORWARD_DB_PORT=3306` or `5432` when a database is enabled
- `FORWARD_REDIS_PORT=6379` when Redis is enabled
- `FORWARD_MAILPIT_SMTP_PORT=1025` when Mailpit is enabled
- `FORWARD_MAILPIT_DASHBOARD_PORT=8025` when Mailpit is enabled

You can change these in a generated project's `.env` without forcing the same
local ports on other developers.

Examples:

```bash
laravel-new my-app
laravel-new my-app -d PostgreSQL
laravel-new my-app -d PostgreSQL --db-host-port 5433
laravel-new my-app -d MySQL -c -m
laravel-new my-app -n 24
```

## Node (NVM)

If you provide a Node version (via `-n` or the interactive prompt), the
generator writes a `.nvmrc`. Use:

```bash
nvm install
nvm use
```

## Project Creation Script

`scripts/laravel-new.sh` performs the full bootstrap:

1. Uses `laravel.build` to create a fresh Laravel app (DB only if requested).
2. Removes Laravel Sail files (`compose.yaml`, `vendor/bin/sail`, `docker/`).
3. Removes the `laravel/sail` dependency using Composer inside a Docker container.
4. Installs `worksome/envy` and publishes its config for `.env.example` hygiene.
5. Installs `symfony/var-dumper` (dev) and wires up `dev:dump-server`.
6. Prompts for omitted optional services during interactive runs.
7. Selects the right compose template based on DB/cache/mail options.
8. Renders `docker/fpm/Dockerfile` from the base template plus the DB variant.
9. Copies in minimal Docker files from `templates/laravel/`.
10. Optionally writes a `.nvmrc` when a Node version is provided (flag or prompt).
11. If no DB is selected, sets SQLite defaults and creates `database/database.sqlite`.
12. If a DB is selected, sets `DB_DATABASE` and `DB_USERNAME` to the sanitized app
    name (lowercase, alphanumeric only), and `DB_PASSWORD=secret`.
13. Rewrites `.env` and `.env.example` to a minimal baseline (preserving `APP_KEY`)
    and then applies DB/Redis/Mailpit settings plus host-port `FORWARD_*` values.
14. Prunes `.env.example` using Envy (via the Composer container, no Compose needed).
15. Checks available Docker disk space and errors if it's too low (override with `DOCKER_MIN_FREE_GB`).
16. Runs `docker compose down -v` and `docker compose up -d --build` for a clean start,
    retrying likely transient apt/package mirror failures and optionally prompting for
    a one-time `apt-get --fix-missing` recovery attempt.
17. Runs database migrations with retries.
18. Writes a project README tailored to selected services.

## Development Validation

There is no build step for this repository. Before opening a PR, run:

```bash
bash -n scripts/*.sh scripts/lib/*.sh
shellcheck scripts/*.sh scripts/lib/*.sh
```

For functional changes, generate a project in a disposable directory and confirm
Docker Compose can build and start it. Template-output changes should be checked
against the affected service combinations where practical: no database, MySQL,
PostgreSQL, Redis, and Mailpit.

For framework, Docker image, database, Redis, Mailpit, Node, or generated tooling
upgrades, follow `docs/upgrade-laranew.md`.

## Debugging

If the installer fails, a full log is saved to `.laravel-new.log` inside the
project directory. On success, the log file is deleted.

## Templates

The minimal Docker files live in:

- `templates/laravel/compose/` (prebuilt Compose variants copied to generated projects as `compose.yml`)
- `templates/laravel/docker/nginx/default.conf`
- `templates/laravel/docker/fpm/Dockerfile.base` (base template with placeholders)
- `templates/laravel/docker/fpm/Dockerfile.mysql` (MySQL variant values)
- `templates/laravel/docker/fpm/Dockerfile.pgsql` (PostgreSQL variant values)
- `scripts/render-dockerfile.sh` (renders the final Dockerfile)
- `scripts/lib/laravel-new-compose-recovery.sh` (Compose build recovery helpers)
- `scripts/lib/laravel-new-docker-preflight.sh` (Docker preflight checks)
