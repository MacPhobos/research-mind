# CLAUDE.md Organization Recommendations

> **Analysis Date**: 2026-02-01
> **Target**: All three CLAUDE.md files in research-mind monorepo
> **Status**: Complete reorganization based on three launch contexts
> **Updated**: Includes comprehensive UI CLAUDE.md enhancement

---

## Executive Summary

The monorepo has **three launch contexts** requiring **three standalone CLAUDE.md files**:

1. **Monorepo root** (`/Users/mac/workspace/research-mind/CLAUDE.md`) — Cross-project coordination
2. **Service root** (`research-mind-service/CLAUDE.md`) — Backend development (FastAPI/Python)
3. **UI root** (`research-mind-ui/CLAUDE.md`) — Frontend development (SvelteKit/TypeScript)

**Key Decisions from User**:

1. **Root CLAUDE.md trimmed** — ONLY coordination, no project-specific details
2. **API contract workflow in BOTH** — Service and UI CLAUDE.md files must contain complete end-to-end contract sync workflow
3. **Sub-projects fully standalone** — No dependency on root CLAUDE.md
4. **UI CLAUDE.md significantly enhanced** — Currently just KuzuMemory config, needs full frontend guidance
5. **Service CLAUDE.md location** — Move `docs/CLAUDE.md` to `research-mind-service/CLAUDE.md`

**Recommendation**: Create comprehensive, standalone CLAUDE.md files for each launch context with clear content boundaries and complete API contract workflows in both service and UI files.

---

## Analysis of Current State

### 1. Root CLAUDE.md (Current)

**Location**: `/Users/mac/workspace/research-mind/CLAUDE.md`

**Current Purpose**: Monorepo-wide coordination

**Current Coverage**:

- API contract synchronization workflow (Backend → Frontend) ✓
- Contract change checklist ("Golden Rule") ✓
- Type generation strategy (OpenAPI → TypeScript) ✓
- API versioning guidelines (major/minor/patch) ✓
- Deployment safety protocol ✓
- Port configuration (Service: 15010, UI: 15000) ✓
- Database reset commands ✓
- Common tasks (make dev, make test, etc.) ✓
- Guard rails (cross-project) ✓
- Adding new endpoints workflow ✓

**Assessment**: **TRIM NEEDED** — Too much detail on backend-specific patterns (FastAPI, Pydantic, OpenAPI). Should focus only on coordination between projects.

**What should MOVE to service/UI CLAUDE.md**:

- FastAPI implementation details → Service CLAUDE.md
- OpenAPI generation details → Service CLAUDE.md
- TypeScript type generation workflow details → UI CLAUDE.md
- Component/testing patterns → Service/UI CLAUDE.md

---

### 2. UI CLAUDE.md (Current)

**Location**: `/Users/mac/workspace/research-mind/research-mind-ui/CLAUDE.md`

**Current Purpose**: KuzuMemory configuration (NOT development guidance)

**Current Coverage**:

- Project path and language detection
- KuzuMemory integration commands
- MCP tools for memory management

**Assessment**: **MAJOR ENHANCEMENT NEEDED** — Currently just KuzuMemory config. Needs full SvelteKit/TypeScript development guidance.

**What is MISSING**:

- SvelteKit patterns (routing, layouts, server vs client)
- Svelte 5 runes ($state, $derived, $effect, $props)
- TanStack Query integration (createQuery, hooks pattern)
- API client patterns (client.ts, hooks.ts, generated types)
- Component conventions (props, events, slots, styling)
- Zod validation patterns
- Testing with Vitest
- Styling approach (scoped styles, no Tailwind yet)
- State management (Svelte stores)
- Environment variables (VITE_API_BASE_URL)
- Type generation workflow from OpenAPI
- API contract sync workflow (UI perspective)

---

### 3. Service CLAUDE.md (Current)

**Location**: `/Users/mac/workspace/research-mind/research-mind-service/docs/CLAUDE.md`

**Current Purpose**: Basic service development guidance

**Current Coverage**:

- Quick start commands ✓
- Project structure overview ✓
- Common tasks (testing, linting, migrations) ✓
- API endpoint examples (health, version) ✓
- Configuration via environment variables ✓
- Database migration commands ✓
- Testing with pytest ✓
- Vertical slice architecture pattern ✓
- CORS configuration ✓
- Production considerations ✓

**Assessment**: **MOVE + ENHANCE** — Good foundation but needs to move to `research-mind-service/CLAUDE.md` and expand with missing patterns.

**What is MISSING**:

- API contract sync workflow (service perspective) — CRITICAL
- Adding new endpoints (detailed workflow)
- Pydantic schema patterns and best practices
- SQLAlchemy model conventions
- Database session management patterns
- Dependency injection patterns (FastAPI Depends)
- Error handling conventions
- Testing patterns for async endpoints
- Migration best practices (autogenerate gotchas)
- OpenAPI schema customization
- Request/Response validation patterns
- Database transaction patterns
- Service-specific guard rails

---

## UI Project Inventory (Discovered Patterns)

### Directory Structure

```
research-mind-ui/
├── src/
│   ├── routes/
│   │   ├── +layout.svelte         # Root layout (app.css import)
│   │   └── +page.svelte            # Home page (Svelte 5 runes)
│   ├── lib/
│   │   ├── api/
│   │   │   ├── client.ts           # API client with Zod validation
│   │   │   ├── hooks.ts            # TanStack Query hooks
│   │   │   └── generated.ts        # OpenAPI-generated types
│   │   ├── components/
│   │   │   └── ApiStatus.svelte    # Component with $props rune
│   │   ├── stores/
│   │   │   └── ui.ts               # Svelte writable stores
│   │   └── utils/
│   │       └── env.ts              # Environment variable utilities
│   ├── App.svelte                  # Legacy app root
│   ├── app.css                     # Global styles
│   └── vite-env.d.ts               # Vite type declarations
├── vitest.config.ts                # Vitest configuration (jsdom)
├── svelte.config.js                # SvelteKit config (adapter-auto)
├── eslint.config.js                # ESLint flat config
├── .prettierrc                     # Prettier config
├── package.json                    # Dependencies
└── tsconfig.json                   # TypeScript config
```

### Key Technologies Detected

**Core Stack**:

- **Svelte** 5.0.0-next.0 (preview) - Component framework with runes
- **SvelteKit** (adapter-auto) - Full-stack meta-framework
- **TypeScript** 5.6.3 - Type safety
- **Vite** 6.0.0 - Build tool
- **Vitest** 2.1.8 - Testing framework
- **jsdom** 27.4.0 - DOM testing environment

**State & Data Fetching**:

- **@tanstack/svelte-query** 5.51.23 - Data fetching and caching
- **Zod** 3.22.0 - Runtime validation

**Development Tools**:

- **ESLint** 9.18.0 - Linting (flat config)
- **Prettier** 3.4.2 - Formatting
- **svelte-check** 3.8.6 - Type checking
- **openapi-typescript** 7.4.0 - Type generation

**UI Libraries**:

- **lucide-svelte** 0.344.0 - Icon library
- **NO TAILWIND** — Using scoped Svelte styles

### Patterns Found

#### 1. Svelte 5 Runes Pattern

**Location**: `src/routes/+page.svelte`, `src/lib/components/ApiStatus.svelte`

**$state rune** (reactive local state):

```svelte
<script lang="ts">
  let loading = $state(true);
  let apiStatus = $state('Checking...');
</script>
```

**$effect rune** (reactive side effects):

```svelte
<script lang="ts">
  $effect(() => {
    const checkApi = async () => {
      // Runs when component mounts
      try {
        const response = await fetch(`${apiBaseUrl}/api/v1/version`);
        // ...
      } finally {
        loading = false;
      }
    };
    checkApi();
  });
</script>
```

**$props rune** (component props):

```svelte
<script lang="ts">
  interface QueryState {
    isPending: boolean;
    isError: boolean;
    data?: any;
    error?: Error | null;
  }

  let { query }: { query: QueryState } = $props();
</script>
```

**Pattern**: Svelte 5 runes replace old $ reactive syntax. Use `$state` for local reactive state, `$effect` for side effects, `$props` for component props.

---

#### 2. API Client Pattern with Zod Validation

**Location**: `src/lib/api/client.ts`

```typescript
import { z } from "zod";

const apiBaseUrl =
  import.meta.env.VITE_API_BASE_URL || "http://localhost:15010";

// Zod schema for runtime validation
const VersionResponseSchema = z.object({
  version: z.string(),
  environment: z.string().optional(),
  timestamp: z.string().optional(),
});

// Infer TypeScript type from Zod schema
export type VersionResponse = z.infer<typeof VersionResponseSchema>;

// API Client
export const apiClient = {
  async getVersion(): Promise<VersionResponse> {
    const response = await fetch(`${apiBaseUrl}/api/v1/version`);
    if (!response.ok) {
      throw new Error(`Failed to fetch version: ${response.statusText}`);
    }
    const data = await response.json();
    return VersionResponseSchema.parse(data); // Runtime validation
  },
};
```

**Pattern**: Use Zod schemas for runtime validation + TypeScript type inference. API client methods are async functions that fetch, validate, and return typed data.

---

#### 3. TanStack Query Hooks Pattern

**Location**: `src/lib/api/hooks.ts`

```typescript
import { createQuery } from "@tanstack/svelte-query";
import { apiClient, type VersionResponse } from "./client";

export function useVersionQuery() {
  return createQuery<VersionResponse>({
    queryKey: ["version"],
    queryFn: () => apiClient.getVersion(),
    staleTime: 60000, // 1 minute
    gcTime: 300000, // 5 minutes (formerly cacheTime)
  });
}
```

**Pattern**: Create query hooks using `createQuery`. Use descriptive names (`useXQuery`). Configure staleTime and gcTime for caching.

---

#### 4. Svelte Stores Pattern

**Location**: `src/lib/stores/ui.ts`

