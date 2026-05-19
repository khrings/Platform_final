#!/bin/bash
set -e

# Check if running on Railway and set DATABASE_URL from Railway variables
if [ -n "$RAILWAY_TCP_PROXY_DOMAIN" ] && [ -n "$RAILWAY_TCP_PROXY_PORT" ]; then
    export DATABASE_URL="mysql://${MYSQLUSER}:${MYSQL_ROOT_PASSWORD}@${RAILWAY_TCP_PROXY_DOMAIN}:${RAILWAY_TCP_PROXY_PORT}/${MYSQL_DATABASE}?serverVersion=8.0.32&charset=utf8mb4"
    echo "Using Railway database: $RAILWAY_TCP_PROXY_DOMAIN:$RAILWAY_TCP_PROXY_PORT"
fi

echo "DATABASE_URL is set to: ${DATABASE_URL:0:50}..."

echo "Running database migrations..."
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration 2>&1 || echo "Migration warning (continuing anyway)"

echo "Clearing cache..."
php bin/console cache:clear || true

echo "Starting PHP-FPM..."
php-fpm -F &
PHP_PID=$!

echo "Waiting for PHP-FPM to start..."
sleep 2

echo "Starting Nginx..."
nginx -g "daemon off;"

wait $PHP_PID
