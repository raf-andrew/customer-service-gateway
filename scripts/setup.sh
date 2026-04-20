#!/bin/bash
# setup.sh - Initialize the gateway and integration stack from scratch
# Usage: bash scripts/setup.sh
# Time: ~3-5 minutes (depending on image download/build speed)

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEBAPP_ROOT="$(dirname "$PROJECT_ROOT")/webapp_core"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Customer Service Gateway Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Verify prerequisites
echo "Step 1: Verifying prerequisites..."
if ! command -v docker &> /dev/null; then
  echo "❌ Docker not found. Please install Docker."
  exit 1
fi
echo "✓ Docker available: $(docker --version)"

if ! command -v docker-compose &> /dev/null; then
  echo "❌ Docker Compose not found. Please install Docker Compose."
  exit 1
fi
echo "✓ Docker Compose available: $(docker-compose --version)"

if ! command -v npm &> /dev/null; then
  echo "⚠️  npm not found (optional for local dev)"
else
  echo "✓ npm available: $(npm --version)"
fi

echo ""

# Step 2: Install Node dependencies
echo "Step 2: Installing Node dependencies..."
cd "$PROJECT_ROOT"
if [ -f "package.json" ]; then
  npm install
  echo "✓ npm dependencies installed"
else
  echo "❌ package.json not found in $PROJECT_ROOT"
  exit 1
fi

echo ""

# Step 3: Build TypeScript
echo "Step 3: Building TypeScript..."
npm run build
echo "✓ TypeScript compiled to dist/"

echo ""

# Step 4: Build Docker image
echo "Step 4: Building Docker image..."
docker build -t customer-service-gateway:local .
echo "✓ Docker image built: customer-service-gateway:local"

echo ""

# Step 5: Start webapp_core stack
echo "Step 5: Starting webapp_core stack..."
cd "$WEBAPP_ROOT"
if [ ! -f "docker-compose.local.yml" ]; then
  echo "❌ docker-compose.local.yml not found in $WEBAPP_ROOT"
  echo "   This file is required. Check INSTALLATION.md"
  exit 1
fi

docker compose -f docker-compose.local.yml up -d
echo "✓ webapp_core stack started"

# Wait for database to be ready
echo "   Waiting for database to be ready..."
for i in {1..30}; do
  if docker exec webapp_core_db_fresh mysql -uroot -proot -e "SELECT 1;" > /dev/null 2>&1; then
    echo "   ✓ Database ready"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "   ❌ Database failed to start"
    exit 1
  fi
  sleep 1
done

echo ""

# Step 6: Start gateway
echo "Step 6: Starting gateway..."
cd "$PROJECT_ROOT"
docker compose up -d gateway
echo "✓ Gateway started"

# Wait for gateway to be ready
echo "   Waiting for gateway to be ready..."
for i in {1..30}; do
  if curl -s http://127.0.0.1:3101/health > /dev/null 2>&1; then
    echo "   ✓ Gateway ready"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "   ❌ Gateway failed to start"
    exit 1
  fi
  sleep 1
done

echo ""

# Step 7: Verify all containers
echo "Step 7: Verifying container health..."
RUNNING=$(docker ps --format 'table {{.Names}}\t{{.Status}}' | \
  grep -E "customer-service-gateway|webapp_core_" | \
  grep -c "Up")

echo "   Running: $RUNNING / 5 containers"
docker ps --format 'table {{.Names}}\t{{.Status}}' | \
  grep -E "customer-service-gateway|webapp_core_"

echo ""

# Step 8: Quick health check
echo "Step 8: Running health checks..."

HEALTH=$(curl -s http://127.0.0.1:3101/health | jq -r '.status' 2>/dev/null || echo "error")
if [ "$HEALTH" = "ok" ]; then
  echo "✓ Gateway health: OK"
else
  echo "⚠️  Gateway health check failed"
fi

NGINX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8081/ 2>/dev/null || echo "000")
echo "✓ Nginx status: HTTP $NGINX_STATUS"

echo ""

# Step 9: Print quick reference
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Quick Reference:"
echo "  Gateway API:        http://127.0.0.1:3101"
echo "  Health Check:       curl http://127.0.0.1:3101/health"
echo "  Webapp (Nginx):     http://127.0.0.1:8081"
echo "  MySQL:              127.0.0.1:3308 (root:root)"
echo "  Redis:              127.0.0.1:6382"
echo ""
echo "View Logs:"
echo "  Gateway:  docker compose logs -f gateway"
echo "  Nginx:    docker compose -f ../webapp_core/docker-compose.local.yml logs -f nginx"
echo "  All:      bash scripts/logs.sh"
echo ""
echo "Stop Everything:"
echo "  docker compose -f ../webapp_core/docker-compose.local.yml down"
echo "  docker compose down"
echo ""
echo "Next Steps:"
echo "  1. Verify routes are registered: DEPLOYMENT_VERIFICATION.md"
echo "  2. Apply N1 + N2 fixes if needed: BLOCKERS_AND_FIXES.md"
echo "  3. Run tests: TESTING_PLAYBOOK.md"
echo ""
