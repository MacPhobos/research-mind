# Monorepo Scaffolding: FastAPI Service + SvelteKit UI

## Phase 0: User Input Collection (INTERACTIVE - DO NOT SKIP)

Before scaffolding, collect these inputs from the user and confirm:

### Required Inputs:

1. **Project Name Stem (FOO)**:

   - Pattern: `{FOO}` will create `{FOO}-ui/` and `{FOO}-service/`
   - Example: If user says "acme", create `acme-ui/` and `acme-service/`
   - Prompt: "What is your project name stem? (e.g., 'myapp', 'acme', 'weather-app')"

2. **Service Port**:

   - Prompt: "What port should the service run on? (e.g., 15010, must be available)"
   - Validation: Must be integer 1024-65535, check `lsof -i :{PORT}` to avoid conflicts
   - Store in: `.env.example` (service) and docs

3. **UI Port**:

   - Prompt: "What port should the UI dev server run on? (e.g., 15000, must differ from service port)"
   - Validation: Must differ from service port, check availability
   - Store in: `.env.example` (ui) and docs

4. **Database Password** (for local Postgres):

   - Prompt: "Set a local Postgres password for development (e.g., 'devpass123')"
   - Validation: Minimum 8 chars
   - Store in: `.env.example` and `docker-compose.yml`

5. **API Domain** (optional, for production reference):
   - Prompt: "Production API domain? (e.g., 'api.myapp.com', or 'not-decided-yet')"
   - Default: `not-decided-yet` if not provided

**Confirmation Prompt:**

```
Scaffolding Configuration:
  Project Name: {FOO}
  Service Port: {SERVICE_PORT}
  UI Port: {UI_PORT}
  Database User: postgres (fixed)
  Database Password: [hidden]
  Production Domain: {API_DOMAIN}

Correct? (yes/no)
```

---

## Phase 1: Directory Structure

Create the following layout:

```
{FOO}-monorepo/
├── {FOO}-ui/                    # SvelteKit frontend (empty clone)
├── {FOO}-service/               # FastAPI backend (empty clone)
├── docs/                        # Shared documentation
│   ├── README.md
│   ├── api-contract.md          # API contract (source of truth)
│   └── SETUP.md                 # Bootstrapping guide
├── docker-compose.yml
├── Makefile
├── .tool-versions               # asdf tooling
├── .env.example
├── .gitignore
└── CLAUDE.md                    # Root instructions
```

**Critical Notes:**

- UI and Service repos are assumed pre-cloned into `{FOO}-ui/` and `{FOO}-service/`
- They should be empty (no scaffolding yet)
- If not pre-cloned, initialize them as empty directories

---

## Phase 2: Root-Level Configuration

### 2.1 `.tool-versions` (Root)

Specify asdf tooling requirements:

```
python 3.12.0          # Latest stable 3.12.x
nodejs 20.11.0         # Latest stable 20.x
```

Add to `{FOO}-ui/` as needed (inherit from root if possible).

### 2.2 Root `.env.example`

```bash
# Service Configuration
SERVICE_HOST=localhost
SERVICE_PORT={SERVICE_PORT}
SERVICE_ENV=development
DATABASE_URL=postgresql://postgres:{DB_PASSWORD}@localhost:5432/{FOO}_db

# UI Configuration
UI_HOST=localhost
UI_PORT={UI_PORT}
VITE_API_BASE_URL=http://localhost:{SERVICE_PORT}

# Database (Docker)
POSTGRES_USER=postgres
POSTGRES_PASSWORD={DB_PASSWORD}
POSTGRES_DB={FOO}_db
```

### 2.3 Root `Makefile`

