# LaraNew Upgrade SOP

This document is the standard operating procedure for reviewing and upgrading the tools that LaraNew installs or templates into generated Laravel projects.

LaraNew has two kinds of dependencies:

- Floating dependencies resolved when the generator runs, such as Laravel, Composer packages, and unpinned Docker tags.
- Pinned template dependencies in this repository, mainly Docker image tags and generated config defaults.

Prefer the latest LTS release when an upstream publishes an active LTS track; otherwise prefer the latest stable release. Record any major-version tradeoffs in the PR notes.

## 1. Prepare

Start from a clean understanding of the current repository state.

```bash
git status --short
grep -R "image:\|FROM \|composer:\|laravel.build\|composer require\|node" scripts templates README.md AGENTS.md
```

Required local tools for the checks below:

```bash
command -v curl
command -v jq
command -v docker
```

Optional but recommended:

```bash
command -v shellcheck
docker compose version
```

## 2. Inventory Current Versions

List every version or floating source LaraNew currently uses.

```bash
grep -R "image:" templates/laravel/compose
grep -R "^FROM " templates/laravel/docker/fpm
grep -R "composer:[0-9]\|composer require\|laravel.build" scripts
grep -R "Node\|node\|nvmrc" scripts README.md
```

Current upgrade surfaces to review:

- Laravel framework through `https://laravel.build/<app>` in `scripts/laravel-new.sh`.
- PHP FPM base image in `templates/laravel/docker/fpm/Dockerfile.base`.
- PHP extensions and OS build dependencies in `templates/laravel/docker/fpm/Dockerfile.base`, `Dockerfile.mysql`, and `Dockerfile.pgsql`.
- Composer CLI image uses in `scripts/laravel-new.sh` and `templates/laravel/docker/fpm/Dockerfile.base`.
- Nginx image tags in `templates/laravel/compose/*.yml`.
- MySQL image tags in `templates/laravel/compose/compose.mysql*.yml`.
- PostgreSQL image tags in `templates/laravel/compose/compose.pgsql*.yml`.
- Redis image tags in `templates/laravel/compose/*.cache*.yml`.
- Mailpit image tags in `templates/laravel/compose/*.mail*.yml`.
- Optional Node `.nvmrc` prompt and examples in `scripts/lib/laravel-new-node.sh` and `README.md`.
- Dev Composer packages installed by the generator: `worksome/envy` and `symfony/var-dumper`.

## 3. Check Laravel

LaraNew delegates project creation to `laravel.build`. The `laravel.build` URL returns an installer script, not a Laravel framework version. Use it to inspect installer behavior, then generate a disposable app to confirm the actual framework version.

First, inspect the installer script and confirm whether it pins Laravel or runs unpinned `laravel new`:

```bash
curl -fsSL https://laravel.build/version-check-placeholder \
  | grep -E 'laravelsail/.+-composer:latest|laravel new'
```

If the installer image changes, use the image from the script output in the disposable version check below. This example uses the current `laravelsail/php84-composer:latest` image:

```bash
mkdir -p /tmp/laranew-laravel-version-check
cd /tmp/laranew-laravel-version-check
rm -rf version-check-placeholder

docker run --rm --pull=always \
  -v "$PWD":/opt \
  -w /opt \
  laravelsail/php84-composer:latest \
  bash -lc 'laravel new version-check-placeholder --no-interaction && cd version-check-placeholder && php artisan --version && composer show laravel/framework'
```

Compare the generated framework version with the latest supported Laravel release:

```bash
curl -fsSL https://endoflife.date/api/laravel.json | jq '.[0]'
curl -fsSL https://repo.packagist.org/p2/laravel/framework.json \
  | jq -r '.packages["laravel/framework"]
    | map(select(.version_normalized | test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.0$")))
    | .[0]
    | [.version, .time, (.require.php // "")] | @tsv'
```

Review these links when the output suggests a major upgrade:

- https://laravel.com/docs/releases
- https://github.com/laravel/laravel/releases
- https://packagist.org/packages/laravel/framework

Decision criteria:

