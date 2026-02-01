# Verification Audit Report: Implementation Plans vs Research

**Audit Date**: 2026-02-01
**Auditor**: Claude Code Research Agent (Opus 4.5)
**Scope**: All 15 plan files in docs/plans/ vs all research sources in docs/research/ and docs/research2/
**Method**: Full cross-reference of claims, deliverables, dependencies, and acceptance criteria

---

## Overall Confidence: MEDIUM

The plans have been significantly improved by the subprocess architecture correction (v2.0 update). Phase 1 subphase plans (01_1_1 through 01_1_8) are well-structured with clear deliverables and subprocess-aware code templates. However, several critical issues remain:

1. **Stale research documents still in the tree** create confusion about which integration approach is correct
2. **IMPLEMENTATION_PLAN.md retains legacy library-embedding code snippets** despite the header disclaimer
3. **Phase 2-4 plans are thin** relative to Phase 1 detail, with vague acceptance criteria
4. **Missing rollback/backout plans** across all phases
5. **Two analysis artifacts (PLAN_VS_RESEARCH_ANALYSIS.md, IMPLEMENTATION_PLAN_ANALYSIS.md) are stale** -- they were written before the subprocess correction and still reference library-based patterns as correct

---

## Top 5 Critical Issues (Blocker / High)

### ISSUE-1: IMPLEMENTATION_PLAN.md Contains Active Library-Embedding Code [Blocker]

**Plan ref**: `IMPLEMENTATION_PLAN.md`, Section 1.1 (lines 202-230), Section 1.3 (lines 292-345)
**Research ref**: `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0), `docs/research2/RESEARCH_SUMMARY.md`

The IMPLEMENTATION_PLAN.md header says "REFERENCE ONLY" and notes the subprocess correction, but the body still contains:

- `VectorSearchManager singleton` pattern (Phase 1.1, line 209)
- `from mcp_vector_search import Client` verification step (Phase 1.0.2, line 88)
- `SessionIndexer` class using `self._vs_manager.indexer.index_directory()` (Phase 1.3, lines 320-345)
- `VectorSearchManager.search_engine.search()` calls (Phase 1.3, line 339)
- Per-session ChromaDB collection naming `session_{session_id}` (Phase 1.3, line 298)

**Why it matters**: Engineers who read the "reference" plan may follow the wrong integration pattern. The code templates will not work -- mcp-vector-search cannot be imported as a Python library.

**Recommended fix**: Either (a) delete the body of IMPLEMENTATION_PLAN.md and redirect entirely to IMPLEMENTATION_ROADMAP.md, or (b) add prominent `[DEPRECATED CODE]` markers around every code block.

---

### ISSUE-2: Stale Research Documents Not Deprecated [High]

**Plan ref**: `IMPLEMENTATION_ROADMAP.md`, Section "Research Document Integration" (lines 436-458)
**Research ref**: `docs/research/mcp-vector-search-packaging-installation.md` (line 12: "Python library integration (not CLI subprocess)"), `docs/research/PLAN_VS_RESEARCH_ANALYSIS.md` (line 44: "correctly adopts library approach")

Three research documents actively contradict the corrected subprocess architecture:

1. **`docs/research/mcp-vector-search-packaging-installation.md`**: Entire document (1,388 lines) describes library embedding. Executive summary line 16: "Approach: Python library integration (not CLI subprocess)". No deprecation notice.
2. **`docs/research/PLAN_VS_RESEARCH_ANALYSIS.md`**: States "Plan correctly adopts library approach (not embedding REST)" (line 44). Written pre-correction. No deprecation notice.
3. **`docs/research2/IMPLEMENTATION_PLAN_ANALYSIS.md`**: References "singleton ChromaDB manager" and "SessionIndexer wrapper class" (lines 131-148). Pre-correction analysis. No deprecation notice.

Only `docs/research/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v1) has a proper deprecation header.

**Why it matters**: New engineers following research references in the roadmap will encounter contradictory guidance with no warning.

**Recommended fix**: Add deprecation headers to all three files, similar to the v1 integration guide header.

---

### ISSUE-3: Missing Reference File (mcp-vector-search-rest-api-proposal.md) [High]

**Plan ref**: `IMPLEMENTATION_ROADMAP.md` line 443, `01-PHASE_1_FOUNDATION.md` line 436, `01_1_2-SESSION_MANAGEMENT.md` references "REST proposal Section 2.1"
**Research ref**: File `docs/research/mcp-vector-search-rest-api-proposal.md` does not exist on disk