```makefile
.PHONY: help install dev stop test lint fmt typecheck gen-client db-up db-reset clean

help:
	@echo "Available targets:"
	@grep "^[a-z-]*:" Makefile | cut -d: -f1 | sed 's/^/  make /'

install:
	@echo "Installing dependencies..."
	cd {FOO}-ui && npm install
	cd {FOO}-service && uv sync
	@echo "✓ Dependencies installed"

dev:
	@echo "Starting dev stack (Service + UI + Postgres)..."
	docker-compose up -d postgres
	@sleep 2
	@cd {FOO}-service && uv run uvicorn app.main:app --host 0.0.0.0 --port {SERVICE_PORT} --reload &
	@cd {FOO}-ui && npm run dev &
	@echo "✓ Dev stack running"
	@echo "  Service: http://localhost:{SERVICE_PORT}"
	@echo "  UI: http://localhost:{UI_PORT}"
	@echo "  Health: curl http://localhost:{SERVICE_PORT}/health"

stop:
	pkill -f "uvicorn" || true
	pkill -f "vite" || true
	docker-compose down

test:
	@echo "Running tests..."
	cd {FOO}-service && uv run pytest
	cd {FOO}-ui && npm run test

lint:
	@echo "Linting..."
	cd {FOO}-service && uv run ruff check app tests
	cd {FOO}-ui && npm run lint

fmt:
	@echo "Formatting..."
	cd {FOO}-service && uv run black app tests && uv run ruff check --fix app tests
	cd {FOO}-ui && npm run format

typecheck:
	@echo "Type checking..."
	cd {FOO}-service && uv run mypy app
	cd {FOO}-ui && npm run typecheck

gen-client:
	@echo "Generating TypeScript client from OpenAPI..."
	cd {FOO}-ui && npx openapi-typescript http://localhost:{SERVICE_PORT}/openapi.json -o src/lib/api/generated.ts
	@echo "✓ Client generated at {FOO}-ui/src/lib/api/generated.ts"

db-up:
	docker-compose up -d postgres
	@sleep 2
	@echo "✓ Postgres running on localhost:5432"

db-reset:
	docker-compose down -v
	docker-compose up -d postgres
	@sleep 2
	@cd {FOO}-service && uv run alembic upgrade head
	@echo "✓ Database reset and migrated"

clean:
	rm -rf {FOO}-ui/node_modules {FOO}-service/.venv
	docker-compose down -v
	@echo "✓ Cleaned"
```

### 2.4 `docker-compose.yml`

```yaml
version: "3.8"
services:
  postgres:
    image: postgres:18-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### 2.5 Root `CLAUDE.md`

```markdown
# {FOO} Monorepo Development Guide

## Quick Start

\`\`\`bash
make install
make dev
\`\`\`

Service: http://localhost:{SERVICE_PORT}
UI: http://localhost:{UI_PORT}

## Project Structure

- **{FOO}-service/**: Python FastAPI backend
- **{FOO}-ui/**: SvelteKit TypeScript frontend
- **docs/**: Shared documentation + API contract

## The Golden Rule: API Contract First

**Contract Location**: `docs/api-contract.md` (source of truth)

All changes to the API must:

1. Update `{FOO}-service/docs/api-contract.md`
2. Update service models
3. Run service tests
4. Copy contract to `{FOO}-ui/docs/api-contract.md`
5. Run `make gen-client` in UI
6. Update UI code using new types
7. Run UI tests

**NEVER**:

- Manually edit generated types
- Deploy without regenerating client
- Change API without updating contract in BOTH places

## Configuration

### Service Port: {SERVICE_PORT}

- Change in root `.env` and `docker-compose.yml`
- Update UI's `VITE_API_BASE_URL`

### UI Port: {UI_PORT}

- Change in {FOO}-ui/.env
- CORS may need adjustment in service

### Database

- Default: Postgres (port 5432, user: postgres)
- Reset with: `make db-reset`

## Common Tasks

\`\`\`bash
make dev # Start everything
make stop # Stop everything
make test # Run all tests
make lint # Check code quality
make gen-client # Regenerate TS client from OpenAPI
make db-reset # Drop and recreate database
\`\`\`

## Adding a New Endpoint

1. **Service**:

   - Add route in `{FOO}-service/app/routes/`
   - Add Pydantic models in `{FOO}-service/app/schemas/`
   - Write test in `{FOO}-service/tests/`
   - Update `docs/api-contract.md`

2. **UI**:
   - Copy contract to `{FOO}-ui/docs/api-contract.md`
   - Run `make gen-client`
   - Use generated types in UI components

## Guard Rails

- **No `.env` in git**: Use `.env.example` only
- **Migrations required**: All schema changes via Alembic
- **Type safety**: Generated TypeScript types (no hand-rolled fetch)
- **Tests required**: >1 test per component
- **Ports must differ**: Service ≠ UI port

## Non-Goals

- User authentication (stubs exist, production auth TBD)
- Multi-environment setup (local dev only for now)
- Load testing or scale optimization
  \`\`\`

---

## Phase 3: Service Scaffolding ({FOO}-service/)

### 3.1 Core Structure
```

