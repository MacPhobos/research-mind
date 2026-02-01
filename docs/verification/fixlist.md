# Prioritized Fix List

**Audit Date**: 2026-02-01
**Format**: [Priority] Task (file:section) / Reason / Evidence / Proposed Patch

---

## P0 - Must Fix Before Phase 1 Execution

### [P0] Deprecate stale research documents (docs/research/)

- **Reason**: Three research files describe the wrong integration architecture (library embedding) with no deprecation notice. Engineers following research references in the roadmap will get contradictory guidance.
- **Evidence**:
  - `docs/research/mcp-vector-search-packaging-installation.md` line 16: "Approach: Python library integration (not CLI subprocess)"
  - `docs/research/PLAN_VS_RESEARCH_ANALYSIS.md` line 44: "correctly adopts library approach"
  - `docs/research2/IMPLEMENTATION_PLAN_ANALYSIS.md` line 131: "singleton ChromaDB manager"
  - Contrast with `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` v2.0 (subprocess-based)
- **Proposed patch**: Add the following header to each of the 3 files (after line 1):

```markdown
> **DEPRECATED (2026-02-01)**: This document describes an incorrect integration approach.
> mcp-vector-search runs as a CLI subprocess, NOT as an embedded Python library.
> See `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0) for the correct approach.
```

---

### [P0] Locate or replace missing research file (mcp-vector-search-rest-api-proposal.md)

- **Reason**: Multiple plan files reference `docs/research/mcp-vector-search-rest-api-proposal.md` for session endpoint design justification. File does not exist on disk.
- **Evidence**:
  - `IMPLEMENTATION_ROADMAP.md` line 443
  - `01-PHASE_1_FOUNDATION.md` line 436
  - `01_1_2-SESSION_MANAGEMENT.md` (references "REST proposal Section 2.1")
  - Glob search: no matches for this filename
- **Proposed patch**:
  - Option A: Locate file in git history (`git log --all --full-history -- "*rest-api-proposal*"`) and restore
  - Option B: Update references in plan files to point to `docs/research/combined-architecture-recommendations.md` Section 4.1 (which contains similar MVP endpoint design)
  - Option C: Create a brief replacement document extracting relevant content from existing research

---

### [P0] Add per-workspace indexing mutex to Phase 1.3 plan

- **Reason**: Research confirms ChromaDB single-writer constraint. Concurrent indexing of the SAME workspace will corrupt the index. No locking mechanism is described in the plan.
- **Evidence**:
  - `docs/research2/RESEARCH_SUMMARY.md` line 81: "Don't index same workspace from multiple processes simultaneously"
  - `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` lines 680-685: unsafe pattern example
  - `01_1_3-INDEXING_OPERATIONS.md`: no mutex or lock mechanism mentioned
- **Proposed patch**: Add to `01_1_3-INDEXING_OPERATIONS.md` Task 1.3.2 or create new task:

```markdown
### Task 1.3.X: Per-Workspace Indexing Lock (2-4 hours)

**Objective**: Prevent concurrent subprocess invocations for the same workspace

**Implementation**:

- Maintain in-memory dict of currently-indexing workspace IDs
- Before spawning subprocess, check if workspace is already indexing
- If already indexing, return 409 Conflict with message
- Release lock on subprocess completion (success or failure)
- Handle lock cleanup on service restart (stale locks)

**Research ref**: research2/RESEARCH_SUMMARY.md line 81 (ChromaDB single-writer)
```

---

### [P0] Document project root detection risk

- **Reason**: mcp-vector-search walks UP the directory tree from cwd to find project root. If a workspace directory is inside a git repository, it will use the parent .git directory as project root instead of the workspace itself, creating the index in the wrong location.
- **Evidence**:
  - `docs/research2/mcp-vector-search-subprocess-integration-research.md` Section 2.1 lines 216-238: detection algorithm checks for `.git` first
  - Not addressed in any plan document
- **Proposed patch**: Add note to `01_1_3-INDEXING_OPERATIONS.md`:

```markdown
**IMPORTANT**: mcp-vector-search detects project root by walking UP the directory tree
looking for indicators (.git, .mcp-vector-search, pyproject.toml, etc.). The init command
MUST be run BEFORE index, because init creates .mcp-vector-search/ which becomes the
primary indicator. If workspace is nested inside a git repo, ensure init is called first
so .mcp-vector-search/ takes priority. Alternatively, use --project-root flag if available.

