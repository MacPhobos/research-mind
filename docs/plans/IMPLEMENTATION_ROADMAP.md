# Research-Mind Implementation Roadmap

**Master Index & Timeline for Phase 1 MVP**
**Last Updated**: 2026-02-01
**Status**: READY FOR EXECUTION

---

## Executive Summary

This roadmap outlines Phase 1 (MVP) for research-mind, a session-scoped agentic research system combining semantic code indexing (mcp-vector-search, subprocess-based) with Claude agent analysis (claude-ppm).

**Architecture Note**: mcp-vector-search is integrated as a **subprocess** spawned by research-mind-service, NOT as an embedded Python library. See `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0) for the definitive integration approach.

**Key Metrics**:

- **MVP Timeline**: 22-27 calendar days (Phase 1.0 + Phase 1 subphases)
- **Team**: 2 FTE engineers
- **Test Coverage**: >90%
- **Session Isolation**: 100%
- **Path Traversal Blocked**: 100%

---

## Phase 1 Timeline

```
Week 0 (Pre-Week 1): Phase 1.0 Environment Setup (2-3 days)
|
+-- Day -3 to -1: Dependency installation, baseline documentation
|   +-- Gate 1 Review: Phase 1.0 complete, team consensus to proceed
|
Week 1-3: Phase 1 Foundation (MVP Core Research Loop) - 12-16 days
|
+-- Days 1-6: Phase 1.1 Service Architecture (5-6 days, BLOCKING)
|   +-- FastAPI scaffold
|   +-- WorkspaceIndexer subprocess manager
|   +-- Configuration system
|   +-- Docker multi-stage build
|
+-- Parallel (Days 6-10): Phase 1.2, 1.3, 1.4
|   +-- Phase 1.2: Session Management (3-4 days)
|   |   +-- CRUD endpoints
|   |   +-- Database schema
|   |   +-- Workspace initialization
|   |
|   +-- Phase 1.3: Indexing Operations (5-6 days)
|   |   +-- Subprocess invocation (init + index)
|   |   +-- Indexing endpoints
|   |   +-- Search deferred to future phase
|   |
|   +-- Phase 1.4: Path Validator (2-3 days)
|       +-- Path validation logic
|       +-- Middleware integration
|
+-- Days 10-13: Phase 1.5 (Phase 1.6 deferred)
|   +-- Phase 1.5: Audit Logging (2-3 days)
|   |   +-- AuditLog model
|   |   +-- Logging integration
|   |
|   +-- Phase 1.6: Agent Integration (DEFERRED to future phase)
|       +-- Depends on search functionality
|       +-- Depends on Claude Code MCP integration
|       +-- Placeholder only in Phase 1
|
+-- Days 13-20: Phase 1.7, 1.8 (sequential)
    +-- Phase 1.7: Integration Tests (5-7 days)
    |   +-- End-to-end tests
    |   +-- Isolation tests
    |   +-- Security tests
    |   +-- Gate 3 Review: >90% coverage, security passed
    |
    +-- Phase 1.8: Documentation & Release (2 days)
        +-- README and docs
        +-- Docker Compose setup
        +-- Gate 4 Review: MVP ready for release