- If `laravel.build` still uses unpinned `laravel new`, LaraNew generally does not need a Laravel version bump.
- If `laravel.build` changes its installer image, command flags, default services, or generated files, regenerate a project and review cleanup assumptions in `scripts/laravel-new.sh`.
- If a new Laravel major changes `.env`, `routes/console.php`, Sail output, Vite defaults, or database defaults, update LaraNew cleanup and README generation accordingly.

## 4. Check PHP FPM

Current local pin lives in `templates/laravel/docker/fpm/Dockerfile.base`.

```bash
grep '^FROM php:' templates/laravel/docker/fpm/Dockerfile.base
curl -fsSL https://endoflife.date/api/php.json | jq '.[0:3]'
```

Confirm the Docker image tag exists and is actively pushed:

```bash
curl -fsSL https://registry.hub.docker.com/v2/repositories/library/php/tags/8.5-fpm | jq '{name,last_updated,tag_status}'
```

Review links:

- https://www.php.net/supported-versions.php
- https://endoflife.date/php
- https://hub.docker.com/_/php/tags

Decision criteria:

- Prefer the newest supported PHP minor that Laravel supports.
- Confirm Laravel's supported PHP range before bumping PHP.
- Recheck `docker-php-ext-install` extension names and required Debian packages when changing the base image.
- Confirm PECL Redis still builds against the target PHP version.

## 5. Check Composer

LaraNew uses `composer:2`, which floats within Composer major 2.

```bash
grep -R "composer:2" scripts templates
curl -fsSL https://endoflife.date/api/composer.json | jq '.[0:3]'
curl -fsSL https://registry.hub.docker.com/v2/repositories/library/composer/tags/2 | jq '{name,last_updated,tag_status}'
```

Review links:

- https://getcomposer.org/changelog/2.0.0
- https://endoflife.date/composer
- https://hub.docker.com/_/composer/tags

Decision criteria:

- Keep `composer:2` unless there is a reproducibility requirement to pin a minor or digest.
- Do not switch to Composer 3 until Laravel and installed packages explicitly support it.

## 6. Check Nginx

Nginx tags are repeated across every compose template.

```bash
grep -R "image: nginx:" templates/laravel/compose
curl -fsSL https://endoflife.date/api/nginx.json | jq '.[0:4]'
curl -fsSL https://registry.hub.docker.com/v2/repositories/library/nginx/tags/1.30-alpine | jq '{name,last_updated,tag_status}'
curl -fsSL https://registry.hub.docker.com/v2/repositories/library/nginx/tags/1.31-alpine | jq '{name,last_updated,tag_status}'
```

Review links:

- https://nginx.org/en/CHANGES
- https://endoflife.date/nginx
- https://hub.docker.com/_/nginx/tags

Decision criteria:

- Prefer the current stable Nginx Alpine tag for generated projects.
- Use mainline only if the repo intentionally tracks latest-mainline.
- After updating, make sure every compose template uses the same Nginx tag.

## 7. Check MySQL

MySQL tags are used only in the MySQL compose variants.

```bash
grep -R "image: mysql:" templates/laravel/compose
curl -fsSL https://endoflife.date/api/mysql.json | jq '.[0:6]'
curl -fsSL https://registry.hub.docker.com/v2/repositories/library/mysql/tags/9.7 | jq '{name,last_updated,tag_status}'
```

Review links:

- https://endoflife.date/mysql
- https://dev.mysql.com/doc/relnotes/mysql/
- https://hub.docker.com/_/mysql/tags

Decision criteria:

- Prefer the latest MySQL LTS for default generated apps.
- For major upgrades, review auth defaults, SQL mode changes, initialization env vars, and Laravel driver compatibility.
- Because generated projects may have local Docker volumes, document that existing generated apps need a dump/restore path before changing major DB versions.
- Recheck `templates/laravel/docker/fpm/Dockerfile.mysql` only if client library packages or PHP extension build requirements change.

## 8. Check PostgreSQL

PostgreSQL tags are used only in the PostgreSQL compose variants.

```bash
grep -R "image: postgres:" templates/laravel/compose
curl -fsSL https://endoflife.date/api/postgresql.json | jq '.[0:5]'
curl -fsSL https://registry.hub.docker.com/v2/repositories/library/postgres/tags/18-alpine | jq '{name,last_updated,tag_status}'
```

Review links:

- https://www.postgresql.org/support/versioning/
- https://endoflife.date/postgresql
- https://hub.docker.com/_/postgres/tags

