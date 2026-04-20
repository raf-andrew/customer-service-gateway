# Upgrade Procedures

## Gateway Version Upgrade

### Pre-Upgrade Checklist

- [ ] Back up database: `bash scripts/backup.sh`
- [ ] Document current version: `docker images | grep gateway`
- [ ] Review CHANGELOG.md for breaking changes
- [ ] Test in staging environment first
- [ ] Plan maintenance window (if production)
- [ ] Notify team of planned downtime
- [ ] Prepare rollback plan

### Upgrade Process (Development/Staging)

**Step 1: Pull latest code**

```bash
git checkout main
git pull origin main
```

**Step 2: Check for changes**

```bash
git log --oneline HEAD~5..HEAD
```

**Step 3: Review changes**

```bash
git diff HEAD~1..HEAD -- src/
```

**Step 4: Build new image**

```bash
npm install
npm run build
docker build -t customer-service-gateway:latest .
```

**Step 5: Test locally**

```bash
docker compose up -d gateway
sleep 10
bash scripts/health-check.sh
```

**Step 6: Run tests**

```bash
npm test
```

**Step 7: If successful, tag version**

```bash
git tag v1.1.0
git push origin v1.1.0
```

**Step 8: Push image to registry**

```bash
docker tag customer-service-gateway:latest ghcr.io/yourorg/gateway:v1.1.0
docker push ghcr.io/yourorg/gateway:v1.1.0
docker tag customer-service-gateway:latest ghcr.io/yourorg/gateway:latest
docker push ghcr.io/yourorg/gateway:latest
```

### Production Upgrade (Zero-Downtime)

**Prerequisites:**
- Two gateway instances running (load balanced)
- Staging environment thoroughly tested
- Team lead approval
- Backup created

**Step 1: Create backup**

```bash
ssh deploy@prod-server
cd /opt/gateway
bash scripts/backup.sh
```

**Step 2: Pull new image**

```bash
docker pull ghcr.io/yourorg/gateway:v1.1.0
```

**Step 3: Upgrade first instance (blue)**

```bash
# Stop first instance
docker compose stop gateway-blue

# Start with new image
docker compose up -d gateway-blue

# Wait for health checks
sleep 10
curl http://localhost:3101/health
```

**Step 4: Verify first instance**

```bash
# Run smoke tests
bash scripts/health-check.sh

# Monitor logs
docker compose logs -f gateway-blue | head -20
```

**Step 5: Upgrade second instance (green)**

```bash
# Stop second instance
docker compose stop gateway-green

# Start with new image
docker compose up -d gateway-green

# Verify
curl http://localhost:3102/health  # Different port
```

**Step 6: Verify both instances**

```bash
# Both should respond
curl http://localhost:3101/health
curl http://localhost:3102/health
```

**Step 7: Complete rollout**

```bash
# Both instances now running new version
# Load balancer continues distributing traffic
# No downtime!
```

### Rollback Procedure

If upgrade fails:

**Immediate rollback (within 10 minutes):**

```bash
# Step 1: Switch back to previous image
docker kill gateway-blue
docker pull ghcr.io/yourorg/gateway:v1.0.0
docker run -d ... ghcr.io/yourorg/gateway:v1.0.0

# Step 2: Verify previous version
curl http://localhost:3101/health

# Step 3: If issues persist, restore database
bash scripts/restore.sh ../webapp_core/backups/webapp_core_TIMESTAMP.sql.gz
```

**Delayed rollback (after 1+ hour):**

```bash
# Step 1: Identify good backup
ls -lh ../webapp_core/backups/ | head -5

# Step 2: Full restore procedure
docker compose down
docker compose up -d
bash scripts/restore.sh ../webapp_core/backups/webapp_core_TIMESTAMP.sql.gz

# Step 3: Verify
bash scripts/health-check.sh
```

## Node.js/NPM Dependency Upgrade

### For Patch Updates (v1.0.0 → v1.0.1)

Low risk, can merge directly:

```bash
npm update              # Update to latest patch versions
npm install            # Install updated dependencies
npm test               # Verify tests still pass
git add package-lock.json
git commit -m "chore: update npm dependencies"
git push origin feature/upgrade-deps
```

### For Minor Updates (v1.0.0 → v1.1.0)

Medium risk, needs review:

```bash
npm outdated                    # See available updates
npm install express@1.5.0       # Upgrade specific package
npm install                     # Install all
npm test                        # Run full test suite
git add package*.json
git commit -m "feat: upgrade express to 1.5.0"
```

### For Major Updates (v1.0.0 → v2.0.0)

High risk, needs extensive testing:

```bash
# Step 1: Research changes
# Visit: https://github.com/package/releases

# Step 2: Update in dev branch
npm install express@2.0.0
npm install

# Step 3: Check breaking changes
npm run build
npm test

# Step 4: Fix breaking changes
# Edit src/ files as needed
npm run build
npm test

# Step 5: Create PR and request review
git commit -m "BREAKING: upgrade express to 2.0.0"
```

**Review checklist for major upgrades:**

- [ ] All tests pass
- [ ] No deprecation warnings
- [ ] TypeScript types available
- [ ] Code examples updated
- [ ] Dependencies updated (if needed)

## Docker Base Image Upgrade

### Upgrade Node.js LTS Version

**In Dockerfile:**

```dockerfile
# Old
FROM node:18-alpine

# New
FROM node:20-alpine
```

**Build and test:**

```bash
docker build -t gateway:node20 .
docker run -it gateway:node20 npm test
```

**Verify compatibility:**

```bash
# Check node modules still install
docker run gateway:node20 npm list

# Check final image size
docker images | grep gateway
```

## Database Migration Upgrade

**For Laravel migrations in webapp_core:**

```bash
# Step 1: Verify new migrations exist
docker exec webapp_core_app_fresh php artisan migrate:status

# Step 2: Backup database first
bash scripts/backup.sh

# Step 3: Run migrations
docker exec webapp_core_app_fresh php artisan migrate

# Step 4: Verify tables were created
docker exec webapp_core_db_fresh mysql -uroot -proot webapp_core -e "SHOW TABLES;"

# Step 5: Test application
bash scripts/health-check.sh
```

## Scheduled Maintenance Upgrades

**Monthly patching cycle:**

- Week 1: Review available updates
- Week 2: Test in staging
- Week 3: Upgrade development
- Week 4: Plan production upgrade

**Quarterly major updates:**

- Month 1: Research and planning
- Month 2: Development and testing
- Month 3: Staging validation
- Month 4: Production rollout

## Upgrade Checklist Template

```
VERSION UPGRADE: [old] → [new]
Date: [YYYY-MM-DD]
Approver: [Name]

PRE-UPGRADE:
- [ ] Backup created
- [ ] Staging tested
- [ ] Team notified
- [ ] Rollback plan prepared
- [ ] CHANGELOG reviewed

UPGRADE:
- [ ] New version pulled
- [ ] Build successful
- [ ] Tests passing
- [ ] Health checks pass
- [ ] Smoke tests pass

POST-UPGRADE:
- [ ] Monitor logs (first 1 hour)
- [ ] Verify all endpoints
- [ ] Check database health
- [ ] Monitor performance
- [ ] Document any issues

SIGN-OFF:
- [ ] Tech lead approved
- [ ] All checks passed
- [ ] Team notified
- [ ] Documentation updated
```

## Emergency Upgrade (Production Down)

**If production is completely down:**

```bash
# Step 1: Assess situation
docker ps -a
docker logs gateway 2>&1 | tail -30

# Step 2: Emergency restart
docker restart gateway

# Step 3: If restart fails, restore backup
bash scripts/restore.sh <latest-backup>

# Step 4: Verify recovery
bash scripts/health-check.sh

# Step 5: Document incident
echo "$(date) - Emergency recovery executed" >> incident.log
```

## References

- Node.js Releases: https://nodejs.org/en/about/releases/
- Express.js Breaking Changes: https://expressjs.com/en/changelog.html
- Docker Best Practices: https://docs.docker.com/develop/dev-best-practices/