Multiple plan files reference `docs/research/mcp-vector-search-rest-api-proposal.md` as a primary research source for session management endpoints and REST API design. This file does not exist in the repository. Glob search confirms absence.

**Why it matters**: Plans cite a non-existent document for API contract decisions. Engineers cannot trace the justification for session endpoint design.

**Recommended fix**: Either (a) locate and restore the file, (b) create it from the content that was used to write the plans, or (c) update all references to point to the actual source document.

---

### ISSUE-4: combined-architecture-recommendations.md Not Updated for Subprocess [High]

**Plan ref**: `02-PHASE_2_COST_QUALITY.md` line 107, `03-PHASE_3_RERANKING_UX.md` line 71, `04-PHASE_4_OPERATIONS_SCALE.md` line 74
**Research ref**: `docs/research/combined-architecture-recommendations.md` Section 2.4 (line 148: "Use mcp-vector-search's built-in async indexing APIs directly")

The combined-architecture-recommendations.md still describes the library-based architecture:

- Section 2.1: "Wrapper service importing mcp-vector-search as library" (line 116)
- Section 2.4: "Use mcp-vector-search's built-in async indexing APIs directly" (line 147)
- Section 4.1: MVP flow includes `mcp-vector-search.index()` and `mcp-vector-search.search()` function calls (lines 253, 268)

Phases 2-4 plans reference this document for their research justification. The document is not deprecated and contains active contradictions.

**Why it matters**: Phase 2-4 architectural decisions are justified by a document that describes the wrong integration model. Search via REST API wrapper (Phase 2.3) and warm pools of Claude subprocesses (Phase 2.4) need to be re-validated against the subprocess architecture.

**Recommended fix**: Update combined-architecture-recommendations.md with a v1.2 correction note, or add deprecation header and create a new v2.0 document.

---

### ISSUE-5: Phase 2 Search Architecture Undefined [High]