```typescript
import { writable } from "svelte/store";

interface UIState {
  sidebarOpen: boolean;
  theme: "light" | "dark";
}

const initialState: UIState = {
  sidebarOpen: true,
  theme: "light",
};

export const uiStore = writable<UIState>(initialState);

// Helper functions for common mutations
export function toggleSidebar() {
  uiStore.update((state) => ({ ...state, sidebarOpen: !state.sidebarOpen }));
}

export function setTheme(theme: "light" | "dark") {
  uiStore.update((state) => ({ ...state, theme }));
}
```

**Pattern**: Use writable stores for global state. Export typed store and helper functions. Update using `.update()` with immutable updates.

---

#### 5. Component Styling Pattern

**Location**: All `.svelte` files

```svelte
<div class="container">
  <h1>Research Mind</h1>
</div>

<style>
  .container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 2rem;
  }

  h1 {
    color: #0066cc;
    font-size: 2.5rem;
  }
</style>
```

**Pattern**: **Scoped styles** in each component. No Tailwind CSS detected. Use semantic class names. Styles are component-scoped by default.

---

#### 6. Environment Variable Pattern

**Location**: `src/lib/utils/env.ts`, `src/lib/api/client.ts`

```typescript
// In client.ts
const apiBaseUrl =
  import.meta.env.VITE_API_BASE_URL || "http://localhost:15010";

// In components
import { getApiBaseUrl } from "$lib/utils/env";
const apiBaseUrl = getApiBaseUrl();
```

**Pattern**: Use `import.meta.env.VITE_*` for environment variables. Provide sensible defaults. Create utility functions for common env access.

---

#### 7. Vitest Configuration

**Location**: `vitest.config.ts`

```typescript
import { defineConfig } from "vitest/config";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte({ hot: !process.env.VITEST })],
  test: {
    globals: true,
    environment: "jsdom",
  },
});
```

**Pattern**: Configure Vitest with Svelte plugin and jsdom environment. Use `globals: true` for global test APIs.

---

#### 8. SvelteKit Layout Pattern

**Location**: `src/routes/+layout.svelte`

```svelte
<script lang="ts">
  import './app.css';
</script>

<main>
  <slot />
</main>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
  }
</style>
```

**Pattern**: Root layout imports global CSS. Use `<slot />` for nested routes. Use `:global()` for global style overrides.

---

#### 9. Conditional Rendering Pattern

**Location**: `src/lib/components/ApiStatus.svelte`

```svelte
{#if query.isPending}
  <div class="loading">Loading...</div>
{:else if query.isError}
  <div class="error">Error: {query.error?.message}</div>
{:else if query.data}
  <div class="success">Connected</div>
{:else}
  <div class="idle">No data</div>
{/if}
```

**Pattern**: Use `{#if}`, `{:else if}`, `{:else}`, `{/if}` for conditional rendering. Chain multiple conditions for state machines.

---

## Service Project Inventory

### Directory Structure

```
research-mind-service/
├── app/
│   ├── __init__.py
│   ├── main.py                  # FastAPI app + Settings + CORS
│   ├── routes/
│   │   ├── health.py            # Health check endpoint
│   │   └── api.py               # /api/v1 versioned endpoints
│   ├── schemas/
│   │   ├── common.py            # Generic types (ErrorResponse, PaginatedResponse, HealthResponse)
│   │   └── __init__.py
│   ├── models/
│   │   ├── session.py           # Session SQLAlchemy model
│   │   └── __init__.py
│   ├── db/
│   │   ├── session.py           # Database engine + session factory
│   │   └── __init__.py
│   ├── auth/
│   │   └── __init__.py          # Empty (stubs)
│   └── sandbox/
│       ├── README.md            # Security-critical isolation (Phase 1.4+)
│       └── __init__.py
├── tests/
│   ├── conftest.py              # Pytest fixtures (TestClient)
│   ├── test_health.py           # Health endpoint tests
│   └── __init__.py
├── migrations/
│   ├── env.py                   # Alembic environment
│   ├── script.py.mako           # Migration template
│   └── versions/                # Migration files (empty)
├── docs/
│   ├── api-contract.md          # API contract (18KB, comprehensive)
│   └── CLAUDE.md                # Basic development guide
├── .env.example                 # Environment template
├── alembic.ini                  # Alembic configuration
├── Makefile                     # Common tasks
├── pyproject.toml               # Python dependencies
└── README.md                    # Project README
```

### Key Technologies Detected

**Core Stack**:

- **FastAPI** 0.109.0 - Web framework
- **Uvicorn** 0.27.0 - ASGI server
- **SQLAlchemy** 2.0.23 - ORM (with async support)
- **Alembic** 1.13.0 - Database migrations
- **Psycopg** 3.1.12 - PostgreSQL driver
- **Pydantic** 2.5.0 - Data validation
- **Pydantic Settings** 2.1.0 - Configuration management

**Development Tools**:

- **pytest** 7.4.3 + **pytest-asyncio** 0.21.1 - Testing
- **httpx** 0.25.2 - HTTP client for testing
- **ruff** 0.1.11 - Linting
- **black** 23.12.0 - Formatting
- **mypy** 1.7.1 - Type checking
- **uv** - Package manager

**Authentication** (stubs):

- **python-jose** 3.3.0 - JWT tokens
- **passlib** 1.7.4 - Password hashing

**Additional**:

- **mcp-vector-search** >= 0.1.0 - Vector search integration

### Patterns Found

#### 1. Settings Pattern (Pydantic Settings)

**Location**: `app/main.py`

```python
class Settings(BaseSettings):
    SERVICE_ENV: str = "development"
    SERVICE_HOST: str = "0.0.0.0"
    SERVICE_PORT: int = 15010
    DATABASE_URL: str = "postgresql://postgres:devpass123@localhost:5432/research_mind_db"  <!-- pragma: allowlist secret -->
    CORS_ORIGINS: str = "http://localhost:15000"
    SECRET_KEY: str = "dev-secret-change-in-production"
    ALGORITHM: str = "HS256"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
```

**Pattern**: Environment-based configuration with sensible defaults

---

#### 2. Lazy Database Initialization

**Location**: `app/db/session.py`

```python
_engine = None
_SessionLocal = None

def get_engine():
    global _engine
    if _engine is None:
        from app.main import settings
        _engine = create_engine(
            settings.DATABASE_URL,
            echo=False,
            pool_pre_ping=True,
        )
    return _engine

def get_db() -> Generator[Session, None, None]:
    db = get_session_local()()
    try:
        yield db
    finally:
        db.close()
```

**Pattern**: Lazy initialization to avoid import errors, generator for dependency injection

---

#### 3. SQLAlchemy Model Pattern

**Location**: `app/models/session.py`

```python
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class Session(Base):
    __tablename__ = "sessions"

    session_id = Column(String(36), primary_key=True, default=lambda: str(uuid4()))
    name = Column(String(255), nullable=False)
    description = Column(String(1024), nullable=True)
    workspace_path = Column(String(512), nullable=False, unique=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    last_accessed = Column(DateTime, nullable=False, default=datetime.utcnow)
    status = Column(String(50), nullable=False, default="active")
    index_stats = Column(JSON, nullable=True, default={...})
```

**Pattern**: Declarative models with UUIDs, timestamps, JSON columns for flexible metadata

---

#### 4. Router Organization

**Location**: `app/routes/health.py`, `app/routes/api.py`

```python
from fastapi import APIRouter

router = APIRouter()

@router.get("/health")
async def health_check():
    return {
        "status": "ok",
        "name": "research-mind-service",
        "version": "0.1.0",
        "git_sha": get_git_sha(),
    }
```

**Pattern**: Separate routers for different endpoint groups, included in main app

---

#### 5. Testing Pattern (FastAPI TestClient)

**Location**: `tests/conftest.py`, `tests/test_health.py`

```python
@pytest.fixture
def client():
    return TestClient(app)

def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
```

**Pattern**: pytest fixtures for TestClient, synchronous test functions

---

#### 6. Generic Pydantic Types

**Location**: `app/schemas/common.py`

```python
T = TypeVar("T")

class PaginatedResponse(BaseModel, Generic[T]):
    data: List[T]
    pagination: dict

class ErrorResponse(BaseModel):
    error: dict[str, str | None]
```

**Pattern**: Generic types for reusable schemas

---

#### 7. Git SHA Helper

**Location**: `app/routes/health.py`

```python
def get_git_sha() -> str:
    """Get git SHA, fallback to 'unknown' if not in git repo."""
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"]).decode().strip()[:7]
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"
```

**Pattern**: Defensive utilities with fallbacks

---

## Recommended Content for All Three CLAUDE.md Files

### Part 1: Root CLAUDE.md (Monorepo Coordination ONLY)

**Location**: `/Users/mac/workspace/research-mind/CLAUDE.md`

**Purpose**: Cross-project coordination when working at monorepo level

**Sections to KEEP** (trimmed):

1. **Quick Start** (basic commands only)

   - `make install`, `make dev`, `make test`
   - Service URL, UI URL

2. **Project Structure** (high-level only)

   - List sub-projects: service, UI, docs
   - No deep dive into internal structure

3. **API Contract Sync** (high-level coordination)

   - **Golden Rule**: Contract is frozen
   - **Workflow summary**: Backend → Frontend order
   - **Checklist**: Contract updated, both files identical, types regenerated
   - **Refer to sub-projects** for detailed implementation

4. **Cross-Project Configuration**

   - Service port: 15010
   - UI port: 15000
   - CORS coordination

5. **Common Tasks** (monorepo-level)

   - `make dev`, `make stop`, `make test`, `make lint`
   - `make gen-client`, `make db-reset`

6. **Deployment Order**

   - Backend first, then frontend
   - Version bump strategy

7. **Guard Rails** (cross-project)
   - No .env in git
   - Contract must be identical in both projects
   - Version bump required for API changes
   - Tests required before deployment

**Sections to REMOVE** (move to service/UI):

- FastAPI implementation details
- Pydantic schema examples
- OpenAPI generation details
- TypeScript type generation details
- Component testing patterns
- SQLAlchemy patterns
- SvelteKit routing

