# Documentation Refactor Plan: Subprocess-Based Architecture

**Status**: PENDING APPROVAL
**Date Created**: 2026-01-31
**Scope**: Replace library embedding assumptions with subprocess integration approach

---

## Executive Summary

The recent research confirmed that mcp-vector-search **cannot be embedded as a library** in research-mind-service. Instead, it must run as a subprocess that research-mind-service spawns on demand.

This refactor updates all documentation to reflect this architecture change while maintaining consistency across research, research2, and plans directories.

---

## Files to Update (15 total)

### ❌ Completely Replace (2 files)

These files are fundamentally based on incorrect assumptions and should be rewritten:

1. **`docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md`**

   - **Current State**: Assumes mcp-vector-search can be imported as Python library with ChromaDB, VectorSearchManager classes
   - **Action**: Replace with subprocess integration guide based on research findings
   - **New Content**:
     - Architecture diagram: research-mind-service → subprocess → mcp-vector-search
     - Exact invocation pattern from research (init, then index)
     - Error handling and exit codes
     - Logging and debugging strategies
     - Integration patterns for FastAPI service

2. **`docs/research/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md`**
   - **Current State**: Same incorrect assumptions as research2 version
   - **Action**: Mark as DEPRECATED or replace with cross-reference to research2 version
   - **Recommendation**: Point to research2 as source of truth, keep this as historical record

### ⚠️ Significantly Update (6 files)

These files have architecture sections that assume library embedding and need substantial revision:

3. **`docs/plans/01_1_1-SERVICE_ARCHITECTURE.md`**

   - **Current Issue**: References "VectorSearchManager singleton" and model caching within service
   - **Update**:
     - Replace singleton pattern with subprocess management pattern
     - Index storage now happens in workspace directory (not service memory)
     - Model caching happens in mcp-vector-search subprocess (not service)
     - Session model no longer needs index_stats fields (different tracking needed)
   - **New Section**: "Workspace Indexing Subprocess Pattern"

4. **`docs/plans/01_1_2-SESSION_MANAGEMENT.md`**

   - **Current Issue**: May assume index state tracking in Session model
   - **Update**:
     - Session model tracks workspace registration only
     - Index status tracked separately (in `.mcp-vector-search/` directory, not DB)
     - Acceptance criteria updated to reflect subprocess-based verification

5. **`docs/plans/01_1_3-VECTOR_SEARCH_API.md`**

   - **Current Issue**: Assumes REST wrapper around Python API
   - **Update**:
     - API now handles subprocess orchestration, not Python API calls
     - Search functionality deferred (Phase 2 or later when Claude Code integration available)
     - API focuses on workspace indexing operations (POST /workspaces/{id}/index)
     - Error handling reflects subprocess exit codes, not Python exceptions

6. **`docs/plans/01_1_1-SERVICE_ARCHITECTURE.md` (Architecture Section)**

   - **Current Issue**: Singleton model and threading assumptions
   - **Update**: Subprocess lifecycle management instead of singleton
   - **New Pattern**:
     ```
     Request: POST /workspaces/{id}/index
     Service: Spawn subprocess with timeout
     Subprocess: mcp-vector-search init/index
     Response: JSON with success/failure, index metadata
     ```

7. **`docs/plans/01_1_6-AGENT_INTEGRATION.md`**

   - **Current Issue**: May assume direct API calls to embedded mcp-vector-search
   - **Update**: Agent integration deferred to later phase (search functionality depends on Claude Code MCP)
   - **New Content**: Placeholder for Phase 2 integration with claude-mpm

8. **`docs/plans/01_1_8-DOCUMENTATION_RELEASE.md`**
   - **Current Issue**: May reference library-based examples
   - **Update**: Examples now show subprocess-based integration patterns

### 📝 Minor Updates (5 files)

These files have references to the old architecture but don't need complete rewrites:

9. **`docs/plans/01-PHASE_1_FOUNDATION.md`**

   - Update critical path diagram
   - Clarify that subphases 1-3 focus on indexing operations (not search)
   - Note that 1-6 agent integration is deferred