Decision criteria:

- Prefer the latest stable PostgreSQL major for new generated apps unless compatibility concerns suggest staying one major back.
- For major upgrades, review volume compatibility and note that existing generated apps need `pg_dump`/restore instead of reusing old data directories.
- Recheck `templates/laravel/docker/fpm/Dockerfile.pgsql` only if `libpq-dev` or `pdo_pgsql` build requirements change.

## 9. Check Redis

Redis tags are used in the cache compose variants.

```bash
grep -R "image: redis:" templates/laravel/compose
curl -fsSL https://endoflife.date/api/redis.json | jq '.[0:6]'
curl -fsSL https://registry.hub.docker.com/v2/repositories/library/redis/tags/8-alpine | jq '{name,last_updated,tag_status}'
```

Review links:

- https://redis.io/docs/latest/operate/oss_and_stack/stack-with-enterprise/release-notes/
- https://endoflife.date/redis
- https://hub.docker.com/_/redis/tags

Decision criteria:

- Prefer the latest stable Redis Alpine tag for generated development projects.
- Confirm Laravel cache/session defaults still work with the target Redis major.
- Confirm the PHP `redis` PECL extension builds and loads in the FPM image.

## 10. Check Mailpit

Mailpit is currently unpinned as `axllent/mailpit`, so Docker pulls the latest tag unless the local cache is stale.

```bash
grep -R "image: axllent/mailpit" templates/laravel/compose
curl -fsSL https://api.github.com/repos/axllent/mailpit/releases/latest | jq -r '.tag_name, .published_at, .html_url'
curl -fsSL https://registry.hub.docker.com/v2/repositories/axllent/mailpit/tags/latest | jq '{name,last_updated,tag_status}'
```

Review links:

- https://github.com/axllent/mailpit/releases
- https://hub.docker.com/r/axllent/mailpit/tags

Decision criteria:

- Keep `axllent/mailpit` if the goal is always-latest local development tooling.
- Pin `axllent/mailpit:<version>` if reproducibility matters more than automatic updates.
- If pinning, update every mail compose variant consistently.

## 11. Check Node Guidance

LaraNew does not install Node. It optionally writes `.nvmrc` from the user-provided version.

```bash
grep -R "node\|Node\|nvmrc\|lts/" scripts README.md
curl -fsSL https://endoflife.date/api/nodejs.json | jq '.[0:6]'
```

Review links:

- https://nodejs.org/en/about/previous-releases
- https://endoflife.date/nodejs

Decision criteria:

- Keep accepting explicit versions and `lts/*`.
- Update examples and prompts when the recommended LTS changes.
- Do not force a Node version unless generated Laravel frontend tooling requires it.

## 12. Check Dev Composer Packages

The generator installs these packages dynamically:

- `worksome/envy`
- `symfony/var-dumper`

Check latest package versions and PHP/Laravel constraints:

```bash
curl -fsSL https://repo.packagist.org/p2/worksome/envy.json \
  | jq -r '.packages["worksome/envy"]
    | map(select(.version_normalized | test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.0$")))
    | .[0]
    | [.version, .time, (.require.php // ""), (.require["illuminate/contracts"] // "")] | @tsv'

curl -fsSL https://repo.packagist.org/p2/symfony/var-dumper.json \
  | jq -r '.packages["symfony/var-dumper"]
    | map(select(.version_normalized | test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.0$")))
    | .[0]
    | [.version, .time, (.require.php // "")] | @tsv'
```

Review links:

- https://packagist.org/packages/worksome/envy
- https://packagist.org/packages/symfony/var-dumper

Decision criteria:

- No repo change is usually needed because Composer resolves latest compatible versions during generation.
- If a package drops compatibility with current Laravel or PHP, either adjust PHP/Laravel first or pin the package with an explicit constraint.
- If package commands change, update the installer steps in `scripts/laravel-new.sh`.

## 13. Make Changes

Update only the files required by the chosen versions.

Common files:

- `templates/laravel/docker/fpm/Dockerfile.base`
- `templates/laravel/docker/fpm/Dockerfile.mysql`
- `templates/laravel/docker/fpm/Dockerfile.pgsql`
- `templates/laravel/compose/*.yml`
- `scripts/laravel-new.sh`
- `scripts/lib/laravel-new-node.sh`
- `scripts/lib/laravel-new-readme.sh`
- `README.md`
- `AGENTS.md`

