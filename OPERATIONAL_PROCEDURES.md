# Operational Procedures: Gateway & Integration Stack

Date: 2026-04-19  
Scope: Day-to-day operations — startup, shutdown, health checks, troubleshooting, scaling.

---

## Quick Reference

| Task | Time | Command |
| --- | --- | --- |
| **Start stack** | 30-60 s | `docker compose up -d` |
| **Stop stack** | 10 s | `docker compose down` |
| **Health check** | <2 s | `curl http://127.0.0.1:3101/health` |
| **View logs** | immediate | `docker compose logs -f gateway` |
| **Restart single service** | 5 s | `docker compose restart gateway` |
| **Database backup** | 5-10 s | `docker exec webapp_core_db_fresh mysqldump ...` |

---

## Startup Procedures

### Procedure 1: Full Fresh Start

**Time**: 2-3 minutes (Docker pulls/builds if needed)  
**Prerequisites**: Docker running, compose files present

```bash
cd /f/www/webapp_core

# 1. Bring up all fresh stack containers
docker compose -f docker-compose.local.yml up -d

# 2. Wait for DB to be ready (healthcheck)
echo "Waiting for database..."
docker compose -f docker-compose.local.yml exec webapp_core_db_fresh \
  mysql -uroot -proot -e "SELECT 1;" > /dev/null 2>&1 && echo "DB ready"

# 3. Start gateway
cd /f/www/customer-service-gateway
docker compose up -d gateway

# 4. Verify all running
docker ps --format 'table {{.Names}}\t{{.Status}}' | \
  grep -E "customer-service-gateway|webapp_core_"

# 5. Test health
curl -s http://127.0.0.1:3101/health | jq .
```

**Expected Output**:
```json
{
  "status": "ok",
  "service": "customer-service-gateway",
  "upstreamUrl": "http://webapp_core_nginx_fresh:80/helpdesk/api",
  "timestamp": "2026-04-20T..."
}
```

---

### Procedure 2: Partial Restart (After Code Changes)

**Time**: 30-60 seconds

```bash
# If you changed src/index.ts in gateway:
cd /f/www/customer-service-gateway
npm run build  # Compile TypeScript
docker build -t customer-service-gateway:local .  # Rebuild image
docker compose up -d --force-recreate gateway  # Restart container

# Verify
curl http://127.0.0.1:3101/health
```

---

### Procedure 3: Rebuild Without Stopping (Minimal Downtime)

**Time**: 5-10 seconds downtime

```bash
# Build new image in parallel
cd /f/www/customer-service-gateway
npm run build && docker build -t customer-service-gateway:local .

# Recreate with --no-deps to avoid restarting other services
docker compose up -d --no-deps --force-recreate gateway

# Health check loop (wait for it to come back)
for i in {1..30}; do
  if curl -s http://127.0.0.1:3101/health > /dev/null 2>&1; then
    echo "Gateway up after $((i))s"
    break
  fi
  sleep 1
done
```

---

## Shutdown Procedures

### Procedure 1: Graceful Shutdown (Preserve Data)

**Time**: 10-20 seconds

```bash
cd /f/www/webapp_core
docker compose -f docker-compose.local.yml down

cd /f/www/customer-service-gateway
docker compose down

# Verify all stopped
docker ps | grep -E "customer-service-gateway|webapp_core_" || echo "All stopped"
```

**Note**: `docker compose down` stops containers but preserves volumes (data persists).

---

### Procedure 2: Full Cleanup (Wipe All Data)

**Time**: 30 seconds  
**WARNING**: Deletes all data

```bash
# Remove containers AND volumes
docker compose -f docker-compose.local.yml down -v
docker compose down -v

# Remove images (optional)
docker rmi customer-service-gateway:local
docker rmi webapp_core_app_fresh  # if built locally

echo "Full cleanup complete. Re-run 'docker compose up -d' to restart."
```

---

## Health Check Procedures

### Procedure 1: Quick Health Check (30 seconds)

```bash
#!/bin/bash
# Quick validation that everything is running

echo "=== Gateway ==="
curl -s http://127.0.0.1:3101/health | jq . || echo "FAIL: Gateway unhealthy"

echo ""
echo "=== Nginx ==="
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:8081/

echo ""
echo "=== Database ==="
docker exec webapp_core_db_fresh mysql -uroot -proot -e "SELECT 1;" > /dev/null && \
  echo "MySQL: OK" || echo "FAIL: MySQL down"

echo ""
echo "=== Redis ==="
docker exec webapp_core_redis_fresh redis-cli ping | grep -q "PONG" && \
  echo "Redis: OK" || echo "FAIL: Redis down"

echo ""
echo "=== Containers ==="
docker ps --format 'table {{.Names}}\t{{.Status}}' | \
  grep -E "customer-service-gateway|webapp_core_" | \
  awk '{if ($2 ~ /^Up/) print "✓ " $1; else print "✗ " $1}'
```