10. **`docs/plans/IMPLEMENTATION_ROADMAP.md`**

    - Update timeline if needed
    - Clarify Phase 1 scope: indexing operations only
    - Defer search/query phase to Phase 2

11. **`docs/plans/00-PHASE_1_0_ENVIRONMENT_SETUP.md`**

    - Verify mcp-vector-search CLI (not library) is installed
    - Add verification test for `mcp-vector-search index` command
    - Update acceptance criteria if needed

12. **`docs/plans/01_1_4-PATH_VALIDATOR.md`**

    - No major changes needed
    - Verify it still applies to subprocess-based approach

13. **`docs/plans/01_1_5-AUDIT_LOGGING.md`**

    - No major changes needed
    - May need to log subprocess invocations

14. **`docs/plans/01_1_7-INTEGRATION_TESTS.md`**

    - Update test patterns: now testing subprocess invocation
    - Add tests for timeout handling, exit codes
    - Add tests for index artifact creation

15. **`docs/research/README.md`**
    - Update to clarify that subprocess integration is the correct approach
    - Point to research2 as source of truth

### ℹ️ Review Only (2 files)

These files are general reference and shouldn't need major changes:

- `docs/research2/IMPLEMENTATION_PLAN_ANALYSIS.md` - review for consistency
- `docs/research/combined-architecture-recommendations.md` - review for accuracy

---

## Update Strategy

### Phase A: Documentation Foundation (3 files)

**Goal**: Establish new baseline for architecture

1. **Rewrite** `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md`

   - Source: Subprocess research findings
   - Content: Subprocess invocation patterns, error handling, logging
   - Format: Ready-to-use for implementation team
   - Time: 2-3 hours

2. **Deprecate** `docs/research/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md`

   - Add header: "⚠️ DEPRECATED - See docs/research2 for current integration approach"
   - Keep for historical record

3. **Update** `docs/research/README.md`
   - Clarify subprocess approach
   - Point to research2/mcp-vector-search-subprocess-integration-research.md as primary reference

### Phase B: Plan Architecture (6 files)

**Goal**: Update implementation plans to reflect subprocess approach

1. **Rewrite** `docs/plans/01_1_1-SERVICE_ARCHITECTURE.md`

   - New section: "Workspace Indexing Subprocess Pattern"
   - Remove: VectorSearchManager singleton, in-service model caching
   - Add: Subprocess lifecycle management, error handling, logging patterns
   - Time: 3-4 hours

2. **Update** `docs/plans/01_1_2-SESSION_MANAGEMENT.md`

   - Index tracking removed from Session model
   - Add: Workspace registration and status tracking
   - Time: 1-2 hours

3. **Update** `docs/plans/01_1_3-VECTOR_SEARCH_API.md`

   - Rename consideration: "01_1_3-INDEXING_API.md" (focus on indexing, not search)
   - Refocus: API endpoints for workspace management and indexing
   - Defer: Search functionality to later phase
   - Time: 2-3 hours

4. **Update** `docs/plans/01_1_6-AGENT_INTEGRATION.md`

   - Defer to later phase with clear explanation
   - Add placeholder for Phase 2 design
   - Time: 1 hour

5. **Update** `docs/plans/01_1_8-DOCUMENTATION_RELEASE.md`

   - Update examples to subprocess patterns
   - Time: 1-2 hours

6. **Update** `docs/plans/01-PHASE_1_FOUNDATION.md`
   - Update critical path diagrams
   - Clarify subphase objectives under new architecture
   - Time: 1-2 hours

### Phase C: Supporting Updates (4 files)

**Goal**: Ensure consistency across all phase plans

1. **Update** `docs/plans/00-PHASE_1_0_ENVIRONMENT_SETUP.md`

   - Add CLI verification: `mcp-vector-search --version`
   - Time: 30 minutes

2. **Update** `docs/plans/01_1_4-PATH_VALIDATOR.md`

   - Verification and consistency check
   - Time: 30 minutes

