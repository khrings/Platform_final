# Platform Deployment Guide - Complete Walkthrough

## 1. DOCKERFILE SETUP (1–2 mins)

### Overview
The Dockerfile uses a multi-stage build pattern to optimize the final image size and security.

### Stage 1: Builder
```dockerfile
FROM php:8.3-fpm as builder
WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \
    git unzip curl nodejs npm \
    && docker-php-ext-install pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

# Copy and install dependencies
COPY composer.json composer.lock ./
RUN composer install --no-interaction --no-scripts --optimize-autoloader

# Copy application
COPY . .

# Build PHP assets and warm cache
RUN php bin/console importmap:install --no-interaction
RUN php bin/console cache:warmup --env=prod --no-debug || true
```

**Key Points:**
- Uses PHP 8.3 FPM as base
- Installs Composer for PHP dependency management
- Pre-installs Node.js for front-end asset compilation
- Caches dependencies for faster rebuilds

### Stage 2: Runtime
```dockerfile
FROM php:8.3-fpm as runtime
WORKDIR /app

# Install Nginx and runtime dependencies
RUN apt-get update && apt-get install -y \
    nginx curl \
    && docker-php-ext-install pdo pdo_mysql

# Copy application from builder
COPY --from=builder /app /app

# Setup permissions
RUN mkdir -p /app/var /app/public
RUN chown -R www-data:www-data /app
RUN chmod -R 775 /app/var /app/public
```

**Key Points:**
- Slim runtime image (builder stage discarded)
- Includes Nginx for reverse proxy
- Sets proper file permissions for PHP-FPM user (`www-data`)

### PHP-FPM Configuration
```dockerfile
RUN mkdir -p /usr/local/etc/php-fpm.d /var/run/php-fpm && \
    echo '[global]' > /usr/local/etc/php-fpm.d/zzz-app.conf && \
    echo 'daemonize = no' >> /usr/local/etc/php-fpm.d/zzz-app.conf && \
    echo '[www]' >> /usr/local/etc/php-fpm.d/zzz-app.conf && \
    echo 'listen = 127.0.0.1:9000' >> /usr/local/etc/php-fpm.d/zzz-app.conf && \
    echo 'user = www-data' >> /usr/local/etc/php-fpm.d/zzz-app.conf && \
    echo 'group = www-data' >> /usr/local/etc/php-fpm.d/zzz-app.conf
```

**Why This Matters:**
- PHP-FPM listens on `127.0.0.1:9000` (loopback, secure)
- Runs as `www-data` user for proper permissions
- `daemonize = no` keeps process in foreground (required for Docker)

### Health Check
```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/ || exit 1
```

**What It Does:**
- Every 10 seconds, attempts to fetch the home page
- If 3 consecutive checks fail, marks container as unhealthy
- Railway uses this to auto-restart if needed

---

## 2. NGINX CONFIGURATION (1–2 mins)

### Main Configuration (`nginx-main.conf`)
```nginx
user www-data;
worker_processes auto;  # Auto-detect CPU cores

events {
    worker_connections 768;  # Max connections per worker
}

http {
    sendfile on;           # Efficient static file serving
    tcp_nopush on;         # Optimize TCP packets
    tcp_nodelay on;        # Low-latency communication
    keepalive_timeout 65;  # Connection timeout
    
    gzip on;  # Enable compression for responses
    
    include /etc/nginx/conf.d/*.conf;  # Load app config
}
```

### Application Configuration (`nginx.conf`)
```nginx
server {
    listen 80 default_server;
    root /app/public;
    index index.php;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Serve static assets (CSS, JS) with long cache
    location ~ ^/assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }
    
    # Main routing: all requests go through index.php
    location / {
        try_files $uri $uri/ /index.php$is_args$args;
    }
    
    # PHP-FPM handler
    location ~ ^/index\.php {
        fastcgi_pass 127.0.0.1:9000;  # Connect to PHP-FPM
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        include fastcgi_params;
        
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        
        # Pass environment to PHP
        fastcgi_param APP_ENV prod;
        fastcgi_param APP_DEBUG 0;
        
        # Timeouts for long-running requests
        fastcgi_read_timeout 60s;
        fastcgi_connect_timeout 60s;
    }
    
    # Deny direct access to PHP files (security)
    location ~ \.php$ {
        return 404;
    }
}
```

### Request Flow
```
Browser Request → Nginx (Port 80)
    ↓
Routes to /index.php via FastCGI
    ↓
PHP-FPM (Port 9000) ← Processes request
    ↓
MySQL Database ← Queries data
    ↓
PHP renders response
    ↓
Nginx sends to Browser
```

---

## 3. ENVIRONMENT VARIABLE SETUP (1 min)

