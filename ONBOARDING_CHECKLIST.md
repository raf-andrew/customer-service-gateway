# Onboarding Checklist for New Team Members

## Week 1: Environment Setup

### Day 1: Access & Tools (2 hours)

- [ ] Create GitHub account and request access to repository
- [ ] Install Docker Desktop
- [ ] Install Node.js 20 LTS
- [ ] Install Visual Studio Code (or preferred editor)
- [ ] Install Git
- [ ] Clone repository: `git clone https://github.com/yourorg/customer-service-gateway.git`
- [ ] Verify Docker is running: `docker ps`
- [ ] Verify Node version: `node --version` (expect v20.x.x)

**Success criteria:** All tools installed, repository cloned, `docker ps` returns running containers

### Day 2: Local Setup (4 hours)

**For all roles:**

- [ ] Run setup script: `bash scripts/setup.sh`
- [ ] Wait for stack to start (3-5 minutes)
- [ ] Run health check: `bash scripts/health-check.sh`
- [ ] View logs: `bash scripts/logs.sh`
- [ ] Review FILE_INVENTORY.md
- [ ] Review INTEGRATION_STATUS.md to understand current state
- [ ] Read relevant QUICK_START guide for your role

**For Backend Developers:**

- [ ] Review QUICK_START_BACKEND.md
- [ ] Make a test code change in `src/index.ts`
- [ ] Run `npm run build` to compile
- [ ] Restart gateway: `docker compose restart gateway`
- [ ] Verify change in logs

**For Frontend Developers:**

- [ ] Review QUICK_START_FRONTEND.md
- [ ] Test API endpoint with curl:
  ```bash
  curl http://127.0.0.1:3101/helpdesk/api/v1/guest/routes
  ```
- [ ] Review ENDPOINT_REFERENCE.md
- [ ] Note gateway URL: `http://127.0.0.1:3101`

**For DevOps Engineers:**

- [ ] Review QUICK_START_DEVOPS.md
- [ ] Understand Docker Compose structure: `cat docker-compose.yml`
- [ ] Review OPERATIONAL_PROCEDURES.md
- [ ] Check backup script: `bash scripts/backup.sh`

**For QA Engineers:**

- [ ] Review QUICK_START_QA.md
- [ ] Run health check: `bash scripts/health-check.sh`
- [ ] Review TESTING_PLAYBOOK.md
- [ ] Run smoke tests: `npm test`

**Success criteria:** All stacks running, health checks pass, role-specific setup complete

### Day 3-5: Understanding Architecture (6 hours)

**Read and understand:**

- [ ] DEVELOPER_GUIDE.md — Project structure and conventions
- [ ] INTEGRATION_STATUS.md — Current status and blockers
- [ ] BLOCKERS_AND_FIXES.md — Known issues and workarounds
- [ ] HELPDESKCLIENT_INTERNALS.md — How Laravel package works
- [ ] INFRASTRUCTURE_REFERENCE.md — Network topology
- [ ] RELATED_PACKAGES.md — Optional packages overview

**Hands-on:**

- [ ] Trace a request from gateway → nginx → Laravel
- [ ] View database tables: `docker exec webapp_core_db_fresh mysql -uroot -proot webapp_core -e "SHOW TABLES;"`
- [ ] List Laravel routes: `docker exec webapp_core_app_fresh php artisan route:list | head -20`
- [ ] Check service providers: `cat ../webapp_core/config/app.php | grep -A 20 providers`

**Success criteria:** Can explain proxy chain, understand blocker status, know how to debug

## Week 2: Hands-On Experience

### Backend Developers (Days 6-10)

- [ ] Create a new endpoint in the gateway (modify src/routes/)
- [ ] Test endpoint with curl
- [ ] Add unit test for endpoint
- [ ] Run test suite: `npm test`
- [ ] Understand environment variables in .env
- [ ] Create a git branch: `git checkout -b feature/my-endpoint`
- [ ] Push to GitHub: `git push origin feature/my-endpoint`
- [ ] Create pull request
- [ ] Code review pass (if applicable)

**Success criteria:** Comfortable making code changes, running tests, creating PRs

### Frontend Developers (Days 6-10)

- [ ] Set up your frontend project locally
- [ ] Make API call to gateway endpoint
- [ ] Handle authentication (tokens)
- [ ] Handle CORS (review QUICK_START_FRONTEND.md § CORS)
- [ ] Test error handling
- [ ] Monitor requests in browser DevTools
- [ ] Create test for API integration

**Success criteria:** Can call endpoints, handle auth, understand CORS requirements

### DevOps Engineers (Days 6-10)

- [ ] Create a manual backup: `bash scripts/backup.sh`
- [ ] Test restore procedure: `bash scripts/restore.sh <backup_file>`
- [ ] Monitor container logs: `docker compose logs -f`
- [ ] Restart a service: `docker compose restart gateway`
- [ ] Understand health checks: `bash scripts/health-check.sh`
- [ ] Review CI/CD pipeline (if configured)
- [ ] Document a runbook for common tasks

**Success criteria:** Can perform common ops tasks, understand backup/restore

### QA Engineers (Days 6-10)