**Example trimmed content**:

```markdown
## API Contract Synchronization

The API contract is the single source of truth. Changes flow Backend → Frontend.

**Workflow Summary**:

1. Update contract in service
2. Implement backend changes
3. Run backend tests
4. Copy contract to UI
5. Regenerate UI types
6. Update UI code
7. Run UI tests

**Critical Rules**:

- Both `api-contract.md` files must be identical
- Version bump required for breaking changes
- Deploy backend before frontend

For detailed workflow, see:

- Service: `research-mind-service/CLAUDE.md`
- UI: `research-mind-ui/CLAUDE.md`
```

---

### Part 2: Service CLAUDE.md (Standalone Backend Guide)

**Location**: `/Users/mac/workspace/research-mind/research-mind-service/CLAUDE.md`

**Purpose**: Complete guide for backend development (standalone, no dependency on root)

**Required Sections**:

1. **Quick Start** (service-specific)

   - Installation: `cd research-mind-service && uv sync`
   - Run dev server: `uv run uvicorn app.main:app --reload`
   - Service URL: `http://localhost:15010`

2. **Project Structure** (detailed)

   - `app/routes/` - Endpoint implementations
   - `app/schemas/` - Pydantic models
   - `app/models/` - SQLAlchemy ORM models
   - `app/db/` - Database session management
   - `tests/` - Pytest test suite
   - `migrations/` - Alembic migrations

3. **API Contract Sync Workflow** (COMPLETE END-TO-END - SERVICE PERSPECTIVE)

   ````markdown
   ## API Contract Sync Workflow (Service Side)

   **You are responsible for**:

   1. Updating the contract FIRST
   2. Implementing backend changes
   3. Ensuring contract is copied to UI

   **Step-by-Step**:

   1. Edit `docs/api-contract.md`

      - Add/modify endpoints
      - Update schemas
      - Version bump (major/minor/patch)
      - Add changelog entry

   2. Update Pydantic schemas in `app/schemas/`
      ```python
      class CreateSessionRequest(BaseModel):
          name: str = Field(..., min_length=1)
      ```
   ````

   3. Implement routes in `app/routes/`

      ```python
      @router.post("/sessions", response_model=SessionResponse)
      async def create_session(request: CreateSessionRequest):
          # Implementation
      ```

   4. Run backend tests: `uv run pytest`

   5. Copy contract to UI:

      ```bash
      cp docs/api-contract.md ../research-mind-ui/docs/api-contract.md
      ```

   6. Inform UI team to regenerate types

   **Contract Location**:

   - Service source of truth: `research-mind-service/docs/api-contract.md`
   - UI copy (must be identical): `research-mind-ui/docs/api-contract.md`

   ```

   ```

4. **FastAPI Development Patterns** (from existing recommendations)

   - Adding new endpoints
   - Dependency injection (Depends)
   - Error handling (HTTPException)
   - Request/Response validation
   - OpenAPI customization

5. **Database & SQLAlchemy Patterns**

   - Model conventions
   - Session management
   - Transactions
   - Migration workflow (Alembic)

6. **Testing Conventions**

   - Pytest patterns
   - FastAPI TestClient
   - Async testing
   - Database testing

7. **Pydantic Schema Patterns**

   - Field validation
   - Generic types
   - Model config

8. **Service-Specific Guard Rails**

   - Linting, formatting, type checking
   - Migration safety
   - Configuration management
   - Error exposure

9. **Environment & Configuration**

   - Required environment variables
   - Settings pattern (Pydantic Settings)
   - Development vs production config

10. **Vertical Slice Architecture**
    - Complete feature slice example
    - Shared components
    - Adding new features

**Key Principle**: Service CLAUDE.md must be **fully standalone**. Developers working only on the service should have everything they need without referring to root CLAUDE.md.

---

### Part 3: UI CLAUDE.md (Standalone Frontend Guide)

**Location**: `/Users/mac/workspace/research-mind/research-mind-ui/CLAUDE.md`

**Purpose**: Complete guide for frontend development (standalone, replaces KuzuMemory config)

**Required Sections**:

1. **Quick Start** (UI-specific)

   - Installation: `cd research-mind-ui && npm install`
   - Run dev server: `npm run dev`
   - UI URL: `http://localhost:15000`

2. **Project Structure** (detailed)

   - `src/routes/` - SvelteKit pages and layouts
   - `src/lib/api/` - API client and TanStack Query hooks
   - `src/lib/components/` - Reusable Svelte components
   - `src/lib/stores/` - Svelte stores for global state
   - `src/lib/utils/` - Utility functions
   - `vitest.config.ts` - Test configuration

3. **API Contract Sync Workflow** (COMPLETE END-TO-END - UI PERSPECTIVE)

   ````markdown
   ## API Contract Sync Workflow (UI Side)

   **You are waiting for**:

   1. Backend team to update contract
   2. Backend tests to pass
   3. Contract to be copied to UI

   **Step-by-Step**:

   1. Verify contract copied from service:

      - Service source: `research-mind-service/docs/api-contract.md`
      - UI copy: `research-mind-ui/docs/api-contract.md`
      - Files must be identical (use diff)

   2. Ensure service is running:
      ```bash
      # Service must be up for type generation
      curl http://localhost:15010/health
      ```
   ````

   3. Regenerate TypeScript types:

      ```bash
      npm run gen:api
      # Generates src/lib/api/generated.ts from OpenAPI
      ```

   4. Update API client (`src/lib/api/client.ts`):

      ```typescript
      import type { SessionResponse } from "./generated";

      export const apiClient = {
        async getSession(id: string): Promise<SessionResponse> {
          const response = await fetch(`${baseUrl}/api/v1/sessions/${id}`);
          return response.json();
        },
      };
      ```

   5. Create TanStack Query hook (`src/lib/api/hooks.ts`):

      ```typescript
      export function useSessionQuery(id: string) {
        return createQuery({
          queryKey: ["session", id],
          queryFn: () => apiClient.getSession(id),
        });
      }
      ```

   6. Use in components:

      ```svelte
      <script lang="ts">
        import { useSessionQuery } from '$lib/api/hooks';
        const query = useSessionQuery('session-id');
      </script>

      {#if $query.isPending}
        Loading...
      {:else if $query.isError}
        Error: {$query.error.message}
      {:else if $query.data}
        {$query.data.name}
      {/if}
      ```

   7. Run UI tests: `npm test`

   **Type Generation**:

   - Generated file: `src/lib/api/generated.ts` (DO NOT EDIT)
   - Always in sync with backend OpenAPI schema

   ```

   ```

4. **SvelteKit Patterns**

   - Routing and layouts (+page.svelte, +layout.svelte)
   - Server vs client code (+page.server.ts, +page.ts)
   - File-based routing conventions
   - Nested layouts

5. **Svelte 5 Runes**

   - `$state` - Reactive local state
   - `$derived` - Computed values
   - `$effect` - Side effects
   - `$props` - Component props
   - Migration from Svelte 4 reactive declarations

6. **State Management & Data Fetching**

   - TanStack Query (createQuery, createMutation)
   - Svelte stores (writable, derived, readable)
   - When to use TanStack Query vs stores
   - Query hooks pattern

7. **API Client Patterns**

   - API client structure (client.ts)
   - Zod validation for runtime type safety
   - Error handling
   - Environment variables (VITE_API_BASE_URL)

8. **Component Conventions**

   - Props with $props rune
   - Events and callbacks
   - Slots for composition
   - Scoped styling (no Tailwind)
   - Styling conventions

9. **Testing**

   - Vitest configuration (jsdom environment)
   - Component testing
   - Testing with TanStack Query
   - Testing async effects

10. **Tooling**

    - ESLint (flat config)
    - Prettier
    - svelte-check (type checking)
    - Type generation from OpenAPI

11. **UI-Specific Guard Rails**
    - Never edit generated.ts
    - Always regenerate types after backend changes
    - Test before deploy
    - Lint and format required

**Key Principle**: UI CLAUDE.md must be **fully standalone**. Developers working only on the UI should have everything they need without referring to root CLAUDE.md.

---

## Recommended CLAUDE.md Sections (DEPRECATED - SEE ABOVE)

### Section 1: FastAPI Development Patterns

**Why needed**: Service-specific framework patterns not covered in root CLAUDE.md

**Content**:

````markdown
## FastAPI Development Patterns

### Adding a New Endpoint

Follow this workflow for consistency:

1. **Define Pydantic Schema** (`app/schemas/{feature}.py`):

   - Request models inherit from `BaseModel`
   - Use Pydantic v2 field validators
   - Add docstrings for OpenAPI documentation
   - Example:

     ```python
     from pydantic import BaseModel, Field

     class CreateSessionRequest(BaseModel):
         """Request to create a new research session."""
         name: str = Field(..., min_length=1, max_length=255)
         description: str | None = Field(None, max_length=1024)

     class SessionResponse(BaseModel):
         """Session metadata response."""
         id: str
         name: str
         description: str | None
         status: str
         created_at: str
     ```

2. **Create Router** (`app/routes/{feature}.py`):

   - Use APIRouter for endpoint grouping
   - Include dependency injection (FastAPI `Depends`)
   - Add response models for OpenAPI schema
   - Example:

     ```python
     from fastapi import APIRouter, Depends, HTTPException
     from sqlalchemy.orm import Session
     from app.db.session import get_db
     from app.schemas.session import CreateSessionRequest, SessionResponse

     router = APIRouter(prefix="/sessions", tags=["sessions"])

     @router.post("/", response_model=SessionResponse, status_code=201)
     async def create_session(
         request: CreateSessionRequest,
         db: Session = Depends(get_db)
     ):
         # Implementation here
         pass
     ```

3. **Register Router** (`app/main.py`):
   ```python
   from app.routes import sessions
   app.include_router(sessions.router, prefix="/api/v1")
   ```
````

