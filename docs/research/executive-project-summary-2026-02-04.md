# Research-Mind Executive Project Summary

**Date**: 2026-02-04
**Research Type**: High-Level Executive Summary
**Classification**: Informational

---

## Project Purpose (2-3 Sentences)

**Research-Mind** is a session-based research analysis system that enables users to ask informed questions about specific topics by creating isolated "research sandboxes" containing curated content. Unlike traditional RAG systems that index everything (leading to diluted results), Research-Mind allows users to create focused research sessions with selected content sources (wikis, documentation, PDFs, git repositories, transcripts), ensuring context quality determines answer accuracy.

The system combines semantic code indexing (mcp-vector-search) with Claude agent analysis (claude-mpm) through a modern FastAPI + SvelteKit full-stack application.

---

## Target Audience

| User Type | Benefit |
|-----------|---------|
| **Researchers & Analysts** | Create focused research sessions on specific topics without noise from unrelated content |
| **Engineering Teams** | Onboard faster by curating relevant documentation and codebases into indexed sessions |
| **Product Managers** | Research competitive landscapes, features, and requirements with curated source materials |
| **Knowledge Workers** | Ask complex questions across multiple document sources with high-quality, contextual answers |
| **Teams with Scattered Documentation** | Consolidate and query information across wikis, repos, and documents without building permanent infrastructure |

---

## Key Capabilities

1. **Session-Scoped Research Sandboxes** - Create isolated research environments with curated content, preventing token contamination between topics

2. **Multi-Source Content Ingestion** - Import content from web pages, git repositories, PDF/documents, plaintext, and wiki articles into unified searchable sessions

3. **Semantic Code & Document Indexing** - Automatic chunking, embedding, and indexing of content with language-specific parsing for 8+ programming languages

4. **Agentic Question-Answering** - Claude-powered analysis with iterative refinement and context expansion for higher quality answers on complex topics

5. **Security-First Architecture** - Infrastructure-level sandbox containment with path validation, audit logging, and session isolation (not prompt-based)

6. **Type-Safe Full-Stack Development** - Auto-generated TypeScript types from OpenAPI schema ensure frontend-backend contract synchronization

7. **Async Indexing with Progress Tracking** - Large codebases indexed in background with status polling and progress feedback

---

## Architecture Summary

### System Components

```
+------------------+     +----------------------+     +-------------------+
|  research-mind-  |     |  research-mind-      |     |   External        |
|  ui (SvelteKit)  | <-> |  service (FastAPI)   | <-> |   Components      |
|  Port: 15000     |     |  Port: 15010         |     |                   |
+------------------+     +----------------------+     +-------------------+
        |                         |                          |
        v                         v                          v
  - TanStack Query         - Session CRUD             - mcp-vector-search
  - Zod Validation         - Path Validator             (Subprocess)
  - Type-safe API          - Audit Logging            - claude-mpm (Agent)
                           - Workspace Manager        - PostgreSQL 16
                           - Indexing Jobs            - ChromaDB
```

### Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Frontend** | SvelteKit 5 + TypeScript | Session UI, chat interface, content ingestion |
| **Backend** | FastAPI + Python 3.12 | Session management, indexing orchestration |
| **Vector DB** | ChromaDB (SQLite) | Session-scoped embeddings and similarity search |
| **Indexing Engine** | mcp-vector-search | Code/document parsing, chunking, embedding |
| **Agent Runtime** | claude-mpm | Multi-agent orchestration for Q&A |
| **Database** | PostgreSQL 16 | Session metadata, audit logs, job tracking |

### Key Architectural Decisions

1. **API Contract as Single Source of Truth** - Both frontend and backend derive types from a frozen contract, preventing divergence
2. **Subprocess-Based Integration** - mcp-vector-search runs as subprocess, not embedded library, enabling clean separation
3. **Infrastructure-Level Security** - Path validation at system level, not relying on prompt-based isolation
4. **Per-Session Collections** - Each research session gets dedicated ChromaDB collection for isolation

