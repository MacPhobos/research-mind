# Installation Documentation Analysis for research-mind Monorepo

**Date**: 2026-02-05
**Author**: Research Agent (Claude Opus 4.5)
**Scope**: Comprehensive analysis of installation documentation across all components

---

## Executive Summary

The research-mind monorepo has **extensive but fragmented** installation documentation. The documentation is thorough for developers already familiar with the tech stack, but presents significant gaps for new developers or those attempting containerized deployment.

### Key Findings

| Aspect                             | Status           | Rating     |
| ---------------------------------- | ---------------- | ---------- |
| Backend development setup          | Well documented  | Good       |
| Frontend development setup         | Well documented  | Good       |
| Monorepo orchestration             | Basic coverage   | Fair       |
| Prerequisites clarity              | Incomplete       | Needs Work |
| Containerized deployment           | Partial coverage | Needs Work |
| Single container all-in-one        | Not supported    | Missing    |
| Environment variable documentation | Comprehensive    | Good       |
| Troubleshooting                    | Service only     | Fair       |

### Critical Gaps

1. **No unified installation guide** - Documentation is scattered across 8+ files
2. **Prerequisite installation not documented** - Assumes tools like `uv`, `mcp-vector-search`, PostgreSQL are already installed
3. **No all-in-one container option** - Docker Compose requires separate services, no single-image option
4. **PostgreSQL setup options unclear** - No guidance on using existing DB vs Docker DB
5. **UI has no Dockerfile** - Cannot containerize frontend

---

## Current Documentation Inventory

### Files Found and Analyzed

| File                                             | Purpose                       | Lines | Quality           |
| ------------------------------------------------ | ----------------------------- | ----- | ----------------- |
| `/README.md`                                     | Project overview, quick start | 165   | Overview only     |
| `/CLAUDE.md`                                     | Monorepo development guide    | 153   | Developer-focused |
| `/docs/README.md`                                | Brief structure pointer       | 19    | Minimal           |
| `/research-mind-service/README.md`               | Comprehensive backend docs    | 462   | Excellent         |
| `/research-mind-service/CLAUDE.md`               | Backend patterns and API      | ~500  | Excellent         |
| `/research-mind-service/docs/DEPLOYMENT.md`      | Deployment and DB setup       | 273   | Good              |
| `/research-mind-service/docs/TROUBLESHOOTING.md` | Common issues                 | 310   | Good              |
| `/research-mind-ui/README.md`                    | Frontend overview             | 184   | Good              |
| `/research-mind-ui/CLAUDE.md`                    | Frontend patterns             | ~1100 | Excellent         |
| `/Makefile`                                      | Monorepo commands             | 70    | Helpful           |
| `/docker-compose.yml`                            | Container orchestration       | 51    | Functional        |
| `/.env.example`                                  | Root environment template     | 16    | Minimal           |
| `/research-mind-service/.env.example`            | Backend env vars              | 81    | Comprehensive     |
| `/research-mind-ui/.env.example`                 | Frontend env vars             | 1     | Minimal           |

### Documentation Strengths

1. **Backend README.md** - Exceptional coverage of:

   - Architecture diagrams
   - API endpoints with examples
   - Configuration reference with all env vars
   - Testing patterns
   - Security features
   - Database migration workflow

2. **CLAUDE.md files** - Excellent for:

   - Development patterns
   - API contract workflow
   - Code organization
   - Testing conventions

3. **Environment examples** - Backend `.env.example` is comprehensive with comments

### Documentation Weaknesses

1. **No "Getting Started" guide** - Assumes prerequisite knowledge
2. **Installation scattered** - Must read 3+ files to understand full setup
3. **Prerequisite installation missing** - No guidance for:
   - Installing `uv` package manager
   - Installing `mcp-vector-search` CLI
   - Installing PostgreSQL
   - Installing Node.js version
4. **Cross-referencing issues** - Files reference each other but don't consolidate

---

## Gap Analysis: What's Missing for New Developers

### Prerequisites Not Documented

The following are **required but not explained**:

| Prerequisite            | Mentioned Where               | Installation Guide                                            |
| ----------------------- | ----------------------------- | ------------------------------------------------------------- |
| Python 3.12+            | Service README                | **Not documented**                                            |
| `uv` package manager    | Service README                | **Not documented** - Link provided only                       |
| PostgreSQL 18+          | Service README                | **Not documented**                                            |
| `mcp-vector-search` CLI | Service README, DEPLOYMENT.md | **Not documented** - "install according to its documentation" |
| Node.js 20.x/22.x       | UI README                     | **Not documented**                                            |
| npm 10.x+               | UI README                     | **Not documented**                                            |
| Docker & Docker Compose | DEPLOYMENT.md                 | **Not documented**                                            |

### Assumed Knowledge

Documentation assumes developers already know:

- How to install and configure PostgreSQL
- How to create databases
- Python virtual environment concepts (handled by `uv` but not explained)
- npm/Node.js ecosystem
- Docker concepts

