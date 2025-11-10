#!/bin/bash
# Test script for pgBadger reports accessibility

set -e

CONTAINER_NAME="pgbadger-lab"
HOST_PORT="8081"
PRIMARY_REPORT="primary-report.html"
STANDBY_REPORT="standby-report.html"

echo "=========================================="
echo "Testing pgBadger Reports Accessibility"
echo "=========================================="
echo ""

# Check if container is running
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ Error: Container '${CONTAINER_NAME}' is not running"
    echo "   Start it with: docker-compose up -d pgbadger-lab"
    exit 1
fi

echo "✓ Container '${CONTAINER_NAME}' is running"
echo ""

# Get container IP (optional, for reference)
CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${CONTAINER_NAME} 2>/dev/null || echo "N/A")
echo "Container IP: ${CONTAINER_IP}"
echo "Host port mapping: localhost:${HOST_PORT} -> container:80"
echo ""

# Test primary report
echo "Testing Primary Report..."
echo "URL: http://localhost:${HOST_PORT}/${PRIMARY_REPORT}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HOST_PORT}/${PRIMARY_REPORT}" || echo "000")

if [ "${HTTP_CODE}" = "200" ]; then
    echo "✓ Primary report is accessible (HTTP ${HTTP_CODE})"
    SIZE=$(curl -s "http://localhost:${HOST_PORT}/${PRIMARY_REPORT}" | wc -c)
    echo "  Report size: ${SIZE} bytes"
else
    echo "❌ Primary report is NOT accessible (HTTP ${HTTP_CODE})"
    echo "  Possible issues:"
    echo "    - Web server not running in container"
    echo "    - Report file not generated yet"
    echo "    - Port mapping issue"
fi
echo ""

# Test standby report
echo "Testing Standby Report..."
echo "URL: http://localhost:${HOST_PORT}/${STANDBY_REPORT}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HOST_PORT}/${STANDBY_REPORT}" || echo "000")

if [ "${HTTP_CODE}" = "200" ]; then
    echo "✓ Standby report is accessible (HTTP ${HTTP_CODE})"
    SIZE=$(curl -s "http://localhost:${HOST_PORT}/${STANDBY_REPORT}" | wc -c)
    echo "  Report size: ${SIZE} bytes"
else
    echo "❌ Standby report is NOT accessible (HTTP ${HTTP_CODE})"
    echo "  Possible issues:"
    echo "    - Web server not running in container"
    echo "    - Report file not generated yet"
    echo "    - Port mapping issue"
fi
echo ""

# Check if files exist in container
echo "Checking files in container..."
if docker exec ${CONTAINER_NAME} test -f "/var/www/html/${PRIMARY_REPORT}"; then
    PRIMARY_SIZE=$(docker exec ${CONTAINER_NAME} stat -c%s "/var/www/html/${PRIMARY_REPORT}" 2>/dev/null || echo "unknown")
    echo "✓ Primary report file exists (${PRIMARY_SIZE} bytes)"
else
    echo "❌ Primary report file does not exist in container"
fi

if docker exec ${CONTAINER_NAME} test -f "/var/www/html/${STANDBY_REPORT}"; then
    STANDBY_SIZE=$(docker exec ${CONTAINER_NAME} stat -c%s "/var/www/html/${STANDBY_REPORT}" 2>/dev/null || echo "unknown")
    echo "✓ Standby report file exists (${STANDBY_SIZE} bytes)"
else
    echo "❌ Standby report file does not exist in container"
fi
echo ""

# Check if web server is running
echo "Checking web server status..."
if docker exec ${CONTAINER_NAME} pgrep lighttpd > /dev/null 2>&1; then
    echo "✓ lighttpd web server is running"
elif docker exec ${CONTAINER_NAME} pgrep httpd > /dev/null 2>&1; then
    echo "✓ httpd web server is running"
elif docker exec ${CONTAINER_NAME} pgrep nginx > /dev/null 2>&1; then
    echo "✓ nginx web server is running"
else
    echo "❌ No web server process detected"
    echo "  The container may need to be restarted to start the web server"
fi
echo ""

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Access reports from your browser:"
echo "  Primary:  http://localhost:${HOST_PORT}/${PRIMARY_REPORT}"
echo "  Standby:  http://localhost:${HOST_PORT}/${STANDBY_REPORT}"
echo ""
echo "Or from another machine on your network:"
if command -v hostname &> /dev/null && command -v ip &> /dev/null; then
    HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "YOUR_HOST_IP")
    echo "  Primary:  http://${HOST_IP}:${HOST_PORT}/${PRIMARY_REPORT}"
    echo "  Standby:  http://${HOST_IP}:${HOST_PORT}/${STANDBY_REPORT}"
else
    echo "  Primary:  http://YOUR_HOST_IP:${HOST_PORT}/${PRIMARY_REPORT}"
    echo "  Standby:  http://YOUR_HOST_IP:${HOST_PORT}/${STANDBY_REPORT}"
fi
echo ""
echo "To test with curl:"
echo "  curl http://localhost:${HOST_PORT}/${PRIMARY_REPORT} | head -20"
echo "  curl http://localhost:${HOST_PORT}/${STANDBY_REPORT} | head -20"
echo ""


