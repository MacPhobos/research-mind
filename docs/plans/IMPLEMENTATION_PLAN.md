# Research-Mind Implementation Plan

> **REFERENCE ONLY** - This plan has been superseded by individual phase documents in `docs/plans/`.
> See `IMPLEMENTATION_ROADMAP.md` for the current master index and timeline.
>
> **CRITICAL ARCHITECTURE UPDATE (2026-02-01)**: mcp-vector-search is integrated as a
> **subprocess** spawned by research-mind-service, NOT as an embedded Python library.
> The original plan below assumed library embedding, which is incorrect.
> See `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0) for the definitive
> subprocess-based integration approach.

**Last Updated**: 2026-02-01
**Status**: REFERENCE ONLY - See individual phase plans for current approach
**Timeline**: 12 weeks to production (MVP in 15-21 days with Phase 1.0 setup)
**Revision**: Updated with subprocess-based architecture note. Original library embedding assumptions preserved below for historical reference.

## Executive Summary

**Project**: Research-Mind - Session-scoped agentic research system combining semantic code search (mcp-vector-search) with Claude agent analysis (claude-ppm)

**Objectives**:

- Build minimal end-to-end research loop: create session → index content → search → analyze with agent
- Achieve 90%+ search precision by Phase 2
- Reduce inference costs by 60-70% through caching and warm pools
- Production deployment with 10x throughput capability by Phase 4

**Key Metrics**:

- **Baseline Latency**: 7-13 seconds (agent + search)
- **Target Latency**: 3-5 seconds by Phase 3
- **Cost per Query**: $0.05 (40-50% reduction from baseline)
- **Search Quality**: 95%+ precision
- **Availability**: 99%+ uptime

**Team**: 2-2.5 FTE engineers
**Estimated Cost Savings**: 60-70% vs. baseline through caching + warm pools

**CRITICAL UPDATE - Timeline Revised**:

- **Original Phase 1 estimate**: 10-12 days (OPTIMISTIC)
- **Revised Phase 1.0 (Pre-Phase)**: 2-3 days (mcp-vector-search setup + verification)
- **Revised Phase 1.1-1.8**: 12-16 days (realistic with dependencies)
- **Total to MVP**: 15-21 calendar days (more realistic, lower risk)
- **See docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md for details**

---

## Phase 1: Foundation (Weeks 1-3) - MVP CORE RESEARCH LOOP

### Objective

Build minimal end-to-end flow: create session → index content → search → analyze with agent

### Critical Dependencies

> **UPDATED**: mcp-vector-search is a CLI tool invoked as a subprocess, not an embedded library.
> See `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0) for correct integration.

- mcp-vector-search CLI (installed via pip, invoked as subprocess via `subprocess.run()`)
- claude-ppm installation (requires Claude CLI v2.1.3+)
- FastAPI service scaffold
- SQLite for session storage
- ChromaDB (used internally by mcp-vector-search subprocess, not managed by service)

---

## Phase 1.0: Pre-Phase Environment Setup (2-3 Days) - **CRITICAL**

**IMPORTANT**: Phase 1.0 is a pre-phase task that MUST complete before Phase 1.1 begins. The original 10-12 day estimate was optimistic and didn't account for mcp-vector-search setup complexity. Phase 1.0 de-risks Phase 1.1-1.8 by validating environment and dependencies upfront.

**Objective**: Verify mcp-vector-search is properly installed, configured, and tested. Establish baseline environment documentation.