**Expected Output**:
```
=== Gateway ===
{
  "status": "ok",
  ...
}

=== Nginx ===
HTTP 200

=== Database ===
MySQL: OK

=== Redis ===
Redis: OK

=== Containers ===
✓ customer-service-gateway
✓ webapp_core_nginx_fresh
✓ webapp_core_app_fresh
✓ webapp_core_db_fresh
✓ webapp_core_redis_fresh
```

---

### Procedure 2: Deep Health Check (1-2 minutes)

```bash
#!/bin/bash
# Comprehensive health check including route verification

echo "=== Container Status ==="
docker ps -a --format 'table {{.Names}}\t{{.Status}}'

echo ""
echo "=== Gateway Health ==="
HEALTH=$(curl -s http://127.0.0.1:3101/health)
echo "$HEALTH" | jq .
STATUS=$(echo "$HEALTH" | jq -r '.status')
if [ "$STATUS" != "ok" ]; then
  echo "FAIL: Gateway not healthy"
  exit 1
fi

echo ""
echo "=== Nginx Response ==="
curl -i http://127.0.0.1:8081/ | head -5

echo ""
echo "=== Database Tables ==="
docker exec webapp_core_db_fresh mysql -uroot -proot \
  -e "SHOW DATABASES;" | grep -E "webapp_core|information_schema"

echo ""
echo "=== HelpdeskClient Routes ==="
docker exec webapp_core_app_fresh php artisan route:list 2>/dev/null | \
  grep "helpdesk" | head -5 || echo "Routes not registered (N2 blocker?)"

echo ""
echo "=== Network Connectivity ==="
docker exec customer-service-gateway ping -c 1 webapp_core_nginx_fresh > /dev/null && \
  echo "Gateway → Nginx: OK" || echo "FAIL: Gateway cannot reach Nginx"

echo ""
echo "=== All Checks Complete ==="
```

---

## Troubleshooting Procedures

### Issue 1: Gateway returns 502 (Bad Gateway)

**Diagnosis** (< 1 minute):
```bash
# 1. Check if gateway is running
docker ps | grep customer-service-gateway || echo "FAIL: Gateway not running"

# 2. Check if nginx is reachable
docker exec customer-service-gateway wget -qO- http://webapp_core_nginx_fresh/ \
  | head -5

# 3. Check nginx logs
docker logs webapp_core_nginx_fresh | tail -20

# 4. Check gateway env
docker inspect customer-service-gateway --format '{{range .Config.Env}}{{println .}}{{end}}' | \
  grep HELPDESK_API_URL
```

**Common Causes & Fixes**:

| Cause | Fix |
| --- | --- |
| Nginx container stopped | `docker compose restart nginx` |
| Nginx not forwarding to PHP | Mount nginx config (N1 fix) |
| Wrong upstream URL in env | Update docker-compose.yml HELPDESK_API_URL |
| Network issue | Verify both on integration_net: `docker network inspect integration_net` |

---

### Issue 2: 404 from Laravel (not nginx)

**Diagnosis**:
```bash
# If you see a 404 response with Laravel HTML, routes aren't registered
curl -i http://127.0.0.1:3101/api/helpdesk/customer/login | head -10

# Check if helpdesk routes exist
docker exec webapp_core_app_fresh php artisan route:list | grep helpdesk | head -3
```

**Likely Cause**: N2 blocker (helpdesk_settings table missing)

**Fix**: Run N2 fix procedures (see BLOCKERS_AND_FIXES.md).

---

### Issue 3: Database Connection Refused

**Diagnosis**:
```bash
# Check if DB container is running
docker ps | grep webapp_core_db_fresh || echo "FAIL: DB not running"

# Check if MySQL is accepting connections
docker exec webapp_core_db_fresh mysql -uroot -proot -e "SELECT 1;"

# Check PHP-FPM env
docker exec webapp_core_app_fresh env | grep DB_
```

**Common Causes & Fixes**:

| Cause | Fix |
| --- | --- |
| DB container crashed | `docker logs webapp_core_db_fresh`, check disk space |
| Wrong credentials in .env | Update webapp_core/.env (should be root:root locally) |
| PHP-FPM can't resolve 'db' hostname | Verify both on same network: `docker network inspect webapp_local` |
| Port 3306 not open inside container | Container issue, rebuild image |

---

### Issue 4: High Memory Usage

**Diagnosis**:
```bash
# Check container memory
docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}'

# Check PHP-FPM processes
docker exec webapp_core_app_fresh ps aux | grep php
```

**Common Causes**:

| Cause | Fix |
| --- | --- |
| Too many PHP-FPM processes | Adjust PHP-FPM config (max_children) |
| Memory leak in Laravel | Restart: `docker compose restart app` |
| Redis data bloat | `docker exec redis redis-cli DBSIZE` |

---

