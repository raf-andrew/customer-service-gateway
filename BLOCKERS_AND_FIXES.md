# Integration Blockers & Fix Paths

Date: 2026-04-19
Scope: Detailed decision trees and implementation paths for each of the 6 identified blockers (N1–N6).

---

## N1: webapp_core_nginx_fresh serves default welcome page, not Laravel

**Blocker ID**: N1-NGINX-CONFIG  
**Severity**: Critical (gates all other fixes)  
**Tool evidence**: `docker exec webapp_core_nginx_fresh cat /etc/nginx/conf.d/default.conf` shows default nginx welcome config. No FastCGI block. No PHP-FPM proxy.

### Root Cause

The `F:\www\webapp_core\docker-compose.local.yml` mounts source code (`./:/var/www/html:ro`) but does **not** mount an nginx site config:

```yaml
services:
  nginx:
    image: nginx:1.25-alpine
    volumes:
      - ./:/var/www/html:ro              # Source code
      - ./public:/var/www/html/public:ro # Public dir
      # NO nginx config mount
```

The image's `nginx:1.25-alpine` default `/etc/nginx/conf.d/default.conf` serves the built-in welcome page from `/usr/share/nginx/html`, and the FastCGI block is commented out.

### What Breaks

Every request to the gateway proxies correctly to nginx. But nginx never forwards to `php-fpm:9000` — it returns its default 404 or the welcome page. **No Laravel route can ever be reached through this stack until this is fixed.**

### Fix Option A: Mount the on-disk nginx config

**Files involved**:
- `F:\www\webapp_core\docker/nginx.conf` (940 bytes — main http-level config)
- `F:\www\webapp_core\nginx.conf/` (directory — **currently empty**)

**Steps**:

1. Create a Laravel site config at `F:\www\webapp_core\nginx.conf/laravel.conf`:
   ```bash
   cat > F:\www\webapp_core\nginx.conf/laravel.conf << 'EOF'
   server {
       listen 80 default_server;
       server_name _;
       root /var/www/html/public;
       index index.php;
   
       location / {
           try_files $uri $uri/ /index.php?$query_string;
       }
   
       location ~ \.php$ {
           fastcgi_pass php-fpm:9000;
           fastcgi_index index.php;
           fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
           include fastcgi_params;
       }
   }
   EOF
   ```

2. Update `docker-compose.local.yml`:
   ```yaml
   nginx:
     volumes:
       - ./:/var/www/html:ro
       - ./public:/var/www/html/public:ro
       - ./nginx.conf:/etc/nginx/conf.d:ro  # ADD THIS LINE
   ```

3. Recreate nginx: `docker compose up -d --force-recreate nginx`

4. Verify: `curl http://127.0.0.1:8081/` should return Laravel's default response (or the webapp's public/index.html)

**Pros**:
- Minimal: just add a site config file + 1 volume line
- Keeps existing docker-compose.local.yml pattern
- Works immediately

**Cons**:
- Nginx config must be kept in sync with Laravel requirements
- Won't work if there are multiple nginx config files in `nginx.conf/` (the mount is a volume, not individual files)

**Risk level**: Low. No code changes, fresh stack is isolated.

---

### Fix Option B: Repoint gateway to the staging nginx

**Blocker**: `webapp-nginx-staging` (from `C:\webapp_core\docker-compose.staging.yml`) already has Laravel site config and serves PHP correctly. But:
- It's on a different compose stack + network
- docker-compose.staging.yml declares `ports: 8080:80` but the nginx config listens on port 8080 inside (so the mapping is broken: 8080:80 means 8080 **outside** → 80 **inside**, but nginx listens on 8080)

**Steps**:

1. Fix the staging nginx port mapping:
   ```yaml
   nginx:
     ports:
       - "8081:80"  # Changed from 8080:80
   ```

2. Update gateway docker-compose.yml:
   ```yaml
   environment:
     HELPDESK_API_URL: "http://webapp-nginx-staging:80/helpdesk/api"
   ```

3. Verify both stacks are on the same network (or create integration bridge).

**Pros**:
- Reuses existing, tested nginx config
- Avoids maintaining dual nginx setups

**Cons**:
- Mixes two separate compose stacks (fresh + staging)
- Port mapping issue suggests the staging stack may have other drift
- Requires modifying C:\webapp_core (shared infrastructure)

**Risk level**: Medium. Modifies shared infrastructure.

---

### Fix Option C: Use a dedicated PHP-serving image

**Approach**: Create a custom image that includes the Laravel site config baked into the Dockerfile.

```dockerfile
FROM nginx:1.25-alpine
COPY nginx.conf/laravel.conf /etc/nginx/conf.d/default.conf
WORKDIR /var/www/html
```

