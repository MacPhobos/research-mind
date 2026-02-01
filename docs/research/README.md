# Research-Mind Architecture Research

## Overview

This directory contains comprehensive research and architectural analysis for the Research-Mind project, a session-scoped research system combining semantic code search (mcp-vector-search) with agentic question-answering (claude-mpm).

**Research Completed**: 2026-01-31
**Total Documentation**: 5,745 lines across 6 documents
**Status**: Ready for implementation - Includes packaging/installation guide

---

## Current Integration Approach (Updated 2026-02-01)

### ✅ SUBPROCESS-BASED ARCHITECTURE

**The correct approach**: research-mind-service spawns **mcp-vector-search CLI as subprocess** on demand.

**Key Documents**:

1. **docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md** (Version 2.0 - CURRENT)

   - Subprocess-based integration (definitive guide)
   - Python code examples and patterns
   - FastAPI integration examples
   - Error handling and troubleshooting

2. **docs/research2/mcp-vector-search-subprocess-integration-research.md** (Complete Research)
   - Full CLI reference and testing results
   - Isolation verification
   - Performance baselines
   - Implementation recommendations

---

## Legacy Documents (For Reference Only)

### 0. **mcp-vector-search-packaging-installation.md** (1,388 lines) - DEPRECATED

❌ **INCORRECT APPROACH** - Describes library embedding (not used)

Legacy documentation for integrating mcp-vector-search as Python library (approach abandoned).

**Why Deprecated**:

- mcp-vector-search does NOT expose embeddable classes (ChromaDB, VectorSearchManager)
- Subprocess approach is simpler, safer, and production-ready
- See current guide instead

**For**: Historical reference only - DO NOT USE FOR IMPLEMENTATION

---

### 1. **mcp-vector-search-capabilities.md** (680 lines)

Deep technical analysis of mcp-vector-search architecture, indexing flow, search mechanisms, and extension points.

**Key Findings**:

- Single-project focused, limited multi-collection support
- Session scoping requires per-session collections (already parameterizable)
- ChromaDB-based with connection pooling (13.6% perf improvement)
- 8 language parsers (Python, JS, TS, Dart, PHP, Ruby, HTML, Markdown)
- No REST API or job-based async indexing currently

**For Research-Mind**: Wrapper service recommended (not embedded REST)

---

### 2. **mcp-vector-search-rest-api-proposal.md** (1,015 lines)

Detailed REST API specification for session-scoped indexing and search.

**Key Deliverables**:

- Comprehensive endpoint specifications (Sessions, Indexing, Search)
- Async job model with progress tracking
- Pydantic schemas for all requests/responses
- Mandatory session_id enforcement
- Per-session collections in shared ChromaDB
- Example requests/responses for full workflow
- Security considerations (path validation, rate limiting)

**Architecture**: Wrapper FastAPI service importing mcp-vector-search as library

---

### 3. **claude-mpm-capabilities.md** (984 lines)

Complete analysis of Claude MPM session management, tool configuration, and filesystem access.

**Key Findings**:

- 47+ specialized agents available via git repository deployment
- Session management with 30-day resumption window (configurable)
- **CRITICAL**: Sandbox isolation is PROMPT-BASED only (not enforced)
- 17 bundled skills (git, testing, docker, etc.)
- MCP tool integration (supports mcp-vector-search, google-workspace-mpm)
- Skills auto-linking based on agent role

**For Research-Mind**: Requires infrastructure-level path validation (not prompt-only)

---

### 4. **claude-mpm-sandbox-containment-plan.md** (918 lines)

Security architecture for enforcing sandbox isolation at infrastructure level.

**Key Controls** (Enforced, not Prompt-Based):

- Path allowlist validation (4 levels of defense)
- Session_id validation on every request
- Network isolation via subprocess environment
- Tool call interception and auditing
- Audit logging of all filesystem/tool access
- Session TTL and cleanup
- Rate limiting per session

**Threat Model**: Assumes agent is adversarial; validates at system level

---

### 5. **combined-architecture-recommendations.md** (760 lines)

Final "tell it like it is" recommendations with implementation strategy.

**Key Decisions**:

- ✓ Architecture is sound; both projects are production-ready
- ✗ Requires 6-8 weeks engineering for MVP
- ✓ Cost reduction likely (60-70% savings possible)
- ✗ Initial latency high (7-13s), reducible to 3-6s with optimization
- ✓ MVP feasible within 3-4 weeks
- **Recommendation**: BUILD (with proper sandbox containment)

**Risk Register**: 8 major risks identified with mitigations

- Session isolation breach: CRITICAL (mitigated: multi-layer validation)
- Token contamination: HIGH (mitigated: per-session collections)
- Cost explosion: HIGH (mitigated: token budgeting)
- Others: Medium (all mitigated)

---

## Key Recommendations

### What to Build First (MVP - 3-4 weeks)

```
1. FastAPI wrapper around mcp-vector-search
2. Session CRUD endpoints
3. Async indexing job model
4. Search with mandatory session_id
5. Path validator for claude-mpm
6. Minimal audit logging
7. Integration tests
```