Test case: Create workspace inside a git repo, verify index is created in workspace (not repo root).
```

---

## P1 - Must Fix Before Phase 2 Planning

### [P1] Resolve Phase 2 search architecture (02-PHASE_2_COST_QUALITY.md)

- **Reason**: Phase 2 plan describes REST search endpoints but Phase 1 defers search to Claude Code MCP interface. These are incompatible architectures. Caching and filtering cannot be implemented without knowing the search path.
- **Evidence**:
  - `02-PHASE_2_COST_QUALITY.md` line 62: `POST /api/sessions/{id}/search` with filters
  - `01_1_6-AGENT_INTEGRATION.md` lines 56-65: "search queries will use Claude Code's native MCP interface"
  - `01_1_3-INDEXING_OPERATIONS.md` line 36: "Search endpoints - will use Claude Code MCP interface"
- **Proposed patch**: Add Phase 2.0 task at top of `02-PHASE_2_COST_QUALITY.md`:

```markdown
### 2.0: Search Integration Architecture Decision (3-5 days) - PREREQUISITE

**Problem**: Phase 1 defers search to Phase 2. The search path must be defined before
caching, filtering, and agent integration can be implemented.

**Options**:
A) Claude Code MCP -> mcp-vector-search (search bypasses service)

- Pro: Native MCP integration, no REST wrapper needed
- Con: Cannot cache/filter at service layer, agent is outside service control
  B) research-mind-service REST wrapper -> subprocess search
- Pro: Service controls caching, filtering, audit logging
- Con: Requires implementing search in service, contradicts deferral decision
  C) Hybrid: Service triggers agent, agent uses MCP for search, results flow back through service
- Pro: Agent gets MCP search, service gets audit/caching layer
- Con: Complex architecture, two integration points

**Decision required BEFORE Phase 2 implementation begins.**
```

---

### [P1] Update combined-architecture-recommendations.md for subprocess model

- **Reason**: This document is the primary research source for Phases 2-4 planning. It describes library-based architecture throughout. Phase 2-4 plans cite it without noting the discrepancy.
- **Evidence**:
  - `docs/research/combined-architecture-recommendations.md` line 116: "Wrapper service importing mcp-vector-search as library"
  - `docs/research/combined-architecture-recommendations.md` line 148: "Use mcp-vector-search's built-in async indexing APIs directly"
  - `02-PHASE_2_COST_QUALITY.md` line 107: cites this document
  - `03-PHASE_3_RERANKING_UX.md` line 71: cites this document
  - `04-PHASE_4_OPERATIONS_SCALE.md` line 74: cites this document
- **Proposed patch**: Add correction note at top of file (after line 8):

```markdown
## Correction Note (v1.2) - 2026-02-01

**IMPORTANT**: This document was written before the subprocess architecture correction.
All references to "importing mcp-vector-search as library", "mcp-vector-search.index()",
and "mcp-vector-search.search()" are INCORRECT.

The correct integration approach is subprocess-based. See:

- `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0)

**Sections still valid**: Cost/latency strategies (Section 3), anti-patterns (Section 2.2-2.5),
phase structure (Sections 5-9) -- but implementation details differ.

**Sections outdated**: Section 2.1 (wrapper approach), Section 2.4 (built-in APIs),
Section 4.1 (MVP flow with function calls).
```

---

### [P1] Clean up or delete IMPLEMENTATION_PLAN.md body

