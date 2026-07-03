# Repository Guidelines

## Project Structure & Module Organization
This repository is a Bash-based generator for creating minimal, non-Sail Laravel projects.

- `scripts/laravel-new.sh`: Main entrypoint that orchestrates project creation.
- `scripts/lib/*.sh`: Sourced helpers for args parsing, logging, cleanup, Docker preflight, README generation, and Node version handling.
- `scripts/render-dockerfile.sh`: Renders the final FPM Dockerfile from templates.
- `templates/laravel/compose/`: Docker Compose variants (DB/cache/mail combinations).
- `templates/laravel/docker/`: Nginx + FPM Dockerfile templates.
- `templates/laravel/app/`: App-level template files copied into generated projects.

## Build, Test, and Development Commands
There is no build step for this repo; primary workflows are the generator scripts.

- Generate a project:
  ```bash
  ./scripts/laravel-new.sh my-app -d MySQL -c -m
  ```
- Render a Dockerfile (template tool):
  ```bash
  ./scripts/render-dockerfile.sh templates/laravel/docker/fpm/Dockerfile.base \
    templates/laravel/docker/fpm/Dockerfile.mysql /tmp/Dockerfile
  ```
- Syntax check all Bash scripts:
  ```bash
  bash -n scripts/*.sh scripts/lib/*.sh
  ```
- Lint Bash scripts when `shellcheck` is available:
  ```bash
  shellcheck scripts/*.sh scripts/lib/*.sh
  ```

## Coding Style & Naming Conventions
- Bash scripts use `set -euo pipefail` and `[[ ... ]]` conditionals.
- Indentation is 2 spaces; keep functions small and single-purpose.
- Use uppercase for exported globals (`APP_NAME`, `DB_ENABLED`) and lower_snake for locals.
- Template placeholders (e.g., `__DB_DEV_LIBS__`) should be preserved unless updating the render logic.

## Testing Guidelines
No automated tests exist in this repo. At minimum, run `bash -n scripts/*.sh scripts/lib/*.sh` and `shellcheck scripts/*.sh scripts/lib/*.sh` when available.

Validate functional changes by running the generator in a disposable directory and confirming the generated project boots via Docker Compose (`docker compose up -d --build`). This can be slow and requires Docker. If you cannot run Docker, note that in your PR.

For template-output changes, validate the affected service combinations where practical: no database, MySQL, PostgreSQL, Redis, and Mailpit.

## Upgrading Laravel & Docker Versions
When bumping the generated Laravel version, confirm the installer supports it and adjust the build URL or logic in `scripts/laravel-new.sh` if new params are required. Regenerate a project and confirm `composer.json` and `artisan` commands match.

For PHP/Docker upgrades, update the base image in `templates/laravel/docker/fpm/Dockerfile.base` and recheck extensions and build deps. Update service image tags in `templates/laravel/compose/*.yml` (nginx, mysql, postgres, redis, mailpit). If README output changes, update `scripts/lib/laravel-new-readme.sh`.

## Commit & Pull Request Guidelines
Recent history favors conventional prefixes such as `feat:`, `fix:`, and `docs:`; use that format going forward (short, imperative subjects).

PRs should include:
- A brief summary of changes and rationale.
- Example commands or screenshots when template output changes.
- Test notes (what was run, or “not run” with reason).

## Security & Configuration Tips
- Do not commit secrets or real credentials in templates.
- Keep port defaults consistent with the preflight checks (HTTP 80, DB ports, Redis, Mailpit).
