FROM php:8.3-fpm

ARG UID=1000
ARG GID=1000

# Install only the extensions needed for PostgreSQL.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev \
    && docker-php-ext-install pdo_pgsql \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user matching the host UID/GID.
RUN groupadd -g "${GID}" laravel \
    && useradd -u "${UID}" -g laravel -m laravel

WORKDIR /var/www/html
USER laravel