3. **Update** `docs/plans/01_1_5-AUDIT_LOGGING.md`

   - Add subprocess logging patterns
   - Time: 30 minutes

4. **Update** `docs/plans/01_1_7-INTEGRATION_TESTS.md`
   - Test patterns for subprocess invocation
   - Time: 1-2 hours

### Phase D: Roadmap Updates (2 files)

1. **Update** `docs/plans/IMPLEMENTATION_ROADMAP.md`

   - Verify timeline accuracy
   - Clarify Phase 1 scope
   - Time: 1 hour

2. **Review** `docs/plans/IMPLEMENTATION_PLAN.md`
   - Verify for consistency with new approach
   - Time: 1 hour

---

## Potential Document Renames

Consider renaming for clarity under new architecture:

- `docs/plans/01_1_3-VECTOR_SEARCH_API.md` → `docs/plans/01_1_3-INDEXING_OPERATIONS.md`
  - Clarifies focus is on indexing, not search
  - Defers search to future phase

Would you like me to proceed with renames?

---

## Key Changes Across All Documents

### Architecture Diagram

**Before (incorrect)**:

```
research-mind-service
  ├── VectorSearchManager (singleton)
  │   ├── ChromaDB (in-process)
  │   ├── Model caching
  │   └── Search operations
  └── Session model (tracks index state)
```

**After (subprocess-based)**:

```
research-mind-service
  ├── Workspace API
  │   └── Index operations (POST /index)
  │       └── Subprocess: mcp-vector-search
  │           ├── init
  │           └── index/reindex
  └── Session model (tracks workspace only)

Workspace Directory
  └── .mcp-vector-search/
      ├── index artifacts
      ├── embeddings cache
      └── metadata
```

### Key Phrases to Replace

| Old                             | New                                  |
| ------------------------------- | ------------------------------------ |
| "VectorSearchManager singleton" | "Subprocess indexing"                |
| "In-service model caching"      | "Subprocess model management"        |
| "ChromaDB integration"          | "mcp-vector-search subprocess"       |
| "Embedded vector search"        | "Subprocess-based indexing"          |
| "Direct API calls"              | "Subprocess invocation with timeout" |

---

## Acceptance Criteria for Refactor

- [ ] All 15 files reviewed and categorized correctly
- [ ] Complete/Replace files (2) have subprocess-based content
- [ ] Update files (6) have architecture changes applied
- [ ] Minor update files (4) have consistency checks
- [ ] New subprocess invocation patterns documented
- [ ] Error handling and timeout patterns clear
- [ ] Timeline reviewed for accuracy
- [ ] No contradictions between documents
- [ ] Ready for Phase 1.1 implementation planning
- [ ] All cross-references updated

---

## Timeline

- **Phase A (Foundation)**: 3-4 hours
- **Phase B (Architecture)**: 9-12 hours
- **Phase C (Supporting)**: 2-3 hours
- **Phase D (Roadmap)**: 2 hours
- **Total**: 16-21 hours of work

---

## Questions for User Approval

Before proceeding, please clarify:

1. **Rename plans** for clarity?

   - `01_1_3-VECTOR_SEARCH_API.md` → `01_1_3-INDEXING_OPERATIONS.md` (and update references)
   - Or keep current names?

2. **Search functionality**:

   - Should it remain completely deferred to Phase 2?
   - Or add placeholder for Phase 1 that clarifies search is "out of scope for Phase 1"?

3. **Agent integration timing**:

   - Completely defer 01_1_6-AGENT_INTEGRATION.md to Phase 2?
   - Or keep Phase 1 mention with clear "deferred" status?

4. **Priority order**:
   - Execute in phases A→B→C→D as outlined?
   - Or different priority?

---

## Next Steps (Upon Approval)

1. User approves/adjusts plan
2. PM executes refactor in phases
3. Each update committed to git with detailed commit messages
4. Final review before Phase 1.1 implementation planning begins