{FOO}-service/
├── app/
│ ├── **init**.py
│ ├── main.py # FastAPI app + routes
│ ├── config.py # Pydantic settings
│ ├── schemas/ # Pydantic models (requests/responses)
│ │ ├── **init**.py
│ │ └── common.py # ErrorResponse, HealthResponse
│ ├── models/ # SQLAlchemy ORM models
│ │ ├── **init**.py
│ │ └── base.py # Timestamps, UUID pk
│ ├── routes/
│ │ ├── **init**.py
│ │ ├── health.py # GET /health
│ │ └── api.py # Versioned /api/v1/\* routes
│ ├── db/
│ │ ├── **init**.py
│ │ ├── engine.py # SQLAlchemy setup
│ │ └── session.py # Dependency
│ └── auth/ # OAuth2 + JWT stubs
│ ├── **init**.py
│ ├── oauth2.py
│ └── jwt.py
├── migrations/ # Alembic
│ ├── versions/
│ └── env.py
├── tests/
│ ├── conftest.py
│ ├── test_health.py
│ └── test_api.py
├── pyproject.toml
├── .tool-versions
├── .env.example
├── docs/
│ ├── api-contract.md # LOCKED - copy from root
│ └── CLAUDE.md
└── README.md

````

### 3.2 `pyproject.toml`
```toml
[project]
name = "{FOO}-service"
version = "0.1.0"
description = "FastAPI service for {FOO}"
requires-python = ">=3.12"

dependencies = [
    "fastapi==0.109.0",
    "uvicorn[standard]==0.27.0",
    "sqlalchemy==2.0.23",
    "alembic==1.13.0",
    "psycopg[binary]==3.1.12",
    "pydantic==2.5.0",
    "pydantic-settings==2.1.0",
    "python-jose[cryptography]==3.3.0",
    "passlib[bcrypt]==1.7.4",
]

[project.optional-dependencies]
dev = [
    "pytest==7.4.3",
    "pytest-asyncio==0.21.1",
    "ruff==0.1.11",
    "black==23.12.0",
    "mypy==1.7.1",
]
````

### 3.3 `{FOO}-service/.env.example`

```bash
# Server
SERVICE_ENV=development
SERVICE_HOST=0.0.0.0
SERVICE_PORT={SERVICE_PORT}

# Database
DATABASE_URL=postgresql://postgres:devpass123@localhost:5432/{FOO}_db  # pragma: allowlist secret

# CORS
CORS_ORIGINS=http://localhost:{UI_PORT}

# Auth (stubs - configure for production)
SECRET_KEY=dev-secret-change-in-production
ALGORITHM=HS256
```

### 3.4 Key Service Files

**app/main.py**:

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic_settings import BaseSettings
import os

class Settings(BaseSettings):
    SERVICE_ENV: str = "development"
    DATABASE_URL: str
    CORS_ORIGINS: str = "http://localhost:{UI_PORT}"

    class Config:
        env_file = ".env"

settings = Settings()

app = FastAPI(
    title="{FOO} API",
    version="0.1.0",
    docs_url="/docs",
    openapi_url="/openapi.json"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS.split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routes
from app.routes import health, api
app.include_router(health.router)
app.include_router(api.router, prefix="/api/v1")
```

**app/routes/health.py**:

```python
from fastapi import APIRouter
from typing import Literal
import subprocess

router = APIRouter()

@router.get("/health")
async def health_check():
    git_sha = subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()[:7]
    return {
        "status": "ok",
        "name": "{FOO}-service",
        "version": "0.1.0",
        "git_sha": git_sha,
    }
```

**app/routes/api.py** (Vertical slice example):

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.schemas.common import PaginatedResponse
from app.db.session import get_db

router = APIRouter()

@router.get("/version")
async def get_version():
    """Vertical slice: return API version + git sha"""
    import subprocess
    git_sha = subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()[:7]
    return {
        "name": "{FOO}-service",
        "version": "0.1.0",
        "git_sha": git_sha,
    }
```

**app/schemas/common.py**:

```python
from pydantic import BaseModel
from typing import TypeVar, Generic, List

T = TypeVar('T')

class ErrorResponse(BaseModel):
    error: dict[str, str | None]

class PaginatedResponse(BaseModel, Generic[T]):
    data: List[T]
    pagination: dict

class HealthResponse(BaseModel):
    status: str
    name: str
    version: str
    git_sha: str
```

**tests/test_health.py**:

```python
import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert "git_sha" in data
```

### 3.5 Alembic Migrations

Initialize Alembic:

```bash
cd {FOO}-service
alembic init migrations
```

**First migration** (`migrations/versions/001_initial.py`):

```python
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

