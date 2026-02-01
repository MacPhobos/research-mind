# Combined Architecture Recommendations

**Document Version**: 2.0
**Date**: 2026-02-01
**Status**: Final Recommendations (Subprocess Architecture)
**Supersedes**: v1.1 (library-embedding approach, deprecated)

---

## Correction History

**v2.0 (2026-02-01)**: Full rewrite. mcp-vector-search is a **subprocess** invoked via CLI, not an embedded Python library. All library-embedding references, cost estimates, latency projections, and the 4-phase timeline from v1.1 have been replaced with subprocess-verified data. Search is deferred -- users query through Claude Code's MCP interface, not a REST API we build.

**v1.1 (2026-01-31)**: Corrected SemanticIndexer assumption. Reduced MVP timeline. Still assumed library embedding (wrong).

**v1.0 (2026-01-31)**: Original document. Assumed mcp-vector-search was an embeddable Python library (wrong).

---

## 1. Executive Summary

**Research-Mind** is technically feasible as a workspace-scoped indexing system combining mcp-vector-search (subprocess-based indexing) with claude-mpm (agentic analysis). The architecture is simpler than originally projected because mcp-vector-search handles all indexing internals -- we just spawn it and check the exit code.

**Tell it like it is**:

- The architecture is sound and verified through testing
- mcp-vector-search works reliably as a subprocess (exit codes, isolation, timing all confirmed)
- There is no "out of the box" solution; we are building integration glue
- Phase 1 is the only phase that exists right now (workspace registration + indexing)
- Search is deferred to Claude Code's native MCP interface; we are not building a search API
- Sandbox containment is still the hardest engineering problem
- Cost and latency at scale are TBD -- we have small-project benchmarks only

**Recommendation**: BUILD. Focus exclusively on Phase 1 (workspace registration + subprocess indexing service). Do not plan Phase 2-4 until Phase 1 is complete and real-world behavior is understood.

---

## 2. Architecture Overview

### 2.1 Subprocess-Based Design

mcp-vector-search is a standalone CLI tool. research-mind-service spawns it as a subprocess, passing the workspace directory via `cwd`. There is no Python library import, no singleton, no embedded ChromaDB client.

```
research-mind-service (FastAPI)
  |
  +-- Workspace Management API
  |   +-- POST /workspaces/{id}/register
  |   +-- POST /workspaces/{id}/index
  |
  +-- Indexing Operations (subprocess)
      +-- subprocess.run(["mcp-vector-search", "init", "--force"], cwd=workspace_dir)
      +-- subprocess.run(["mcp-vector-search", "index", "--force"], cwd=workspace_dir)
          |
          +-- workspace_dir/
              +-- source code files
              +-- .mcp-vector-search/       <-- index artifacts (auto-created)
                  +-- config.json
                  +-- chroma.sqlite3
                  +-- index_metadata.json
                  +-- directory_index.json
                  +-- <UUID>/               <-- HNSW index files
```

### 2.2 Two-Step Indexing Flow

Every workspace goes through the same sequence:

1. **Init**: `mcp-vector-search init --force` -- creates `.mcp-vector-search/` directory, downloads embedding model on first run (~250-500 MB, cached at `~/.cache/huggingface/hub/`)
2. **Index**: `mcp-vector-search index --force` -- indexes all source files, stores embeddings in ChromaDB (SQLite-backed)

Both commands use exit code 0 for success, 1 for failure. That is the entire integration contract.

### 2.3 Search Architecture (Deferred)

Search is **not** part of Phase 1. Users query indexed workspaces through Claude Code's native MCP interface (`mcp__mcp-vector-search__search_code`, `search_context`, `search_similar`). research-mind-service does not expose a search endpoint.

This is a deliberate simplification. Building a REST search API on top of mcp-vector-search's MCP tools would add complexity without clear value -- Claude Code already knows how to use these tools natively. If a REST search API becomes necessary later, it can be added in a future phase.

### 2.4 Index Storage