After editing repeated compose image tags, verify consistency:

```bash
grep -R "image:" templates/laravel/compose | sort
```

Render the Dockerfile variants:

```bash
./scripts/render-dockerfile.sh templates/laravel/docker/fpm/Dockerfile.base \
  templates/laravel/docker/fpm/Dockerfile.mysql /tmp/Dockerfile.mysql

./scripts/render-dockerfile.sh templates/laravel/docker/fpm/Dockerfile.base \
  templates/laravel/docker/fpm/Dockerfile.pgsql /tmp/Dockerfile.pgsql
```

## 14. Static Validation

Run Bash syntax checks:

```bash
bash -n scripts/*.sh scripts/lib/*.sh
```

Run ShellCheck when available:

```bash
shellcheck scripts/*.sh scripts/lib/*.sh
```

Validate Docker Compose templates parse. Run these from a disposable generated project or from temporary directories containing the rendered files and minimal placeholders.

```bash
docker compose -f compose.yml config
```

## 15. Functional Validation Matrix

Generate projects in a disposable directory. Do not run this in the repository root unless the target app directory is intentionally disposable.

```bash
mkdir -p /tmp/laranew-upgrade-check
cd /tmp/laranew-upgrade-check
```

Minimum validation commands:

```bash
/path/to/LaraNew/scripts/laravel-new.sh app-none
/path/to/LaraNew/scripts/laravel-new.sh app-mysql -d MySQL
/path/to/LaraNew/scripts/laravel-new.sh app-pgsql -d PostgreSQL
/path/to/LaraNew/scripts/laravel-new.sh app-all-mysql -d MySQL -c -m --db-host-port 3307
/path/to/LaraNew/scripts/laravel-new.sh app-all-pgsql -d PostgreSQL -c -m --db-host-port 5433
```

For each generated project, check:

```bash
docker compose ps
docker compose exec -T fpm php -v
docker compose exec -T fpm php -m
docker compose exec -T fpm php artisan about
docker compose exec -T fpm php artisan migrate:status
```

When Redis is enabled:

```bash
docker compose exec -T redis redis-cli ping
docker compose exec -T fpm php artisan tinker --execute='cache()->put("laranew", "ok", 60); dump(cache()->get("laranew"));'
```

When Mailpit is enabled:

```bash
curl -fsS http://localhost:8025 >/dev/null
```

When MySQL is enabled:

```bash
docker compose exec -T mysql mysql --version
docker compose exec -T fpm php -m | grep pdo_mysql
```

When PostgreSQL is enabled:

```bash
docker compose exec -T pgsql postgres --version
docker compose exec -T fpm php -m | grep pdo_pgsql
```

Clean up disposable projects after validation:

```bash
docker compose down -v
```

Run cleanup in each generated project directory.

## 16. PR Notes

Document the upgrade decisions in the PR:

- Old version and new version for each changed component.
- Whether the target is latest stable, latest LTS, or latest mainline.
- Any major-version migration notes for generated projects with existing Docker volumes.
- Validation commands that passed.
- Validation that was not run and why.

## Quick Reference Commands

Check all endoflife.date metadata used by this SOP:

```bash
for component in laravel php composer nginx mysql postgresql redis nodejs; do
  printf '\n## %s\n' "$component"
  curl -fsSL "https://endoflife.date/api/${component}.json" | jq '.[0:3]'
done
```

Check common Docker tags:

```bash
for tag in \
  library/php:8.5-fpm \
  library/nginx:1.30-alpine \
  library/mysql:9.7 \
  library/postgres:18-alpine \
  library/redis:8-alpine \
  axllent/mailpit:latest; do
  repo="${tag%:*}"
  name="${tag##*:}"
  curl -fsSL "https://registry.hub.docker.com/v2/repositories/${repo}/tags/${name}" \
    | jq '{name,last_updated,tag_status}'
done
```

Check generated template pins after changes:

```bash
grep -R "image:" templates/laravel/compose | sort
grep -R "^FROM " templates/laravel/docker/fpm
```