def upgrade():
    op.create_table(
        'users',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.func.gen_random_uuid(), primary_key=True),
        sa.Column('email', sa.String(255), unique=True, nullable=False),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, server_default=sa.func.now(), onupdate=sa.func.now()),
    )

def downgrade():
    op.drop_table('users')
```

---

## Phase 4: UI Scaffolding ({FOO}-ui/)

### 4.0 CRITICAL: SvelteKit Entry Points (Svelte 5)

**⚠️ DO NOT CREATE:**

- `src/main.ts` - SvelteKit handles component mounting internally
- `index.html` at root - SvelteKit uses `src/app.html` instead
- Raw Vite Svelte plugin - Use `@sveltejs/kit/vite` instead

**Vite Config MUST be** (svelte.config.js or vite.config.ts):

```typescript
import { sveltekit } from "@sveltejs/kit/vite";

export default {
  plugins: [sveltekit()], // NOT svelte() plugin
  // ... rest of config
};
```

**Why?**

- Svelte 4 used `new App()` pattern (no longer valid in Svelte 5)
- SvelteKit 2.0+ with Svelte 5 uses `mount()` internally
- The `@sveltejs/kit/vite` plugin handles all component lifecycle

### 4.1 Core Structure

```
{FOO}-ui/
├── src/
│   ├── routes/
│   │   ├── +page.svelte        # Home page (vertical slice)
│   │   └── +layout.svelte
│   ├── lib/
│   │   ├── api/
│   │   │   ├── generated.ts    # GENERATED - do not edit
│   │   │   ├── client.ts       # Wrapper/helpers
│   │   │   └── hooks.ts        # TanStack Query hooks
│   │   ├── components/
│   │   │   └── ApiStatus.svelte # Vertical slice display
│   │   ├── stores/
│   │   │   └── ui.ts           # UI state only
│   │   └── utils/
│   │       └── env.ts
│   └── app.css
├── tests/
│   └── api.test.ts
├── svelte.config.js
├── vite.config.ts
├── tsconfig.json
├── package.json
├── .env.example
├── docs/
│   ├── api-contract.md         # LOCKED - copy from service
│   └── CLAUDE.md
└── README.md
```

### 4.2 `package.json`

```json
{
  "name": "{FOO}-ui",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest",
    "lint": "eslint . --fix",
    "format": "prettier --write .",
    "typecheck": "svelte-check",
    "gen:api": "openapi-typescript $VITE_API_BASE_URL/openapi.json -o src/lib/api/generated.ts"
  },
  "dependencies": {
    "svelte": "^5.0.0",
    "tailwindcss": "^3.4.0",
    "shadcn-svelte": "^0.7.0",
    "lucide-svelte": "^0.292.0",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "@sveltejs/kit": "^2.0.0",
    "@sveltejs/vite-plugin-svelte": "^3.0.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0",
    "vitest": "^1.1.0",
    "eslint": "^8.55.0",
    "prettier": "^3.1.0",
    "svelte-check": "^3.6.0",
    "openapi-typescript": "^6.7.0"
  }
}
```

### 4.3 `{FOO}-ui/.env.example`

```bash
VITE_API_BASE_URL=http://localhost:{SERVICE_PORT}
```

### 4.4 Key UI Files

**src/routes/+page.svelte** (Vertical slice):

```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  import ApiStatus from '$lib/components/ApiStatus.svelte';
  import { apiClient } from '$lib/api/client';

  let versionData = $state<any>(null);
  let isLoading = $state(true);
  let error = $state<Error | null>(null);

  onMount(async () => {
    try {
      versionData = await apiClient.getVersion();
    } catch (e) {
      error = e as Error;
    } finally {
      isLoading = false;
    }
  });
</script>

<main>
  <h1>Research Mind</h1>
  <ApiStatus {versionData} {isLoading} {error} />
</main>
```

**src/lib/components/ApiStatus.svelte**:

```svelte
<script lang="ts">
  interface Props {
    versionData: any;
    isLoading: boolean;
    error: Error | null;
  }

  const { versionData, isLoading, error }: Props = $props();
</script>