**See Also**: Complete Phase 1.0 guide at `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (3,600+ lines)

### Tasks (2-3 Days Total)

**1.0.1: Environment Prerequisites** (30 min)

- Verify Python 3.12+ installed
- Create/verify virtual environment
- Check 3GB+ disk space available

**1.0.2: Install mcp-vector-search** (2-4 hours) - CRITICAL BLOCKER

- Add mcp-vector-search to pyproject.toml with pinned version
- Run `uv sync` to install ~2.5GB of dependencies
- Verify imports: `from mcp_vector_search import Client`
- Verify transitive deps: transformers, torch, chromadb, sentence_transformers

**1.0.3: Verify PostgreSQL** (1-2 hours)

- Start PostgreSQL service
- Test database connection
- Run Alembic migrations (`alembic upgrade head`)
- Verify tables exist (sessions, audit_logs)

**1.0.4: Create Sandbox Directory** (1 hour)

- Create `research-mind-service/app/sandbox/` directory
- Create `__init__.py` for Python module

**1.0.5: Test Model Caching** (1-2 hours) - Proof of Concept

- Set HuggingFace cache environment variables
- Download embedding model (all-MiniLM-L6-v2, ~400MB)
- First run: 2-3 minutes (one-time)
- Verify second run uses cache: <1 second
- Document performance baseline

**1.0.6: Session Model Stub** (1-2 hours)

- Create `app/models/session.py` stub (will be completed in Phase 1.2)

**1.0.7: Verify Docker** (1 hour)

- Check Docker and docker-compose installed
- Validate `docker-compose.yml` configuration

**1.0.8: Document Baseline** (2-4 hours)

- Create `.env.example` template
- Create `docs/PHASE_1_0_BASELINE.md` documenting:
  - System environment (Python version, OS, disk space)
  - Package versions
  - Performance baselines
  - Known issues discovered
  - Risk assessments

### Critical Integration Patterns Established in Phase 1.0

> **UPDATED**: Patterns revised for subprocess-based architecture.

**Pattern 1: WorkspaceIndexer Subprocess Manager**

- Spawn mcp-vector-search CLI subprocess per workspace
- Use `subprocess.run()` with `cwd` parameter for workspace targeting
- Foundation for Phase 1.1 implementation

**Pattern 2: Per-Workspace Index Isolation**

- Each workspace gets independent `.mcp-vector-search/` directory
- No shared state between workspaces
- Verified in Phase 1.0 subprocess invocation testing

**Pattern 3: Subprocess Model Caching**

- Embedding model cached internally by mcp-vector-search
- First `init` downloads model (~250-500 MB)
- Subsequent inits reuse cached model

### Phase 1.0 Success Criteria

- ✅ mcp-vector-search installed and imports working
- ✅ Model download completes (2-3 min first run)
- ✅ PostgreSQL connected and migrations applied
- ✅ Sandbox directory structure created
- ✅ Docker/docker-compose verified
- ✅ Baseline environment documented
- ✅ Known issues and mitigations captured
- ✅ Team consensus on Phase 1.0 findings and risks

### Phase 1.0 Artifacts

1. Updated `pyproject.toml` with mcp-vector-search dependency
2. `.env.example` template with all required variables
3. `docs/PHASE_1_0_BASELINE.md` - environment documentation
4. `scripts/verify-phase-1-0.sh` - automated verification script
5. Troubleshooting guide for 5 common installation issues

### Risk Mitigations Established in Phase 1.0

> **UPDATED**: Risk mitigations revised for subprocess-based architecture.

- ✅ Subprocess invocation verified (init + index via subprocess.run())
- ✅ Multi-workspace parallel indexing safe (independent .mcp-vector-search/ dirs)
- ✅ Environment setup documented (prevent Phase 1.1 surprises)
- ✅ Installation issues discovered and mitigated
- ✅ Realistic timeline adjustments made (10-12 → 15-21 days)

---

### 1.1: Service Architecture Setup (5-6 days) - REVISED UP FROM 3-4

**Note**: Phase 1.0 pre-phase has already:

- ✅ Installed mcp-vector-search library (~2.5GB)
- ✅ Verified all dependencies
- ✅ Created pyproject.toml with mcp-vector-search
- ✅ Created .env.example
- ✅ Created app/sandbox/ directory

**Phase 1.1 builds on Phase 1.0 foundation.**

**Deliverable**: FastAPI service scaffold with proper project structure and mcp-vector-search integration

**Tasks**:

1. Create FastAPI service skeleton at `research-mind-service/`
2. Set up project structure:
   - `app/main.py` - FastAPI entry point with startup/shutdown hooks
   - `app/core/vector_search.py` - VectorSearchManager singleton (lazy-load model)
   - `app/routes/` - API endpoints
   - `app/services/` - Business logic
   - `app/schemas/` - Pydantic models
   - `app/models/` - Database models
   - `app/sandbox/` - Security/isolation (directory already exists from Phase 1.0)
   - `tests/` - Test suite
3. Implement VectorSearchManager singleton for mcp-vector-search:
   - Load embedding model once per startup (~30s, then cached)
   - Provide per-session SessionIndexer wrapper
   - Environment-based configuration (cache dirs, model name, device)
4. Integrate with FastAPI startup/shutdown hooks
5. Update Dockerfile for multi-stage build with mcp-vector-search

**Critical Files to Create**:

- `research-mind-service/app/main.py` - FastAPI app with VectorSearchManager initialization
- `research-mind-service/app/core/vector_search.py` - VectorSearchManager singleton (see MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md Section 4 for template)
- `research-mind-service/app/core/config.py` - Pydantic Settings for environment loading

**Success Criteria**:

- ✅ Service starts on port 15010
- ✅ GET /api/health returns `{"status": "healthy"}`
- ✅ VectorSearchManager singleton initializes on startup
- ✅ Embedding model loads successfully (30s on first run, then cached)
- ✅ All environment variables configurable via .env
- ✅ Docker image builds successfully with mcp-vector-search

---

### 1.2: Session Management (3-4 days)

**Deliverable**: Session CRUD endpoints with persistent storage

**Tasks**:

1. Design session data model:

   - `session_id` (UUID v4)
   - `name`, `description`
   - `workspace_path` (/var/lib/research-mind/sessions/{session_id})
   - `created_at`, `last_accessed`, `status`
   - `index_stats` (chunk count, file count, etc.)

2. Implement session CRUD endpoints:

   - `POST /api/sessions` - Create session
   - `GET /api/sessions/{session_id}` - Get session details
   - `DELETE /api/sessions/{session_id}` - Delete session
   - `GET /api/sessions` - List sessions

3. Create SQLite schema for session tracking

4. Implement workspace directory setup:
   - Create `/var/lib/research-mind/sessions/{session_id}/`
   - Create `.mcp-vector-search/` config directory
   - Initialize session metadata

**Critical Files to Create**:

- `research-mind-service/app/models/session.py` - SQLAlchemy session model
- `research-mind-service/app/routes/sessions.py` - session CRUD endpoints
- `research-mind-service/app/schemas/session.py` - Pydantic schemas

**Success Criteria**:

- ✅ Can create session with POST /api/sessions
- ✅ Session directory created on disk
- ✅ Session retrievable with GET /api/sessions/{session_id}
- ✅ Session deletion cleans up workspace
- ✅ Multiple sessions can coexist independently

---

### 1.3: Vector Search REST API (Wrapper) (5-6 days) - REVISED UP FROM 4-5

**Deliverable**: REST interface to mcp-vector-search with per-session indexing and search

**Note**: Phase 1.0 has already proven:

- ✅ mcp-vector-search library is installable and working
- ✅ ChromaDB concurrent write safety (tested with multiple collections)
- ✅ Model caching via environment variables works
- ✅ Session-scoped collection approach is sound

**Phase 1.3 extends this foundation with REST API layer.**

**Tasks**:

1. Create SessionIndexer wrapper (see MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md Section 4):

   - **DO NOT** re-implement indexing (use mcp-vector-search's SemanticIndexer directly)
   - **DO NOT** build custom job queue (mcp-vector-search provides it)
   - Create thin wrapper that manages session scoping + provides REST interface
   - Use global VectorSearchManager singleton (initialized in Phase 1.1)
   - Per-session collection naming: `session_{session_id}`

2. Implement indexing endpoints:

   - `POST /api/sessions/{session_id}/index` - Start indexing job
   - `GET /api/sessions/{session_id}/index/jobs/{job_id}` - Get job status/progress
   - `GET /api/sessions/{session_id}/index/jobs` - List jobs

3. Implement search endpoints:

   - `POST /api/sessions/{session_id}/search` - Semantic search (mandatory session_id)
   - `GET /api/sessions/{session_id}/stats` - Index statistics

4. Per-session collection support:
   - Each session gets dedicated ChromaDB collection: `session_{session_id}`
   - Collections in shared ChromaDB instance (one process-wide db)
   - Session isolation via collection_name parameter (already parameterizable in mcp-vector-search)
   - Concurrent access verified safe in Phase 1.0 testing

**Architecture Pattern** (from MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md):

```python
from app.core.vector_search import VectorSearchManager