```

---

## Document Structure

### Core Planning Documents

1. **00-PHASE_1_0_ENVIRONMENT_SETUP.md**

   - Pre-phase setup for mcp-vector-search CLI installation
   - 8 detailed tasks with hour estimates
   - Critical for de-risking Phase 1.1
   - Reference: MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md (v2.0, subprocess-based)

2. **01-PHASE_1_FOUNDATION.md**
   - Phase 1 overview with critical path analysis
   - Covers all 8 subphases (1.1-1.8)
   - Dependency graph and parallelization opportunities
   - Research references and risk register

### Phase 1 Subphase Details (1.1-1.8)

3. **01_1_1-SERVICE_ARCHITECTURE.md**

   - FastAPI scaffold with WorkspaceIndexer subprocess manager
   - Reference: MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md (v2.0, subprocess-based)
   - 6 detailed tasks with code templates

4. **01_1_2-SESSION_MANAGEMENT.md**

   - Session CRUD endpoints with database persistence
   - 7 detailed tasks covering model, schema, routes, service

5. **01_1_3-INDEXING_OPERATIONS.md**

   - Subprocess-based workspace indexing operations
   - Reference: MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md (v2.0, subprocess-based)
   - Per-workspace indexing via subprocess, search deferred to future phase

6. **01_1_4-PATH_VALIDATOR.md**

   - Infrastructure-level path validation for sandbox
   - Reference: claude-ppm-sandbox-containment-plan.md Section 2
   - Security-critical path traversal prevention

7. **01_1_5-AUDIT_LOGGING.md**

   - Audit trail for all operations
   - Minimal performance overhead
   - Queryable by session_id

8. **01_1_6-AGENT_INTEGRATION.md**

   - Custom research-analyst agent (DEFERRED to future phase)
   - Depends on search functionality and Claude Code MCP integration
   - Reference: claude-ppm-capabilities.md Sections 3-5

9. **01_1_7-INTEGRATION_TESTS.md**

   - Comprehensive test suite (>90% coverage)
   - End-to-end, isolation, security, concurrency tests
   - Fuzzing with 20+ attack patterns

10. **01_1_8-DOCUMENTATION_RELEASE.md**
    - README, Docker Compose, API contract
    - Deployment and troubleshooting guides

### Master Reference

11. **IMPLEMENTATION_ROADMAP.md** (this document)
    - Master timeline and critical path
    - Document index and navigation
    - Go/no-go criteria summary
    - Success metrics dashboard

---

## Critical Path Analysis

**Note**: Phase 1 uses subprocess-based mcp-vector-search integration. Phase 1.6 (Agent Integration) is deferred to a future phase. Search functionality is also deferred to a future phase.

```
Phase 1.0 (2-3 days) - CLI installation and subprocess verification
  |
Phase 1.1 (5-6 days) - Service architecture with WorkspaceIndexer subprocess manager
  |
Phase 1.2/1.3/1.4 (can parallel, longest is 1.3 @ 5-6 days)
  |                  1.3 = Indexing Operations (subprocess-based)
Phase 1.5 (2-3 days, audit logging with subprocess events)
  |                  1.6 = DEFERRED to future phase
Phase 1.7 (5-7 days, subprocess + security testing)
  |
Phase 1.8 (2 days)

TOTAL: Phase 1.0 (2-3) + 1.1 (5-6) + 1.3 (5-6) + 1.5 (2-3) + 1.7 (5-7) + 1.8 (2)
     = 22-27 calendar days to MVP (3-4 weeks including Phase 1.0)
     (Reduced from 25-31 days due to deferral of Phase 1.6 Agent Integration)