### Local Development (`.env`)
```bash
APP_ENV=prod
APP_DEBUG=0
APP_SECRET=ChangeMe123!ChangeMe123!ChangeMe123!ChangeMe123
DATABASE_URL="mysql://app:app_password@127.0.0.1:3310/app?serverVersion=8.0.32&charset=utf8mb4"
```

### Railway Production Variables
**Set these in Railway Dashboard → Project Settings:**

```
APP_ENV=prod                    # Production mode
APP_DEBUG=0                     # Disable debug mode
APP_SECRET=<secure-random>      # Generate with: php -r 'echo bin2hex(random_bytes(16));'
MYSQL_HOST=<railway-host>       # Auto from MySQL plugin
MYSQL_PORT=3306                 # Auto from MySQL plugin
MYSQL_USER=<railway-user>       # Auto from MySQL plugin
MYSQL_PASSWORD=<railway-pass>   # Auto from MySQL plugin
MYSQL_DB_NAME=<railway-db>      # Auto from MySQL plugin
```

### How entrypoint.sh Constructs DATABASE_URL
```bash
# If Railway environment variables exist, build the connection string
if [ -n "${MYSQL_HOST}" ] && [ -n "${MYSQL_PORT}" ] && \
   [ -n "${MYSQL_USER}" ] && [ -n "${MYSQL_PASSWORD}" ] && \
   [ -n "${MYSQL_DB_NAME}" ]; then
    
    export DATABASE_URL="mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DB_NAME}?serverVersion=8.0.32&charset=utf8mb4"
fi
```

**Why This Matters:**
- Railway provides each plugin's credentials as environment variables
- The script dynamically constructs the connection URL at startup
- Allows same Dockerfile to work in local Docker and Railway

---

## 4. DEPLOYMENT PROCESS WALKTHROUGH (2–3 mins)

### Step 1: Local Development
```bash
# Start local MySQL with Docker Compose
docker-compose up -d

# Run migrations
php bin/console doctrine:migrations:migrate

# Test locally
symfony serve

# Access at: http://localhost:8000
# Products at: http://localhost:8000/product
```

### Step 2: Push to GitHub
```bash
git add .
git commit -m "Deploy to Railway"
git push origin master
```

### Step 3: Railway Automatic Deployment
**What Railway Does (Automatically):**

1. **Detects Push**
   - GitHub webhook triggers Railway build
   
2. **Builds Docker Image**
   - Executes Dockerfile multi-stage build
   - Downloads dependencies
   - Optimizes for production
   
3. **Creates Container**
   - Runs `entrypoint.sh` script
   - Sets up file permissions
   - Constructs DATABASE_URL from variables
   
4. **Runs Migrations**
   ```bash
   php bin/console doctrine:migrations:migrate --no-interaction
   ```
   
5. **Warms Cache**
   ```bash
   php bin/console cache:clear --env=prod --no-debug
   php bin/console cache:warmup --env=prod --no-debug
   ```
   
6. **Starts Services**
   - PHP-FPM starts listening on 127.0.0.1:9000
   - Nginx starts listening on 0.0.0.0:80
   - Railway's reverse proxy routes traffic to Nginx
   
7. **Health Check**
   - Every 10 seconds, tries to access `/`
   - If 3 checks fail, restarts container

### Step 4: Access Deployed Application
```
https://platformfinal-production.up.railway.app/           # Home
https://platformfinal-production.up.railway.app/product    # Products
```

---

## 5. FINAL PROOF - DEPLOYMENT VERIFICATION (1–2 mins)

### Run This Verification Script

```bash
#!/bin/bash

echo "=========================================="
echo "Platform Deployment Verification"
echo "=========================================="
echo ""

# Set the production URL
PROD_URL="https://platformfinal-production.up.railway.app"

echo "🚀 Testing Production Deployment"
echo "   URL: $PROD_URL"
echo ""

# Test 1: Home page
echo "📍 Test 1: Home Page"
echo "   Fetching: $PROD_URL/"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL/")
if [ "$RESPONSE" = "200" ]; then
    echo "   ✅ Status: $RESPONSE - SUCCESS"
else
    echo "   ❌ Status: $RESPONSE - FAILED"
fi
echo ""

# Test 2: Products page
echo "📍 Test 2: Products Page"
echo "   Fetching: $PROD_URL/product"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$PROD_URL/product")
if [ "$RESPONSE" = "200" ]; then
    echo "   ✅ Status: $RESPONSE - SUCCESS"
else
    echo "   ❌ Status: $RESPONSE - FAILED"
fi
echo ""

# Test 3: Database connectivity
echo "📍 Test 3: Database Connection"
echo "   Checking: Application health indicator"
HOME_RESPONSE=$(curl -s "$PROD_URL/" | grep -o "Database connection is working")
if [ ! -z "$HOME_RESPONSE" ]; then
    echo "   ✅ Database: Connected"
else
    echo "   ⚠️  Could not verify database status from HTML"
fi
echo ""

# Test 4: Get response headers
echo "📍 Test 4: Response Headers (Security)"
echo "   Checking: Security headers"
HEADERS=$(curl -s -i "$PROD_URL/" | head -20)
if echo "$HEADERS" | grep -q "X-Frame-Options"; then
    echo "   ✅ X-Frame-Options: Present"
fi
if echo "$HEADERS" | grep -q "X-Content-Type-Options"; then
    echo "   ✅ X-Content-Type-Options: Present"
fi
echo ""

echo "=========================================="
echo "✅ Deployment Verification Complete"
echo "=========================================="
```

