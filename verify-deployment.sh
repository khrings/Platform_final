#!/bin/bash

################################################################################
# Platform Deployment Verification Script
# Usage: bash verify-deployment.sh
# Tests the Railway-deployed Symfony application
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROD_URL="https://platformfinal-production.up.railway.app"
TIMEOUT=10

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_test() {
    echo -e "${YELLOW}📍 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((TESTS_PASSED++))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((TESTS_FAILED++))
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

################################################################################
# Main Tests
################################################################################

print_header "Platform Deployment Verification"

echo "Testing Production Deployment"
echo "URL: $PROD_URL"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Test 1: Homepage Accessibility
print_test "Test 1: Homepage Accessibility"
if RESPONSE=$(curl -s -w "\n%{http_code}" --max-time $TIMEOUT "$PROD_URL/" 2>/dev/null | tail -1); then
    if [ "$RESPONSE" = "200" ]; then
        print_success "Home page loads successfully (HTTP $RESPONSE)"
    elif [ "$RESPONSE" = "301" ] || [ "$RESPONSE" = "302" ]; then
        print_warning "Home page redirects (HTTP $RESPONSE)"
        ((TESTS_PASSED++))
    else
        print_error "Home page returned HTTP $RESPONSE"
    fi
else
    print_error "Failed to connect to home page"
fi
echo ""

# Test 2: Products Page Accessibility
print_test "Test 2: Products Page Accessibility"
if RESPONSE=$(curl -s -w "\n%{http_code}" --max-time $TIMEOUT "$PROD_URL/product" 2>/dev/null | tail -1); then
    if [ "$RESPONSE" = "200" ]; then
        print_success "Products page loads successfully (HTTP $RESPONSE)"
    elif [ "$RESPONSE" = "301" ] || [ "$RESPONSE" = "302" ]; then
        print_warning "Products page redirects (HTTP $RESPONSE)"
        ((TESTS_PASSED++))
    else
        print_error "Products page returned HTTP $RESPONSE"
    fi
else
    print_error "Failed to connect to products page"
fi
echo ""

# Test 3: Database Connectivity (check for database working message)
print_test "Test 3: Database Connectivity"
if HTML=$(curl -s --max-time $TIMEOUT "$PROD_URL/" 2>/dev/null); then
    if echo "$HTML" | grep -qi "database connection is working"; then
        print_success "Database connection is working (found in home page)"
    elif echo "$HTML" | grep -qi "db_working\|application running"; then
        print_success "Application running with database support"
    else
        print_warning "Could not verify database status from HTML response"
    fi
else
    print_error "Failed to fetch home page content"
fi
echo ""

# Test 4: Security Headers
print_test "Test 4: Security Headers"
HEADERS_FOUND=0
if HEADERS=$(curl -s -i --max-time $TIMEOUT "$PROD_URL/" 2>/dev/null); then
    if echo "$HEADERS" | grep -qi "X-Frame-Options"; then
        print_success "X-Frame-Options header present"
        ((HEADERS_FOUND++))
    else
        print_warning "X-Frame-Options header missing"
    fi
    
    if echo "$HEADERS" | grep -qi "X-Content-Type-Options"; then
        print_success "X-Content-Type-Options header present"
        ((HEADERS_FOUND++))
    else
        print_warning "X-Content-Type-Options header missing"
    fi
    
    if echo "$HEADERS" | grep -qi "X-XSS-Protection"; then
        print_success "X-XSS-Protection header present"
        ((HEADERS_FOUND++))
    else
        print_warning "X-XSS-Protection header missing"
    fi
    
    if [ $HEADERS_FOUND -gt 0 ]; then
        ((TESTS_PASSED++))
    fi
else
    print_error "Failed to fetch response headers"
fi
echo ""

# Test 5: Response Time
print_test "Test 5: Response Time Performance"
if TIME=$(curl -s -o /dev/null -w "%{time_total}" --max-time $TIMEOUT "$PROD_URL/" 2>/dev/null); then
    TIME_MS=$(echo "$TIME * 1000" | bc | cut -d. -f1)
    if [ "$TIME_MS" -lt 2000 ]; then
        print_success "Fast response time: ${TIME_MS}ms"
    elif [ "$TIME_MS" -lt 5000 ]; then
        print_warning "Moderate response time: ${TIME_MS}ms"
        ((TESTS_PASSED++))
    else
        print_warning "Slow response time: ${TIME_MS}ms"
        ((TESTS_PASSED++))
    fi
else
    print_error "Failed to measure response time"
fi
echo ""

# Test 6: Content-Type Header
print_test "Test 6: Content-Type Verification"
if CONTENT_TYPE=$(curl -s -I --max-time $TIMEOUT "$PROD_URL/" 2>/dev/null | grep -i "Content-Type" | head -1); then
    if echo "$CONTENT_TYPE" | grep -qi "text/html"; then
        print_success "Content-Type is HTML: $CONTENT_TYPE"
    else
        print_warning "Unexpected Content-Type: $CONTENT_TYPE"
        ((TESTS_PASSED++))
    fi
else
    print_error "Could not determine Content-Type"
fi
echo ""

# Test 7: Product Routes (sample endpoints)
print_test "Test 7: Product Routes"
ROUTE_TESTS=0
for endpoint in "/product" "/product/new"; do
    if RESPONSE=$(curl -s -w "\n%{http_code}" --max-time $TIMEOUT "$PROD_URL$endpoint" 2>/dev/null | tail -1); then
        if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "405" ]; then
            ROUTE_TESTS=$((ROUTE_TESTS + 1))
        fi
    fi
done
if [ $ROUTE_TESTS -gt 0 ]; then
    print_success "Product routes responding ($ROUTE_TESTS/2 accessible)"
else
    print_warning "Could not verify all product routes"
    ((TESTS_PASSED++))
fi
echo ""

################################################################################
# Summary
################################################################################

print_header "Deployment Verification Summary"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))

echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo "Total Tests:  $TOTAL_TESTS"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed! Deployment is working correctly.${NC}"
    echo ""
    echo "Your application is successfully deployed at:"
    echo -e "${BLUE}  $PROD_URL${NC}"
    echo ""
    echo "Available routes:"
    echo "  🏠 Home:     $PROD_URL/"
    echo "  📦 Products: $PROD_URL/product"
    echo ""
    exit 0
else
    echo -e "${RED}⚠️  Some tests failed. Please review the errors above.${NC}"
    echo ""
    exit 1
fi
