# CI/CD Guide

**Last Updated:** 2026-04-20  
**Version:** 1.0  
**Status:** Ready for GitHub setup

---

## Overview

This repository uses GitHub Actions for continuous integration and deployment. Three automated workflows validate code quality, infrastructure health, and deployment readiness on every push.

---

## Workflows

### 1. Health Check (01-health-check.yml)

**Purpose:** Validate all infrastructure components are operational

**Trigger:**
- On every push to `main` or `develop` branches
- On every pull request to `main` or `develop`
- Scheduled daily (6-hour intervals)

**Actions:**
1. Build Docker images from Dockerfile.web
2. Start all containers (gateway, nginx, PHP-FPM, MySQL, Redis)
3. Run health check script
4. Report pass/fail status
5. Collect logs on failure
6. Clean up containers

**Expected Result:** 7/8 checks passing
- 7 checks always pass (gateway, nginx, PHP-FPM, MySQL, Redis, network, basic routing)
- 1 check warns if N2 blocker not resolved (routes not registered)

**Troubleshooting:**
- If health check fails, see OPERATIONAL_PROCEDURES.md
- Check Docker daemon is running
- Verify port 8081 is available

---

### 2. Code Quality (02-code-quality.yml)

**Purpose:** Validate code quality and configuration correctness

**Trigger:**
- On every push to `main` or `develop` branches
- On every pull request to `main` or `develop`

**Checks:**
1. Docker Compose validation - Ensures docker-compose.local.yml syntax is correct
2. Shell script linting - Checks scripts for common issues
3. YAML validation - Validates workflow YAML files
4. Nginx configuration - Tests nginx config syntax
5. Security checks - Looks for hardcoded passwords or secrets

**Expected Result:**
- Docker Compose: ✓ Valid
- Shell Scripts: ✓ Checked
- YAML: ✓ Valid
- Nginx: ✓ Valid
- Security: ✓ Passed

**Troubleshooting:**
- ShellCheck warnings are informational only
- YAML errors must be fixed before merge
- Nginx config errors indicate configuration problems

---

### 3. Deployment Validation (03-deploy-validation.yml)

**Purpose:** Verify system readiness for deployment

**Trigger:**
- On every push to `main` branch
- Manual trigger via `workflow_dispatch`

**Checks:**
1. Documentation completeness
2. Infrastructure files present
3. Scripts executable
4. Status reports current
5. Blockers documented

**Expected Result:**
- System is ready for deployment
- All documentation in place
- Known blockers identified
- Deployment report generated

**Artifacts:**
- `deployment-readiness-report.txt` - Full deployment assessment

---

## Local Testing

### Run Health Check Locally

```bash
cd /f/www/customer-service-gateway
bash scripts/health-check.sh
```

Expected: 7/8 checks passing

### Validate Docker Compose

```bash
cd /f/www/webapp_core
docker-compose -f docker-compose.local.yml config
```

Expected: Configuration valid (no errors)

### Test Nginx Configuration

```bash
docker run --rm \
  -v /f/www/webapp_core/docker/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v /f/www/webapp_core/docker/conf.d:/etc/nginx/conf.d:ro \
  nginx:1.25-alpine \
  nginx -t
```

Expected: Configuration test successful

### Lint Shell Scripts

```bash
shellcheck /f/www/customer-service-gateway/scripts/*.sh
```

Expected: No critical errors (warnings OK)

---

## GitHub Setup (Required)

To enable CI/CD workflows, you need to:

### Step 1: Create GitHub Repository

```bash
gh repo create customer-service-gateway \
  --public \
  --source=. \
  --remote=origin
```

Or via GitHub web interface:
1. Create new repository on github.com
2. Copy HTTPS or SSH URL
3. Add remote: `git remote add origin <URL>`

### Step 2: Push Initial Commit

```bash
cd /f/www/customer-service-gateway
git add .
git commit -m "Initial commit: Infrastructure and CI/CD setup

- Docker Compose configuration (local + staging)
- Health check and operational scripts
- Backup/restore procedures
- GitHub Actions workflows
- Comprehensive documentation"
git push -u origin main
```

### Step 3: Verify Workflows

1. Go to GitHub repository
2. Click "Actions" tab
3. Verify workflows appear: Health Check, Code Quality, Deployment Validation
4. Wait for first run to complete (5-10 minutes)