### What to Avoid (Anti-Patterns)

- ✗ DO NOT: Embed REST in mcp-vector-search
- ✗ DO NOT: Rely on prompts for sandbox isolation
- ✗ DO NOT: Single global ChromaDB collection
- ✗ DO NOT: Synchronous indexing in HTTP handler
- ✗ DO NOT: Trust agent to respect restrictions

### Cost & Latency Optimization

**Baseline** (MVP): ~$0.20/query, 7-13s latency
**With Phase 2-3 optimizations**: ~$0.05/query, 3-6s latency

**Strategies**:

- Incremental indexing (80% cost savings)
- Batch embeddings (30% savings)
- Query result caching (40% savings)
- Warm session pools (2-3s → 0.1s startup)

---

## Architecture Summary

```
┌─────────────────────────────────────────┐
│  SvelteKit UI (research-mind-ui)         │
└──────────────────┬──────────────────────┘
                   │
┌──────────────────▼──────────────────────┐
│  FastAPI Service (research-mind-service) │
│  - Session CRUD                          │
│  - Indexing jobs                        │
│  - Search routing                       │
│  - Path validation (sandbox)            │
│  - Audit logging                        │
└──────┬──────────────────┬──────────┬────┘
       │                  │          │
    [Search]        [Indexing]  [Analysis]
       │                  │          │
   [mcp-vector-    [SemanticIndexer] [claude-mpm
    search]          (async)         research-
   (library)                         analyst]
       │                  │          │
       └────────┬─────────┴──────────┘
                │
        [ChromaDB Vector DB]
        (per-session collections)
                │
        [Session Workspaces]
        (isolated + validated)
```

---

## Implementation Timeline

| Phase       | Weeks | Deliverable           | Key Completion               |
| ----------- | ----- | --------------------- | ---------------------------- |
| **MVP**     | 1-3   | Core research loop    | Session isolation working    |
| **Phase 2** | 4-6   | Search quality (90%+) | Hybrid retrieval + filtering |
| **Phase 3** | 7-9   | Production polish     | Reranking + deduplication    |
| **Phase 4** | 10-12 | Scale ready           | Multi-instance deployment    |

---

## Risk Register (Top 8)

1. **Session Isolation Breach** (CRITICAL) → Mitigated: Multi-layer validation
2. **Token Contamination** (HIGH) → Mitigated: Per-session collections
3. **Agent Cost Explosion** (HIGH) → Mitigated: Token budgeting
4. **Indexing Crashes** (MEDIUM) → Mitigated: Error handling + resume
5. **ChromaDB Corruption** (MEDIUM) → Mitigated: Connection pooling + recovery
6. **Agent Jailbreak** (MEDIUM) → Mitigated: Infrastructure enforcement
7. **Deployment Complexity** (MEDIUM) → Mitigated: Docker + K8s
8. **Latency Too High** (MEDIUM) → Mitigated: Warm pools + caching

**All risks are manageable with documented mitigations.**

---

## Success Criteria (MVP)

- [ ] Can create/delete sessions
- [ ] Can index content (async job with progress)
- [ ] Can search indexed content (<100ms)
- [ ] Can invoke agent with context
- [ ] Can get answer with citations
- [ ] Session isolation verified (100%)
- [ ] No data leaks between sessions
- [ ] Audit logging operational

---

## Code References

### mcp-vector-search

- Core indexer: `/src/mcp_vector_search/core/indexer.py` (line 61+)
- Search engine: `/src/mcp_vector_search/core/search.py` (line 22+)
- Database: `/src/mcp_vector_search/core/database.py` (line 35+)
- Collection manager: `/src/mcp_vector_search/core/collection_manager.py`
- MCP server: `/src/mcp_vector_search/mcp/server.py`

### claude-mpm

- Session manager: `/src/claude_mpm/core/session_manager.py`
- Agent registry: `/src/claude_mpm/core/agent_registry.py`
- Skills system: `/src/claude_mpm/skills/`
- MCP integration: `/src/claude_mpm/mcp/`

### research-mind (to be created)

- Service: `research-mind-service/app/`
- UI: `research-mind-ui/src/`

---

## Next Steps

1. **Review**: Stakeholder approval of recommendations
2. **Plan**: Detailed sprint planning for MVP
3. **Scaffold**: Create service structure and Docker setup
4. **Implement**:
   - Week 1: Session management + FastAPI scaffold
   - Week 2: Vector search integration + indexing jobs
   - Week 3: Agent integration + integration tests
5. **Test**: Comprehensive security and isolation testing
6. **Deploy**: Single-server production deployment

---

**Final Recommendation**: BUILD ✓
**Go/No-Go Decision**: GO ✓
**Estimated Effort**: 12-16 weeks to production (MVP 3-4 weeks)

---

_Research completed by Claude Code_
_Date: 2026-01-30_
_Total analysis: 4,357 lines of documentation_