Build once, reuse. Isolates the config from the host.

**Pros**:
- Config never drifts (baked in)
- Clean separation (image = runnable unit)

**Cons**:
- Requires rebuilding the image every time nginx config changes
- Adds a build step to the docker-compose up workflow

**Risk level**: Low, but adds build complexity.

---

## Recommendation for N1

**Choose Fix Option A** (mount site config). It's minimal, low-risk, and keeps the fresh stack self-contained.

After applying N1 fix:
- Run `curl http://127.0.0.1:8081/` → should return Laravel's 500 or welcome (app not fully initialized yet)
- Run `curl http://127.0.0.1:3101/api/helpdesk/customer/login` → will return 404 from Laravel (not 404 from nginx), which means **nginx is now forwarding to PHP-FPM correctly**

---

## N2: No `helpdesk_*` tables in webapp_core database

**Blocker ID**: N2-HELPDESK-MIGRATIONS  
**Severity**: Critical (gates helpdesk route registration)  
**Tool evidence**: `docker exec webapp_core_db_fresh mysql -uroot -proot -e "USE webapp_core; SHOW TABLES LIKE 'helpdesk%';"` returns no rows.

### Root Cause

The HelpdeskClient package has 77 migrations in `packages/HelpdeskClient/database/migrations/`, but none have been run against the webapp_core database. Laravel's `Schema::hasTable('helpdesk_settings')` check fails, so the package's AppServiceProvider doesn't register any sub-providers, so RouteServiceProvider never mounts the `/helpdesk/api/*` routes.

### What Breaks

Even if N1 is fixed and nginx forwards to PHP-FPM, Laravel will return a 404 for `/helpdesk/api/customer/login` because the route doesn't exist yet.

### Fix Option A: Run migrations to the main webapp_core database

**Steps**:

1. Run migrations inside the app container:
   ```bash
   docker exec webapp_core_app_fresh php artisan migrate \
     --path=packages/HelpdeskClient/database/migrations
   ```

2. Verify tables were created:
   ```bash
   docker exec webapp_core_db_fresh mysql -uroot -proot \
     -e "USE webapp_core; SHOW TABLES LIKE 'helpdesk%';" | head -20
   ```

3. Verify routes are now registered:
   ```bash
   docker exec webapp_core_app_fresh php artisan route:list | grep helpdesk
   ```

**Pros**:
- Simple: one command
- All data in one database (no connection switching)

**Cons**:
- **Migration collision risk** (see N3 blocker below)
- helpdesk_* tables are now intermingled with webapp_core tables (coupling)
- Future helpdesk migrations will run in the same DB as app migrations

**Risk level**: High. Requires N3 triage first.

---

### Fix Option B: Use a separate helpdesk connection (matches original .env design)

The `.env.example` declares:
```
HELPDESK_DB_CONNECTION=helpdesk
HELPDESK_DB_DATABASE=webapp_core_helpdesk
```

This suggests the original architecture planned for a **separate connection**.

**Steps**:

1. Create a second MySQL database:
   ```bash
   docker exec webapp_core_db_fresh mysql -uroot -proot -e \
     "CREATE DATABASE webapp_core_helpdesk;"
   ```

2. Add a `helpdesk` connection to `config/database.php` (copy the `mysql` connection, change database name).

3. Configure the HelpdeskClient to use this connection. Check if there's a config file:
   ```bash
   ls /f/www/webapp_core/packages/HelpdeskClient/config/
   ```

4. Run migrations against the helpdesk connection:
   ```bash
   docker exec webapp_core_app_fresh php artisan migrate \
     --database=helpdesk \
     --path=packages/HelpdeskClient/database/migrations
   ```

5. Update `.env`:
   ```
   HELPDESK_DB_CONNECTION=helpdesk
   HELPDESK_DB_DATABASE=webapp_core_helpdesk
   HELPDESK_DB_HOST=db
   HELPDESK_DB_USERNAME=root
   HELPDESK_DB_PASSWORD=root
   ```

**Pros**:
- Matches the intended .env design
- Completely isolates helpdesk schema from app schema
- Collision risk from N3 disappears
- Easier to backup / restore helpdesk separately
- Aligns with the sidecar / SOA architecture

**Cons**:
- Requires modifying `config/database.php` (app-level change)
- Requires an additional database on the MySQL container
- More setup steps

**Risk level**: Low. More complex, but lower collision risk.

---

## Recommendation for N2

**Choose Fix Option B** (separate connection) because:
1. It matches the `.env.example` design intent
2. It avoids the N3 collision risk entirely
3. It's more maintainable long-term (helpdesk schema isolated)

