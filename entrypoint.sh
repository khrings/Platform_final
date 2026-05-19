#!/bin/bash
set -e

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