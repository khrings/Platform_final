#!/bin/bash
set -e

# Check if running on Railway and set DATABASE_URL from Railway variables
if [ -n "$RAILWAY_TCP_PROXY_DOMAIN" ]; then
    export DATABASE_URL="mysql://${MYSQL_USER}:${MYSQL_ROOT_PASSWORD}@${RAILWAY_TCP_PROXY_DOMAIN}:${RAILWAY_TCP_PROXY_PORT}/${MYSQL_DATABASE}"
    echo "Using Railway database connection"
fi

echo "Running database migrations..."
php bin/console doctrine:migrations:migrate --no-interaction || true
echo "Starting PHP-FPM..."
php-fpm -F &
PHP_PID=$!
echo "Waiting for PHP-FPM to start..."
sleep 2
echo "Starting Nginx..."
nginx -g "daemon off;"
wait $PHP_PID