### Step 4: Configure Branch Protection (Optional)

To require workflows to pass before merging:

1. Go to Settings → Branches
2. Add branch protection rule for `main`
3. Require status checks to pass:
   - Health Check
   - Code Quality
   - Deployment Validation

---

## Workflow Status Badges

Add to README.md to display workflow status:

```markdown
[![Health Check](https://github.com/YOUR_ORG/customer-service-gateway/actions/workflows/01-health-check.yml/badge.svg)](https://github.com/YOUR_ORG/customer-service-gateway/actions/workflows/01-health-check.yml)
[![Code Quality](https://github.com/YOUR_ORG/customer-service-gateway/actions/workflows/02-code-quality.yml/badge.svg)](https://github.com/YOUR_ORG/customer-service-gateway/actions/workflows/02-code-quality.yml)
[![Deployment Validation](https://github.com/YOUR_ORG/customer-service-gateway/actions/workflows/03-deploy-validation.yml/badge.svg)](https://github.com/YOUR_ORG/customer-service-gateway/actions/workflows/03-deploy-validation.yml)
```

---

## Troubleshooting

### Workflow Won't Start

**Check:**
- Repository is public or has Actions enabled
- Workflow files are in `.github/workflows/` directory
- Workflow YAML syntax is valid (run `yamllint`)

### Health Check Fails

**Common causes:**
- Docker daemon not running
- Port 8081 already in use
- Insufficient disk space for Docker images
- PHP extensions not installed in container

**Fix:**
- Check Docker status: `docker ps`
- Free ports: `sudo lsof -i :8081`
- Check disk: `df -h`
- Rebuild image: `docker-compose build --no-cache`

### Code Quality Check Fails

**Common causes:**
- Docker Compose YAML syntax error
- Shell script syntax error
- Nginx configuration invalid

**Fix:**
- Run locally: `docker-compose config`
- Lint script: `shellcheck scripts/*.sh`
- Test nginx: `nginx -t`

### Deployment Validation Fails

**Common causes:**
- Missing documentation files
- Scripts not executable
- Status reports outdated

**Fix:**
- Check file permissions: `ls -l`
- Update status reports: Run Batch completion steps
- Ensure all required files present

---

## Customization

### Add Custom Checks

Edit workflow files to add:
- Code coverage thresholds
- Performance benchmarks
- Security scanning
- Dependency checks

### Adjust Schedules

**Health Check schedule** (line 8):
```yaml
schedule:
  - cron: '0 */6 * * *'  # Every 6 hours
```

Change to run more/less frequently:
- `0 * * * *` - Every hour
- `0 9 * * *` - Daily at 9am
- `0 9 * * 1` - Weekly on Monday

### Modify Triggers

Change which branches trigger workflows:
```yaml
on:
  push:
    branches: [ main, develop, staging ]
  pull_request:
    branches: [ main, develop ]
```

---

## Best Practices

1. **Keep workflows fast** - Target 5-10 minute execution time
2. **Document failures** - Always capture logs on failure
3. **Test locally first** - Run scripts locally before pushing
4. **Review reports** - Check deployment readiness reports regularly
5. **Update blockers** - Keep N2_BLOCKER_DETAILED_ANALYSIS.md current
6. **Branch protection** - Require status checks on main branch

---

## Related Documentation

- **Health Check Script:** `scripts/health-check.sh`
- **Operational Procedures:** `OPERATIONAL_PROCEDURES.md`
- **Deployment Guide:** `DEPLOYMENT_VERIFICATION.md`
- **Blockers:** `BLOCKERS_AND_FIXES.md` and `N2_BLOCKER_DETAILED_ANALYSIS.md`
- **Batch Reports:** `BATCH_*_STATUS_REPORT.md`

---

## Support

If workflows fail:

1. Check GitHub Actions logs (click on failed workflow)
2. Run health check locally: `bash scripts/health-check.sh`
3. Review troubleshooting section above
4. Check OPERATIONAL_PROCEDURES.md for system-level issues
5. Consult N2_BLOCKER_DETAILED_ANALYSIS.md for known blockers

---

**Created:** 2026-04-20  
**Last Updated:** 2026-04-20  
**Status:** Ready for GitHub setup