### Missing Procedural Steps

1. **Database creation workflow**:

   - `createdb research_mind` mentioned but PostgreSQL installation not explained
   - No guidance on connecting to existing PostgreSQL vs Docker PostgreSQL

2. **Service dependency order**:

   - Backend must be running before `npm run gen:api` works
   - This dependency is mentioned but not in a clear "first do X, then do Y" format

3. **Initial data setup**:

   - Migrations create tables but no seed data guidance

4. **Verification checklist**:
   - No step-by-step verification that each component is working

---

## Containerized Installation Analysis

### Current State: Docker Compose

**Location**: `/docker-compose.yml`

**What It Provides**:

```yaml
services:
  postgres:
    image: postgres:18-alpine
    # Health check, volumes, credentials

  service:
    build: ./research-mind-service/Dockerfile
    # Environment, volumes, health check
```

**What's Missing**:

1. **No UI container** - Frontend has no Dockerfile
2. **No all-in-one option** - Always separate containers
3. **Migration step not automated** - Must run manually after start
4. **No build instructions** - How to build images for deployment

### Backend Dockerfile Analysis

**Location**: `/research-mind-service/Dockerfile`

**Quality**: Good

**Features**:

- Multi-stage build (builder + runtime)
- Non-root user (`appuser`)
- Health check configured
- `curl` included for health probes
- Warning for missing `mcp-vector-search`

**Issues**:

- `mcp-vector-search` installation not included (only warning)
- No documentation on how to include `mcp-vector-search` in the image

### What's Needed for All-in-One Container

An all-in-one container (frontend + backend + PostgreSQL) would require:

1. **Frontend Dockerfile** - Currently missing entirely
2. **Multi-service container approach**:
   - Option A: supervisord managing multiple processes
   - Option B: Combined image with entrypoint script
3. **Embedded PostgreSQL** or SQLite option for simple deployments
4. **Static asset serving** - Frontend could be served by backend

**Complexity assessment**: Medium-High

- Frontend build system outputs static files (can be served by any web server)
- Backend could serve frontend static files with FastAPI `StaticFiles` middleware
- PostgreSQL cannot be easily embedded; would need SQLite alternative for all-in-one

---

## Development Mode Installation Analysis

### Current "Happy Path"

The intended development workflow (pieced together from multiple docs):

```bash
# 1. Clone repository
git clone <repo>
cd research-mind

# 2. Install backend dependencies
cd research-mind-service
uv sync
cp .env.example .env
# Edit .env with database URL

# 3. Start PostgreSQL (Docker)
docker compose up -d postgres

# 4. Run migrations
uv run alembic upgrade head

# 5. Start backend
uv run uvicorn app.main:app --host 0.0.0.0 --port 15010 --reload

# 6. Install frontend dependencies (new terminal)
cd ../research-mind-ui
npm install
cp .env.example .env

# 7. Start frontend
npm run dev

# 8. Access application
# UI: http://localhost:15000
# API: http://localhost:15010
```

### Alternative: Root Makefile

```bash
make install  # Installs both service and UI dependencies
make dev      # Starts postgres, service, and UI
```

**Problem with `make dev`**:

- Runs processes in background with `&`
- No log visibility
- Hard to stop gracefully (`make stop` uses `pkill`)
- Does not wait for PostgreSQL to be ready properly

### PostgreSQL Setup Options

| Option                       | Documentation Status | Steps Needed                    |
| ---------------------------- | -------------------- | ------------------------------- |
| Docker Compose               | Documented           | `docker compose up -d postgres` |
| Local PostgreSQL             | Partially documented | Create DB manually              |
| Use existing PostgreSQL      | Not documented       | Modify `DATABASE_URL` only      |
| Docker PostgreSQL standalone | Not documented       | -                               |

**Gap**: No guidance on choosing between these options or their trade-offs.

### Identified Configuration Pitfalls

1. **Database URL mismatch**:

   - Root `.env.example`: `DATABASE_URL=postgresql://postgres:devpass123@localhost:5432/research-mind_db`
   - Service `.env.example`: `DATABASE_URL=postgresql+psycopg://postgres:password@localhost:5432/research_mind`
   - Docker Compose: `DATABASE_URL=postgresql+psycopg://postgres:postgres@postgres:5432/research_mind`
   - **Three different formats and passwords!**

2. **Database name inconsistency**:

   - Root: `research-mind_db`
   - Service: `research_mind`
   - These are different databases!

3. **Port discrepancy in UI Makefile**:
   - `Makefile` help says "port 5173" but vite.config.ts uses port 15000

---

## Recommendations for Documentation Improvement

### Priority 1: Create Unified Getting Started Guide

Create `/docs/GETTING_STARTED.md` with:

```markdown
# Getting Started with research-mind

## Prerequisites Installation

### macOS

brew install python@3.12 postgresql@18 node@20
pip install uv

# Install mcp-vector-search (link/instructions)

### Linux (Ubuntu/Debian)

# Specific commands...

## Quick Start (5 minutes)

1. Clone and install
2. Start PostgreSQL
3. Run migrations
4. Start services
5. Verify installation

## Full Development Setup (30 minutes)

# Detailed walkthrough with explanations
```

### Priority 2: Fix Configuration Inconsistencies

1. **Standardize database name**: `research_mind` everywhere
2. **Standardize credentials**: Same password in all `.env.example` files
3. **Use consistent DATABASE_URL format**: `postgresql+psycopg://`
4. **Fix UI Makefile port comment**: 15000 not 5173

### Priority 3: Add Frontend Dockerfile

Create `/research-mind-ui/Dockerfile`:

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM node:20-alpine AS runner
WORKDIR /app
COPY --from=builder /app/build ./build
COPY package*.json ./
RUN npm ci --omit=dev
CMD ["node", "build"]
```

Update `docker-compose.yml` to include UI service.

### Priority 4: Document mcp-vector-search Installation

Add `/docs/PREREQUISITES.md` or section in main README:

```markdown
## Installing mcp-vector-search

The indexing features require mcp-vector-search CLI.

### Option 1: pip install

pip install mcp-vector-search

### Option 2: From source

git clone https://github.com/...
cd mcp-vector-search
pip install .

### Verify installation

mcp-vector-search --version
```

### Priority 5: Add Installation Verification Script

Create `/scripts/verify-install.sh`:

```bash
#!/bin/bash
echo "Checking prerequisites..."
command -v python3 && python3 --version
command -v uv && uv --version
command -v node && node --version
command -v npm && npm --version
command -v psql && psql --version
command -v mcp-vector-search && mcp-vector-search --version

echo "Checking services..."
curl -s http://localhost:15010/health && echo "Backend: OK"
curl -s http://localhost:15000 && echo "Frontend: OK"
```

### Priority 6: Add Troubleshooting for UI

Create `/research-mind-ui/docs/TROUBLESHOOTING.md` covering:

- Port conflicts
- Node version issues
- Type generation failures
- Build failures

---

## Summary Table: Documentation Status

| Category              | Current            | Needed                 | Gap              |
| --------------------- | ------------------ | ---------------------- | ---------------- |
| Project overview      | README.md          | Good                   | None             |
| Backend setup         | README, CLAUDE.md  | Excellent              | None             |
| Frontend setup        | README, CLAUDE.md  | Good                   | Troubleshooting  |
| Prerequisites         | Scattered mentions | Unified guide          | **High**         |
| Database setup        | DEPLOYMENT.md      | Multiple options guide | **Medium**       |
| Docker single-service | docker-compose.yml | Works                  | Minor            |
| Docker all-in-one     | None               | Not planned            | **Low priority** |
| Frontend Docker       | None               | Dockerfile + docs      | **Medium**       |
| Verification          | None               | Script + checklist     | **Medium**       |
| Troubleshooting       | Service only       | Both services          | **Low**          |

---

## Actionable Next Steps

### Immediate (This Week)

1. Fix database URL inconsistencies across `.env.example` files
2. Fix UI Makefile port comment
3. Add prerequisite installation section to root README.md

### Short-term (This Month)

4. Create `/docs/GETTING_STARTED.md` unified guide
5. Create `/research-mind-ui/Dockerfile`
6. Update `docker-compose.yml` to include UI service
7. Add verification script

### Medium-term (Next Quarter)

8. Document mcp-vector-search installation comprehensively
9. Add UI troubleshooting guide
10. Consider all-in-one container option (with SQLite fallback)

---

## Appendix: File Locations Reference

```
research-mind/
├── README.md                           # Project overview
├── CLAUDE.md                           # Monorepo dev guide
├── Makefile                            # Monorepo commands
├── docker-compose.yml                  # Container orchestration
├── .env.example                        # Root env vars
├── docs/
│   ├── README.md                       # Docs structure
│   └── research/installation/          # This analysis
├── research-mind-service/
│   ├── README.md                       # Backend docs (main)
│   ├── CLAUDE.md                       # Backend patterns
│   ├── Makefile                        # Backend commands
│   ├── Dockerfile                      # Backend container
│   ├── .env.example                    # Backend env vars
│   ├── pyproject.toml                  # Python dependencies
│   ├── alembic.ini                     # Migration config
│   └── docs/
│       ├── DEPLOYMENT.md               # Deployment guide
│       └── TROUBLESHOOTING.md          # Issue resolution
└── research-mind-ui/
    ├── README.md                       # Frontend docs
    ├── CLAUDE.md                       # Frontend patterns
    ├── Makefile                        # Frontend commands
    ├── package.json                    # Node dependencies
    └── .env.example                    # Frontend env vars (minimal)
```

---

_Research completed 2026-02-05. This document should be reviewed when significant documentation changes are made._