After applying N2 fix:
- Run the migration command
- Run `curl -X POST http://127.0.0.1:3101/api/helpdesk/customer/login -H "Content-Type: application/json" -d '{}'`
- Should return a Laravel error (invalid input, auth required, etc.) — **not 404**
- This confirms the `/helpdesk/api/customer/login` route is now registered and reached

---

## N3: HelpdeskClient migrations collide with webapp_core migrations

**Blocker ID**: N3-MIGRATION-COLLISIONS  
**Severity**: High (if N2 Option A is chosen; low if Option B is chosen)  
**Tool evidence**: 
- `webapp_core/database/migrations/2023_08_03_111536_create_media_table.php` exists
- `packages/HelpdeskClient/database/migrations/2021_07_15_035926_create_media_table.php` exists
- Both tables named `media`

### Root Cause

HelpdeskClient was developed against an older Laravel version where `media` and `personal_access_tokens` tables didn't exist (or existed under different names). Running all 77 HelpdeskClient migrations into the same database as webapp_core will trigger "table already exists" errors.

### What Breaks (if Option A of N2 is chosen)

`php artisan migrate --path=packages/HelpdeskClient/database/migrations` will fail at or before `2021_07_15_035926_create_media_table.php` with:
```
SQLSTATE[HY000]: General error: 1050 Can't create table `webapp_core`.`media` (table already exists)
```

The migration transaction will roll back, and no helpdesk tables will be created.

### Fix Option A: Hand-curate the migrations

**Steps**:

1. List both sets of migrations:
   ```bash
   ls /f/www/webapp_core/database/migrations/ | sort
   ls /f/www/webapp_core/packages/HelpdeskClient/database/migrations/ | sort
   ```

2. Identify collisions by filename and table name (grep `Schema::create('media'` in both).

3. Delete colliding migrations from HelpdeskClient (or edit them to rename the tables).

4. Run migrations:
   ```bash
   docker exec webapp_core_app_fresh php artisan migrate \
     --path=packages/HelpdeskClient/database/migrations
   ```

**Pros**:
- Fine-grained control
- Can preserve both schemas if desired

**Cons**:
- Manual, error-prone
- Easy to miss collisions
- Changes package source code (bad practice)
- Needs owner verification of which collisions are safe to skip

**Risk level**: High. Requires careful review.

---

### Fix Option B: Use separate database (N2 Option B)

If N2 Option B is applied, N3 becomes **non-blocking** — helpdesk migrations run in a separate `webapp_core_helpdesk` database, so `media` table collisions never happen.

**Steps**: Same as N2 Option B (see above).

**Pros**:
- Eliminates collision risk entirely
- No manual curation needed

**Cons**:
- Requires N2 Option B to be chosen

**Risk level**: Low (if N2 Option B applied).

---

### Fix Option C: Fork the package

Create a local version of HelpdeskClient with colliding migrations removed or renamed. Maintain as an internal fork.

**Pros**: Fine-grained control, version control.  
**Cons**: Maintenance burden (upstream changes require manual merge).

**Risk level**: Medium (fork maintenance).

---

## Recommendation for N3

**Only relevant if N2 Option A is chosen.** If N2 Option B is chosen, this blocker is eliminated.

If you must apply Option A:
1. Have the HelpdeskClient owner review the 77 migrations
2. Remove or rename only the migrations that collide with existing webapp_core tables
3. Keep all others

Collisions suspected (need verification):
- `create_media_table`
- `create_personal_access_tokens_table` (Sanctum)

---

## N4: CVE-2024-28859 in swiftmailer (transitive dependency)

**Blocker ID**: N4-SECURITY-CVE  
**Severity**: Medium (not urgent for local dev, critical for deployment)  
**Tool evidence**: `composer audit` flagged `swiftmailer/swiftmailer` as vulnerable. It's a transitive dependency (pulled in by another package, not directly required).

### Root Cause

The `swiftmailer/swiftmailer` package is abandoned and has a known vulnerability. It's likely pulled in by the email notification stack (EmailClient or another mailer).

### Fix Options

1. **Update the transitive dependency's package** to use a non-vulnerable mail library (e.g., if it's pulled by Laravel Mailgun mailer, update to a newer version that doesn't use swiftmailer).
2. **Wait for patches** if swiftmailer is replaced upstream.
3. **Document the risk** and monitor composer audit reports monthly.

### Recommendation

**For local dev**: Acceptable to proceed. The vulnerability is real but unlikely to be exploited in a local docker environment.

**For production**: Must be resolved before deployment. Escalate to the owner to upgrade the mail library.

---

## N5: 7 abandoned packages in the dependency tree