- [ ] Execute all test suites: `npm test`
- [ ] Run TESTING_PLAYBOOK.md manually
- [ ] Create test case for new feature
- [ ] Document test results
- [ ] Review DEPLOYMENT_VERIFICATION.md
- [ ] Understand BLOCKERS_AND_FIXES.md
- [ ] Identify blockers affecting testing

**Success criteria:** Can run tests independently, understand test coverage

## Week 3: Integration & Productivity

### All Roles (Days 11-15)

**Blockers & Known Issues:**

- [ ] Review BLOCKERS_AND_FIXES.md in detail
- [ ] Understand which blockers affect your work
- [ ] Know escalation path if blocked

**Disaster Recovery:**

- [ ] Review DISASTER_RECOVERY.md
- [ ] Understand RTO/RPO targets
- [ ] Know how to respond to outages

**Deployment:**

- [ ] Review DEPLOYMENT_VERIFICATION.md
- [ ] Understand pre-deployment checklist
- [ ] Know deployment approval process

**Documentation:**

- [ ] Update personal notes with setup commands
- [ ] Document any gaps you found in onboarding
- [ ] Suggest improvements to documentation

**Communication:**

- [ ] Join team Slack/chat channels
- [ ] Schedule 1-on-1 with team lead
- [ ] Ask questions and get feedback on Week 1-2 work

**Success criteria:** Understand blocker landscape, can contribute independently, productive on tasks

## Role-Specific Responsibilities

### Backend Developers

**Required Knowledge:**
- TypeScript/Node.js
- Express.js middleware
- Proxy patterns
- HTTP request/response cycle
- Testing practices

**Key Docs:**
- QUICK_START_BACKEND.md
- DEVELOPER_GUIDE.md
- ENDPOINT_REFERENCE.md

**First Task:** Add a new endpoint to the gateway

### Frontend Developers

**Required Knowledge:**
- HTTP requests (fetch/axios)
- CORS and authentication
- API integration patterns
- Browser DevTools
- Error handling

**Key Docs:**
- QUICK_START_FRONTEND.md
- ENDPOINT_REFERENCE.md
- BLOCKERS_AND_FIXES.md (N5 - auth)

**First Task:** Integrate gateway API into your frontend

### DevOps Engineers

**Required Knowledge:**
- Docker & Docker Compose
- Container networking
- Backup/restore procedures
- Health checks & monitoring
- Deployment strategies

**Key Docs:**
- QUICK_START_DEVOPS.md
- OPERATIONAL_PROCEDURES.md
- DISASTER_RECOVERY.md

**First Task:** Document a deployment runbook

### QA Engineers

**Required Knowledge:**
- Test planning & execution
- API testing
- Manual vs automated testing
- Test data management
- Defect tracking

**Key Docs:**
- QUICK_START_QA.md
- TESTING_PLAYBOOK.md
- DEPLOYMENT_VERIFICATION.md

**First Task:** Execute full test suite and document results

## Onboarding Completion Checklist

**Week 3 Sign-Off:**

- [ ] All tools installed and working
- [ ] Both Docker stacks running
- [ ] Health checks passing
- [ ] Completed role-specific training
- [ ] Completed first task independently
- [ ] Received code/work review feedback
- [ ] Know escalation path for blockers
- [ ] Documentation questions answered
- [ ] Invited to all relevant meetings/channels
- [ ] Scheduled follow-up (1 week, 1 month)

**Team Lead Sign-Off Required:**

- [ ] New developer is productive
- [ ] New developer understands architecture
- [ ] New developer can debug issues
- [ ] New developer can follow runbooks
- [ ] Ready for independent assigned work

## Common Onboarding Issues

| Issue | Solution |
|-------|----------|
| Docker won't start | See TROUBLESHOOTING.md § Docker daemon |
| Health check fails | See BLOCKERS_AND_FIXES.md |
| Can't connect to database | Check network: `docker network ls` |
| API returns 502 | Check nginx: `docker compose logs nginx` |
| Routes not registered | See BLOCKERS_AND_FIXES.md § N2 |
| CORS errors | See QUICK_START_FRONTEND.md § CORS |
| Tests failing | See TESTING_PLAYBOOK.md |

## Post-Onboarding (After Week 3)

- [ ] Schedule 1-month check-in
- [ ] Gather onboarding feedback
- [ ] Suggest documentation improvements
- [ ] Assign first production task
- [ ] Begin code review rotation
- [ ] Included in on-call rotation (if applicable)

## Resources

- **Setup:** `scripts/setup.sh`
- **Testing:** `npm test`
- **Logs:** `scripts/logs.sh`
- **Documentation:** See FILE_INVENTORY.md
- **Slack channel:** #customer-service-gateway (or equivalent)
- **Meetings:** See calendar invites
- **On-call runbook:** OPERATIONAL_PROCEDURES.md
- **Escalation:** Team lead → Tech lead → Engineering manager

## Success Metrics

After onboarding, new team member should be able to:

- ✓ Run gateway and supporting stacks locally
- ✓ Understand system architecture and data flow
- ✓ Debug common issues independently
- ✓ Make code changes and test them
- ✓ Follow runbooks for common tasks
- ✓ Identify and report blockers appropriately
- ✓ Review others' code against standards
- ✓ Handle on-call situations with guidance

**Estimated time to productivity:** 3 weeks
