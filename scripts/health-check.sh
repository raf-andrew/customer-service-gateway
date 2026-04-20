#!/bin/bash
# health-check.sh - Quick health check of the entire integration stack
# Usage: bash scripts/health-check.sh
# Time: ~5 seconds

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PASS=0
FAIL=0

# Check 1: Gateway container running
echo -n "Gateway container:     "
if docker ps | grep -q "Up.*customer-service-gateway"; then
  echo "✓ Running"
  ((PASS++))
else
  echo "✗ Not running"
  ((FAIL++))
fi

# Check 2: Gateway health endpoint
echo -n "Gateway health:        "
HEALTH=$(curl -s http://127.0.0.1:3101/health 2>/dev/null | jq -r '.status' 2>/dev/null)
if [ "$HEALTH" = "ok" ]; then
  echo "✓ OK"
  ((PASS++))
else
  echo "✗ Unhealthy or unreachable"
  ((FAIL++))
fi

# Check 3: Webapp nginx
echo -n "Nginx:                 "
if docker ps | grep -q "Up.*webapp_core_nginx"; then
  echo "✓ Running"
  ((PASS++))
else
  echo "✗ Not running"
  ((FAIL++))
fi

# Check 4: PHP-FPM
echo -n "PHP-FPM:               "
if docker ps | grep -q "Up.*webapp_core_app"; then
  echo "✓ Running"
  ((PASS++))
else
  echo "✗ Not running"
  ((FAIL++))
fi

# Check 5: Database
echo -n "MySQL:                 "
if docker ps | grep -q "Up.*webapp_core_db"; then
  if docker exec webapp_core_db_fresh mysql -uroot -proot -e "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ Running"
    ((PASS++))
  else
    echo "✗ Not responding"
    ((FAIL++))
  fi
else
  echo "✗ Not running"
  ((FAIL++))
fi

# Check 6: Redis
echo -n "Redis:                 "
if docker ps | grep -q "Up.*webapp_core_redis"; then
  if docker exec webapp_core_redis_fresh redis-cli ping > /dev/null 2>&1; then
    echo "✓ Running"
    ((PASS++))
  else
    echo "✗ Not responding"
    ((FAIL++))
  fi
else
  echo "✗ Not running"
  ((FAIL++))
fi

# Check 7: Network connectivity (gateway → nginx)
echo -n "Gateway→Nginx:         "
if docker exec customer-service-gateway ping -c 1 webapp_core_nginx_fresh > /dev/null 2>&1; then
  echo "✓ Connected"
  ((PASS++))
else
  echo "✗ Connection failed"
  ((FAIL++))
fi

# Check 8: HelpdeskClient migrations (N2 blocker verification)
echo -n "Helpdesk DB setup:     "
HELPDESK_MIGRATIONS=$(docker exec webapp_core_db_fresh mysql -h localhost -u root -proot -e "USE webapp_core_helpdesk; SELECT COUNT(*) FROM migrations;" 2>/dev/null | tail -1 || echo "0")
if [ "$HELPDESK_MIGRATIONS" -eq 77 ]; then
  echo "✓ All 77 migrations completed (N2 resolved)"
  ((PASS++))
elif [ "$HELPDESK_MIGRATIONS" -gt 0 ]; then
  echo "⚠ Only $HELPDESK_MIGRATIONS/77 migrations (partial setup)"
  ((FAIL++))
else
  echo "✗ No migrations found (0/77)"
  ((FAIL++))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: ✓ $PASS passed, ✗ $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAIL -eq 0 ]; then
  echo "✅ All checks passed!"
  exit 0
else
  echo "⚠️  Some checks failed. See OPERATIONAL_PROCEDURES.md for troubleshooting."
  exit 1
fi