**Blocker ID**: N5-ABANDONED-PACKAGES  
**Severity**: Low (informational, monitoring required)  
**Tool evidence**: `composer audit` reported 7 abandoned packages. Notably `beyondcode/laravel-websockets` is an abandoned dep that HelpdeskClient relies on for real-time chat.

### Packages

1. `aecy/badge` — abandoned
2. `beyondcode/laravel-websockets` — abandoned (used by HelpdeskClient for chat)
3. `doctrine/cache` — abandoned
4. `mattkingshott/axiom` — abandoned
5. `pear/text_languagedetect` — abandoned
6. `swiftmailer/swiftmailer` — abandoned (see N4)

### Impact

- **Chat features won't work** without resolving the websockets dependency (see `project_chat_sidecar_2026-04-19` in MEMORY.md for a separate extraction plan).
- **No active support** for these packages (if bugs are discovered, no patches will be released).

### Fix Options

1. **Remove unused packages** (aecy/badge, etc.). Identify why they're in composer.json and if they're actually used.
2. **Replace** websockets + swiftmailer with maintained alternatives.
3. **Accept and monitor**. Document the abandoned status and track for vulnerabilities.

### Recommendation

**For MVP**: Accept. Focus on getting HelpdeskClient routes working first.

**For post-MVP**: Schedule a dependency audit to replace abandoned packages. This is a separate, planned effort (not urgent for local testing).

---

## N6: Gateway pilot routes reference undeployed sidecars

**Blocker ID**: N6-MISSING-SIDECARS  
**Severity**: Medium (affects admin routes only, not customer routes)  
**Tool evidence**: `src/index.ts:56-93` declares pilot routing to `http://cs-tickets:80`, `http://cs-kb:80`, `http://cs-chat:80`. None of these exist in `docker ps`.

### Root Cause

The gateway was designed to route admin-side requests (e.g., `/api/helpdesk/admin/tickets/*`) to microservices that haven't been deployed yet. The default behavior falls back to DNS names, which don't resolve.

### What Breaks

**Admin routes** like `POST /api/helpdesk/admin/tickets/create` will timeout trying to reach `http://cs-tickets:80` and return HTTP 502 (Bad Gateway).

**Customer routes** like `POST /api/helpdesk/customer/login` bypass this logic and route directly to `HELPDESK_API_URL`, so they're unaffected.

### Fix Options

1. **Leave commented-out** (current state). Routes go to upstream HelpdeskClient handlers.
2. **Deploy the sidecars** when they're ready. Update the env vars to point to real services.
3. **Override pilot routes** with env vars. Set `CS_TICKETS_URL`, `CS_KB_URL`, `CS_CHAT_URL` to existing services (or leave unset to use the defaults in `src/index.ts`).

### Recommendation

**For MVP**: Leave as-is. Admin routes will fail with 502, but customer-facing routes work fine.

**When sidecars are ready**: Deploy them, update env vars, and test the admin routes.

---

## Summary Table: All Blockers

| ID | Severity | Type | N1 Fix | N2 Fix | N3 Status | Impacts |
| --- | --- | --- | --- | --- | --- | --- |
| N1 | Critical | Infra | Option A | Recommended | N/A | All requests |
| N2 | Critical | Data | N/A | Option B | Eliminated | Helpdesk route registration |
| N3 | High (if N2-A) | Data | N/A | N/A | Eliminated (N2-B) | DB integrity |
| N4 | Medium | Security | N/A | N/A | Accept/Monitor | Mailer |
| N5 | Low | Dependencies | N/A | N/A | Accept/Schedule | Chat features, package support |
| N6 | Medium | Routing | N/A | N/A | Accept | Admin routes (not customer) |

---

## Validation Checkpoints (After Fixes)

After applying recommended fixes (N1 Option A + N2 Option B), test with:

```bash
# 1. Verify nginx forwards to PHP-FPM
curl http://127.0.0.1:8081/

# 2. Verify helpdesk routes exist
curl http://127.0.0.1:8081/helpdesk/api/customer/login

# 3. Verify gateway proxies correctly
curl -X POST http://127.0.0.1:3101/api/helpdesk/customer/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"test"}'

# 4. Verify helpdesk_settings table exists
docker exec webapp_core_db_fresh mysql -uroot -proot \
  -e "USE webapp_core_helpdesk; SHOW TABLES LIKE 'helpdesk_settings';"
```

Expected outcomes:
- Step 1: HTTP 500 or 200 (app is up)
- Step 2: HTTP 404 from Laravel (route exists, missing parameters or validation fails)
- Step 3: HTTP 400 or 422 (validation error — expected, not 502)
- Step 4: 1 row returned (helpdesk_settings table exists)