All index artifacts live in `.mcp-vector-search/` at the workspace root. This directory is automatically added to `.gitignore` by the init command.

| Artifact                  | Typical Size   | Purpose                                |
| ------------------------- | -------------- | -------------------------------------- |
| `config.json`             | <1 KB          | Embedding model settings               |
| `chroma.sqlite3`          | ~410 KB        | Vector database (ChromaDB)             |
| `index_metadata.json`     | <1 KB          | Index statistics                       |
| `directory_index.json`    | <1 KB          | File tracking for incremental indexing |
| `<UUID>/` (HNSW index)    | ~13 KB         | Binary similarity search index         |
| **Total (small project)** | **432-552 KB** | Complete index for 2-file project      |

Estimated scaling (not yet tested):

- Small project (1-50 files): 1-2 MB
- Medium project (50-500 files): 10-50 MB
- Large project (500-5000 files): 50-500 MB

Disk usage scales primarily with **file count**, not lines of code.

---

## 3. Component Analysis

### 3.1 mcp-vector-search (Subprocess Integration)

**What it is**: A CLI tool that indexes source code into a ChromaDB vector database for semantic search. Installed via `pip install mcp-vector-search`. Provides both CLI commands and an MCP server for Claude Code integration.

**How we use it**: Subprocess invocation only. We call `init` and `index` commands with `subprocess.run()`, setting `cwd` to the workspace directory. We check exit codes. We capture stdout/stderr for logging.

**What it handles for us**:

- File discovery and language detection (TreeSitter-based)
- Code chunking (functions, classes, comment blocks)
- Embedding generation (sentence-transformers/all-MiniLM-L6-v2, 384-dim vectors)
- ChromaDB storage and retrieval
- Incremental indexing (change detection via file hashes and timestamps)
- `.gitignore` awareness (auto-excludes .git, node_modules, **pycache**, etc.)

**What we handle**:

- Workspace path validation (sandbox enforcement)
- Subprocess lifecycle (timeouts, error handling, retry)
- Indexing status tracking (is this workspace indexed? when? how long did it take?)
- Concurrency control (don't index the same workspace twice simultaneously)

**Verified characteristics** (from subprocess integration research):

| Property                    | Status    | Details                                           |
| --------------------------- | --------- | ------------------------------------------------- |
| Subprocess invocation       | Confirmed | `subprocess.run()` works correctly                |
| Working directory detection | Confirmed | `cwd` parameter is sufficient, no flags needed    |
| Exit code reliability       | Confirmed | 0 = success, 1 = failure                          |
| Per-workspace isolation     | Confirmed | Parallel indexing of different workspaces is safe |
| Same-workspace concurrency  | NOT SAFE  | ChromaDB SQLite single-writer limitation          |
| Index self-containment      | Confirmed | Everything in `.mcp-vector-search/`               |

### 3.2 claude-mpm (Agent Orchestration)

**What it is**: A multi-agent orchestration framework for Claude Code CLI. Provides session management, agent deployment (47+ agents), skills system, and MCP tool integration.

**Current status for research-mind**: Agent integration is deferred to Phase 2. The claude-mpm analysis from `claude-mpm-capabilities.md` remains valid. Key points:

- **Session management**: UUID-based sessions with 30-day resumption window, persisted to disk
- **Agent system**: 47+ deployed agents with customizable definitions (AGENT.md format)
- **MCP integration**: Auto-discovers configured MCP servers, including mcp-vector-search
- **Tool access**: Filesystem, git, execution, analysis, and MCP tools available to agents
- **Sandbox gap**: Current implementation relies on prompt-based restrictions, NOT code-level enforcement. This is the primary security concern for research-mind.

**What we need to build** (Phase 2):

- Custom `research-analyst` agent definition
- Infrastructure-level path validation wrapping all agent filesystem access
- Audit logging for all tool calls
- Token budgeting and cost tracking

### 3.3 research-mind-service (FastAPI Wrapper)

**What it is**: The service we are building. A FastAPI application that orchestrates workspace registration, subprocess-based indexing, session management, and (eventually) agent invocation.

**Phase 1 scope**:

- Workspace CRUD (register, list, delete)
- Workspace indexing via subprocess (init + index)
- Path validation (sandbox enforcement)
- Indexing status tracking
- Audit logging for all operations
- Health checks

**What it is NOT** (in Phase 1):

- Not a search API (search goes through Claude Code MCP)
- Not an agent runner (agent integration is Phase 2)
- Not a job queue (subprocess invocation is synchronous or simple async)

---

## 4. Security & Containment

The sandbox containment plan from `claude-mpm-sandbox-containment-plan.md` remains fully valid. The subprocess architecture actually strengthens isolation because each mcp-vector-search invocation is a separate OS process with its own filesystem scope.

### 4.1 Defense-in-Depth Layers

```
Layer 1: FastAPI Middleware
  - Validate session_id on every request
  - Rate limiting per session

Layer 2: Service-Level Validation
  - Path allowlist (workspace root enforcement)
  - Symlink detection and resolution
  - Disallowed patterns (.ssh, .env, /etc, /root)

Layer 3: Subprocess Isolation
  - cwd = workspace directory (filesystem boundary)
  - Timeout per operation (prevent hanging)
  - stdout/stderr capture (no interactive input)
  - Exit code verification

Layer 4: Per-Workspace Index Isolation
  - Each workspace has independent .mcp-vector-search/
  - No shared ChromaDB instance
  - Cross-workspace queries impossible by design

Layer 5: Audit & Monitoring
  - Log all subprocess invocations
  - Log all filesystem access
  - Alert on path validation failures
```

### 4.2 Key Security Principles

1. **Never trust the agent or prompt.** Enforce restrictions at the system level.
2. **Validate every path** before passing it to any subprocess or filesystem operation.
3. **Per-workspace isolation** is inherent in the subprocess design -- each workspace's index is physically separate.
4. **Subprocess timeout** prevents runaway processes. Use 300-600s for production workspaces.
5. **Audit everything.** Every subprocess invocation, every path validation, every error.

### 4.3 Subprocess-Specific Security

The subprocess approach introduces these security considerations:

- **Command injection**: We construct the subprocess command array programmatically (not via shell string). `subprocess.run(["mcp-vector-search", "init", "--force"], ...)` is safe. Never use `shell=True`.
- **Path traversal**: The `cwd` parameter must be validated before use. A malicious workspace path could point anywhere on the filesystem.
- **Resource exhaustion**: Large workspaces could consume significant CPU/memory during indexing. Timeout enforcement is mandatory.
- **Concurrent indexing**: Two simultaneous index operations on the same workspace can corrupt the ChromaDB SQLite database. The service must enforce single-writer per workspace.

---

## 5. Performance Characteristics

### 5.1 Measured Performance (Small Project)

From subprocess integration testing (2 Python files, 11 total lines):

| Operation                      | Time       | Details                                            |
| ------------------------------ | ---------- | -------------------------------------------------- |
| Init (first run, model cached) | 3-5s       | Creates .mcp-vector-search/, runs initial indexing |
| Index (force full)             | 3.89s      | Indexes all files, generates embeddings            |
| Reindex (force full)           | 3.78s      | Comparable to initial index for small projects     |
| Index size                     | 432-552 KB | Complete index artifacts                           |
| Files indexed                  | 2          | With 4 searchable chunks                           |

**Key finding**: For very small projects, incremental indexing provides no meaningful advantage over full reindex. The overhead is in embedding model loading and ChromaDB initialization, not in file processing.

### 5.2 Estimated Performance (Larger Projects)

These estimates are extrapolated, NOT tested:

| Project Size                | Estimated Index Time | Recommended Timeout |
| --------------------------- | -------------------- | ------------------- |
| <100 files, <10K LOC        | 10-15s               | 120s                |
| 100-500 files, 10-50K LOC   | 30-60s               | 300s                |
| 500-1000 files, 50-100K LOC | 60-180s              | 600s                |
| 1000+ files, 100K+ LOC      | 120-300s             | 600s                |

**Important**: These are rough estimates. Real-world performance will depend on file sizes, language distribution, embedding batch size, and system resources. Phase 1 should include benchmarking on representative real workspaces to replace these estimates.

### 5.3 First-Run Overhead

The first time `mcp-vector-search init` runs on any machine, it downloads the sentence-transformers embedding model (~250-500 MB) from HuggingFace. This is cached at `~/.cache/huggingface/hub/` and reused for all subsequent workspaces.

- First init on new machine: 3-15 minutes (network dependent)
- Subsequent init on same machine: 3-5 seconds

### 5.4 Parallel Indexing

Verified safe: Multiple workspaces can be indexed simultaneously from separate subprocess invocations. Testing showed two workspaces indexing in parallel completed in 10.81s total with no interference or cross-contamination.

Verified unsafe: Two simultaneous index operations on the same workspace. ChromaDB uses SQLite with single-writer locking. Concurrent writes to the same `chroma.sqlite3` will fail or corrupt the index.

---

## 6. Risk Register

### Risk 1: Session/Workspace Isolation Breach (CRITICAL)

**Risk**: Agent or subprocess accesses files outside its designated workspace directory.

**Likelihood**: Medium (if path validation is skipped or bypassed)
**Impact**: CRITICAL (data exfiltration, cross-workspace contamination)
**Mitigation**:

- Multi-layer path validation (middleware, service, pre-subprocess)
- Symlink detection
- Comprehensive audit logging
- Security test suite with 20+ attack patterns
- Subprocess `cwd` enforcement

**Residual Risk**: Low (with mitigations in place)

---

### Risk 2: Same-Workspace Concurrent Indexing (HIGH)

**Risk**: Two index operations run simultaneously on the same workspace, corrupting the ChromaDB SQLite database.

**Likelihood**: Medium (if service does not enforce single-writer)
**Impact**: HIGH (corrupted index, requires full re-init)
**Mitigation**:

- Service-level locking per workspace (mutex or database flag)
- Check for existing `.mcp-vector-search/` lock files before indexing
- Recovery procedure: delete `.mcp-vector-search/` and re-init

**Residual Risk**: Low (with single-writer enforcement)

---

### Risk 3: Subprocess Timeout / Hang (MEDIUM)

**Risk**: mcp-vector-search subprocess hangs or takes excessively long on large workspaces.

**Likelihood**: Medium (large codebases, slow embedding generation)
**Impact**: MEDIUM (blocked workspace, user frustration)
**Mitigation**:

- Configurable timeout per subprocess call (300-600s for production)
- `subprocess.TimeoutExpired` handling with cleanup
- Index status tracking (in-progress, completed, failed, timed-out)
- Retry with increased timeout

**Residual Risk**: Low

---

### Risk 4: Agent Cost Explosion (HIGH)

**Risk**: When agent integration is added (Phase 2), agents consume excessive tokens.

**Likelihood**: Medium (agents are verbose by nature)
**Impact**: HIGH (budget overrun)
**Mitigation**:

- Token budgeting in claude-mpm (auto-summarization at 70%, 85%, 95% thresholds)
- Per-session cost caps
- Cost logging per operation
- Phase 2 concern -- not relevant until agent integration

**Residual Risk**: Medium (requires monitoring in Phase 2)

---

### Risk 5: Embedding Model Availability (MEDIUM)

**Risk**: First-run model download fails (network timeout, disk space, HuggingFace outage).

**Likelihood**: Low (model is well-cached, HuggingFace is reliable)
**Impact**: MEDIUM (workspace init fails, all indexing blocked until resolved)
**Mitigation**:

- Pre-download model during deployment/setup (Phase 1.0)
- Check for `~/.cache/huggingface/hub/` existence before first workspace init
- Clear error message when model download fails
- Minimum 1 GB free disk space check

**Residual Risk**: Low

---

### Risk 6: Agent Jailbreak / Sandbox Escape (MEDIUM)

**Risk**: Agent ignores session scope instructions, attempts to access files outside workspace.

**Likelihood**: Low (LLM generally compliant, but not guaranteed)
**Impact**: MEDIUM (containment breach)
**Mitigation**:

- Infrastructure-level enforcement (not prompt-only)
- Path validation at every filesystem access point
- Tool call interception and audit
- Network isolation for subprocess
- Phase 2 concern -- not relevant until agent integration

**Residual Risk**: Low (with code-level enforcement)

---

### Risk 7: Scale Unknowns (MEDIUM)

**Risk**: Performance characteristics change significantly with real-world workspaces (hundreds of files, multiple languages, large files).

**Likelihood**: High (we only have 2-file benchmarks)
**Impact**: MEDIUM (may need architecture adjustments)
**Mitigation**:

- Phase 1 includes benchmarking on representative real workspaces
- Timeout values are configurable, not hardcoded
- Index size monitoring per workspace
- Do not commit to Phase 2-4 timelines until Phase 1 data is available

**Residual Risk**: Medium (inherent uncertainty)

---

### Risk 8: Deployment Complexity (MEDIUM)

**Risk**: Multiple dependencies (FastAPI, mcp-vector-search, ChromaDB, sentence-transformers, HuggingFace model cache) make deployment fragile.

**Likelihood**: Medium
**Impact**: MEDIUM (operations burden)
**Mitigation**:

- Docker multi-stage build with all dependencies
- Health check endpoint that verifies mcp-vector-search CLI availability
- Pre-baked model cache in Docker image
- docker-compose for local development

**Residual Risk**: Medium (requires DevOps investment)

---

## 7. Implementation Recommendation

### 7.1 Phase 1: Workspace Registration & Indexing Service

This is the only phase we are committing to. It delivers:

- FastAPI service with workspace CRUD
- Subprocess-based indexing (init + index)
- Path validation and sandbox enforcement
- Audit logging
- Integration tests with security coverage

**Phase 1 subphases** (from IMPLEMENTATION_ROADMAP.md):

| Subphase | Scope                                                        | Duration            | Dependencies |
| -------- | ------------------------------------------------------------ | ------------------- | ------------ |
| 1.0      | Environment setup, CLI installation, subprocess verification | 2-3 days            | None         |
| 1.1      | FastAPI scaffold, WorkspaceIndexer class, config system      | 5-6 days            | 1.0          |
| 1.2      | Session/workspace CRUD endpoints, database schema            | 3-4 days            | 1.1          |
| 1.3      | Indexing operations (subprocess invocation, status tracking) | 5-6 days            | 1.1          |
| 1.4      | Path validator (sandbox enforcement)                         | 2-3 days            | 1.1          |
| 1.5      | Audit logging                                                | 2-3 days            | 1.2, 1.3     |
| 1.6      | Agent integration                                            | DEFERRED to Phase 2 | --           |
| 1.7      | Integration tests (>90% coverage, security suite)            | 5-7 days            | 1.2-1.5      |
| 1.8      | Documentation and release                                    | 2 days              | 1.7          |

**Critical path**: 1.0 -> 1.1 -> 1.3 -> 1.5 -> 1.7 -> 1.8
**Estimated duration**: 22-27 calendar days (3-4 weeks including Phase 1.0)
**Team**: 2 FTE engineers

### 7.2 What Phase 1 Does NOT Include

- Search REST API (search goes through Claude Code MCP)
- Agent integration (deferred to Phase 2)
- Incremental indexing optimization (mcp-vector-search handles this internally)
- Cost optimization / warm pools / query caching
- Multi-region deployment
- Auth/RBAC
- Rate limiting (beyond basic timeout enforcement)

### 7.3 Phase 1 Success Criteria

- [ ] Can register a workspace (path validation, sandbox check)
- [ ] Can index a workspace (subprocess init + index, status tracking)
- [ ] Can list and delete workspaces (cleanup including .mcp-vector-search/)
- [ ] Session/workspace isolation working (no cross-workspace access)
- [ ] 100% path traversal blocking in security tests
- [ ] > 90% test coverage
- [ ] All subprocess error cases handled (timeout, permission, corruption)
- [ ] Audit logging for all operations
- [ ] Docker image builds and runs
- [ ] docker-compose up works end-to-end

---

## 8. Future Considerations

These are potential future directions. None are committed. All depend on what we learn from Phase 1 in production.

### Search API (Possible Phase 2)

If Claude Code's native MCP search proves insufficient (e.g., we need REST access for the SvelteKit UI, or we need to combine search with agent context), we may build a search wrapper. This would likely be a thin FastAPI endpoint that invokes mcp-vector-search's MCP tools programmatically.

### Agent Integration (Planned Phase 2)

Custom `research-analyst` agent wrapping claude-mpm, with:

- Infrastructure-level sandbox enforcement (not prompt-based)
- Vector search context injection
- Token budgeting and cost tracking
- Audit trail for all agent actions

### Optimization (Possible Phase 3+)

- Warm session pools for agent reuse
- Query caching
- Semantic reranking
- Result deduplication
- Background/watch mode indexing

### Operations & Scale (Possible Phase 4+)

- TTL pruning for inactive workspaces
- Multi-instance deployment (Kubernetes)
- Distributed session state
- Encrypted audit logs
- Compliance reporting

**Timeline for these phases**: TBD. We will plan Phase 2 after Phase 1 is complete, deployed, and generating real usage data. Committing to Phase 2-4 timelines now would be speculative.

---

## 9. Anti-Patterns to Avoid

### DO NOT: Import mcp-vector-search as a Python Library

It is not designed for this. The subprocess CLI is the supported integration surface. Attempting to import internal modules will break on upgrades and is not thread-safe.

### DO NOT: Rely on Prompts for Sandbox Isolation

Agent instructions like "only access files in the project directory" are not enforceable. Agents can and do ignore prompt constraints. All filesystem restrictions must be enforced at the code level.

### DO NOT: Index Same Workspace Concurrently

ChromaDB uses SQLite with single-writer locking. Two simultaneous index operations on the same workspace will corrupt the database. The service must enforce mutual exclusion per workspace.

### DO NOT: Build What mcp-vector-search Already Provides

mcp-vector-search handles file discovery, chunking, embedding, storage, incremental indexing, and search. Our service is a thin orchestration layer -- not a reimplementation of indexing logic.

### DO NOT: Plan Phases 2-4 in Detail

We have small-project benchmarks and untested scale estimates. Planning detailed timelines for optimization, reranking, and multi-region deployment before Phase 1 is complete is premature. Ship Phase 1, learn from it, then plan the next increment.

### DO NOT: Use shell=True in subprocess calls

Always pass commands as a list to `subprocess.run()`. Never construct shell command strings. This prevents command injection vulnerabilities.

---

## 10. Key Documents

### Architecture & Integration

- `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` -- Definitive subprocess integration guide (v2.0)
- `docs/research2/RESEARCH_SUMMARY.md` -- Quick summary of subprocess research findings
- `docs/research2/mcp-vector-search-subprocess-integration-research.md` -- Full research with test results (1,500+ lines)

### Component Analysis

- `docs/research/claude-mpm-capabilities.md` -- Claude MPM capabilities and architecture (still valid)
- `docs/research/claude-mpm-sandbox-containment-plan.md` -- Security architecture (still valid)
- `docs/research/mcp-vector-search-capabilities.md` -- mcp-vector-search technical deep dive

### Implementation Planning

- `docs/plans/IMPLEMENTATION_ROADMAP.md` -- Master timeline and phase details

### Deprecated / Removed

- ~~`docs/research/mcp-vector-search-rest-api-proposal.md`~~ (deleted - library-based approach was abandoned)
- ~~`docs/plans/IMPLEMENTATION_PLAN.md`~~ (deleted - replaced by IMPLEMENTATION_ROADMAP.md)

---

**Status**: Ready for Phase 1 implementation.
**Decision**: BUILD -- subprocess-based architecture, Phase 1 only, learn before committing to more.
