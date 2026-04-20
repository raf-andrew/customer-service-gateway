# Pre-Deployment Verification Checklist

Date: 2026-04-19  
Scope: Step-by-step checklist to verify N1+N2 fixes are working before declaring integration complete.

---

## Checklist: Run This After Applying N1 + N2 Fixes

**Estimated Time**: 5-10 minutes  
**Prerequisites**: Both N1 and N2 fixes applied (nginx config mounted, helpdesk_settings table created)

---

### Phase 1: Container Startup (2 min)

- [ ] All containers running: `docker ps | grep -c "customer-service-gateway\|webapp_core_" | grep -E "^[5-9]"`
- [ ] No containers in "Restarting" state: `docker ps | grep "Restarting" | wc -l | grep -q "^0$"`
- [ ] Gateway healthy: `docker ps | grep customer-service-gateway | grep -q "healthy"`
- [ ] App healthy: `docker ps | grep webapp_core_app_fresh | grep -q "healthy"`
- [ ] DB healthy: `docker ps | grep webapp_core_db_fresh | grep -q "healthy"`
- [ ] Redis healthy: `docker ps | grep webapp_core_redis_fresh | grep -q "healthy"`

---

### Phase 2: Gateway Health (30 sec)

```bash
# Run command:
curl -s http://127.0.0.1:3101/health | jq .
```

**Expected Output**:
```json
{
  "status": "ok",
  "service": "customer-service-gateway",
  "upstreamUrl": "http://webapp_core_nginx_fresh:80/helpdesk/api",
  "timestamp": "..."
}
```

- [ ] Status is "ok"
- [ ] Service is "customer-service-gateway"
- [ ] upstreamUrl contains "helpdesk/api" (not just "/api")
- [ ] Timestamp is current (within last 10 seconds)

---

### Phase 3: Nginx Integration (30 sec)

```bash
# Run command:
curl -i http://127.0.0.1:8081/ | head -1
```

**Expected**: `HTTP 200` or `HTTP 302` (NOT `HTTP 404` from nginx welcome page, NOT `Connection refused`)

- [ ] HTTP status is 200 or 302 (NOT 404 from nginx default page)
- [ ] If 404, it's from Laravel (check error page mentions "404 Not Found" from Laravel)

---

### Phase 4: Database Verification (1 min)

```bash
# Run command:
docker exec webapp_core_db_fresh mysql -uroot -proot \
  -e "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='webapp_core' AND TABLE_NAME LIKE 'helpdesk%';" | wc -l
```

**Expected**: Output > 20 (indicating 20+ helpdesk_* tables)

- [ ] Count > 20
- [ ] helpdesk_settings exists: `docker exec webapp_core_db_fresh mysql -uroot -proot -e "USE webapp_core; SHOW TABLES LIKE 'helpdesk_settings';" | tail -1`

---

### Phase 5: Route Registration (1 min)

```bash
# Run command:
docker exec webapp_core_app_fresh php artisan route:list 2>/dev/null | grep -c "helpdesk"
```

**Expected**: Output > 20 (indicating 20+ registered helpdesk routes)

- [ ] Count > 20
- [ ] Sample routes present:
  - [ ] `/helpdesk/api/customer/register` (POST)
  - [ ] `/helpdesk/api/customer/login` (POST)
  - [ ] `/helpdesk/api/openticket` (POST)

---

### Phase 6: Proxy Chain (1 min)

**Test 1: Proxy to nginx**
```bash
curl -i http://127.0.0.1:3101/api/helpdesk/customer/login \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{}' | head -1
```

**Expected**: `HTTP 422` or `HTTP 400` or `HTTP 401` (NOT `HTTP 404` from nginx, NOT `HTTP 502` from gateway)