**Plan ref**: `02-PHASE_2_COST_QUALITY.md` (all sections), `01_1_6-AGENT_INTEGRATION.md` lines 38-65
**Research ref**: `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (no search section), `docs/research2/RESEARCH_SUMMARY.md` line 74 ("No embedded library")

Phase 1 correctly defers search to Phase 2. The agent integration plan (01_1_6) describes search flowing through "Claude Code's MCP interface to mcp-vector-search." However:

- Phase 2 plan (02-PHASE_2_COST_QUALITY.md) still shows REST search endpoints: `POST /api/sessions/{id}/search` (line 62)
- Phase 2.2 (Query Caching) assumes search goes through the service layer
- Phase 2.3 (Advanced Filtering) shows REST request body with filters
- No research document describes how Claude Code MCP interface-based search integrates with research-mind-service
- The MCP-based search path (Claude Code -> mcp-vector-search via MCP protocol) would bypass the service entirely, making caching and filtering at the service layer impossible

**Why it matters**: The fundamental search architecture for Phase 2+ is unresolved. Either search goes through the service (requires a REST wrapper that contradicts the subprocess decision) or through MCP (requires rethinking caching, filtering, and cost controls).

**Recommended fix**: Create a Phase 2 architecture decision record that resolves: (a) does search go through research-mind-service or Claude Code MCP, (b) how are caching and filtering implemented in each scenario, (c) how is agent integration layered on top.

---

## Top 5 Omissions

### OMISSION-1: No Rollback/Backout Plan for Any Phase

**Plan ref**: All phase documents (00 through 04)
**Research ref**: N/A (not covered in research)

None of the 15 plan files include a rollback or backout plan. Phase gates have go/no-go criteria but no "what happens if we fail the gate" procedure beyond "address blockers."

**Severity**: High
**Recommended fix**: Add a "Rollback Plan" section to each phase overview (01, 02, 03, 04) specifying: what to revert, how to revert, and the fallback state.

---

### OMISSION-2: No Incident Response or Runbook

**Plan ref**: `04-PHASE_4_OPERATIONS_SCALE.md` (mentions monitoring/alerting but no runbook)
**Research ref**: N/A

No plan document mentions incident response procedures, on-call rotation, or operational runbooks. Phase 4 mentions "monitoring and alerting operational" as a success criterion but provides no detail.

**Severity**: Medium (only relevant at Phase 4, but should be planned earlier)

---

### OMISSION-3: No Data Migration Strategy Between Phases

**Plan ref**: All phase transitions
**Research ref**: N/A

Plans assume smooth phase transitions but never address: How do existing sessions survive a Phase 1 -> Phase 2 upgrade? If the index format changes, is re-indexing required? If the database schema changes, what migration path exists for in-flight sessions?

**Severity**: Medium

---

### OMISSION-4: No Secrets Management Plan

**Plan ref**: `01_1_5-AUDIT_LOGGING.md`, `01_1_4-PATH_VALIDATOR.md`
**Research ref**: `docs/research/claude-mpm-sandbox-containment-plan.md` Section 1.2 (mentions "Store secrets in logs" as MEDIUM threat)

The sandbox containment research identifies credential exposure risk, but no plan document addresses secrets management: How are database credentials stored? How is the service API secured? What happens to secrets in audit logs? Phase 1.0 `.env.example` template includes `DATABASE_URL` with a password, but no guidance on production secrets management.

**Severity**: Medium

---

### OMISSION-5: No Performance Testing Plan for Large Workspaces

**Plan ref**: `01_1_3-INDEXING_OPERATIONS.md` (mentions timeout of 300-600s for large projects)
**Research ref**: `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` Section "Performance & Optimization" (line 626: "Estimated Scaling (not tested)")

Research explicitly states that performance estimates for large projects are "not tested." Plans assume 300-600s timeouts but have no performance testing task to validate these assumptions. Phase 1.7 integration tests use small projects (2-file test cases).

**Severity**: Medium

---

## Top 5 Sequencing/Dependency Errors

### SEQ-1: Phase 1.5 Prerequisite Lists Both 1.2 AND 1.3, But Header Says Only 1.2

**Plan ref**: `01_1_5-AUDIT_LOGGING.md` line 7: "Prerequisite: Phase 1.2 (sessions), Phase 1.3 (indexing operations)"
**Plan ref**: `01-PHASE_1_FOUNDATION.md` line 69: "1.5 ... can start after 1.2"

The Phase 1 overview says 1.5 can start after 1.2, but the detailed plan says it needs both 1.2 AND 1.3 (because it logs subprocess invocation details from indexing operations).

**Severity**: Low (minor scheduling confusion)
**Fix**: Clarify that 1.5 can start after 1.2 for session audit logging, but subprocess audit logging requires 1.3 integration.

---

### SEQ-2: Phase 1.7 Duration Inconsistency

**Plan ref**: `01_1_7-INTEGRATION_TESTS.md` line 5: "5-7 business days"
**Plan ref**: `01-PHASE_1_FOUNDATION.md` line 71: "4-5 days"
**Plan ref**: `IMPLEMENTATION_ROADMAP.md` line 69: "5-7 days"
**Plan ref**: `IMPLEMENTATION_PLAN.md` line 481: "5-7 days"

Phase 1.7 is estimated at 4-5 days in the Phase 1 overview but 5-7 days in the detailed plan and roadmap. The critical path calculation in `01-PHASE_1_FOUNDATION.md` uses 4-5 days.

**Severity**: Low (impacts timeline accuracy)
**Fix**: Align to 5-7 days everywhere since agent tests are deferred but subprocess tests were added.

---

### SEQ-3: Phase 2 Assumes Search Exists But Phase 1 Defers It

**Plan ref**: `02-PHASE_2_COST_QUALITY.md` line 62: "POST /api/sessions/{id}/search"
**Plan ref**: `01_1_3-INDEXING_OPERATIONS.md` line 36: "Search endpoints (POST /search) - will use Claude Code MCP interface"
**Plan ref**: `01_1_6-AGENT_INTEGRATION.md` line 56: "search queries will use Claude Code's native MCP interface"

Phase 2 plan references search endpoints that do not exist after Phase 1. The Phase 2 plan needs to explicitly include "build search integration" as a prerequisite task before caching, filtering, and warm pools can be implemented.

**Severity**: High (blocks Phase 2 execution)
**Fix**: Add Phase 2.0 "Search Integration Architecture" task as first deliverable.

---

### SEQ-4: Phase 1.1 Duration Inconsistency Affects Critical Path

**Plan ref**: `01_1_1-SERVICE_ARCHITECTURE.md` line 4: "5-6 business days"
**Plan ref**: `IMPLEMENTATION_ROADMAP.md` line 36: "5-6 days"
**Plan ref**: `IMPLEMENTATION_PLAN.md` line 1017: "Day 1-2" (implies 2 days)

The original IMPLEMENTATION_PLAN.md day-by-day schedule allocates only 2 days for Phase 1.1, while the detailed plan and roadmap say 5-6 days. This discrepancy exists because IMPLEMENTATION_PLAN.md was not fully updated.

**Severity**: Low (IMPLEMENTATION_PLAN.md is marked as reference-only)

---

### SEQ-5: Operational Monitoring Deferred Until Phase 4 But Needed Earlier

**Plan ref**: `04-PHASE_4_OPERATIONS_SCALE.md` line 52: "Monitoring/alerting integration"
**Research ref**: `docs/research/combined-architecture-recommendations.md` (mentions monitoring throughout)

Basic metrics and logging are implicit in Phase 1.5 (audit logging), but structured metrics (request latency, subprocess duration histograms, error rates) are not introduced until Phase 4. Phase 2 cost optimization targets ($0.05/query, 40% reduction) cannot be measured without metrics infrastructure.

**Severity**: Medium
**Fix**: Add basic metrics collection (Prometheus/StatsD) to Phase 1.1 or Phase 2.0.

---

## Findings Table

| ID    | Severity | Type          | Plan Ref                                                         | Research Ref                                                  | Why It Matters                                                                    | Recommended Fix                                                                                |
| ----- | -------- | ------------- | ---------------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| F-001 | Blocker  | CONTRADICTION | IMPLEMENTATION_PLAN.md Sections 1.1, 1.3 (code blocks)           | research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md v2.0         | Library-embedding code will not work; misleads engineers                          | Delete body or add [DEPRECATED CODE] markers to all code blocks                                |
| F-002 | High     | CONTRADICTION | IMPLEMENTATION_ROADMAP.md line 443                               | research/mcp-vector-search-packaging-installation.md line 16  | Stale research describes wrong architecture without deprecation                   | Add deprecation headers to 3 stale research files                                              |
| F-003 | High     | OMISSION      | IMPLEMENTATION_ROADMAP.md line 443, 01_1_2-SESSION_MANAGEMENT.md | Filesystem: file does not exist                               | Referenced research doc missing from repo                                         | Locate, restore, or update references                                                          |
| F-004 | High     | CONTRADICTION | 02-PHASE_2_COST_QUALITY.md line 107                              | research/combined-architecture-recommendations.md line 148    | Phase 2-4 justified by library-based doc                                          | Update or deprecate combined-architecture-recommendations.md                                   |
| F-005 | High     | VAGUE         | 02-PHASE_2_COST_QUALITY.md lines 62-73                           | 01_1_6-AGENT_INTEGRATION.md lines 56-65                       | Search architecture for Phase 2+ is undefined                                     | Create Phase 2 architecture decision record                                                    |
| F-006 | High     | OMISSION      | All phase docs                                                   | N/A                                                           | No rollback plan for any phase                                                    | Add rollback section to each phase overview                                                    |
| F-007 | Medium   | OMISSION      | 04-PHASE_4_OPERATIONS_SCALE.md                                   | N/A                                                           | No incident response or runbook                                                   | Plan runbook creation in Phase 4                                                               |
| F-008 | Medium   | OMISSION      | All phase transitions                                            | N/A                                                           | No data migration strategy                                                        | Document migration path between phases                                                         |
| F-009 | Medium   | OMISSION      | 01_1_5-AUDIT_LOGGING.md, 01_1_4-PATH_VALIDATOR.md                | research/claude-mpm-sandbox-containment-plan.md Section 1.2   | No secrets management plan                                                        | Add secrets management to Phase 1.8 or Phase 4.3                                               |
| F-010 | Medium   | OMISSION      | 01_1_3-INDEXING_OPERATIONS.md                                    | research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md line 626     | No performance testing for large workspaces                                       | Add performance testing task to Phase 1.7 or Phase 2                                           |
| F-011 | Medium   | SEQUENCING    | 02-PHASE_2_COST_QUALITY.md                                       | 01_1_6-AGENT_INTEGRATION.md                                   | Phase 2 assumes search endpoints that Phase 1 defers                              | Add Phase 2.0 search integration task                                                          |
| F-012 | Medium   | SEQUENCING    | 04-PHASE_4_OPERATIONS_SCALE.md                                   | combined-architecture-recommendations.md                      | Metrics deferred to Phase 4 but needed for Phase 2 cost targets                   | Add basic metrics to Phase 1.1 or 2.0                                                          |
| F-013 | Low      | VAGUE         | 01_1_5-AUDIT_LOGGING.md line 7                                   | 01-PHASE_1_FOUNDATION.md line 69                              | Prerequisite inconsistency for Phase 1.5                                          | Clarify split prerequisites                                                                    |
| F-014 | Low      | VAGUE         | 01_1_7-INTEGRATION_TESTS.md line 5                               | 01-PHASE_1_FOUNDATION.md line 71                              | Duration estimate inconsistency (4-5 vs 5-7 days)                                 | Align to 5-7 days                                                                              |
| F-015 | Low      | UNJUSTIFIED   | 02-PHASE_2_COST_QUALITY.md: "$0.05/query"                        | No research source                                            | Cost target has no baseline measurement or methodology                            | Define baseline and measurement methodology                                                    |
| F-016 | Low      | UNJUSTIFIED   | 03-PHASE_3_RERANKING_UX.md: "95%+ precision"                     | No research source                                            | Precision target has no evaluation framework defined                              | Define evaluation methodology and test set                                                     |
| F-017 | Low      | CONTRADICTION | IMPLEMENTATION_PLAN.md line 64: "SQLite for session storage"     | CLAUDE.md: "Database: Postgres (port 5432)"                   | SQLite vs PostgreSQL inconsistency in original plan                               | Already resolved in detailed plans (PostgreSQL used), but original plan body still says SQLite |
| F-018 | Medium   | RISK          | 01_1_3-INDEXING_OPERATIONS.md                                    | research2/subprocess-integration-research.md line 81          | ChromaDB single-writer constraint not enforced in plan                            | Add mutex/lock for per-workspace indexing in Phase 1.3                                         |
| F-019 | Medium   | VAGUE         | 01_1_4-PATH_VALIDATOR.md                                         | research/claude-mpm-sandbox-containment-plan.md Section 2.3   | Network isolation (disable curl/wget) not in any Phase 1 plan                     | Clarify if network isolation is Phase 1 or Phase 2 scope                                       |
| F-020 | Low      | UNJUSTIFIED   | IMPLEMENTATION_ROADMAP.md line 20: "60-70% cost reduction"       | research/combined-architecture-recommendations.md Section 3.1 | Cost savings claim from library-based document; may not apply to subprocess model | Re-validate cost model for subprocess architecture                                             |

---

## Summary of Architecture Correction Completeness

The subprocess architecture correction was applied to the following files with varying completeness:

| File                              | Correction Applied                                | Residual Issues                                                           |
| --------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------- |
| IMPLEMENTATION_ROADMAP.md         | YES - Header, timeline, critical path updated     | References stale research docs without noting deprecation                 |
| IMPLEMENTATION_PLAN.md            | PARTIAL - Header added but body unchanged         | Code blocks still show library embedding patterns                         |
| 00-PHASE_1_0_ENVIRONMENT_SETUP.md | YES - Fully subprocess-based                      | Minor: still references "~2.5GB dependencies" which includes library deps |
| 01-PHASE_1_FOUNDATION.md          | YES - Subprocess throughout                       | Clean                                                                     |
| 01_1_1-SERVICE_ARCHITECTURE.md    | YES - WorkspaceIndexer subprocess manager         | Clean                                                                     |
| 01_1_2-SESSION_MANAGEMENT.md      | YES - `.mcp-vector-search/` directory checking    | Clean                                                                     |
| 01_1_3-INDEXING_OPERATIONS.md     | YES - Subprocess orchestration                    | Clean                                                                     |
| 01_1_4-PATH_VALIDATOR.md          | YES - Validates paths before subprocess `cwd`     | Clean                                                                     |
| 01_1_5-AUDIT_LOGGING.md           | YES - Logs subprocess events                      | Clean                                                                     |
| 01_1_6-AGENT_INTEGRATION.md       | YES - Deferred with correct MCP architecture note | Clean                                                                     |
| 01_1_7-INTEGRATION_TESTS.md       | YES - Subprocess-specific test categories         | Clean                                                                     |
| 01_1_8-DOCUMENTATION_RELEASE.md   | YES - References subprocess guide                 | Clean                                                                     |
| 02-PHASE_2_COST_QUALITY.md        | NOT UPDATED - Still shows REST search endpoints   | Contradicts Phase 1 deferral of search                                    |
| 03-PHASE_3_RERANKING_UX.md        | NOT UPDATED - Implicitly assumes REST search      | No subprocess-specific content                                            |
| 04-PHASE_4_OPERATIONS_SCALE.md    | NOT UPDATED - Generic operations plan             | No subprocess-specific content                                            |

**Verdict**: Phase 1 subphase plans (01_1_1 through 01_1_8) are well-corrected. Phase 2-4 and the original IMPLEMENTATION_PLAN.md have not been fully updated.