{#if isLoading}
  <p>Checking API status...</p>
{:else if error}
  <p class="text-red-500">API Error: {error.message}</p>
{:else if versionData}
  <div class="bg-green-100 p-4 rounded">
    <p class="font-bold">✓ API Reachable</p>
    <p>Service: {versionData.name} v{versionData.version}</p>
    <p class="text-sm text-gray-600">SHA: {versionData.git_sha}</p>
  </div>
{/if}
```

**src/lib/api/client.ts**:

```typescript
import { PUBLIC_API_BASE_URL } from "$env/static/public";
import type * as API from "./generated";

export const apiClient = {
  async getVersion(): Promise<API.VersionResponse> {
    const res = await fetch(`${PUBLIC_API_BASE_URL}/api/v1/version`);
    if (!res.ok) throw new Error("Failed to fetch version");
    return res.json();
  },
};
```

**tests/api.test.ts**:

```typescript
import { describe, it, expect } from "vitest";

describe("API Client", () => {
  it("should be defined", () => {
    expect(true).toBe(true);
  });
});
```

---

## Phase 5: Integration & Verification

### 5.1 Run Full Stack

```bash
make install
make dev
```

Verify in order:

1. ✅ **Service starts**: `curl http://localhost:{SERVICE_PORT}/health`
2. ✅ **OpenAPI available**: `curl http://localhost:{SERVICE_PORT}/openapi.json`
3. ✅ **UI loads**: Open `http://localhost:{UI_PORT}` in browser
4. ✅ **UI calls service**: Page displays "API Reachable" with version info
5. ✅ **Database connected**: Service can read/write (verify in tests)

### 5.2 Acceptance Criteria (QA Gate)

**MUST PASS before declaring done:**

- [ ] `make install` completes without errors
- [ ] `make dev` starts service + UI + database
- [ ] `curl http://localhost:{SERVICE_PORT}/health` returns `status: "ok"`
- [ ] `curl http://localhost:{SERVICE_PORT}/api/v1/version` returns version + git_sha
- [ ] Service OpenAPI available at `http://localhost:{SERVICE_PORT}/openapi.json`
- [ ] UI loads at `http://localhost:{UI_PORT}` without JS errors
- [ ] UI displays "API Reachable" (uses generated client to fetch `/api/v1/version`)
- [ ] `make test` passes all tests (service + ui)
- [ ] `make lint` / `make fmt` / `make typecheck` all pass
- [ ] `make gen-client` generates TypeScript without errors
- [ ] Postgres migrations run cleanly via `make db-reset`
- [ ] `.env` files not committed (only `.env.example`)
- [ ] Git history clean: `git log --oneline | head -5`
- [ ] `docs/api-contract.md` exists and contains health + version endpoints
- [ ] No `src/main.ts` file exists
- [ ] No root `index.html` file exists (only `src/app.html`)
- [ ] `vite.config.ts` uses `@sveltejs/kit/vite` plugin (not raw svelte plugin)
- [ ] UI components use Svelte 5 Runes ($state, $effect, $props)
- [ ] No "component_api_invalid_new" errors in browser console

**Vertical Slice Definition:**

- Service exposes 2 working endpoints: `/health`, `/api/v1/version`
- UI uses generated TypeScript client to call service
- UI displays result from service in the browser
- All code is type-safe (no `any`)

---

## Anti-Patterns to Avoid

❌ **Manual port configuration** → Use `.env` files always
❌ **Hardcoded API URLs** → Use `VITE_API_BASE_URL` environment variable
❌ **Hand-written fetch calls** → Generate from OpenAPI
❌ **Skipped migrations** → All schema changes via Alembic
❌ **Modified generated types** → Regenerate, don't edit
❌ **Missing tests** → Every module needs >1 test
❌ **Untracked dependencies** → Use `uv` (service) and `npm` (UI)
❌ **Using Svelte 4 entry point patterns** → SvelteKit 2.0+ with Svelte 5 doesn't use `src/main.ts` or `new App()`
❌ **Using raw @sveltejs/vite-plugin-svelte** → Use @sveltejs/kit/vite instead for proper SvelteKit integration
❌ **Creating root index.html** → SvelteKit uses src/app.html, never create root index.html
❌ **Old Svelte component patterns** → Use Svelte 5 Runes ($state, $effect, $props) not export declarations

---

## Files Reference

**Root Level Files to Create:**

- `Makefile`
- `.tool-versions`
- `docker-compose.yml`
- `.env.example`
- `CLAUDE.md`
- `docs/README.md`
- `docs/api-contract.md`
- `.gitignore`

**Service Setup:**

- Generated by `uv init` and project structure above

**UI Setup:**

- Generated by `npm create vite` (SvelteKit template) then customized

---

## Success Definition

You are DONE when:

1. Running `make dev` starts all services
2. The UI page displays "API Reachable" from real API calls
3. All tests pass
4. All linting/type checking passes
5. Generated TypeScript client is in place and used by UI
6. API contract documentation is complete and synced
7. Database migrations execute cleanly
