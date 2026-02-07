# PostgreSQL 16 Compatibility & Dockerfile.combined Assessment

**Date:** 2026-02-07
**Researcher:** Claude Opus 4.6 (research agent)
**Scope:** Two-item investigation for research-mind monorepo

---

## Item 1: PostgreSQL 16 Compatibility Check

### Summary

**SAFE TO DOWNGRADE.** The project uses zero PostgreSQL 18-specific features. All SQL operations go through SQLAlchemy 2.0 ORM and Alembic migrations using only standard, version-agnostic column types and operations. PostgreSQL 16 (or even 15) will work without any code changes.

### Evidence

#### Migration Files Analyzed (4 total)

All migrations located in `research-mind-service/migrations/versions/`:

| Migration | Revision | Tables | PG-Specific Features |
|-----------|----------|--------|---------------------|
| `5d88e65ab411` | Initial | `sessions` | None |
| `56afc8db4b50` | 2nd | `audit_logs` | None |
| `4bd8cd1f8ec7` | 3rd | `content_items` | None |
| `chat001` | 4th | `chat_messages` | None |

#### Column Types Used (complete inventory)

Every column type across all 4 migrations and 4 ORM models:

- `sa.String(length=N)` -- Standard since PG 7.x
- `sa.Text()` -- Standard since PG 7.x
- `sa.Integer()` -- Standard since PG 7.x
- `sa.Boolean()` -- Standard since PG 7.x
- `sa.DateTime(timezone=True)` -- Standard since PG 7.x
- `sa.JSON()` -- Available since **PostgreSQL 9.2** (2012)
- `sa.ForeignKeyConstraint` -- Standard SQL
- `sa.PrimaryKeyConstraint` -- Standard SQL
- `sa.text("false")` (server_default) -- Standard SQL expression

#### SQL Features NOT Used (PG18-specific)

Grep searches confirmed zero usage of:
- `MERGE` improvements (PG15+ feature, enhanced in PG17/18)
- `JSON_TABLE` (PG17+)
- SQL/JSON standard functions (`json_scalar`, `json_serialize`, `json_objectagg`, `json_arrayagg`, `json_exists`, `json_query`, `json_value`)
- Virtual generated columns (PG12+ stored, PG18 virtual)
- `GENERATED ALWAYS` expressions
- New system views (`pg_stat_*`, `pg_catalog` extensions)
- PostgreSQL extensions (`pgvector`, `pg_trgm`, `ltree`, `citext`, `hstore`, `tsvector`, `tsquery`)
- `jsonb_path` queries

#### SQLAlchemy Models Analyzed (4 models)

| Model | File | Complexity | PG-Specific |
|-------|------|-----------|-------------|
| `Session` | `app/models/session.py` | Simple CRUD | None |
| `ContentItem` | `app/models/content_item.py` | Simple CRUD + JSON | None |
| `ChatMessage` | `app/models/chat_message.py` | Simple CRUD + JSON | None |
| `AuditLog` | `app/models/audit_log.py` | Simple CRUD + JSON | None |

All models use:
- Standard `Column()` definitions
- `DeclarativeBase` (SQLAlchemy 2.0 style)
- Python-side defaults (`default=lambda: str(uuid4())`, `default=_utcnow`)
- No raw SQL queries, no PostgreSQL-specific dialect features

#### Database Layer Analysis

- `app/db/base.py` -- Minimal `DeclarativeBase` (no PG-specific config)
- `app/db/session.py` -- Standard `create_engine` with `pool_pre_ping=True`
  - Also supports SQLite (`check_same_thread=False` for testing)
  - No PG-specific connection arguments or pool settings
- Driver: `psycopg[binary]>=3.1.0` (psycopg 3, supports PG 12+)
- ORM: `sqlalchemy>=2.0.0` (supports PG 12+)
- Migrations: `alembic>=1.12.0` (supports PG 12+)

#### Alembic Configuration

`migrations/env.py` uses standard configuration:
- Standard `engine_from_config` with `pool.NullPool`
- No dialect-specific options
- No PG-specific migration operations

### Files That Need Updating (for PG16 downgrade)

| File | Current Reference | Change To |
|------|-------------------|-----------|
| `docker-compose.yml:5` | `postgres:18-alpine` | `postgres:16-alpine` |
| `docker-compose-standalone-postgres.yml:23` | `postgres:18-alpine` | `postgres:16-alpine` |

**Documentation files to update** (informational only, non-blocking):
- `TECHNOLOGY_STACK.md` (lines 33, 151, 195, 280, 311)
- `README.md` (line 100)
- `docs/GETTING_STARTED.md` (lines 48, 65-67, 85-86, 362)
- `docs/PHASE_1_0_BASELINE.md` (lines 46, 136, 236, 285)
- Various files in `docs/research/`, `docs/summary/`, `docs/plans/`, `docs/team-research/`

### Recommendation

**Proceed with the PG16 downgrade.** The project's database usage is completely version-agnostic at the SQL level. The minimum PostgreSQL version required is effectively **PostgreSQL 12** (due to `sa.JSON()` type usage), though PostgreSQL 16 is a sensible target given it is an actively maintained LTS version.