```

---

## Phase Milestones & Go/No-Go Gates

### Gate 1: Phase 1.0 Complete (End of Pre-Week 1)

**Prerequisites**:

- mcp-vector-search CLI installed and subprocess invocation verified
- Model download validated via subprocess init
- PostgreSQL running and migrations applied
- All 8 Phase 1.0 tasks complete

**Decision**: Proceed to Phase 1.1 or address blockers
**Owner**: Tech lead + Engineering team lead

---

### Gate 2: Phase 1.1 Complete (End of Day 5-6)

**Prerequisites**:

- FastAPI service running on port 15010
- WorkspaceIndexer subprocess manager working
- Health check endpoint responding
- Docker image builds successfully

**Decision**: Proceed to Phase 1.2-1.5 parallelization
**Owner**: Tech lead

---

### Gate 3: Phase 1.7 Security Testing Complete (End of Day 18-23)

**Prerequisites**:

- > 90% test coverage
- End-to-end flow verified
- 100% path traversal blocking
- Cross-session isolation verified
- Security audit ready

**Decision**: Proceed to Phase 1.8 or address security issues
**Owner**: Security lead + Tech lead

---

### Gate 4: Phase 1 Complete - MVP Release (End of Day 24-27)

**Prerequisites**:

- All Phase 1 tasks complete
- All tests passing
- Documentation complete
- docker-compose up works end-to-end

**Decision**: Release MVP or defer non-critical features
**Owner**: Product lead + Executive sponsor

---

## Success Metrics Dashboard

### Phase 1 (MVP)

| Metric                 | Target      | Status |
| ---------------------- | ----------- | ------ |
| Service uptime         | 99% (local) | Gate 4 |
| Test coverage          | >90%        | Gate 3 |
| Session isolation      | 100%        | Gate 3 |
| Path traversal blocked | 100%        | Gate 3 |
| Core loop working      | 100%        | Gate 4 |

---

## Research Document Integration

**Phase 1.0**:

- docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md (v2.0, subprocess-based)
- docs/research/mcp-vector-search-packaging-installation.md (1,388 lines)

**Phase 1.1-1.8**:

- docs/research/claude-ppm-capabilities.md (984 lines)
- docs/research/claude-ppm-sandbox-containment-plan.md (918 lines)
- docs/research/mcp-vector-search-capabilities.md (680 lines)

**Analysis**:

- docs/research2/IMPLEMENTATION_PLAN_ANALYSIS.md (1,000+ lines)

**Total Research Base**: 10,000+ lines of detailed architecture documentation

---

## Team Staffing

### Phase 1 (MVP Development)

- **Total**: 2 FTE engineers
- **Distribution**:
  - Engineer A: Phase 1.1, 1.2, 1.5 (service architecture, sessions, audit)
  - Engineer B: Phase 1.3, 1.4 (indexing operations, security)
  - Both: Phase 1.7 (integration testing), Phase 1.8 (documentation)
  - Phase 1.6 (Agent Integration): Deferred to future phase

---

## Risk Summary & Mitigation

### Critical Risks (Addressed in Detail)

1. **Session Isolation Breach** - Multi-layer validation + testing
2. **Vector Search Token Contamination** - Per-session collections + isolation tests
3. **Prompt-Based Sandbox Failure** - Infrastructure-level path validation (Phase 1.4)
4. **Indexing Crashes** - Timeout + error handling + resume capability

### Risk Escalation Path

- **Phase 1.0**: Dependency blockers - Infrastructure team
- **Phase 1.1-1.8**: Architecture issues - Tech lead review
- **Phase 1.7**: Security failures - Security lead + Tech lead
- **Gate failures**: Escalate to Executive sponsor

---

## MVP Release Plan (End of Phase 1)

1. Internal user testing (engineering team)
2. Feedback collection on core loop
3. Bug fixes and minor optimizations
4. Beta release to select users

---

## Document Navigation

```
research-mind-project/
+-- docs/
    +-- plans/
    |   +-- IMPLEMENTATION_ROADMAP.md (this file - master index)
    |   +-- 00-PHASE_1_0_ENVIRONMENT_SETUP.md
    |   +-- 01-PHASE_1_FOUNDATION.md
    |   +-- 01_1_1-SERVICE_ARCHITECTURE.md
    |   +-- 01_1_2-SESSION_MANAGEMENT.md
    |   +-- 01_1_3-INDEXING_OPERATIONS.md
    |   +-- 01_1_4-PATH_VALIDATOR.md
    |   +-- 01_1_5-AUDIT_LOGGING.md
    |   +-- 01_1_6-AGENT_INTEGRATION.md
    |   +-- 01_1_7-INTEGRATION_TESTS.md
    |   +-- 01_1_8-DOCUMENTATION_RELEASE.md
    +-- research/
    |   +-- MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md
    |   +-- claude-ppm-capabilities.md
    |   +-- claude-ppm-sandbox-containment-plan.md
    |   +-- combined-architecture-recommendations.md
    |   +-- [others]
    +-- research2/
        +-- IMPLEMENTATION_PLAN_ANALYSIS.md
        +-- MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md
```

---

## Handoff Instructions

### For Next Engineer/Team

1. **Start Here**: Read this IMPLEMENTATION_ROADMAP.md (5 min)
2. **Phase Context**: Read 01-PHASE_1_FOUNDATION.md (15 min)
3. **Task Details**: Read specific subphase document (30 min)
4. **Research**: Consult research documents as referenced (30 min)
5. **Begin Work**: Start with first unfinished task in phase

### Approval Before Starting

- [ ] Roadmap reviewed with tech lead
- [ ] Phase milestones and gates understood
- [ ] Current phase gate status verified
- [ ] Task assignment confirmed

---

## Quick Links

- [Phase 1.0 Setup](00-PHASE_1_0_ENVIRONMENT_SETUP.md) - Start here for environment
- [Phase 1 Overview](01-PHASE_1_FOUNDATION.md) - MVP architecture and dependencies
- [Phase 1.1 Service](01_1_1-SERVICE_ARCHITECTURE.md) - FastAPI and WorkspaceIndexer subprocess manager

For questions or updates, refer to the research documents or contact tech lead.

---

## Future Work

Phases for cost optimization, search quality, reranking, and operational scaling will be planned after Phase 1 implementation is complete and real-world behavior is understood.

---

**Document Version**: 2.0
**Status**: READY FOR EXECUTION (Updated for subprocess-based architecture, Phase 1 focus only)
**Last Updated**: 2026-02-01
**Next Review**: Phase 1.0 gate completion
**Maintained By**: Research-Mind Development Team
