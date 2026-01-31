# Research-Mind Implementation Plan

**Last Updated**: 2026-01-31
**Status**: GO - Architecture sound, ready for implementation
**Timeline**: 12 weeks to production (MVP in 10-12 days)

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

---

## Phase 1: Foundation (Weeks 1-3) - MVP CORE RESEARCH LOOP

### Objective

Build minimal end-to-end flow: create session → index content → search → analyze with agent

### Critical Dependencies

- mcp-vector-search library (as Python package, not CLI)
- claude-ppm installation (requires Claude CLI v2.1.3+)
- FastAPI service scaffold
- SQLite for session storage
- ChromaDB (included in mcp-vector-search)

### 1.1: Service Architecture Setup (3-4 days)

**Deliverable**: FastAPI service scaffold with proper project structure

**Tasks**:

1. Create FastAPI service skeleton at `research-mind-service/`
2. Set up project structure:
   - `app/main.py` - FastAPI entry point
   - `app/routes/` - API endpoints
   - `app/services/` - Business logic
   - `app/schemas/` - Pydantic models
   - `app/models/` - Database models
   - `app/sandbox/` - Security/isolation
   - `tests/` - Test suite
3. Add mcp-vector-search to `pyproject.toml` as dependency (~2.5GB disk space required)
4. Create `.env.example` with service configuration
5. Set up Docker/docker-compose for local development

**Critical Files to Create**:

- `research-mind-service/pyproject.toml` - dependency management (add mcp-vector-search)
- `research-mind-service/app/main.py` - FastAPI app with middleware
- `research-mind-service/Dockerfile` - service containerization

**Success Criteria**:

- ✅ Service starts on port 15010
- ✅ GET /api/health returns `{"status": "healthy"}`
- ✅ mcp-vector-search library imports successfully
- ✅ All dependencies in pyproject.toml

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

### 1.3: Vector Search REST API (Wrapper) (4-5 days)

**Deliverable**: REST interface to mcp-vector-search with per-session indexing and search

**Tasks**:

1. Create thin FastAPI wrappers around mcp-vector-search library

   - **DO NOT** re-implement indexing (use mcp-vector-search's SemanticIndexer directly)
   - **DO NOT** build custom job queue (mcp-vector-search provides it)
   - Create wrapper that manages session scoping + provides REST interface

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

**Architecture Pattern**:

```python
from mcp_vector_search import SemanticIndexer, SemanticSearchEngine

class SessionIndexer:
    def __init__(self, session_id: str, session_root: Path):
        self.collection_name = f"session_{session_id}"
        # Direct calls to mcp-vector-search APIs
        self.indexer = SemanticIndexer(
            database=ChromaVectorDatabase(...),
            project_root=session_root
        )

    async def index(self, force: bool = False):
        # Direct delegation to mcp-vector-search
        return await self.indexer.index_directory(force=force)

    async def search(self, query: str, limit: int = 10):
        # Direct delegation to mcp-vector-search
        return await SemanticSearchEngine(...).search(query, limit=limit)
```

**Critical Files to Create**:

- `research-mind-service/app/services/session_indexer.py` - wrapper around mcp-vector-search
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

### 1.6: Agent Integration (4-5 days)

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

### 1.7: Integration Tests (4 days)

**Deliverable**: Comprehensive test suite validating MVP functionality

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

3. Error case tests:
   - Invalid session_id → 404
   - Expired session → 410
   - Path traversal attempt → blocked + logged
   - Indexing timeout → error returned

**Critical Files to Create**:

- `research-mind-service/tests/test_integration_e2e.py` - end-to-end tests
- `research-mind-service/tests/test_isolation.py` - isolation verification
- `research-mind-service/tests/test_security.py` - security tests

**Success Criteria**:

- ✅ All tests pass (>90% coverage)
- ✅ End-to-end flow works (session → index → search → analyze)
- ✅ Cross-session isolation verified (100%)
- ✅ Security tests confirm path traversal blocked

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

| Phase             | Weeks    | Components                                             | Effort     | Team          | Notes                                            |
| ----------------- | -------- | ------------------------------------------------------ | ---------- | ------------- | ------------------------------------------------ |
| **MVP (Phase 1)** | 1-3      | Service arch, sessions, indexing, search, agent, tests | 10-12 days | 2 FTE         | **CRITICAL PATH** - Blocks all subsequent phases |
| **Phase 2**       | 4-6      | Incremental indexing, caching, filtering, warm pools   | 3 weeks    | 1.5 FTE       | Parallel with initial user feedback              |
| **Phase 3**       | 7-9      | Reranking, dedup, UX polish                            | 3 weeks    | 1 FTE         | Quality improvements                             |
| **Phase 4**       | 10-12    | K8s, multi-instance, hardening                         | 3 weeks    | 2 FTE         | Production hardening                             |
| **Total**         | 12 weeks | Production-ready system                                | 12 weeks   | 2-2.5 FTE avg | Can achieve MVP in 10-12 calendar days           |

**Critical Path**: MVP (weeks 1-3) → Phase 2 cost optimization (weeks 4-6) → Phase 3 quality (weeks 7-9)

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

### Week 1: Foundation

- **Day 1-2**: Service Architecture (1.1) + pyproject.toml
- **Day 3-4**: Session Management (1.2)
- **Day 5**: Path Validator (1.4) - do early for security

### Week 2: Search Integration

- **Day 6-10**: Vector Search REST API (1.3)
- **Day 11**: Audit Logging (1.5)

### Week 3: Agent + Tests

- **Day 12-15**: Agent Integration (1.6)
- **Day 16-19**: Integration Tests (1.7)
- **Day 20**: Documentation & Release (1.8)

### Weeks 4-12: Optimization & Production

- Weeks 4-6: Phase 2 (Cost/Quality)
- Weeks 7-9: Phase 3 (Reranking/UX)
- Weeks 10-12: Phase 4 (Operations/Scale)

---

## Key Decisions & Trade-offs

### Decision 1: mcp-vector-search as Library vs. CLI

- **Choice**: Library (imported in Python)
- **Rationale**: Better control, session scoping, lower overhead
- **Trade-off**: Need to manage ChromaDB instance directly

### Decision 2: Per-Session ChromaDB Collections vs. Separate Instances

- **Choice**: Collections in shared instance
- **Rationale**: Lower memory overhead, easier management
- **Trade-off**: Requires strict middleware validation (mitigated by Phase 1.4)

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

1. **Immediate**: Create pyproject.toml with mcp-vector-search dependency
2. **Day 1-2**: Implement Phase 1.1 (Service Architecture)
3. **Day 3-4**: Implement Phase 1.2 (Session Management)
4. **Day 5**: Implement Phase 1.4 (Path Validator) - security critical
5. **Day 6-10**: Implement Phase 1.3 (Vector Search REST API)
6. **Day 11-15**: Implement Phase 1.5 (Audit) + 1.6 (Agent Integration)
7. **Day 16-20**: Implement Phase 1.7 (Tests) + 1.8 (Release)
8. **Week 4+**: Begin Phase 2 (Cost/Quality Optimizations)

---

**Document Status**: Complete
**Review Date**: 2026-01-31
**Next Review**: After Phase 1 MVP completion