4. **Write Tests** (`tests/test_{feature}.py`):

   - Use `TestClient` fixture from `conftest.py`
   - Test happy path, validation errors, edge cases
   - Example:
     ```python
     def test_create_session(client):
         response = client.post("/api/v1/sessions", json={
             "name": "Test Session",
             "description": "Test description"
         })
         assert response.status_code == 201
         data = response.json()
         assert data["name"] == "Test Session"
     ```

5. **Update API Contract** (`docs/api-contract.md`):
   - Document request/response schemas
   - Add error codes
   - Update changelog
   - Version bump if breaking change

### Dependency Injection Pattern

FastAPI's `Depends` is the preferred method for injecting dependencies:

**Database Session**:

```python
from fastapi import Depends
from sqlalchemy.orm import Session
from app.db.session import get_db

@router.get("/sessions/{session_id}")
async def get_session(
    session_id: str,
    db: Session = Depends(get_db)  # Injected
):
    # Use db here
    pass
```

**Current User** (when auth is implemented):

```python
from app.auth import get_current_user

@router.get("/sessions")
async def list_sessions(
    user: User = Depends(get_current_user)
):
    # user is validated and injected
    pass
```

### Error Handling Conventions

**Use HTTPException for client errors**:

```python
from fastapi import HTTPException

if not session:
    raise HTTPException(
        status_code=404,
        detail={
            "error": {
                "code": "SESSION_NOT_FOUND",
                "message": f"Session '{session_id}' not found"
            }
        }
    )
```

**Error codes match api-contract.md**:

- `SESSION_NOT_FOUND` - 404
- `SESSION_NOT_INDEXED` - 400
- `VALIDATION_ERROR` - 400
- `INTERNAL_ERROR` - 500

### Request/Response Validation

**Always use Pydantic models**:

- NO: `request: dict`
- YES: `request: CreateSessionRequest`

**Benefits**:

- Automatic validation
- OpenAPI schema generation
- Type safety
- IDE autocomplete

### OpenAPI Customization

**Add descriptions and examples**:

```python
from pydantic import Field

class CreateSessionRequest(BaseModel):
    """Create a new research session."""
    name: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Human-readable session name",
        examples=["OAuth2 Auth Module Research"]
    )
```

**Result**: Better API documentation at `/docs`

````

---

### Section 2: Database & SQLAlchemy Patterns

**Why needed**: Service uses SQLAlchemy 2.0 with specific patterns for sessions, models, migrations

**Content**:

```markdown
## Database & SQLAlchemy Patterns

### Model Conventions

**Location**: `app/models/{entity}.py`

**Required fields**:
- Primary key (usually UUID)
- Timestamps (`created_at`, `updated_at`)
- Nullable fields explicit (`nullable=True` or `nullable=False`)

**Example**:
```python
from datetime import datetime
from uuid import uuid4
from sqlalchemy import Column, String, DateTime, JSON
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class MyModel(Base):
    __tablename__ = "my_table"

    # Primary key (UUID)
    id = Column(String(36), primary_key=True, default=lambda: str(uuid4()))

    # Required fields
    name = Column(String(255), nullable=False)

    # Optional fields
    description = Column(String(1024), nullable=True)

    # Timestamps
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    # JSON for flexible metadata
    metadata = Column(JSON, nullable=True)
````

### Database Session Management

**DO**: Use dependency injection

```python
from fastapi import Depends
from sqlalchemy.orm import Session
from app.db.session import get_db

@router.get("/items")
def get_items(db: Session = Depends(get_db)):
    items = db.query(MyModel).all()
    return items
```

**DON'T**: Create sessions manually

```python
# WRONG - session not closed properly
from app.db.session import get_session_local
SessionLocal = get_session_local()
db = SessionLocal()
items = db.query(MyModel).all()
```

### Transaction Patterns

**Auto-commit with context manager**:

```python
from app.db.session import get_session_local

SessionLocal = get_session_local()

def create_item(data: dict):
    db = SessionLocal()
    try:
        item = MyModel(**data)
        db.add(item)
        db.commit()
        db.refresh(item)
        return item
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
```

**In endpoints (FastAPI Depends handles close)**:

```python
@router.post("/items")
def create_item(request: CreateItemRequest, db: Session = Depends(get_db)):
    item = MyModel(name=request.name)
    db.add(item)
    db.commit()
    db.refresh(item)
    return item
```

### Migration Best Practices

**Create migration**:

```bash
make migrate-new MSG="Add users table"
# OR
uv run alembic revision --autogenerate -m "Add users table"
```

**Review before applying**:

- ALWAYS review autogenerated migrations in `migrations/versions/`
- Alembic can miss:
  - Index changes
  - Constraint modifications
  - Enum alterations
- Manual fixes often needed

**Apply migrations**:

```bash
make migrate
# OR
uv run alembic upgrade head
```

**Rollback**:

```bash
make migrate-down
# OR
uv run alembic downgrade -1
```

### Alembic Autogenerate Gotchas

**Alembic CANNOT detect**:

- Table name changes (creates drop + create)
- Column name changes (creates drop + create)
- Enum value changes (manual migration required)

**Workaround**: Write manual migrations for renames

```python
# In migration file
def upgrade():
    op.rename_table('old_name', 'new_name')
    # OR
    op.alter_column('table', 'old_column', new_column_name='new_column')
```

### Database Configuration

**Environment Variables** (`.env`):

```bash
DATABASE_URL=postgresql://user:password@host:port/dbname  <!-- pragma: allowlist secret -->
SQLALCHEMY_ECHO=false  # Set to true for SQL logging
```

**Connection Pool Settings**:

```python
# In app/db/session.py
_engine = create_engine(
    settings.DATABASE_URL,
    echo=settings.SQLALCHEMY_ECHO,
    pool_pre_ping=True,      # Verify connections before using
    pool_size=5,              # Max connections
    max_overflow=10,          # Extra connections when pool full
)
```

````

---

### Section 3: Testing Conventions

**Why needed**: Service uses pytest + pytest-asyncio with specific patterns for FastAPI testing

**Content**:

```markdown
## Testing Conventions

### Test Structure

**Location**: `tests/test_{feature}.py`

**Naming**:
- Test files: `test_*.py`
- Test functions: `def test_*():`
- Test classes: `class Test*:`

### FastAPI Testing Pattern

**Use TestClient fixture**:
```python
from fastapi.testclient import TestClient
from app.main import app

def test_endpoint():
    client = TestClient(app)
    response = client.get("/api/v1/endpoint")
    assert response.status_code == 200
````

**Shared fixture in conftest.py**:

```python
# tests/conftest.py
import pytest
from fastapi.testclient import TestClient
from app.main import app

@pytest.fixture
def client():
    return TestClient(app)

# tests/test_feature.py
def test_create_item(client):
    response = client.post("/api/v1/items", json={"name": "Test"})
    assert response.status_code == 201
```

### Database Testing

**Option 1: In-memory SQLite** (fast, isolated):

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.models.base import Base

@pytest.fixture
def test_db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(bind=engine)
    yield SessionLocal()
    Base.metadata.drop_all(engine)

def test_create_session(test_db):
    session = Session(name="Test")
    test_db.add(session)
    test_db.commit()
    assert session.id is not None
```

**Option 2: Test database** (more realistic):

```python
import pytest
from app.db.session import get_db
from app.main import app

@pytest.fixture
def override_db():
    # Use test database
    # Return dependency override
    pass

def test_with_real_db(client, override_db):
    app.dependency_overrides[get_db] = override_db
    response = client.post("/api/v1/items", json={"name": "Test"})
    assert response.status_code == 201
    app.dependency_overrides.clear()
```

### Async Testing

**pytest-asyncio required**:

```bash
# Already in pyproject.toml
pytest-asyncio==0.21.1
```

**Test async functions**:

```python
import pytest

@pytest.mark.asyncio
async def test_async_endpoint():
    # Test async code here
    result = await some_async_function()
    assert result is not None
```

### Test Coverage

**Run with coverage**:

```bash
uv run pytest --cov=app --cov-report=html
```

**View report**:

```bash
open htmlcov/index.html
```

**Minimum coverage**: Aim for >80% on new code

### Testing Best Practices

**DO**:

- Test happy path
- Test validation errors (400)
- Test not found (404)
- Test edge cases (empty lists, boundary values)
- Use descriptive test names
- Assert specific error messages

**DON'T**:

- Test third-party libraries (SQLAlchemy, FastAPI)
- Skip cleanup (use fixtures for teardown)
- Share state between tests (use fresh fixtures)

````

---

### Section 4: Pydantic Schema Patterns

**Why needed**: Service uses Pydantic v2 with specific conventions for request/response validation

**Content**:

```markdown
## Pydantic Schema Patterns

### Schema Organization

**Location**: `app/schemas/{feature}.py`

**Naming Conventions**:
- Request models: `{Action}{Entity}Request` (e.g., `CreateSessionRequest`)
- Response models: `{Entity}Response` (e.g., `SessionResponse`)
- Update models: `Update{Entity}Request` (partial fields)

### Field Validation

**Use Pydantic Field for constraints**:
```python
from pydantic import BaseModel, Field

class CreateSessionRequest(BaseModel):
    name: str = Field(
        ...,                          # Required field
        min_length=1,                 # Minimum length
        max_length=255,               # Maximum length
        description="Session name",  # OpenAPI description
        examples=["My Research Session"]  # OpenAPI examples
    )
    description: str | None = Field(
        None,                         # Optional (default None)
        max_length=1024,
        description="Optional description"
    )
````

### Generic Types

**Reuse common patterns** (`app/schemas/common.py`):

```python
from typing import TypeVar, Generic, List
from pydantic import BaseModel

T = TypeVar("T")

class PaginatedResponse(BaseModel, Generic[T]):
    """Generic paginated response."""
    data: List[T]
    pagination: dict

class ErrorResponse(BaseModel):
    """Standard error response."""
    error: dict[str, str | None]
```

**Usage**:

```python
from app.schemas.common import PaginatedResponse
from app.schemas.session import SessionResponse