### Example Output
```
==========================================
Platform Deployment Verification
==========================================

🚀 Testing Production Deployment
   URL: https://platformfinal-production.up.railway.app

📍 Test 1: Home Page
   Fetching: https://platformfinal-production.up.railway.app/
   ✅ Status: 200 - SUCCESS

📍 Test 2: Products Page
   Fetching: https://platformfinal-production.up.railway.app/product
   ✅ Status: 200 - SUCCESS

📍 Test 3: Database Connection
   Checking: Application health indicator
   ✅ Database: Connected

📍 Test 4: Response Headers (Security)
   Checking: Security headers
   ✅ X-Frame-Options: Present
   ✅ X-Content-Type-Options: Present

==========================================
✅ Deployment Verification Complete
==========================================
```

---

## Architecture Summary

```
┌─────────────────────────────────────────────────┐
│          User's Web Browser                      │
└────────────────────┬────────────────────────────┘
                     │ HTTPS Request
                     ▼
┌─────────────────────────────────────────────────┐
│      Railway Load Balancer / Reverse Proxy       │
│      (Handles SSL/TLS, routing)                  │
└────────────────────┬────────────────────────────┘
                     │ HTTP (Internal)
                     ▼
┌─────────────────────────────────────────────────┐
│              Nginx (Port 80)                     │
│  ┌───────────────────────────────────────────┐  │
│  │ Routes requests → index.php               │  │
│  │ Serves static assets (CSS, JS, images)   │  │
│  │ FastCGI proxy to PHP-FPM                  │  │
│  └──────────────┬──────────────────────────┘  │
└─────────────────┼──────────────────────────────┘
                  │ FastCGI (Port 9000)
                  ▼
┌─────────────────────────────────────────────────┐
│          PHP-FPM (Port 9000)                    │
│  ┌───────────────────────────────────────────┐  │
│  │ Executes PHP code                         │  │
│  │ Loads Symfony application                 │  │
│  │ Processes routes & business logic         │  │
│  └──────────────┬──────────────────────────┘  │
└─────────────────┼──────────────────────────────┘
                  │ SQL
                  ▼
┌─────────────────────────────────────────────────┐
│         Railway MySQL Database                  │
│  ┌───────────────────────────────────────────┐  │
│  │ Stores: Products, Users, Migrations       │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

---

## Key Files Summary

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build: builder stage (compile) → runtime stage (optimized) |
| `entrypoint.sh` | Startup script: migrations, permissions, start PHP-FPM + Nginx |
| `nginx-main.conf` | Nginx worker configuration |
| `nginx.conf` | Nginx server configuration + routing |
| `.env` | Environment variables (local defaults) |
| `config/routes.yaml` | Symfony routing configuration (points to controllers) |
| `docker-compose.yaml` | Local MySQL + app setup for development |

---

## Troubleshooting Guide

### Issue: 500 Error
**Check:** File permissions in `/app/var/cache`
```bash
docker-compose exec app ls -la /app/var/
```
**Fix:** Run entrypoint.sh permission fixes

### Issue: Database Connection Failed
**Check:** Railway environment variables set
```
MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB_NAME
```

### Issue: Routes Not Found (404)
**Check:** `config/routes.yaml` points to correct controller path
```yaml
controllers:
    resource: ../../src/Controller
    type: attribute
```

### Issue: Asset/CSS Not Loading
**Check:** Nginx static asset location configured
```nginx
location ~ ^/assets/ {
    expires 1y;
    try_files $uri =404;
}
```

---

## Conclusion

Your **Symfony Platform Technology Project** is now:
✅ Running on Railway production
✅ Connected to Railway MySQL database
✅ Using Nginx + PHP-FPM architecture
✅ Serving both home (`/`) and products (`/product`) routes
✅ Secured with headers and proper permissions
✅ Auto-scaling with health checks

**Deployment URL:** https://platformfinal-production.up.railway.app
