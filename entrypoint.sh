#!/bin/bash
set -e

# Output environment info for debugging
echo "=== Starting Platform Deployment ==="
echo "APP_ENV: ${APP_ENV:-prod}"
echo "APP_DEBUG: ${APP_DEBUG:-false}"

# Construct DATABASE_URL from Railway environment variables
if [ -n "${MYSQL_HOST}" ] && [ -n "${MYSQL_PORT}" ] && [ -n "${MYSQL_USER}" ] && [ -n "${MYSQL_PASSWORD}" ] && [ -n "${MYSQL_DB_NAME}" ]; then
    export DATABASE_URL="mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DB_NAME}?serverVersion=8.0.32&charset=utf8mb4"
    echo "Using Railway database: ${MYSQL_HOST}:${MYSQL_PORT}"
else
    echo "Warning: Railway MySQL variables not fully set. Using default DATABASE_URL"
fi

echo "DATABASE_URL is set to: ${DATABASE_URL:0:60}..."

# Ensure var directory has correct permissions
mkdir -p /app/var /app/public
chmod -R 775 /app/var
chown -R www-data:www-data /app/var /app/public

# Wait for database to be ready (if using Railway)
if [ -n "${MYSQL_HOST}" ]; then
    echo "Waiting for database to be ready..."
    attempt=0
    max_attempts=30
    while [ $attempt -lt $max_attempts ]; do
        if php /app/bin/console doctrine:query:sql "SELECT 1" > /dev/null 2>&1; then
            echo "✓ Database is ready!"
            break
        fi
        attempt=$((attempt + 1))
        echo "Database not ready, attempt $attempt/$max_attempts. Waiting..."
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "WARNING: Database connection timeout. Continuing anyway..."
    fi
fi

echo "Running database migrations..."
php /app/bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration 2>&1 || echo "Migration warning (continuing anyway)"

echo "Clearing cache..."
php /app/bin/console cache:clear --env=prod --no-debug || true

echo "Warming up cache..."
php /app/bin/console cache:warmup --env=prod --no-debug || true

echo "=== Starting PHP-FPM and Nginx ==="

# Start PHP-FPM with explicit configuration
php-fpm -F &
PHP_PID=$!

# Give PHP-FPM a moment to start
sleep 1

echo "PHP-FPM started with PID: $PHP_PID"

# Start Nginx in foreground (this will keep the container running)
echo "Starting Nginx..."
exec nginx -g "daemon off;"
