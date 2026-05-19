#!/bin/bash
set -e

# Output environment info for debugging
echo "=== Starting Platform Deployment ==="
echo "APP_ENV: ${APP_ENV:-prod}"
echo "APP_DEBUG: ${APP_DEBUG:-false}"

# Check if running on Railway and set DATABASE_URL from Railway variables
if [ -n "$RAILWAY_TCP_PROXY_DOMAIN" ] && [ -n "$RAILWAY_TCP_PROXY_PORT" ]; then
    export DATABASE_URL="mysql://${MYSQLUSER}:${MYSQL_ROOT_PASSWORD}@${RAILWAY_TCP_PROXY_DOMAIN}:${RAILWAY_TCP_PROXY_PORT}/${MYSQL_DATABASE}?serverVersion=8.0.32&charset=utf8mb4"
    echo "Using Railway database: $RAILWAY_TCP_PROXY_DOMAIN:$RAILWAY_TCP_PROXY_PORT"
fi

echo "DATABASE_URL is set to: ${DATABASE_URL:0:50}..."

# Ensure var directory has correct permissions
mkdir -p /app/var
chmod -R 775 /app/var
chown -R www-data:www-data /app/var

echo "Running database migrations..."
php /app/bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration 2>&1 || echo "Migration warning (continuing anyway)"

echo "Clearing cache..."
php /app/bin/console cache:clear --env=prod --no-debug || true

echo "Warming up cache..."
php /app/bin/console cache:warmup --env=prod --no-debug || true

echo "Starting PHP-FPM and Nginx..."

# Start PHP-FPM in background
php-fpm -F &
PHP_PID=$!

# Start Nginx in foreground
nginx -g "daemon off;"
