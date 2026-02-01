# Phase 1.6: Agent Integration

**Subphase**: 1.6 of 8 (Phase 1)
**Status**: DEFERRED TO PHASE 2

> **DEFERRAL NOTICE**: This subphase is deferred to Phase 2.
> Agent integration depends on search functionality, which is out of scope
> for Phase 1 under the subprocess-based architecture.
>
> Search queries will flow through Claude Code's MCP interface to mcp-vector-search,
> NOT through a REST API wrapper in research-mind-service.
> Agent integration will be designed around this MCP-based search pattern.

---

## Original Scope (Now Deferred)

- ~~Custom "research-analyst" agent for claude-ppm~~
- ~~Agent invocation endpoint (POST /api/sessions/{id}/analyze)~~
- ~~Agent returns answer with citations to code locations~~
- ~~Session isolation enforced (agent can only see session files)~~
- ~~Network disabled (no curl, wget, or external API calls)~~

---

## Why Deferred

The original Phase 1.6 design assumed:

1. **Search API available in Phase 1**: The agent would call search endpoints to find relevant code, then synthesize results. Under the subprocess-based architecture, search is deferred to Phase 2.

2. **Embedded vector search**: The agent would use in-process search via VectorSearchManager. This is incorrect - mcp-vector-search runs as a subprocess, not an embedded library.

3. **Direct API calls**: Agent would make REST calls to search endpoints. Instead, search will go through Claude Code's native MCP interface.

**Correct Architecture (Phase 2)**:

```
User Question
  ↓
Claude Code Agent
  ├── MCP Protocol → mcp-vector-search (search indexed workspace)
  │   └── Reads .mcp-vector-search/ index in workspace directory
  ├── File reading (within session sandbox)
  └── Synthesis and citation extraction
```

---

## Phase 2 Design Notes

When this subphase is implemented in Phase 2, the architecture will differ significantly from the original plan:

### Search via MCP (Not REST)

Search queries will use Claude Code's native MCP interface to communicate with mcp-vector-search. The research-mind-service will NOT wrap search in a REST API.

```
Phase 2 Architecture:
  research-mind-service
    └── POST /api/v1/workspaces/{id}/analyze
        └── Spawns Claude Code agent subprocess
            └── Agent uses MCP to query mcp-vector-search
                └── mcp-vector-search reads workspace index
```

### Agent Sandbox

The agent sandbox design from the original plan remains valid:

- SESSION_DIR environment variable for workspace scoping
- Read-only file access within workspace
- Network disabled
- Timeout management (300s default)

### Citation Extraction

The citation extraction pattern from the original plan remains valid:

- Parse agent response for file:line_number references
- Return structured citations in API response

### Dependencies for Phase 2

Before this subphase can begin:

- [ ] Phase 1 complete (workspace registration + indexing working)
- [ ] Search via MCP interface verified (Claude Code can query mcp-vector-search)
- [ ] Agent subprocess execution pattern validated
- [ ] Session sandbox constraints tested

---

## Impact on Phase 1

### Phase 1.7 (Integration Tests)

Integration tests should be scoped to:

- Session CRUD operations
- Workspace indexing via subprocess
- Path validation and security
- Audit logging

End-to-end test flow is now: **create session -> index workspace -> verify indexed**
(Search and analyze are Phase 2)

### Phase 1.8 (Documentation)

Documentation should reflect:

- Phase 1 delivers workspace registration and indexing
- Search and analysis are Phase 2 features
- API endpoints limited to session CRUD + indexing operations

### Phase 1 Critical Path

With 1.6 deferred, the Phase 1 critical path is shorter:

```
1.0 → 1.1 → 1.2/1.3/1.4 (parallel) → 1.5 → 1.7 → 1.8
```

---

## Original Effort Estimates (Preserved for Phase 2 Planning)

- **Duration**: 5-7 business days
- **Effort**: 40-56 hours
- **Team Size**: 2 FTE engineers
- **Prerequisite**: Phase 1.1 (FastAPI), Phase 2 search via MCP

### Original Deliverables (Preserved)

1. **~/.claude/agents/research-analyst/AGENT.md** - Custom agent definition
2. **research-mind-service/app/services/agent_runner.py** - Agent subprocess execution
3. **research-mind-service/app/routes/analyze.py** - Analysis endpoint
4. **research-mind-service/app/schemas/analyze.py** - Pydantic models

---

## Summary

**Phase 1.6 is DEFERRED TO PHASE 2** because:

1. Agent integration depends on search, which is deferred
2. Search will use Claude Code MCP interface (not REST API)
3. The subprocess-based architecture changes how agents interact with indexes
4. Phase 1 focus is narrowed to: workspace registration + indexing

The agent sandbox design, citation extraction, and subprocess execution patterns
from the original plan remain valid and will be adapted for the MCP-based
architecture in Phase 2.

---

**Document Version**: 2.0
**Last Updated**: 2026-02-01
**Status**: DEFERRED TO PHASE 2
**Architecture**: Subprocess-based (replaces v1.0 library embedding approach)
**Parent**: 01-PHASE_1_FOUNDATION.md