- [ ] Status is 4xx (client error) — means route exists and Laravel validates input
- [ ] NOT 404 (which would mean route doesn't exist)
- [ ] NOT 502 (which would mean upstream unreachable)

**Test 2: Auth headers forwarded**
```bash
curl -s -X POST http://127.0.0.1:3101/api/helpdesk/customer/login \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token" \
  -d '{"email":"user@test.com","password":"password"}' | head -5
```

**Expected**: HTTP 422 or 401 (same as Test 1, but with auth header forwarded)

- [ ] Request completed (not hanging)
- [ ] Same status as Test 1 (confirms headers are forwarded)

**Test 3: JSON body forwarded**
```bash
curl -s -X POST http://127.0.0.1:3101/api/helpdesk/openticket \
  -H "Content-Type: application/json" \
  -d '{
    "name":"John Doe",
    "email":"john@example.com",
    "title":"Test Ticket",
    "description":"This is a test",
    "category_id":1
  }' | jq -r '.message // .error // "no error"'
```

**Expected**: Either success response or validation error message (NOT generic gateway error)

- [ ] Response is JSON
- [ ] Contains either success data or validation errors (not "upstream unavailable")

---

### Phase 7: Error Handling (1 min)

**Test: Upstream unavailable**
```bash
# Stop nginx to simulate upstream failure
docker stop webapp_core_nginx_fresh

# Try to call gateway
curl -s http://127.0.0.1:3101/api/helpdesk/customer/login \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{}' | jq .

# Restart nginx
docker start webapp_core_nginx_fresh
```

**Expected**: HTTP 502 with JSON error message

- [ ] Status is 502
- [ ] Response contains `"error": "Bad Gateway"`
- [ ] nginx comes back up when restarted

---

### Phase 8: Final Validation (1 min)

**Run full test script**:
```bash
#!/bin/bash
set -e

echo "✓ VERIFICATION START"

# 1. Containers
RUNNING=$(docker ps --format 'table {{.Names}}\t{{.Status}}' | \
  grep -E "customer-service-gateway|webapp_core_" | wc -l)
[ "$RUNNING" -ge 5 ] && echo "✓ All containers running ($RUNNING)" || exit 1

# 2. Gateway health
HEALTH=$(curl -s http://127.0.0.1:3101/health | jq -r '.status')
[ "$HEALTH" = "ok" ] && echo "✓ Gateway healthy" || exit 1

# 3. Database tables
TABLES=$(docker exec webapp_core_db_fresh mysql -uroot -proot \
  -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='webapp_core' AND TABLE_NAME LIKE 'helpdesk%';" \
  2>/dev/null | tail -1)
[ "$TABLES" -gt 20 ] && echo "✓ Database tables present ($TABLES)" || exit 1

# 4. Routes registered
ROUTES=$(docker exec webapp_core_app_fresh php artisan route:list 2>/dev/null | \
  grep -c "helpdesk" || echo 0)
[ "$ROUTES" -gt 20 ] && echo "✓ Routes registered ($ROUTES)" || exit 1

# 5. Proxy chain
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  http://127.0.0.1:3101/api/helpdesk/customer/login \
  -H "Content-Type: application/json" \
  -d '{}')
[[ "$STATUS" =~ ^4 ]] && echo "✓ Proxy chain working (HTTP $STATUS)" || exit 1

echo ""
echo "✅ ALL CHECKS PASSED — Integration is ready!"
```

- [ ] All 5 validation checks pass
- [ ] Output shows "✅ ALL CHECKS PASSED"

---

## Success Criteria Summary

If all checks pass, the integration is **ready for feature development**:

| Check | Threshold | Pass/Fail |
| --- | --- | --- |
| Containers running | ≥5 | ☐ |
| Gateway health | "ok" | ☐ |
| Database tables | >20 | ☐ |
| Routes registered | >20 | ☐ |
| Proxy chain | HTTP 4xx (not 404/502) | ☐ |
| Error handling | HTTP 502 on upstream down | ☐ |

**Gate**: Proceed to Phase 3 (Features) in INTEGRATION_ROADMAP.md only if ALL checks pass.

---

## Troubleshooting Quick Links

| Symptom | Check | Reference |
| --- | --- | --- |
| Gateway returns 502 | Test 2 (proxy chain) | OPERATIONAL_PROCEDURES.md § Issue 1 |
| Gateway returns 404 | Test 1 (route registration) | HELPDESKCLIENT_INTERNALS.md § Migration Collision Analysis |
| Database tables missing | Phase 4 | BLOCKERS_AND_FIXES.md § N2 |
| Nginx serving welcome page | Phase 3 | BLOCKERS_AND_FIXES.md § N1 |
| Routes not registered | Phase 5 | HELPDESKCLIENT_INTERNALS.md § Service Boot Order |

---

## Sign-Off

**Verified By**: ________________  
**Date/Time**: ________________  
**Environment**: ☐ Local Dev  ☐ Staging  ☐ Production  

**All checks passed**: ☐ Yes  ☐ No (if no, see Troubleshooting section)

**Ready to proceed to Phase 3**: ☐ Yes  ☐ No
