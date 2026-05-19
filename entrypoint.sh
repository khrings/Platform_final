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
chown -R www-data:www-data /app/var /app/public

# Wait for database to be ready (if using Railway)
if [ -n "$DATABASE_URL" ]; then
    echo "Waiting for database to be ready..."
    attempt=0
    max_attempts=30
    while [ $attempt -lt $max_attempts ]; do
        if php /app/bin/console doctrine:query:sql "SELECT 1" > /dev/null 2>&1; then
            echo "Database is ready!"
            break
        fi
        attempt=$((attempt + 1))
        echo "Database not ready, attempt $attempt/$max_attempts. Waiting..."
        sleep 2
    done
fi

echo "Running database migrations..."
php /app/bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration 2>&1 || echo "Migration warning (continuing anyway)"

echo "Clearing cache..."
php /app/bin/console cache:clear --env=prod --no-debug || true

echo "Warming up cache..."
php /app/bin/console cache:warmup --env=prod --no-debug || true

echo "=== Starting PHP-FPM and Nginx ==="

# Create PHP-FPM configuration for listening on 127.0.0.1:9000
mkdir -p /usr/local/etc/php-fpm.d

# Start PHP-FPM with explicit configuration
php-fpm -F &
PHP_PID=$!

# Give PHP-FPM a moment to start
sleep 1

# Verify PHP-FPM is listening
if ! netstat -tuln 2>/dev/null | grep -q ":9000"; then
    echo "Warning: PHP-FPM may not be listening on port 9000"
fi

echo "PHP-FPM started with PID: $PHP_PID"

# Start Nginx in foreground (this will keep the container running)
echo "Starting Nginx..."
exec nginx -g "daemon off;"