---

## Strategic Benefits

### Business Value

| Benefit | Impact |
|---------|--------|
| **Reduced Research Time** | Users get contextual answers from curated sources instead of sifting through noise |
| **Higher Answer Quality** | Focused context = more accurate responses than broad indexing approaches |
| **Knowledge Preservation** | Research sessions can be saved, resumed, and shared across teams |
| **Compliance Ready** | Audit logging tracks all operations for accountability |
| **Cost Control** | Token budgeting prevents runaway costs; "cheap vs deep" modes planned |

### Technical Value

| Benefit | Impact |
|---------|--------|
| **Security by Design** | 4-layer path validation, session isolation, infrastructure enforcement |
| **Scalability** | Architecture supports hundreds of concurrent sessions |
| **Maintainability** | Type-safe contracts, generated code, comprehensive testing |
| **Extensibility** | Modular architecture allows adding new content types and agents |

---

## Current Status / Phase

**Status**: MVP Development Phase (Phase 1)

### Progress Summary

| Milestone | Status | Notes |
|-----------|--------|-------|
| Architecture Design | Complete | 10,000+ lines of research documentation |
| Environment Setup | Complete | Dependencies, baseline infrastructure |
| Service Architecture | In Progress | FastAPI scaffold, subprocess manager |
| Session Management | In Progress | CRUD endpoints, database schema |
| Indexing Operations | Planned | Subprocess invocation pending |
| Security Layer | Planned | Path validation, audit logging |
| Integration Testing | Planned | >90% coverage target |
| Documentation | Planned | Final release docs |

### Timeline

- **MVP Completion**: 22-27 calendar days (3-4 weeks from Phase 1.0)
- **Production Ready**: 8-12 weeks (with hardening, monitoring, optimization)
- **Team Size**: 2 FTE engineers

### Recent Commits (Velocity Indicator)

- `feat: auto-create CLAUDE.md in session sandboxes`
- `feat: two-stage response streaming with expandable process output`
- `feat: session chat interface with claude-mpm integration`
- `docs: add git repo content retriever implementation plan`

---

## Investment & ROI

### Investment Required

| Category | Estimate |
|----------|----------|
| Engineering Effort | 6-8 weeks to production ready |
| Infrastructure | ~$5-10K initial setup |
| Per-Query Cost (MVP) | ~$0.20 baseline |
| Per-Query Cost (Optimized) | ~$0.05-0.08 with Phase 2-3 optimizations |

### ROI Drivers

1. **Time Savings**: Research tasks that take hours reduced to minutes
2. **Quality Improvement**: Better answers from focused context
3. **Knowledge Leverage**: Teams build on curated research sessions
4. **Reduced Duplication**: Research sessions reusable across team members

---

## Risk Summary

| Risk | Severity | Mitigation |
|------|----------|------------|
| Session Isolation Breach | Critical | Multi-layer path validation + testing |
| Token Contamination | High | Per-session collections, isolation verification |
| Cost Explosion | High | Token budgeting, tiered modes planned |
| Agent Containment | Medium | Infrastructure enforcement (not prompts) |

**Assessment**: All risks manageable with documented mitigations. None are show-stoppers.

---

## Recommendation

**BUILD** - Research-Mind is technically sound, addresses a real problem in knowledge discovery, and has comprehensive architecture documentation supporting implementation.

---

## Key Documentation References

- **Executive Summary**: `/Users/mac/workspace/research-mind/docs/summary/EXECUTIVE_SUMMARY-20260131.md`
- **Implementation Roadmap**: `/Users/mac/workspace/research-mind/docs/plans/IMPLEMENTATION_ROADMAP.md`
- **API Contract**: `/Users/mac/workspace/research-mind/docs/api-contract.md`
- **Development Guide**: `/Users/mac/workspace/research-mind/CLAUDE.md`

---

**Research Completed By**: Research Agent
**Sources**: Project documentation, CLAUDE.md files, implementation plans, executive summary