@router.get("/sessions", response_model=PaginatedResponse[SessionResponse])
async def list_sessions():
    return {
        "data": [...],
        "pagination": {...}
    }
```

### Request vs Response Models

**Separate models for requests and responses**:

```python
# Request model (what client sends)
class CreateUserRequest(BaseModel):
    email: str
    password: str  # NOT in response

# Response model (what server returns)
class UserResponse(BaseModel):
    id: str
    email: str
    created_at: str
    # password omitted for security
```

### Model Config

**Pydantic v2 config**:

```python
class SessionResponse(BaseModel):
    id: str
    name: str
    created_at: str

    model_config = {
        "from_attributes": True,  # Allow ORM models (was orm_mode in v1)
        "json_schema_extra": {
            "examples": [{
                "id": "sess_abc123",
                "name": "My Session",
                "created_at": "2026-01-31T14:30:00Z"
            }]
        }
    }
```

### Validators

**Custom validation**:

```python
from pydantic import BaseModel, field_validator

class CreateSessionRequest(BaseModel):
    name: str
    workspace_path: str

    @field_validator('workspace_path')
    @classmethod
    def validate_path(cls, v: str) -> str:
        if not v.startswith('/var/lib/research-mind'):
            raise ValueError('Invalid workspace path')
        return v
```

### Serialization

**Convert ORM to Pydantic**:

```python
from sqlalchemy.orm import Session
from app.models.session import Session as SessionModel
from app.schemas.session import SessionResponse

@router.get("/sessions/{id}", response_model=SessionResponse)
def get_session(id: str, db: Session = Depends(get_db)):
    session = db.query(SessionModel).filter_by(id=id).first()
    if not session:
        raise HTTPException(status_code=404)

    # Pydantic automatically converts ORM model (from_attributes=True)
    return session
```

````

---

### Section 5: Service-Specific Guard Rails

**Why needed**: Service has specific constraints beyond monorepo rules

**Content**:

```markdown
## Service-Specific Guard Rails

### Code Quality Requirements

**Linting** (must pass before commit):
```bash
make lint
# OR
uv run ruff check app tests
````

**Formatting** (automatic):

```bash
make fmt
# OR
uv run black app tests
uv run ruff check --fix app tests
```

**Type Checking** (must pass):

```bash
make typecheck
# OR
uv run mypy app
```

**All checks**:

```bash
make check  # Runs lint + typecheck + test
```

### Migration Safety

**ALWAYS**:

- Review autogenerated migrations before applying
- Test migrations on development database first
- Create backups before production migrations
- Use `make migrate-down` if migration fails

**NEVER**:

- Skip migration review (autogenerate has blind spots)
- Apply untested migrations to production
- Delete migration files (breaks version history)
- Modify applied migrations (create new migration instead)

### Database Constraints

**ALWAYS**:

- Use transactions for multi-step operations
- Add database constraints (unique, not null, foreign keys)
- Use indexes for frequently queried columns
- Validate data in Pydantic schemas AND database

**Example**:

```python
# Pydantic validation
class CreateUserRequest(BaseModel):
    email: str = Field(..., regex=r'^[^@]+@[^@]+\.[^@]+$')

# Database constraint
class User(Base):
    __tablename__ = "users"
    email = Column(String(255), nullable=False, unique=True)
    # Database enforces uniqueness even if validation bypassed
```

### Configuration Management

**NEVER**:

- Hardcode secrets in code
- Commit `.env` to git
- Use development secrets in production
- Store API keys in database

**ALWAYS**:

- Use environment variables
- Keep `.env.example` updated
- Rotate production secrets regularly
- Use different secrets per environment

### Error Exposure

**NEVER expose internal errors to clients**:

```python
# WRONG - leaks implementation details
@router.get("/items/{id}")
def get_item(id: str, db: Session = Depends(get_db)):
    return db.query(Item).filter_by(id=id).first()  # Returns None, not 404
```

```python
# CORRECT - explicit error handling
@router.get("/items/{id}")
def get_item(id: str, db: Session = Depends(get_db)):
    item = db.query(Item).filter_by(id=id).first()
    if not item:
        raise HTTPException(
            status_code=404,
            detail={"error": {"code": "ITEM_NOT_FOUND", "message": f"Item {id} not found"}}
        )
    return item
```

### Testing Requirements

**Minimum requirements**:

- 1 test per endpoint (happy path)
- 1 test for validation errors
- 1 test for not found (404)
- All tests must pass before merge

**NO exceptions**: Tests required for ALL code paths

````

---

### Section 6: Environment & Configuration

**Why needed**: Service has specific environment variable patterns and configuration management

**Content**:

```markdown
## Environment & Configuration

### Environment Variables

**Required** (must be set):
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY` - JWT secret (change in production!)

**Optional** (have defaults):
- `SERVICE_ENV` - Environment (development/production)
- `SERVICE_HOST` - Host to bind (default: 0.0.0.0)
- `SERVICE_PORT` - Port to bind (default: 15010)
- `CORS_ORIGINS` - Allowed CORS origins (default: http://localhost:15000)
- `ALGORITHM` - JWT algorithm (default: HS256)

**Vector Search** (Phase 1.0+):
- `VECTOR_SEARCH_ENABLED` - Enable vector search (default: true)
- `VECTOR_SEARCH_MODEL` - Model name (default: all-MiniLM-L6-v2)
- `HF_HOME` - HuggingFace cache directory
- `TRANSFORMERS_CACHE` - Transformers cache directory
- `HF_HUB_CACHE` - HuggingFace Hub cache directory

### Configuration Pattern

**Centralized settings** (`app/main.py`):
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Server
    SERVICE_ENV: str = "development"
    SERVICE_HOST: str = "0.0.0.0"
    SERVICE_PORT: int = 15010

    # Database
    DATABASE_URL: str = "postgresql://postgres:password@localhost:5432/research_mind"  <!-- pragma: allowlist secret -->

    # CORS
    CORS_ORIGINS: str = "http://localhost:15000"

    # Auth
    SECRET_KEY: str = "dev-secret-change-in-production"
    ALGORITHM: str = "HS256"

    class Config:
        env_file = ".env"
        extra = "ignore"  # Ignore unknown env vars

settings = Settings()
````

**Access settings**:

```python
from app.main import settings

database_url = settings.DATABASE_URL
```

### Development Setup

**1. Copy environment template**:

```bash
cp .env.example .env
```

**2. Edit `.env`** with local values:

```bash
DATABASE_URL=postgresql://postgres:mypassword@localhost:5432/research_mind_dev  <!-- pragma: allowlist secret -->
SECRET_KEY=my-dev-secret-key
CORS_ORIGINS=http://localhost:15000
```

**3. Verify configuration**:

```bash
make dev
# Service starts on http://localhost:15010
```

### Production Configuration

**CRITICAL**: Change these in production:

- `SECRET_KEY` - Generate secure random key
- `DATABASE_URL` - Use production database
- `CORS_ORIGINS` - Set allowed frontend domains
- `SERVICE_ENV=production` - Enable production mode

**Generate secure secret**:

```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

**Production `.env` example**:

```bash
SERVICE_ENV=production
DATABASE_URL=postgresql://user:password@db.example.com:5432/research_mind_prod  <!-- pragma: allowlist secret -->
CORS_ORIGINS=https://research-mind.io,https://app.research-mind.io
SECRET_KEY=<generated-secure-key>
```

### CORS Configuration

**Development** (single origin):

```bash
CORS_ORIGINS=http://localhost:15000
```

**Production** (multiple origins):

```bash
CORS_ORIGINS=https://research-mind.io,https://app.research-mind.io,https://api.research-mind.io
```

**How it works**:

```python
# app/main.py
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS.split(","),  # Comma-separated
    allow_methods=["*"],
    allow_headers=["*"],
)
```

````

---

### Section 7: Vertical Slice Architecture (Service-Specific)

**Why needed**: Expand on the vertical slice pattern mentioned in docs/CLAUDE.md with concrete examples

**Content**:

```markdown
## Vertical Slice Architecture

### What is a Vertical Slice?

A **vertical slice** is a complete feature that cuts through all layers:
- Route (API endpoint)
- Schema (request/response validation)
- Model (database entity)
- Business logic
- Test

**Benefits**:
- Features are self-contained
- Easy to understand complete flow
- Changes isolated to one slice
- Parallel development possible

### Example Slice: Session Management

**Route** (`app/routes/sessions.py`):
```python
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.schemas.session import CreateSessionRequest, SessionResponse
from app.models.session import Session as SessionModel

router = APIRouter(prefix="/sessions", tags=["sessions"])