## Scaling Procedures

### Horizontal Scaling: Run Multiple Gateway Instances

**Setup**:
```yaml
# docker-compose.yml modification
services:
  gateway1:
    build: .
    ports:
      - "127.0.0.1:3101:3100"
    environment:
      GATEWAY_PORT: 3100
  
  gateway2:
    build: .
    ports:
      - "127.0.0.1:3102:3100"
    environment:
      GATEWAY_PORT: 3100
  
  # Add a load balancer (nginx, HAProxy, etc.)
  lb:
    image: nginx:alpine
    ports:
      - "127.0.0.1:3100:80"
    volumes:
      - ./nginx-lb.conf:/etc/nginx/nginx.conf
```

**Note**: For production, use Kubernetes or a managed container service (ECS, GKE, etc.) instead of manual scaling.

---

## Backup & Restore Procedures

### Database Backup (5 seconds)

```bash
# Backup to local file
docker exec webapp_core_db_fresh mysqldump -uroot -proot webapp_core > \
  /f/www/webapp_core/backups/webapp_core_$(date +%Y%m%d_%H%M%S).sql

# Backup with gzip compression
docker exec webapp_core_db_fresh mysqldump -uroot -proot webapp_core | \
  gzip > /f/www/webapp_core/backups/webapp_core_$(date +%Y%m%d_%H%M%S).sql.gz

# List backups
ls -lh /f/www/webapp_core/backups/
```

---

### Database Restore (10-30 seconds)

```bash
# Restore from backup
docker exec -i webapp_core_db_fresh mysql -uroot -proot webapp_core < \
  /f/www/webapp_core/backups/webapp_core_YYYYMMDD_HHMMSS.sql

# Verify restore
docker exec webapp_core_db_fresh mysql -uroot -proot \
  -e "USE webapp_core; SHOW TABLES;" | wc -l
```

---

## Maintenance Tasks

### Daily (Morning)

```bash
# 1. Check health
curl -s http://127.0.0.1:3101/health | jq .status

# 2. Check logs for errors
docker compose logs --since 24h gateway | grep -i error | head -10

# 3. Backup database
docker exec webapp_core_db_fresh mysqldump -uroot -proot webapp_core | \
  gzip > /f/www/webapp_core/backups/daily_$(date +%Y%m%d).sql.gz
```

### Weekly

```bash
# 1. Review resource usage
docker stats --no-stream

# 2. Clean up unused images/containers
docker image prune -f
docker container prune -f

# 3. Check disk space
df -h /f
df -h /c

# 4. Verify backups were created
ls -lah /f/www/webapp_core/backups/ | tail -10
```

### Monthly

```bash
# 1. Test disaster recovery (restore from backup)
# 2. Review security logs
# 3. Check for package updates (npm, composer)
# 4. Performance analysis (response times, error rates)
```

---

## Emergency Procedures

### Gateway is Down (Customer Impact)

```bash
# 1. IMMEDIATE: Restart
docker compose restart gateway
curl -s http://127.0.0.1:3101/health  # Verify it comes back

# 2. If restart fails, check logs
docker logs customer-service-gateway | tail -50

# 3. If logs show config error, fix .env and restart
vim /f/www/customer-service-gateway/.env
docker compose up -d --force-recreate gateway

# 4. If upstream is the issue, see "Nginx is Down" below
```

### Database is Down (Data Loss Risk)

```bash
# 1. Check if container is running
docker ps | grep webapp_core_db_fresh

# 2. If crashed, check logs
docker logs webapp_core_db_fresh | tail -50

# 3. Restart
docker compose restart db

# 4. If still failing, restore from backup
docker exec webapp_core_db_fresh mysql -uroot -proot \
  -e "DROP DATABASE webapp_core; CREATE DATABASE webapp_core;"
docker exec -i webapp_core_db_fresh mysql -uroot -proot webapp_core < \
  /f/www/webapp_core/backups/latest.sql.gz

# 5. Run migrations if needed
docker exec webapp_core_app_fresh php artisan migrate
```

### Nginx is Down (No Laravel Access)

```bash
# 1. Check if running
docker ps | grep webapp_core_nginx

# 2. Check logs
docker logs webapp_core_nginx_fresh | tail -50

# 3. Verify config is mounted (N1 blocker)
docker exec webapp_core_nginx_fresh cat /etc/nginx/conf.d/default.conf | head -10

# 4. Restart
docker compose restart nginx

# 5. Verify
curl http://127.0.0.1:8081/
```

---

## Runbook Quick Links

- **Gateway starts but no routes**: See N2 blocker (BLOCKERS_AND_FIXES.md)
- **Gateway can't reach nginx**: See Troubleshooting Procedure "Issue 1"
- **Database backups**: See "Backup & Restore Procedures"
- **Performance slow**: See "Scaling Procedures"
- **Emergency downtime**: See "Emergency Procedures"