- **Reason**: Header says "REFERENCE ONLY" but code blocks actively show library embedding patterns (VectorSearchManager, SessionIndexer, ChromaDB collections). New engineers may follow these patterns.
- **Evidence**:
  - `IMPLEMENTATION_PLAN.md` line 88: "Verify imports: from mcp_vector_search import Client"
  - `IMPLEMENTATION_PLAN.md` lines 320-345: SessionIndexer class using embedded library
  - `IMPLEMENTATION_PLAN.md` line 209: "VectorSearchManager singleton"
- **Proposed patch**: Replace the body (lines 47 onward) with:

```markdown
## Content Removed

The detailed plan content has been moved to individual phase documents.
See IMPLEMENTATION_ROADMAP.md for the master index.

The original content contained library-embedding code examples that are
incompatible with the current subprocess-based architecture and has been
removed to prevent confusion.

**Historical record**: Available in git history prior to this cleanup.
```

---

### [P1] Add basic metrics infrastructure to Phase 2 (or late Phase 1)

- **Reason**: Phase 2 cost optimization targets ($0.05/query, 40% reduction, cache hit rate >40%) require measurement infrastructure that does not exist in Phase 1 plans.
- **Evidence**:
  - `02-PHASE_2_COST_QUALITY.md` lines 18-20: measurable targets with no measurement plan
  - `04-PHASE_4_OPERATIONS_SCALE.md` line 52: monitoring deferred to Phase 4
  - No metrics collection in Phase 1 plans
- **Proposed patch**: Add to `02-PHASE_2_COST_QUALITY.md` as prerequisite:

```markdown
### 2.0.1: Metrics Foundation (2 days)

**Deliverables**:

- Request latency histogram (per endpoint)
- Subprocess duration tracking (per operation type)
- Cache hit/miss counter (for Phase 2.2)
- Cost estimation framework (token counting or proxy metric)
- Basic Prometheus/StatsD integration OR structured JSON logs with metrics fields
```

---

## P2 - Should Fix Before Phase Execution

### [P2] Add rollback plan section to each phase overview

- **Reason**: No phase document includes a rollback procedure. Go/no-go gates say "address blockers" but don't specify what happens if the phase is abandoned.
- **Evidence**: All 4 phase overview files (01, 02, 03, 04) lack rollback sections
- **Proposed patch**: Add to each phase overview document:

```markdown
## Rollback Plan

If this phase fails its gate criteria:

1. **Revert**: Roll back to last stable phase tag (git tag phase-N-complete)
2. **Data**: [Phase-specific data migration notes]
3. **State**: Service returns to Phase N-1 functionality
4. **Communication**: Notify stakeholders within 24 hours of gate failure
```

---

### [P2] Define evaluation methodology for precision targets (Phase 2-3)

- **Reason**: Plans claim 90%+ and 95%+ precision targets but no evaluation framework is defined anywhere in research or plans.
- **Evidence**:
  - `02-PHASE_2_COST_QUALITY.md` line 18: "90%+ precision (manual evaluation)"
  - `03-PHASE_3_RERANKING_UX.md` line 14: "95%+ precision"
  - No evaluation methodology defined in any research document
- **Proposed patch**: Add to Phase 2 plan:

```markdown
### Evaluation Framework for Precision Targets

**Test Set**: 50 representative queries across 3 codebases
**Evaluation**: Manual relevance scoring (1-5 scale) by 2 reviewers
**Precision Formula**: (relevant results in top 10) / 10
**Baseline Measurement**: Conduct before Phase 2 optimizations begin
**Frequency**: Re-evaluate at each Phase gate
```

---

### [P2] Add network isolation scope clarification

- **Reason**: Network isolation (disable curl/wget in agent subprocess) is described in research but its phase assignment is unclear in plans.
- **Evidence**:
  - `docs/research/claude-mpm-sandbox-containment-plan.md` Section 2.3: NetworkIsolation class with env manipulation
  - `01_1_6-AGENT_INTEGRATION.md` lines 69-74: mentions network disabled but phase is deferred
  - `01_1_4-PATH_VALIDATOR.md`: only covers path validation, not network
  - No Phase 2 plan includes network isolation as a deliverable
- **Proposed patch**: Add to `01_1_6-AGENT_INTEGRATION.md` Phase 2 Design Notes:

```markdown
### Network Isolation (Phase 2 Scope)

When agent integration is implemented in Phase 2, include:

- Subprocess environment stripping (remove HTTP_PROXY, etc.)
- SESSION_DIR environment variable for workspace scoping
- Timeout management (300s default)
- Audit logging of agent subprocess invocations
- Reference: research/claude-mpm-sandbox-containment-plan.md Section 2.3
```

---

### [P2] Address distributed session state feasibility (Phase 4)

- **Reason**: Phase 4 plans Redis-based distributed session state, but per-workspace .mcp-vector-search/ directories are local filesystem artifacts. Distributing sessions across nodes requires either shared filesystem (NFS, EFS) or re-indexing on target node.
- **Evidence**:
  - `04-PHASE_4_OPERATIONS_SCALE.md` line 64: "Distributed session state (Redis)"
  - `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md`: index is local filesystem only
  - No research on distributed indexing strategies
- **Proposed patch**: Add note to `04-PHASE_4_OPERATIONS_SCALE.md`:

```markdown
**Architecture Note**: mcp-vector-search indexes are stored in local .mcp-vector-search/
directories. For multi-instance deployment, session affinity (sticky sessions) is required
to route requests to the node holding the index. Alternatives:

- Shared filesystem (NFS, EFS) for workspace directories
- Re-index on failover (accept cold-start latency)
- Session migration with index copy
  This requires research and architecture decision BEFORE Phase 4 implementation.
```

---

### [P2] Add corruption recovery procedure to Phase 1.3

- **Reason**: Research documents corruption as a known error condition but plans do not include a recovery procedure.
- **Evidence**:
  - `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` lines 548-552: "Delete .mcp-vector-search/ directory and re-run init"
  - `01_1_3-INDEXING_OPERATIONS.md`: mentions error handling but no explicit corruption recovery
- **Proposed patch**: Add to `01_1_3-INDEXING_OPERATIONS.md`:

```markdown
### Corruption Recovery Procedure

If indexing fails with "Index corruption detected" error:

1. Delete workspace/.mcp-vector-search/ directory
2. Re-run init + index subprocess flow
3. Log corruption event to audit log with workspace_id
4. Return 500 with message "Index rebuilt after corruption"

Implementation: Add to indexing_service.py error handling (try init+index, on corruption error, delete dir and retry once).
```

---

### [P2] Add secrets management guidance to Phase 1.8

- **Reason**: .env.example includes DATABASE_URL with password. No guidance on production secrets management.
- **Evidence**:
  - `00-PHASE_1_0_ENVIRONMENT_SETUP.md` line 313: `DATABASE_URL=postgresql://postgres:password@localhost:5432/research_mind` <!-- pragma: allowlist secret -->
  - `research/claude-mpm-sandbox-containment-plan.md` Section 1.2: "Store secrets in logs" identified as MEDIUM threat
  - No plan addresses secrets rotation, vault integration, or audit log sanitization
- **Proposed patch**: Add to `01_1_8-DOCUMENTATION_RELEASE.md`:

```markdown
### Secrets Management

- .env files must NOT be committed (already in .gitignore)
- Production: Use environment variables from orchestrator (K8s secrets, Docker secrets)
- Audit logs must NOT contain database credentials or API keys
- Document in README: "For production, use [K8s secrets / Docker secrets / Vault]"
```

---

## Summary

| Priority  | Count  | Description                                                                   |
| --------- | ------ | ----------------------------------------------------------------------------- |
| P0        | 4      | Must fix before Phase 1 execution (blockers and high-risk omissions)          |
| P1        | 4      | Must fix before Phase 2 planning (architectural decisions and source cleanup) |
| P2        | 5      | Should fix before respective phase execution (quality and completeness)       |
| **Total** | **13** | Actionable fix items                                                          |

**Estimated effort**: P0 items = 4-8 hours, P1 items = 8-16 hours, P2 items = 8-12 hours
**Total estimated effort**: 20-36 hours of plan/documentation updates (no code changes required)
