#!/bin/bash
# logs.sh - Unified log viewing across the integration stack
# Usage: bash scripts/logs.sh [search_term]
# Examples:
#   bash scripts/logs.sh                  # View all logs (last 100 lines per service)
#   bash scripts/logs.sh error            # View only lines containing 'error'
#   bash scripts/logs.sh "customer/login" # View lines containing this route

SEARCH_TERM="${1:-.}"  # Default to "." (match all) if no search term

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Logs from Integration Stack"
if [ "$SEARCH_TERM" != "." ]; then
  echo "  Search: $SEARCH_TERM"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Gateway logs
echo "=== GATEWAY ==="
docker compose logs gateway --tail=50 2>/dev/null | grep -i "$SEARCH_TERM" | tail -20

echo ""
echo "=== NGINX ==="
docker compose -f ../webapp_core/docker-compose.local.yml logs nginx --tail=50 2>/dev/null | \
  grep -i "$SEARCH_TERM" | tail -20

echo ""
echo "=== PHP-FPM ==="
docker logs webapp_core_app_fresh --tail=50 2>/dev/null | grep -i "$SEARCH_TERM" | tail -20

echo ""
echo "=== DATABASE ==="
docker logs webapp_core_db_fresh --tail=50 2>/dev/null | grep -i "$SEARCH_TERM" | tail -20

echo ""
echo "=== REDIS ==="
docker logs webapp_core_redis_fresh --tail=50 2>/dev/null | grep -i "$SEARCH_TERM" | tail -20

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Tip: Use 'docker compose logs -f gateway' for live tail of a single service"