class SessionIndexer:
    def __init__(self, session_id: str, session_root: Path):
        self.session_id = session_id
        self.collection_name = f"session_{session_id}"
        self._vs_manager = VectorSearchManager()  # Singleton

    async def index_directory(self, path: Path) -> dict:
        # Delegate to mcp-vector-search with session scoping
        result = await self._vs_manager.indexer.index_directory(
            path=path,
            session_id=self.session_id,
            collection_name=self.collection_name
        )
        return {"status": "success", "job_id": result.get("job_id")}

    async def search(self, query: str, limit: int = 10) -> dict:
        # Delegate to mcp-vector-search with session scoping
        results = await self._vs_manager.search_engine.search(
            query=query,
            collection_name=self.collection_name,
            top_k=limit
        )
        return {"results": results, "count": len(results)}
```

**Critical Files to Create**:

- `research-mind-service/app/core/session_indexer.py` - SessionIndexer wrapper (use template from MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md Section 4)
- `research-mind-service/app/routes/vector_search.py` - REST endpoints
- `research-mind-service/app/schemas/vector_search.py` - Pydantic request/response models

**Success Criteria**:

- ✅ Can start indexing with POST /api/sessions/{id}/index
- ✅ Job status returned with job_id
- ✅ Can poll job progress with GET /api/sessions/{id}/index/jobs/{job_id}
- ✅ Can search with POST /api/sessions/{id}/search
- ✅ Search results include file_path, line numbers, code_snippet, relevance_score
- ✅ Per-session isolation verified (search only returns results from correct collection)

---

### 1.4: Path Validator (Sandbox Layer 1) (2-3 days)

**Deliverable**: Infrastructure-level path validation preventing directory traversal and unauthorized access

**Tasks**:

1. Implement path validation for claude-ppm isolation:

   - Validate all file paths stay within session workspace
   - Block path traversal attempts (`../../../etc/passwd`)
   - Disallow hidden directories, dotfiles
   - Reject system paths (`/etc`, `/root`, `/home/*/.*`, `.ssh`, `.env` files)

2. Create PathValidator class that enforces allowlist:

   - `validate_path(requested_path)` → bool
   - `safe_read(path)` → str (with validation)
   - `safe_list_dir(path)` → List[str] (with validation)

3. Add middleware to FastAPI that validates session_id on all requests

**Critical Files to Create**:

- `research-mind-service/app/sandbox/path_validator.py` - path validation logic
- `research-mind-service/app/middleware/session_validation.py` - FastAPI middleware

**Success Criteria**:

- ✅ Path traversal attempts blocked and logged
- ✅ Session_id validation on every request
- ✅ Invalid sessions return 404
- ✅ Expired sessions return 410
- ✅ 100% validation on every request path

---

### 1.5: Minimal Audit Logging (2-3 days)

**Deliverable**: Audit trail for all session operations and searches

**Tasks**:

1. Create AuditLog model with minimal fields:

   - `timestamp`, `session_id`, `action` (search, index_start, index_complete)
   - `query` (for searches), `result_count`, `duration_ms`
   - `status` (success/failed), `error` (if failed)

2. Implement logging for:

   - Search queries (query text, result count, latency)
   - Indexing job lifecycle (start, progress updates, completion)
   - Session creation/deletion
   - Failed requests (path traversal, invalid sessions, etc.)

3. Store logs in SQLite (searchable)

**Critical Files to Create**:

- `research-mind-service/app/models/audit_log.py` - audit log schema
- `research-mind-service/app/services/audit_service.py` - logging operations

**Success Criteria**:

- ✅ All search queries logged
- ✅ All indexing jobs logged
- ✅ Audit logs queryable by session_id
- ✅ Failed attempts (blocked paths, invalid sessions) logged as warnings

---

### 1.6: Agent Integration (5-7 days) - REVISED UP FROM 4-5

**Deliverable**: Claude-ppm agent invocation with session scoping

**Tasks**:

1. Create custom "research-analyst" agent for claude-ppm:

   - Deploy to `~/.claude/agents/research-analyst/AGENT.md`
   - Define capabilities: read files, semantic search, synthesize findings
   - Constraints: SESSION_DIR scoping, read-only mode, no network access

2. Implement ResearchSession wrapper:

   - `ask_question(question: str) → findings_with_citations`
   - Calls vector_search REST API (from Phase 1.3)
   - Passes results to claude-ppm agent
   - Parses citations from agent response

3. Create agent invocation endpoint:

   - `POST /api/sessions/{session_id}/analyze`
   - Body: `{"question": str, "agent": str = "research-analyst"}`
   - Returns: `{"answer": str, "evidence": List[citation]}`

4. Subprocess execution with constraints:
   - Pass `SESSION_DIR={session_root}` environment variable
   - Set `cwd={session_root}` for subprocess
   - Disable network (environment variable blocking)
   - Timeout per task (5 minutes)

**Critical Files to Create**:

- `research-mind-service/app/services/agent_runner.py` - agent execution + result parsing
- `research-mind-service/app/routes/analyze.py` - analysis endpoint
- `~/.claude/agents/research-analyst/AGENT.md` - agent definition

**Success Criteria**:

- ✅ Can invoke agent with POST /api/sessions/{id}/analyze
- ✅ Agent returns answer with citations to code locations
- ✅ Session isolation enforced (agent can only see session files)
- ✅ Network disabled (curl/wget blocked in subprocess)

---

### 1.7: Integration Tests (5-7 days) - REVISED UP FROM 4 DAYS

**Deliverable**: Comprehensive test suite validating MVP functionality with security focus

**Note**: Security testing is more involved than initially estimated. Includes:

- Path traversal fuzzing
- Concurrent access verification
- Cross-session contamination prevention
- Agent containment verification
- Audit logging validation

**Tasks**:

1. End-to-end test flow:

   - Create session
   - Add content (copy files to workspace)
   - Index content (poll until complete)
   - Search for results
   - Invoke agent with context
   - Verify answer returned with citations

2. Isolation tests:

   - Create two sessions
   - Index different content in each
   - Verify search in session 1 only returns session 1 results
   - Verify agent in session 1 cannot access session 2 files
   - Test concurrent indexing (multiple sessions simultaneously)
   - ChromaDB concurrent write safety verification (from Phase 1.0 testing)

3. Security tests (CRITICAL):

   - Path traversal attempts: `../../../etc/passwd`, symlinks, etc. (fuzzing)
   - Hidden file access blocked (dotfiles, .env, etc.)
   - Session validation on every request
   - Invalid session_id → 404
   - Expired session → 410
   - Audit logging captures all attempts (successful and failed)
   - Agent network isolation verified

4. Error case tests:
   - Indexing timeout → error returned
   - Missing workspace → handled gracefully
   - ChromaDB corruption → recovery tested
   - Model download failure → fallback tested

**Critical Files to Create**:

- `research-mind-service/tests/test_integration_e2e.py` - end-to-end tests
- `research-mind-service/tests/test_isolation.py` - isolation verification
- `research-mind-service/tests/test_security.py` - security tests (path traversal, isolation)
- `research-mind-service/tests/test_concurrent_access.py` - concurrent indexing safety

**Success Criteria**:

- ✅ All tests pass (>90% coverage)
- ✅ End-to-end flow works (session → index → search → analyze)
- ✅ Cross-session isolation verified (100% separation)
- ✅ Path traversal blocked (100% detection rate)
- ✅ Concurrent access safe (verified in Phase 1.0 + retested in Phase 1.7)
- ✅ Security audit ready for stakeholder review

---

### 1.8: Documentation & MVP Release (2 days)

**Deliverable**: Complete documentation and local deployment capability

**Tasks**:

1. Write README with setup instructions
2. Create Docker Compose for local dev
3. Document API contract (update docs/api-contract.md)
4. Create deployment guide (Docker single-server)
5. Document configuration (env variables, paths, timeouts)

**Critical Files to Create**:

- `research-mind-service/README.md` - setup & architecture
- `docker-compose.yml` - local development setup
- `Dockerfile` - service containerization
- `docs/api-contract.md` - OpenAPI contract (updated)

**Success Criteria**:

- ✅ Can boot service with `docker-compose up`
- ✅ All endpoints documented with examples
- ✅ Configuration documented
- ✅ Error codes documented

---

## Phase 2: Search Quality & Cost (Weeks 4-6)

### Objective

Improve search quality to 90%+ precision, reduce costs by 40-50%

### 2.1: Incremental Indexing (1 week)

**Strategy**: Only reindex changed files (80% cost savings for small changes)

**Implementation**:

- Track file content hashes in session metadata
- Use git to detect changed files when available
- Only process deltas in indexing job
- Preserve ChromaDB collections between indexing runs

**Impact**: 80% cost reduction for incremental changes, 50% faster reindex

---

### 2.2: Query Caching (3-4 days)

**Strategy**: Cache search results per query per session (40% cost savings)

**Implementation**:

- Cache key: `hash(session_id + query_text)`
- TTL: 1 hour
- Invalidate on reindex
- Monitor cache hit rate

**Impact**: 40% request reduction, 2-3s latency improvement

---

### 2.3: Advanced Filtering (3-4 days)

**Strategy**: Filter results by language, chunk type, complexity

**API**:

```json
POST /api/sessions/{id}/search
{
  "query": "authentication",
  "filters": {
    "language": ["python", "typescript"],
    "chunk_type": ["function", "method"],
    "file_pattern": "auth/**"
  }
}
```

**Impact**: More precise results, better UX

---

### 2.4: Warm Session Pools (1 week)

**Strategy**: Keep Claude subprocesses warm for reuse (2-3s → 0.1s per query)

**Implementation**:

- Maintain pool of pre-started agent sessions (3-5 agents)
- Reuse warm sessions for queries
- Monitor pool health
- Respawn agents as needed

**Impact**: 90% latency reduction for follow-up queries

---

### 2.5: Cost Optimization (Ongoing)

**Strategies**:

- Monitor tokens per session
- Implement token budgets
- Auto-summarize at 70%/85%/95% thresholds
- Cache embeddings per session

**Impact**: 40-50% cost reduction

**Success Criteria by End of Phase 2**:

- ✅ Search quality: 90%+ precision (manual evaluation)
- ✅ Cost: $0.05 per query (40% reduction from baseline)
- ✅ Latency: <5s for agent analysis
- ✅ Cache hit rate: >40% for typical usage patterns

---

## Phase 3: Reranking & UX Polish (Weeks 7-9)

### Objective

Production-ready search quality and user experience

### 3.1: Semantic Reranking

**Implementation**:

- Use Claude to rerank search results by relevance
- Consider code structure (public API vs. internal)
- Boost recent code, penalize deprecated
- Rerank by citation frequency

**Impact**: 50% better precision, 95%+ accuracy

---

### 3.2: Result Deduplication

**Implementation**:

- Hash-based deduplication across sessions
- Similarity-based duplicate detection
- Clean UX (no redundant results)

**Impact**: Cleaner results, better UX

---

### 3.3: Advanced Agent Features

**Features**:

- Multi-turn conversation history (per session)
- Follow-up questions support
- Citation tracking and export
- Result export (markdown, JSON)

**Impact**: Better usability, research workflows enabled

**Success Criteria by End of Phase 3**:

- ✅ Search quality: 95%+ precision (manual evaluation)
- ✅ Agent response: 3-5s latency (from 5-10s)
- ✅ UX: Clean, deduped results with strong citations
- ✅ Multi-turn: Conversation history working

---

## Phase 4: Operations & Scale (Weeks 10-12)

### Objective

Production deployment with 10x throughput capability

### 4.1: TTL Pruning & Cleanup

**Implementation**:

- Auto-delete expired sessions (24h max)
- Archive audit logs
- Disk quota enforcement (10GB per session)
- Cleanup via background job

**Impact**: Cost reduction through cleanup, 99%+ uptime

---

### 4.2: Multi-Instance Deployment

**Implementation**:

- Kubernetes manifests (3+ replicas)
- Horizontal scaling
- Load balancing
- Health checks + auto-restart
- Monitoring/alerting

**Impact**: 10x throughput, 99.9% availability

---

### 4.3: Production Hardening

**Implementation**:

- Rate limiting per session
- Distributed session state (Redis)
- Encrypted audit logs
- Compliance reporting
- Security audit

**Success Criteria by End of Phase 4**:

- ✅ 99%+ uptime
- ✅ 10x throughput vs. single instance
- ✅ Multi-region ready
- ✅ Security audit passed

---

## Critical Files for Implementation

The following are the **top priority files** to implement first:

### 1. **`research-mind-service/app/main.py`** (CRITICAL - BLOCKS ALL PHASES)

**Purpose**: FastAPI entry point with middleware, session validation, audit logging setup
**Why Critical**: Ties together the entire service, must be done first
**Estimated Size**: 150-200 lines
**Dependencies**: None

### 2. **`research-mind-service/app/services/session_indexer.py`** (CRITICAL - PHASE 1.3)

**Purpose**: Core wrapper around mcp-vector-search that manages session-scoped indexing and search
**Why Critical**: Heart of integration with mcp-vector-search library
**Estimated Size**: 200-300 lines
**Dependencies**: main.py (for registry)

### 3. **`research-mind-service/app/sandbox/path_validator.py`** (CRITICAL - PHASE 1.4)

**Purpose**: Security-critical path validation for claude-ppm isolation
**Why Critical**: Prevents data exfiltration and cross-session contamination
**Estimated Size**: 100-150 lines
**Dependencies**: None

### 4. **`research-mind-service/pyproject.toml`** (CRITICAL - PHASE 1.1)

**Purpose**: Dependency management, mcp-vector-search integration
**Why Critical**: Must have mcp-vector-search as dependency, specify Python 3.12+
**Estimated Size**: 50-100 lines
**Dependencies**: None

### 5. **`research-mind-service/app/routes/vector_search.py`** (CRITICAL - PHASE 1.3)

**Purpose**: REST API endpoints for indexing, search, and session management
**Why Critical**: Implements thin adapters over SessionIndexer
**Estimated Size**: 200-250 lines
**Dependencies**: session_indexer.py, path_validator.py

---

## Risk Register & Mitigations

### Critical Risks (CRITICAL Severity)

**Risk 1: Session Isolation Breach**

- **Impact**: Cross-session data contamination, security violation
- **Probability**: Medium (if validation not comprehensive)
- **Mitigation**:
  - Multi-layer validation (middleware + service + subprocess)
  - Audit logging of all access attempts
  - Regular security audits
  - Comprehensive test suite (Phase 1.7)
- **Detection**: Failed tests in phase 1.7, audit log anomalies
- **Fallback**: Revert to single-session-per-instance model

**Risk 2: Vector Search Token Contamination**

- **Impact**: Agent receives mixed session data, compromised analysis
- **Probability**: Low (ChromaDB isolates by collection)
- **Mitigation**:
  - Per-session collections enforced at ChromaDB level
  - Middleware validation on every request
  - Comprehensive isolation tests
- **Detection**: Search results from wrong session, failed isolation tests
- **Fallback**: Use separate ChromaDB instances per session

### High Risks (HIGH Severity - Managed with documented mitigation)

**Risk 3: Agent Cost Explosion**

- **Impact**: Unexpected high token usage, cost overruns
- **Probability**: Medium (without token budgets)
- **Mitigation**:
  - Token budgets per session (Phase 2.5)
  - Auto-summarization at thresholds (70%/85%/95%)
  - Cost logging per session
  - User warnings when approaching limits
- **Detection**: Cost monitoring dashboard, alerts at $50/session
- **Fallback**: Pause session, notify user, require approval to continue

**Risk 4: Prompt-Based Sandbox Failure**

- **Impact**: Agent escapes sandbox, accesses unauthorized files
- **Probability**: Low (infrastructure-level enforcement)
- **Mitigation**:
  - Infrastructure-level enforcement (not prompt-only)
  - Tool call interception
  - Command whitelisting
  - Path validator as last line of defense
- **Detection**: Path validator logs, audit trail
- **Fallback**: Immediately revoke agent session, review logs

### Medium Risks (MEDIUM Severity - All mitigated with documented strategies)

**Risk 5: Indexing Crashes**

- **Mitigation**: Timeout + error handling + resume capability
- **Detection**: Job status API returns error state
- **Fallback**: Retry with reduced scope (subset of files)

**Risk 6: ChromaDB Corruption**

- **Mitigation**: Connection pooling + recovery procedures
- **Detection**: Corruption detected at search time
- **Fallback**: Rebuild from scratch (accept latency spike)

**Risk 7: High Latency**

- **Mitigation**: Warm pools (Phase 2.4) + caching (Phase 2.2)
- **Detection**: Latency monitoring + alerting
- **Fallback**: Enable emergency caching, return cached results

**Risk 8: Deployment Complexity**

- **Mitigation**: Docker/K8s templates provided (Phase 4)
- **Detection**: Deployment test suite
- **Fallback**: Single-instance docker deployment

---

## Timeline & Effort Estimates

| Phase             | Weeks    | Components                                                 | Effort         | Team          | Notes                                                   |
| ----------------- | -------- | ---------------------------------------------------------- | -------------- | ------------- | ------------------------------------------------------- |
| **Phase 1.0**     | Pre-1    | Environment setup, mcp-vector-search install, verification | 2-3 days       | 1 FTE         | **CRITICAL** - Must complete before Phase 1.1           |
| **MVP (Phase 1)** | 1-3      | Service arch, sessions, indexing, search, agent, tests     | 12-16 days     | 2 FTE         | **CRITICAL PATH** - Blocks all subsequent phases        |
| **Total to MVP**  | -        | Phase 1.0 + Phase 1 combined                               | **15-21 days** | 2 FTE         | More realistic than original 10-12 day estimate         |
| **Phase 2**       | 4-6      | Incremental indexing, caching, filtering, warm pools       | 3 weeks        | 1.5 FTE       | Parallel with initial user feedback                     |
| **Phase 3**       | 7-9      | Reranking, dedup, UX polish                                | 3 weeks        | 1 FTE         | Quality improvements                                    |
| **Phase 4**       | 10-12    | K8s, multi-instance, hardening                             | 3 weeks        | 2 FTE         | Production hardening                                    |
| **Total to Prod** | 12 weeks | Production-ready system                                    | 12 weeks       | 2-2.5 FTE avg | Phase 1.0 impact: +5-9 days, net benefit risk reduction |

**Critical Path**: Phase 1.0 (2-3 days) → MVP Phase 1 (12-16 days) → Phase 2 (weeks 4-6) → Phase 3 (weeks 7-9) → Phase 4 (weeks 10-12)

**Important**: Original 10-12 day MVP estimate was optimistic. Realistic timeline with Phase 1.0 is 15-21 days. Phase 1.0 adds 2-3 days but saves 3-5 days of Phase 1.1 troubleshooting (net benefit).

**Parallel Tracks**:

- Phase 2 can begin after Phase 1 complete
- Phase 3 can begin after Phase 2 complete
- Phase 4 can begin after Phase 3 complete (no parallelization)

---

## Dependencies Matrix

### External Dependencies

| Dependency          | Version              | Status    | Purpose                    |
| ------------------- | -------------------- | --------- | -------------------------- |
| mcp-vector-search   | Latest (PyPI or git) | Available | Semantic indexing & search |
| claude-ppm          | v2.1.3+              | Available | Agent orchestration        |
| FastAPI             | 0.104+               | Available | REST API framework         |
| SQLAlchemy          | 2.0+                 | Available | ORM for session storage    |
| ChromaDB            | (bundled)            | Available | Vector database            |
| PostgreSQL / SQLite | Latest               | Available | Session storage            |

### Internal Dependencies

**Blocking Chain**:

```
Phase 1.1 (Service Arch)
    ↓ (BLOCKS)
Phase 1.2 (Sessions), 1.3 (Search), 1.4 (Path Validator)
    ↓ (BLOCKS)
Phase 1.5 (Audit), 1.6 (Agent Integration)
    ↓ (BLOCKS)
Phase 1.7 (Integration Tests), 1.8 (Release)
    ↓ (BLOCKS)
Phase 2 (Cost/Quality Optimizations)
    ↓ (BLOCKS)
Phase 3 (Reranking/UX)
    ↓ (BLOCKS)
Phase 4 (Operations/Scale)
```

**No Blocking Issues Identified** - All dependencies available, architecture is sound

---

## Success Verification Checklist

### ✅ MVP Completion (Phase 1)

- [ ] Session CRUD endpoints working
- [ ] Indexing async with job progress tracking
- [ ] Search working with per-session isolation
- [ ] Agent invocation returning answers with citations
- [ ] Audit logging capturing all actions
- [ ] Path validation blocking traversal attempts (100% detection)
- [ ] Cross-session isolation verified (100% separation)
- [ ] Integration tests passing (>90% coverage)
- [ ] Docker Compose bootable
- [ ] All endpoints documented

### ✅ Phase 2 Completion

- [ ] Search quality: 90%+ precision (manual evaluation)
- [ ] Cost: $0.05 per query (40% reduction)
- [ ] Latency: <5s for agent analysis
- [ ] Cache hit rate: >40% for typical usage patterns
- [ ] Incremental indexing working correctly
- [ ] Query caching reducing API calls by 40%+
- [ ] Warm pools reducing latency by 90% for follow-up queries

### ✅ Phase 3 Completion

- [ ] Search quality: 95%+ precision (manual evaluation)
- [ ] Agent latency: 3-5s average
- [ ] Results deduplicated (zero duplicates in top 10)
- [ ] Citations accurate and traceable
- [ ] Multi-turn conversation working
- [ ] Export functionality (markdown, JSON)

### ✅ Phase 4 Completion

- [ ] Multi-instance deployment working
- [ ] 99%+ uptime in production
- [ ] 10x throughput vs. single instance (300+ concurrent sessions)
- [ ] Security audit passed
- [ ] Monitoring/alerting operational
- [ ] Rate limiting preventing abuse

---

## Implementation Order (Day by Day)

### Pre-Week 1: Phase 1.0 Environment Setup (2-3 Days)

**CRITICAL - Must complete before Phase 1 formal kickoff**

- **Day -3 to -1**:
  - Install mcp-vector-search library (~2.5GB)
  - Verify Python 3.12+ and virtual environment
  - Test PostgreSQL connection and migrations
  - Create app/sandbox/ directory
  - Test model caching (embedding download + cache verification)
  - Create .env.example and PHASE_1_0_BASELINE.md
  - All verification tests must pass
  - **Approval gate**: Engineering team signs off on Phase 1.0 findings

### Week 1: Foundation (Service Architecture + Sessions)

- **Day 1-2**: Service Architecture (1.1) - FastAPI setup + VectorSearchManager singleton
  - VectorSearchManager loads model on startup (~30s first run, cached after)
  - Set up configuration system (Pydantic Settings)
- **Day 3-4**: Session Management (1.2)
  - Session database model
  - CRUD endpoints
  - Workspace directory initialization
- **Day 5**: Path Validator (1.4) - do early for security
  - Path validation logic
  - FastAPI middleware integration

### Week 2: Search Integration + Audit

- **Day 6-11**: Vector Search REST API (1.3) (5-6 days, revised up)
  - SessionIndexer wrapper around VectorSearchManager
  - Index and search endpoints
  - Per-session collection management
  - Job progress tracking
- **Day 11-12**: Audit Logging (1.5)
  - Audit log model
  - Logging for all operations

### Week 3: Agent Integration + Tests + Release

- **Day 13-18**: Agent Integration (1.6) (5-7 days, revised up)
  - research-analyst agent definition
  - Agent runner with subprocess isolation
  - Analysis endpoint
- **Day 19-25**: Integration Tests (1.7) (5-7 days, revised up)
  - End-to-end tests
  - Isolation tests
  - **Security tests** (path traversal, concurrent access, etc.)
  - Concurrent access validation
- **Day 26-27**: Documentation & Release (1.8)
  - README, API contract, deployment guide
  - Docker Compose local dev
  - Code complete

### Weeks 4-12: Optimization & Production

- Weeks 4-6: Phase 2 (Cost/Quality Optimizations)
- Weeks 7-9: Phase 3 (Reranking/UX Polish)
- Weeks 10-12: Phase 4 (Operations/Scale)

---

## Key Decisions & Trade-offs

### Decision 1: mcp-vector-search as Library vs. CLI

> **SUPERSEDED**: Research confirmed mcp-vector-search CANNOT be embedded as a library.
> It runs as a CLI subprocess. See `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0).

- **Original Choice**: Library (imported in Python) -- **INCORRECT**
- **Revised Choice**: CLI subprocess (spawned via `subprocess.run()`)
- **Rationale**: mcp-vector-search is designed as a CLI tool; per-workspace isolation via `cwd` parameter
- **Trade-off**: Subprocess overhead per invocation, but cleaner isolation and no shared state

### Decision 2: Per-Session ChromaDB Collections vs. Per-Workspace Index Directories

> **SUPERSEDED**: Each workspace has its own `.mcp-vector-search/` directory with independent ChromaDB index.

- **Original Choice**: Collections in shared instance -- **SUPERSEDED**
- **Revised Choice**: Per-workspace `.mcp-vector-search/` directories (automatic with subprocess approach)
- **Rationale**: Subprocess `cwd` determines workspace; each workspace is fully independent
- **Trade-off**: More disk usage, but zero cross-workspace contamination risk

### Decision 3: Infrastructure-Level Sandbox vs. Prompt-Based

- **Choice**: Infrastructure-level (path validation + env vars + subprocess limits)
- **Rationale**: Prompt-based alone insufficient for security
- **Trade-off**: More implementation complexity, but required for production

### Decision 4: MVP Scope

- **Choice**: 10-12 day MVP with core loop only
- **Rationale**: Get to user feedback quickly
- **Trade-off**: Optimize later (Phases 2-4)

---

## Next Steps

### Immediate Actions (Before Phase 1.0)

1. **Review Subprocess Integration Guide**: Read `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0, subprocess-based)
2. **Approval Gate**: Team reviews research findings and Phase 1.0 timeline
3. **Execute Phase 1.0**: Run pre-phase environment setup (2-3 days)
   - Install mcp-vector-search CLI (~2.5GB)
   - Verify subprocess invocation (`mcp-vector-search init --force`)
   - Run verification script
   - Create PHASE_1_0_BASELINE.md
   - Sign off on findings

### Phase 1 Implementation (after Phase 1.0 complete)

1. **Day 1-2**: Implement Phase 1.1 (Service Architecture)
   - FastAPI app with VectorSearchManager singleton
   - Use template from MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md Section 4
2. **Day 3-4**: Implement Phase 1.2 (Session Management)
3. **Day 5**: Implement Phase 1.4 (Path Validator) - security critical
4. **Day 6-11**: Implement Phase 1.3 (Vector Search REST API)
   - SessionIndexer wrapper (template in integration guide)
5. **Day 11-12**: Implement Phase 1.5 (Audit Logging)
6. **Day 13-18**: Implement Phase 1.6 (Agent Integration)
7. **Day 19-25**: Implement Phase 1.7 (Integration Tests) with security focus
8. **Day 26-27**: Implement Phase 1.8 (Documentation & Release)
9. **Week 4+**: Begin Phase 2 (Cost/Quality Optimizations)

### Key Documents & Resources

- **docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md** (v2.0): Subprocess-based integration guide with code templates
- **docs/research2/RESEARCH_SUMMARY.md**: Quick reference of research findings
- **IMPLEMENTATION_ROADMAP.md**: Master index and timeline (supersedes this document)
- **PHASE_1_0_BASELINE.md**: (To be created during Phase 1.0) Environment documentation

---

**Document Status**: REFERENCE ONLY - Superseded by individual phase documents in docs/plans/
**Review Date**: 2026-02-01
**Architecture Update**: Subprocess-based mcp-vector-search integration (see docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md v2.0)
**Next Review**: After Phase 1 MVP completion