**Required changes:** 2 files (docker-compose configs)
**Code changes:** 0 files (no application code changes needed)
**Risk level:** Very low

---

## Item 2: Dockerfile.combined Assessment

### Summary

`Dockerfile.combined` **exists and is a well-structured multi-stage Dockerfile**, but it has **never been tested end-to-end** and has a potential build issue. It is a useful placeholder for future single-container deployment but should not be documented as "working" until verified.

### What It Contains

A 3-stage multi-stage Docker build:

1. **Stage 1 (ui-builder):** Builds the SvelteKit frontend using `node:20-alpine`
   - Copies `research-mind-ui/` source
   - Runs `npm ci` and `npm run build`
   - Accepts `VITE_API_BASE_URL` build arg (defaults to `http://localhost:15010`)

2. **Stage 2 (backend-builder):** Installs Python dependencies using `python:3.12-slim`
   - Installs gcc and libpq-dev for building psycopg
   - Installs backend Python packages from `pyproject.toml`

3. **Stage 3 (runtime):** Final combined image using `python:3.12-slim`
   - Installs Node.js 20 for serving the SvelteKit build
   - Copies Python packages from backend-builder stage
   - Copies backend app code and migrations
   - Copies frontend build output
   - Creates non-root `appuser`
   - Runs `scripts/docker-entrypoint-combined.sh`
   - Exposes ports 15010 (backend) and 15000 (frontend)
   - Health check for both services

### Entrypoint Script

`scripts/docker-entrypoint-combined.sh` exists and is functional:
- Validates `DATABASE_URL` environment variable
- Optionally runs Alembic migrations (if `AUTO_MIGRATE=true`)
- Starts backend (uvicorn) in background
- Waits for backend health check (30s timeout)
- Starts frontend (`node build`) in background
- Traps SIGTERM/SIGINT for graceful shutdown
- Waits on both PIDs

### Referenced In

| Location | Type | Context |
|----------|------|---------|
| `Dockerfile.combined:7` | Self-reference | Build instructions in comment header |
| `scripts/README.md:10` | Documentation | Lists entrypoint script |
| `docs/research/installation/` | Research docs | Multiple analysis files discuss it |
| `docs/team-research/installation/` | Team research | Identified as "probably broken" |

### NOT Referenced In

| Location | Significance |
|----------|-------------|
| `docker-compose.yml` | Not used for compose-based deployment |
| `Makefile` (root) | No build/run target for combined container |
| `docs/GETTING_STARTED.md` | No user-facing documentation references it |
| `research-mind-service/Makefile` | Not in service-level Makefile |

### Would It Build Successfully?

**Likely YES with caveats.** Analysis of potential issues:

| Concern | Status | Detail |
|---------|--------|--------|
| Stage 1 (UI build) | Probably works | Standard `npm ci && npm run build` |
| Stage 2 (Python deps) | Probably works | Standard pip install |
| Stage 3 (runtime) | Probably works | Standard multi-stage copy |
| Entrypoint script | EXISTS | `scripts/docker-entrypoint-combined.sh` is present |
| `pip install . from pyproject.toml` | **Potential issue** | Line 42 does `pip install --prefix=/install .` but only `pyproject.toml` is copied (no `app/` source). This installs dependencies but not the app itself, which is fine since app code is copied separately in Stage 3 |
| NodeSource 20.x repo | **Potential fragility** | Uses `curl | bash` pattern from `deb.nodesource.com` which may change |
| SvelteKit `node build` | Needs verification | Depends on SvelteKit adapter-node being configured |

### Previous Analysis Results

The existing team research (`docs/team-research/installation/05-devils-advocate-analysis.md`) already flagged this:
- "Dockerfile.combined works -- PROBABLY BROKEN" (section 6.1)
- Entrypoint script exists, but build/run pipeline is unverified
- Recommended end-to-end testing before documenting as working

### Recommendation

**Keep `Dockerfile.combined` as a useful placeholder** for future single-container deployment. It is well-structured and close to working.

**Action items:**
1. **Do NOT remove it** -- it represents intentional architecture for future deployment
2. **Do NOT document it as working** in user-facing docs until tested
3. **Add a Makefile target** for building it when ready: `make docker-combined`
4. **Test the build** when Docker is available: `docker build -f Dockerfile.combined -t research-mind .`
5. **Fix the NodeSource install** -- consider using a multi-stage approach that copies Node.js from the `node:20-alpine` image instead of installing via apt
6. **Verify SvelteKit adapter-node** is configured for `node build` to work

**Priority:** Low. The standard `docker-compose.yml` approach (separate containers) is the primary deployment method and works correctly.

---

## Summary of Findings

| Item | Verdict | Risk | Action Required |
|------|---------|------|----------------|
| PG16 Downgrade | **SAFE** | Very Low | Change 2 docker-compose files, update docs |
| Dockerfile.combined | **Keep as placeholder** | None (not in use) | Test when ready, do not remove |
