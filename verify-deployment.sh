#!/bin/bash

# ===================================================================
# Platform Deployment Verification Script
# Use this to verify all components are working correctly
# ===================================================================

echo "================================"
echo "Platform Deployment Verification"
echo "================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counter for results
PASSED=0
FAILED=0

# Function to test a condition
test_condition() {
    local test_name=$1
    local condition=$2
    
    if eval "$condition"; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        ((FAILED++))
    fi
}

# ===================================================================
# 1. DOCKERFILE CHECKS
# ===================================================================
echo ""
echo "1. Dockerfile Configuration"
echo "----------------------------"

test_condition "Dockerfile exists" "[ -f Dockerfile ]"
test_condition "Contains PHP 8.3 FPM" "grep -q 'php:8.3-fpm' Dockerfile"
test_condition "Installs PDO MySQL" "grep -q 'pdo_mysql' Dockerfile"
test_condition "Installs Nginx" "grep -q 'nginx' Dockerfile"
test_condition "Configures PHP-FPM port 9000" "grep -q '127.0.0.1:9000' Dockerfile"
test_condition "Has health check" "grep -q 'HEALTHCHECK' Dockerfile"
test_condition "Exposes port 80" "grep -q 'EXPOSE 80' Dockerfile"

# ===================================================================
# 2. NGINX CONFIGURATION CHECKS
# ===================================================================
echo ""
echo "2. Nginx Configuration"
echo "----------------------"

test_condition "nginx.conf exists" "[ -f nginx.conf ]"
test_condition "Listens on port 80" "grep -q 'listen 80' nginx.conf"
test_condition "Document root is /app/public" "grep -q 'root /app/public' nginx.conf"
test_condition "Fastcgi passes to 127.0.0.1:9000" "grep -q 'fastcgi_pass 127.0.0.1:9000' nginx.conf"
test_condition "Has security headers" "grep -q 'X-Frame-Options' nginx.conf"
test_condition "Routes requests through index.php" "grep -q 'try_files.*index.php' nginx.conf"

# ===================================================================
# 3. ENVIRONMENT CONFIGURATION
# ===================================================================
echo ""
echo "3. Environment Configuration"
echo "----------------------------"

test_condition ".env file exists" "[ -f .env ]"
test_condition "APP_ENV set to prod" "grep -q 'APP_ENV=prod' .env"
test_condition "APP_DEBUG set to 0" "grep -q 'APP_DEBUG=0' .env"
test_condition "APP_SECRET configured" "grep -q 'APP_SECRET=' .env"
test_condition "DATABASE_URL configured" "grep -q 'DATABASE_URL=' .env"
test_condition "Uses MySQL database" "grep -q 'mysql://' .env"

# ===================================================================
# 4. ENTRYPOINT SCRIPT
# ===================================================================
echo ""
echo "4. Entrypoint Script"
echo "-------------------"

test_condition "entrypoint.sh exists" "[ -f entrypoint.sh ]"
test_condition "Constructs DATABASE_URL from env vars" "grep -q 'MYSQL_HOST.*MYSQL_PORT' entrypoint.sh"
test_condition "Waits for database" "grep -q 'Waiting for database' entrypoint.sh"
test_condition "Runs migrations" "grep -q 'doctrine:migrations:migrate' entrypoint.sh"
test_condition "Clears cache" "grep -q 'cache:clear' entrypoint.sh"
test_condition "Starts PHP-FPM" "grep -q 'php-fpm' entrypoint.sh"
test_condition "Starts Nginx" "grep -q 'nginx' entrypoint.sh"

# ===================================================================
# 5. APPLICATION STRUCTURE
# ===================================================================
echo ""
echo "5. Application Structure"
echo "------------------------"

test_condition "src/Controller exists" "[ -d src/Controller ]"
test_condition "HomeController exists" "[ -f src/Controller/HomeController.php ]"
test_condition "ProductController exists" "[ -f src/Controller/ProductController.php ]"
test_condition "src/Entity exists" "[ -d src/Entity ]"
test_condition "Product entity exists" "[ -f src/Entity/Product.php ]"
test_condition "Migrations exist" "[ -d migrations ] && [ $(ls -1 migrations/*.php 2>/dev/null | wc -l) -gt 0 ]"
test_condition "Doctrine configured" "[ -f config/packages/doctrine.yaml ]"

# ===================================================================
# 6. ROUTING CONFIGURATION
# ===================================================================
echo ""
echo "6. Routing Configuration"
echo "------------------------"

test_condition "routes.yaml exists" "[ -f config/routes.yaml ]"
test_condition "Routes point to src/Controller" "grep -q 'src/Controller' config/routes.yaml"
test_condition "Uses attribute routing" "grep -q 'type: attribute' config/routes.yaml"

# ===================================================================
# 7. DOCKER COMPOSE (Local Development)
# ===================================================================
echo ""
echo "7. Docker Compose Configuration"
echo "-------------------------------"

test_condition "docker-compose.yaml exists" "[ -f docker-compose.yaml ]"
test_condition "MySQL service configured" "grep -q 'image: mysql:8.0' docker-compose.yaml"
test_condition "Nginx configured in Dockerfile" "grep -q 'nginx' Dockerfile"
test_condition "App service uses .env variables" "grep -q 'DATABASE_URL' docker-compose.yaml"

# ===================================================================
# 8. SUMMARY
# ===================================================================
echo ""
echo "================================"
echo "Verification Summary"
echo "================================"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Deployment is configured correctly.${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Some checks failed. Review the output above.${NC}"
    exit 1
fi