@router.post("/", response_model=SessionResponse, status_code=201)
async def create_session(
    request: CreateSessionRequest,
    db: Session = Depends(get_db)
):
    session = SessionModel(
        name=request.name,
        description=request.description
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return session
````

**Schema** (`app/schemas/session.py`):

```python
from pydantic import BaseModel, Field

class CreateSessionRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = Field(None, max_length=1024)

class SessionResponse(BaseModel):
    id: str
    name: str
    description: str | None
    status: str
    created_at: str

    model_config = {"from_attributes": True}
```

**Model** (`app/models/session.py`):

```python
from sqlalchemy import Column, String, DateTime
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
from uuid import uuid4

Base = declarative_base()

class Session(Base):
    __tablename__ = "sessions"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid4()))
    name = Column(String(255), nullable=False)
    description = Column(String(1024), nullable=True)
    status = Column(String(50), nullable=False, default="active")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
```

**Test** (`tests/test_sessions.py`):

```python
def test_create_session(client):
    response = client.post("/api/v1/sessions", json={
        "name": "Test Session",
        "description": "Test description"
    })
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Test Session"
    assert "id" in data
```

### Shared Components

Some components are shared across slices:

- `app/db/` - Database session management
- `app/schemas/common.py` - Generic types (PaginatedResponse, ErrorResponse)
- `app/auth/` - Authentication (when implemented)
- `tests/conftest.py` - Shared test fixtures

### Slice Workflow

**When adding a new feature**:

1. Create schema (`app/schemas/{feature}.py`)
2. Create model (`app/models/{feature}.py`)
3. Create migration (`make migrate-new MSG="Add {feature} table"`)
4. Create router (`app/routes/{feature}.py`)
5. Register router (`app/main.py`)
6. Write tests (`tests/test_{feature}.py`)
7. Update API contract (`docs/api-contract.md`)

**Result**: Complete feature in one pull request

````

---

## Content Boundary Guidance

### What Belongs in Root CLAUDE.md (Monorepo-Wide)

**Purpose**: Cross-project coordination

**Topics**:
- API contract synchronization (Backend → Frontend)
- Type generation workflow (OpenAPI → TypeScript)
- API versioning (major/minor/patch)
- Deployment order (backend first, then frontend)
- Port configuration (service: 15010, UI: 15000)
- Make targets (dev, test, lint, gen-client)
- Guard rails that apply to both projects

**Key Principle**: If it affects BOTH service and UI, it belongs in root CLAUDE.md

---

### What Belongs in Service CLAUDE.md (Service-Specific)

**Purpose**: FastAPI/Python development patterns

**Topics**:
- FastAPI patterns (routers, dependency injection, error handling)
- Pydantic schema patterns (validation, serialization, generic types)
- SQLAlchemy patterns (models, sessions, transactions)
- Alembic migration workflow (autogenerate gotchas, rollback)
- Testing patterns (pytest, FastAPI TestClient, async tests)
- Database session management
- Service-specific guard rails (linting, type checking, migration safety)
- Environment variable configuration
- Vertical slice architecture (service implementation)

**Key Principle**: If it's Python/FastAPI-specific and doesn't affect the UI, it belongs in service CLAUDE.md

---

### Overlap Resolution

**If a topic affects both**:
- **Root CLAUDE.md**: High-level coordination (e.g., "Backend must be deployed first")
- **Service CLAUDE.md**: Implementation details (e.g., "How to add a new endpoint")

**Example**:
- **Root**: "Update contract, then backend, then frontend"
- **Service**: "Add Pydantic schema, create router, write tests, update contract"

---

## Specific Recommendations Based on Codebase

### 1. Dependency Injection Patterns

**Found**: `get_db()` generator in `app/db/session.py`

**Recommendation**: Document this pattern and show how to create additional dependencies:

```python
# For current user (when auth implemented)
def get_current_user() -> User:
    # JWT validation logic
    pass

# For service dependencies
def get_vector_search() -> VectorSearch:
    # Initialize vector search
    pass
````

---

### 2. Lazy Initialization Pattern

**Found**: `get_engine()` and `get_session_local()` use lazy initialization

**Recommendation**: Explain why this pattern is used:

- Avoids circular imports
- Delays database connection until needed
- Allows settings to be loaded first

---

### 3. SQLAlchemy Model Pattern

**Found**: `Session` model uses UUIDs, timestamps, JSON columns

**Recommendation**: Document standard model template:

- UUID primary keys
- Timestamps (created_at, updated_at)
- Nullable fields explicit
- JSON for flexible metadata
- `__repr__` for debugging

---

### 4. Git SHA Helper

**Found**: `get_git_sha()` with fallback to "unknown"

**Recommendation**: Document defensive utility pattern:

- Try operation
- Catch specific exceptions
- Return safe fallback
- Never crash on missing git

---

### 5. Testing with TestClient

**Found**: `conftest.py` has `client` fixture

**Recommendation**: Show how to extend fixtures:

```python
@pytest.fixture
def auth_client(client):
    """Client with authentication headers."""
    client.headers = {"Authorization": "Bearer test-token"}
    return client

@pytest.fixture
def test_db():
    """In-memory database for testing."""
    # Setup test database
    yield db
    # Teardown
```

---

### 6. Environment Variable Configuration

**Found**: Pydantic Settings with `.env` file

**Recommendation**: Document configuration patterns:

- Required vs optional variables
- Default values
- Type conversion (int, bool, list)
- Validation

---

### 7. Router Organization

**Found**: Separate routers for health and API endpoints

**Recommendation**: Document router grouping strategy:

- `/health` - No prefix, no auth
- `/api/v1/*` - Versioned, auth required (when implemented)
- Tags for OpenAPI grouping

---

### 8. Pydantic Generic Types

**Found**: `PaginatedResponse[T]` and `ErrorResponse`

**Recommendation**: Show how to create and use generic types:

```python
# Define once
class PaginatedResponse(BaseModel, Generic[T]):
    data: List[T]
    pagination: dict

# Reuse everywhere
@router.get("/items", response_model=PaginatedResponse[ItemResponse])
async def list_items():
    ...
```

---

## Migration Strategy

### Current State

- Service has `docs/CLAUDE.md` (basic development guide)
- Service lacks root `research-mind-service/CLAUDE.md`

### Recommended Approach

**Option 1: Move + Enhance** (Recommended)

1. Move `docs/CLAUDE.md` to `research-mind-service/CLAUDE.md`
2. Expand with missing sections (FastAPI patterns, SQLAlchemy, testing, etc.)
3. Keep `docs/` for API contract only

**Option 2: Create New + Deprecate**

1. Create new `research-mind-service/CLAUDE.md` with comprehensive content
2. Add deprecation notice to `docs/CLAUDE.md`:
   ```markdown
   > **DEPRECATED**: This file has moved to `/Users/mac/workspace/research-mind/research-mind-service/CLAUDE.md`
   ```

**Option 3: Keep Both** (Not Recommended)

- Confusing to have two CLAUDE.md files
- Risk of divergence

---

## Proposed File Structure

```
research-mind/
├── CLAUDE.md                              # Monorepo coordination
├── research-mind-service/
│   ├── CLAUDE.md                          # Service development guide (NEW)
│   ├── docs/
│   │   ├── api-contract.md                # API contract (keep)
│   │   └── CLAUDE.md                      # DEPRECATED or REMOVED
│   └── ...
└── research-mind-ui/
    ├── CLAUDE.md                          # KuzuMemory config (keep as-is)
    └── ...
```

---

## API Contract Workflow (Concise Version for Both Service and UI)

Both service and UI CLAUDE.md files must contain the **complete end-to-end workflow**. Below is the concise version that should appear in both files (customized per perspective).

### Service CLAUDE.md Version

````markdown
## API Contract Workflow

**Golden Rule**: Contract is frozen. Changes require version bump and UI sync.

**Service Responsibilities**:

1. Update contract FIRST in `docs/api-contract.md`
2. Implement backend changes
3. Copy contract to UI

**Step-by-Step**:

1. **Edit Contract** (`docs/api-contract.md`):

   - Add/modify endpoints, schemas, error codes
   - Version bump (major/minor/patch)
   - Add changelog entry

2. **Update Backend**:

   - Pydantic schemas: `app/schemas/`
   - Routes: `app/routes/`
   - Tests: `tests/`

3. **Run Tests**: `uv run pytest` (must pass)

4. **Copy Contract to UI**:
   ```bash
   cp docs/api-contract.md ../research-mind-ui/docs/api-contract.md
   ```
````

5. **Notify UI Team**: Contract updated, ready for type generation

**Contract Locations**:

- Service (source of truth): `research-mind-service/docs/api-contract.md`
- UI (copy): `research-mind-ui/docs/api-contract.md`
- Files must be identical

**Version Bumping**:

- Major (1.0.0 → 2.0.0): Breaking changes
- Minor (1.0.0 → 1.1.0): New endpoints or optional fields
- Patch (1.0.0 → 1.0.1): Bug fixes

See `docs/api-contract.md` for full contract specification.

````

### UI CLAUDE.md Version

```markdown
## API Contract Workflow

**Golden Rule**: Contract is frozen. UI receives updates from service.

**UI Responsibilities**:
1. Verify contract copied from service
2. Regenerate TypeScript types
3. Update UI code

**Step-by-Step**:

1. **Verify Contract Updated**:
   - Check `docs/api-contract.md` for changes
   - Verify identical to service version:
     ```bash
     diff docs/api-contract.md ../research-mind-service/docs/api-contract.md
     # Should show no differences
     ```

2. **Ensure Service Running**:
   ```bash
   curl http://localhost:15010/health
   # Service must be up for type generation
````

3. **Regenerate Types**:

   ```bash
   npm run gen:api
   # Generates src/lib/api/generated.ts from OpenAPI
   ```

4. **Update API Client** (`src/lib/api/client.ts`):

   ```typescript
   import type { NewEndpointResponse } from "./generated";

   export const apiClient = {
     async newEndpoint(): Promise<NewEndpointResponse> {
       const response = await fetch(`${baseUrl}/api/v1/new-endpoint`);
       return response.json();
     },
   };
   ```

5. **Create Query Hook** (`src/lib/api/hooks.ts`):

   ```typescript
   export function useNewEndpointQuery() {
     return createQuery({
       queryKey: ["newEndpoint"],
       queryFn: () => apiClient.newEndpoint(),
     });
   }
   ```

6. **Update Components**: Use new types and hooks

7. **Run Tests**: `npm test` (must pass)

**Generated Types**:

- File: `src/lib/api/generated.ts`
- Auto-generated from backend OpenAPI schema
- NEVER edit manually

**Contract Locations**:

- Service (source): `research-mind-service/docs/api-contract.md`
- UI (copy): `research-mind-ui/docs/api-contract.md`
- Files must be identical

See `docs/api-contract.md` for full contract specification.

````

---

## Migration Plan

### Current State → Recommended State

**Step 1: Create New UI CLAUDE.md**

1. **Backup current UI CLAUDE.md**:
   ```bash
   mv research-mind-ui/CLAUDE.md research-mind-ui/CLAUDE.md.kuzu-backup
````

2. **Create new comprehensive UI CLAUDE.md**:

   - Use template from Part 3 above
   - Include all 11 sections
   - Add API contract workflow (UI perspective)
   - Include actual patterns from codebase

3. **Optional: Keep KuzuMemory content**:
   - Move KuzuMemory section to bottom as appendix
   - Or create separate `KUZU_MEMORY.md` file

**Step 2: Enhance Service CLAUDE.md**

1. **Move service CLAUDE.md to root**:

   ```bash
   mv research-mind-service/docs/CLAUDE.md research-mind-service/CLAUDE.md
   ```

2. **Enhance with missing sections**:

   - Add API contract workflow (service perspective)
   - Add all patterns from existing recommendations document
   - Expand testing, Pydantic, SQLAlchemy sections

3. **Add deprecation notice to old location** (optional):
   ```bash
   echo "> **MOVED**: This file has moved to /Users/mac/workspace/research-mind/research-mind-service/CLAUDE.md" > research-mind-service/docs/CLAUDE.md
   ```

**Step 3: Trim Root CLAUDE.md**

1. **Remove project-specific details**:

   - FastAPI implementation examples
   - Pydantic schema details
   - OpenAPI generation internals
   - TypeScript type generation internals

2. **Keep only coordination topics**:

   - High-level workflow summary
   - Deployment order
   - Port configuration
   - Cross-project guard rails
   - Make targets

3. **Add references to sub-project CLAUDE.md files**:

   ```markdown
   For detailed implementation:

   - Service: `research-mind-service/CLAUDE.md`
   - UI: `research-mind-ui/CLAUDE.md`
   ```

**Step 4: Verify Standalone Nature**

Test each CLAUDE.md file for standalone completeness:

1. **Root CLAUDE.md Test**:

   - Can a new developer understand monorepo coordination?
   - Are cross-project workflows clear?
   - No duplicate content with sub-projects?

2. **Service CLAUDE.md Test**:

   - Can a backend developer work without reading root CLAUDE.md?
   - Is API contract workflow complete (service perspective)?
   - All FastAPI/Python patterns documented?

3. **UI CLAUDE.md Test**:
   - Can a frontend developer work without reading root CLAUDE.md?
   - Is API contract workflow complete (UI perspective)?
   - All SvelteKit/Svelte 5 patterns documented?

**Step 5: Update References**

1. **Update README files** to reference correct CLAUDE.md
2. **Update CI/CD** if any scripts reference CLAUDE.md locations
3. **Update onboarding docs** with new CLAUDE.md structure

---

## File Structure (Final State)

```
research-mind/
├── CLAUDE.md                              # Monorepo coordination (TRIMMED)
├── research-mind-service/
│   ├── CLAUDE.md                          # Service guide (MOVED + ENHANCED)
│   ├── docs/
│   │   ├── api-contract.md                # API contract (source of truth)
│   │   └── CLAUDE.md                      # Deprecation notice or removed
│   └── ...
└── research-mind-ui/
    ├── CLAUDE.md                          # UI guide (COMPLETELY NEW)
    ├── CLAUDE.md.kuzu-backup              # Old KuzuMemory config (backup)
    ├── docs/
    │   └── api-contract.md                # API contract (copy from service)
    └── ...
```

---

## Content Boundary Principles

### Root CLAUDE.md Scope

**INCLUDE**:

- Cross-project coordination
- Deployment order (backend → frontend)
- Port configuration (15010, 15000)
- High-level API contract workflow
- Monorepo-level make targets
- Cross-project guard rails

**EXCLUDE**:

- Framework-specific patterns (FastAPI, SvelteKit)
- Implementation details (Pydantic, Svelte runes)
- Language-specific tooling (pytest, Vitest)
- Database patterns (SQLAlchemy)
- Component patterns (Svelte components)

**Key Question**: "Does this affect BOTH service and UI?" → Root CLAUDE.md. Otherwise → Sub-project CLAUDE.md.

---

### Service CLAUDE.md Scope

**INCLUDE**:

- Complete API contract workflow (service perspective)
- All FastAPI patterns
- All Python/Pydantic/SQLAlchemy patterns
- Pytest testing patterns
- Alembic migration workflow
- Service-specific guard rails
- Environment configuration
- OpenAPI customization

**EXCLUDE**:

- UI-specific patterns
- TypeScript/SvelteKit details
- Frontend testing

**Key Question**: "Does a backend developer need this?" → Service CLAUDE.md.

---

### UI CLAUDE.md Scope

**INCLUDE**:

- Complete API contract workflow (UI perspective)
- All SvelteKit patterns
- All Svelte 5 runes patterns
- TanStack Query patterns
- Type generation workflow
- API client patterns
- Vitest testing patterns
- UI-specific guard rails

**EXCLUDE**:

- Backend implementation details
- FastAPI patterns
- Database patterns

**Key Question**: "Does a frontend developer need this?" → UI CLAUDE.md.

---

## Overlap Resolution Strategy

When a topic affects both projects:

1. **Root CLAUDE.md**: High-level coordination ("what" and "why")
2. **Service CLAUDE.md**: Implementation details (service side)
3. **UI CLAUDE.md**: Implementation details (UI side)

**Example: API Contract Workflow**

- **Root**: "Contract updated → backend deployed → UI types regenerated"
- **Service**: "Edit `docs/api-contract.md`, update Pydantic schemas, run tests, copy to UI"
- **UI**: "Verify contract copied, run `npm run gen:api`, update client, run tests"

---

## Summary of Recommendations

### Three Standalone CLAUDE.md Files

**1. Root CLAUDE.md** (`/Users/mac/workspace/research-mind/CLAUDE.md`)

- **Purpose**: Monorepo coordination only
- **Action**: TRIM — Remove project-specific details
- **Sections**: Quick start, project structure, API contract (high-level), deployment order, guard rails
- **Standalone**: Yes — Covers cross-project coordination

**2. Service CLAUDE.md** (`research-mind-service/CLAUDE.md`)

- **Purpose**: Complete backend development guide
- **Action**: MOVE + ENHANCE — Move from `docs/CLAUDE.md` and expand
- **Sections**: Quick start, project structure, API contract workflow (service perspective), FastAPI patterns, SQLAlchemy, testing, Pydantic, guard rails, environment, vertical slices
- **Standalone**: Yes — No dependency on root CLAUDE.md

**3. UI CLAUDE.md** (`research-mind-ui/CLAUDE.md`)

- **Purpose**: Complete frontend development guide
- **Action**: COMPLETELY REWRITE — Replace KuzuMemory config
- **Sections**: Quick start, project structure, API contract workflow (UI perspective), SvelteKit patterns, Svelte 5 runes, TanStack Query, API client, testing, tooling, styling, guard rails
- **Standalone**: Yes — No dependency on root CLAUDE.md

### Critical Requirements

**API Contract Workflow**:

- ✅ MUST appear in BOTH service and UI CLAUDE.md files
- ✅ Complete end-to-end workflow in each (different perspectives)
- ✅ Reference `docs/api-contract.md` for details
- ✅ Concise but comprehensive

**Standalone Requirement**:

- ✅ Each sub-project CLAUDE.md must be fully standalone
- ✅ Developers working in service/UI should not need root CLAUDE.md
- ✅ No circular dependencies between files

**Content Boundaries**:

- Root: ONLY coordination, NO implementation details
- Service: ALL backend patterns, complete workflow
- UI: ALL frontend patterns, complete workflow

### Migration Checklist

- [ ] Backup current UI CLAUDE.md (KuzuMemory config)
- [ ] Create new comprehensive UI CLAUDE.md with 11 sections
- [ ] Move service CLAUDE.md from `docs/` to root
- [ ] Enhance service CLAUDE.md with missing sections
- [ ] Add API contract workflow to service CLAUDE.md
- [ ] Add API contract workflow to UI CLAUDE.md
- [ ] Trim root CLAUDE.md to coordination only
- [ ] Add references to sub-project CLAUDE.md files in root
- [ ] Verify standalone nature of all three files
- [ ] Update README and onboarding docs
- [ ] Optional: Deprecation notice in old service docs/CLAUDE.md location

### Expected Outcomes

**For Monorepo-Level Work**:

- Developers consult root CLAUDE.md for coordination
- Clear understanding of deployment order and cross-project rules
- No duplicate content with sub-projects

**For Backend Work**:

- Developers consult service CLAUDE.md only
- Complete guidance on FastAPI, SQLAlchemy, testing, etc.
- API contract workflow clear (service perspective)

**For Frontend Work**:

- Developers consult UI CLAUDE.md only
- Complete guidance on SvelteKit, Svelte 5, TanStack Query, etc.
- API contract workflow clear (UI perspective)

**For All Contexts**:

- No confusion about where to find information
- No duplication or conflicting advice
- Each file is comprehensive and standalone

---

## Appendix: Draft UI CLAUDE.md Content (Major Sections)

Since the UI CLAUDE.md requires the most significant enhancement, below are draft sections with actual patterns discovered in the codebase.

### Section: SvelteKit Patterns

```markdown
## SvelteKit Patterns

### File-Based Routing

SvelteKit uses file-based routing:

**Directory Structure**:
```

src/routes/
├── +layout.svelte # Root layout (applies to all routes)
├── +page.svelte # Home page (/)
├── about/
│ └── +page.svelte # About page (/about)
└── sessions/
├── +page.svelte # Sessions list (/sessions)
└── [id]/
└── +page.svelte # Session detail (/sessions/:id)

````

**Route Patterns**:
- `+page.svelte` - Page component
- `+layout.svelte` - Layout wrapper
- `+page.ts` - Client-side data loading
- `+page.server.ts` - Server-side data loading
- `[param]` - Dynamic route parameter

### Root Layout Pattern

**File**: `src/routes/+layout.svelte`

```svelte
<script lang="ts">
  import './app.css'; // Import global styles
</script>

<main>
  <slot /> <!-- Nested route content -->
</main>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
  }
</style>
````

**Rules**:

- Import global CSS in root layout
- Use `<slot />` for nested content
- Use `:global()` for global style overrides

### Page Component Pattern

**File**: `src/routes/+page.svelte`

```svelte
<script lang="ts">
  import { getApiBaseUrl } from '$lib/utils/env';

  const apiBaseUrl = getApiBaseUrl();

  let loading = $state(true);
  let data = $state<string | null>(null);

  $effect(() => {
    const fetchData = async () => {
      // Runs on mount
      const response = await fetch(`${apiBaseUrl}/api/v1/data`);
      data = await response.json();
      loading = false;
    };
    fetchData();
  });
</script>

<div>
  {#if loading}
    <p>Loading...</p>
  {:else}
    <p>{data}</p>
  {/if}
</div>
```

**Key Points**:

- Use `$state` for reactive local state
- Use `$effect` for side effects (API calls, subscriptions)
- Import utilities from `$lib/*` (alias for `src/lib/`)

````

---

### Section: Svelte 5 Runes

```markdown
## Svelte 5 Runes

Svelte 5 introduces runes (compiler hints) to replace reactive declarations.

### $state - Reactive State

**Before (Svelte 4)**:
```svelte
<script>
  let count = 0;
  $: doubled = count * 2; // Reactive declaration
</script>
````

**After (Svelte 5)**:

```svelte
<script lang="ts">
  let count = $state(0);
  let doubled = $derived(count * 2);
</script>

<button onclick={() => count++}>
  Count: {count}, Doubled: {doubled}
</button>
```

**Rules**:

- Use `$state()` for reactive local state
- Initial value required: `$state(initialValue)`
- Works with primitives, objects, arrays

---

### $derived - Computed Values

```svelte
<script lang="ts">
  let firstName = $state('John');
  let lastName = $state('Doe');
  let fullName = $derived(`${firstName} ${lastName}`);
</script>

<p>{fullName}</p> <!-- Automatically updates -->
```

**Rules**:

- Automatically recomputes when dependencies change
- Read-only (cannot be reassigned)
- Use for computed values, filtered lists, derived state

---

### $effect - Side Effects

**Purpose**: Run side effects when dependencies change

```svelte
<script lang="ts">
  import { getApiBaseUrl } from '$lib/utils/env';

  const apiBaseUrl = getApiBaseUrl();
  let sessionId = $state<string | null>(null);

  $effect(() => {
    if (sessionId) {
      const fetchSession = async () => {
        const response = await fetch(`${apiBaseUrl}/api/v1/sessions/${sessionId}`);
        console.log(await response.json());
      };
      fetchSession();
    }
  });
</script>
```

**Rules**:

- Runs after component mounts and when dependencies change
- Use for API calls, subscriptions, DOM manipulation
- Clean up with return function:
  ```svelte
  $effect(() => {
    const interval = setInterval(() => console.log('tick'), 1000);
    return () => clearInterval(interval); // Cleanup
  });
  ```

---

### $props - Component Props

**Before (Svelte 4)**:

```svelte
<script>
  export let name;
  export let age = 0; // Default value
</script>
```

**After (Svelte 5)**:

```svelte
<script lang="ts">
  interface Props {
    name: string;
    age?: number;
  }

  let { name, age = 0 }: Props = $props();
</script>

<p>{name} is {age} years old</p>
```

**Rules**:

- Define Props interface for type safety
- Destructure props: `let { prop1, prop2 } = $props()`
- Use default values: `let { prop = defaultValue } = $props()`
- Props are read-only

**Example with Query State**:

```svelte
<!-- ApiStatus.svelte -->
<script lang="ts">
  interface QueryState {
    isPending: boolean;
    isError: boolean;
    data?: any;
    error?: Error | null;
  }

  let { query }: { query: QueryState } = $props();
</script>

<div>
  {#if query.isPending}
    <p>Loading...</p>
  {:else if query.isError}
    <p>Error: {query.error?.message}</p>
  {:else if query.data}
    <pre>{JSON.stringify(query.data, null, 2)}</pre>
  {/if}
</div>
```

**Usage**:

```svelte
<script lang="ts">
  import ApiStatus from '$lib/components/ApiStatus.svelte';
  import { useVersionQuery } from '$lib/api/hooks';

  const versionQuery = useVersionQuery();
</script>

<ApiStatus query={$versionQuery} />
```

````

---

### Section: TanStack Query Integration

```markdown
## TanStack Query (@tanstack/svelte-query)

TanStack Query provides data fetching, caching, and state management.

### Query Hooks Pattern

**File**: `src/lib/api/hooks.ts`

```typescript
import { createQuery, createMutation } from '@tanstack/svelte-query';
import { apiClient, type VersionResponse, type Session } from './client';

// Query hook (GET request)
export function useVersionQuery() {
  return createQuery<VersionResponse>({
    queryKey: ['version'],
    queryFn: () => apiClient.getVersion(),
    staleTime: 60000, // 1 minute
    gcTime: 300000, // 5 minutes (garbage collection time)
  });
}

// Query with parameter
export function useSessionQuery(sessionId: string) {
  return createQuery<Session>({
    queryKey: ['session', sessionId],
    queryFn: () => apiClient.getSession(sessionId),
    enabled: !!sessionId, // Only run if sessionId exists
  });
}

// Mutation hook (POST/PATCH/DELETE)
export function useCreateSessionMutation() {
  return createMutation({
    mutationFn: (data: { name: string; description?: string }) =>
      apiClient.createSession(data),
    onSuccess: () => {
      // Invalidate sessions list to refetch
      queryClient.invalidateQueries({ queryKey: ['sessions'] });
    },
  });
}
````

### Using Queries in Components

```svelte
<script lang="ts">
  import { useVersionQuery } from '$lib/api/hooks';

  const query = useVersionQuery();
</script>

{#if $query.isPending}
  <p>Loading...</p>
{:else if $query.isError}
  <p>Error: {$query.error.message}</p>
{:else if $query.data}
  <div>
    <p>Version: {$query.data.version}</p>
    <p>Environment: {$query.data.environment}</p>
  </div>
{/if}
```

**Key Points**:

- Subscribe to query with `$query` (Svelte store syntax)
- Query automatically refetches on mount, focus, reconnect
- `staleTime` - How long data is considered fresh
- `gcTime` - How long to keep unused data in cache

### Using Mutations in Components

```svelte
<script lang="ts">
  import { useCreateSessionMutation } from '$lib/api/hooks';

  const createSession = useCreateSessionMutation();

  let name = $state('');
  let description = $state('');

  async function handleSubmit() {
    $createSession.mutate({ name, description });
  }
</script>

<form onsubmit|preventDefault={handleSubmit}>
  <input bind:value={name} placeholder="Session name" />
  <textarea bind:value={description} placeholder="Description" />
  <button type="submit" disabled={$createSession.isPending}>
    {$createSession.isPending ? 'Creating...' : 'Create Session'}
  </button>

  {#if $createSession.isError}
    <p class="error">{$createSession.error.message}</p>
  {/if}

  {#if $createSession.isSuccess}
    <p class="success">Session created!</p>
  {/if}
</form>
```

### Query Configuration Best Practices

**Cache Times**:

```typescript
staleTime: 60000,    // 1 minute - Data is fresh
gcTime: 300000,      // 5 minutes - Keep in cache
```

**Refetch Strategies**:

```typescript
refetchOnWindowFocus: true,  // Refetch on window focus
refetchOnReconnect: true,    // Refetch on network reconnect
refetchInterval: 30000,      // Poll every 30 seconds
```

**Error Handling**:

```typescript
retry: 3,              // Retry failed requests 3 times
retryDelay: 1000,      // Wait 1 second between retries
```

````

---

### Section: API Client Patterns

```markdown
## API Client Patterns

### Client Structure

**File**: `src/lib/api/client.ts`

```typescript
import { z } from 'zod';

// Environment configuration
const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || 'http://localhost:15010';

// Zod schemas for runtime validation
const VersionResponseSchema = z.object({
  version: z.string(),
  environment: z.string().optional(),
  timestamp: z.string().optional(),
});

const SessionSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  status: z.enum(['active', 'archived']),
  created_at: z.string(),
  updated_at: z.string(),
});

// Type inference from schemas
export type VersionResponse = z.infer<typeof VersionResponseSchema>;
export type Session = z.infer<typeof SessionSchema>;

// API Client
export const apiClient = {
  // GET request
  async getVersion(): Promise<VersionResponse> {
    const response = await fetch(`${apiBaseUrl}/api/v1/version`);
    if (!response.ok) {
      throw new Error(`Failed to fetch version: ${response.statusText}`);
    }
    const data = await response.json();
    return VersionResponseSchema.parse(data); // Runtime validation
  },

  // GET with parameter
  async getSession(id: string): Promise<Session> {
    const response = await fetch(`${apiBaseUrl}/api/v1/sessions/${id}`);
    if (!response.ok) {
      throw new Error(`Failed to fetch session: ${response.statusText}`);
    }
    const data = await response.json();
    return SessionSchema.parse(data);
  },

  // POST request
  async createSession(data: { name: string; description?: string }): Promise<Session> {
    const response = await fetch(`${apiBaseUrl}/api/v1/sessions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!response.ok) {
      throw new Error(`Failed to create session: ${response.statusText}`);
    }
    const result = await response.json();
    return SessionSchema.parse(result);
  },

  // DELETE request
  async deleteSession(id: string): Promise<void> {
    const response = await fetch(`${apiBaseUrl}/api/v1/sessions/${id}`, {
      method: 'DELETE',
    });
    if (!response.ok) {
      throw new Error(`Failed to delete session: ${response.statusText}`);
    }
  },
};
````

### Why Zod for Validation?

**Runtime Safety**: TypeScript types are erased at runtime. Zod provides runtime validation:

```typescript
// TypeScript type (compile-time only)
type User = { name: string };

// Zod schema (runtime validation)
const UserSchema = z.object({ name: z.string() });
type User = z.infer<typeof UserSchema>; // TypeScript type from schema

// API response validation
const data = await response.json();
const user = UserSchema.parse(data); // Throws if invalid
```

**Benefits**:

- Catch API contract mismatches at runtime
- Validate external data (API responses, user input)
- Single source of truth for types and validation

```

This comprehensive appendix provides detailed, codebase-specific guidance for the UI CLAUDE.md enhancement.
```
