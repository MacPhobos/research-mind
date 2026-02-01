# Research-Mind Executive Summary

**Project Status**: MVP Planning Phase
**Documentation Updated**: 2026-01-31
**Architecture Status**: Validated & Ready for Implementation
**Recommendation**: BUILD ✓

---

## 1. Project Overview

**Research-Mind** is a session-based research analysis system designed to solve the problem of scattered documentation and inefficient knowledge discovery. Instead of indexing everything ("shotgun approach"), Research-Mind allows users to create curated research sessions with selected content entities, ensuring focused and accurate answers.

### Purpose

Enable users to ask informed questions about specific topics by creating isolated "research sandboxes" containing curated content (wikis, docs, PDFs, git repos, transcripts). Only the sandbox content is indexed and searched, eliminating the diluted results that come from broad indexing.

### Core Problem Addressed

Understanding new topics is time-consuming because:

- Information scattered across multiple sources of truth
- Indexing everything leads to diluted/incorrect answers due to semantic drift
- Context quality determines answer accuracy
- Manual stakeholder requests for relevant links are inefficient

### Solution Architecture

Research-Mind combines three open-source projects:

1. **mcp-vector-search**: Semantic indexing and search layer
2. **claude-mpm**: Agentic question-answering and analysis
3. **research-mind**: UI + Service orchestrating the above

---

## 2. Architecture & Technology Stack

### Monorepo Structure

```
research-mind/
├── research-mind-service/    # FastAPI backend (Python)
├── research-mind-ui/          # SvelteKit frontend (TypeScript)
├── docs/                      # Shared documentation
├── docker-compose.yml         # Local dev environment
└── Makefile                   # Dev commands
```

### Technology Stack

| Layer             | Technology               | Purpose                                                     |
| ----------------- | ------------------------ | ----------------------------------------------------------- |
| **Frontend**      | SvelteKit 5 + TypeScript | Session CRUD, chat interface, content ingestion             |
| **Backend**       | FastAPI + Python 3.12    | Session management, indexing orchestration, request routing |
| **Vector DB**     | ChromaDB (SQLite)        | Session-scoped embeddings and vector search                 |
| **Indexing**      | mcp-vector-search        | Code/document parsing, chunking, embedding                  |
| **Agent Runtime** | claude-mpm               | Multi-agent orchestration for question-answering            |
| **Database**      | PostgreSQL 16            | Session metadata, audit logs, job tracking                  |
| **Development**   | Docker Compose           | Local development stack (postgres + services)               |

### Service Ports

- **Backend Service**: `localhost:15010`
- **UI Dev Server**: `localhost:15000`
- **PostgreSQL**: `localhost:5432`

---

## 3. Key Features & Capabilities

### Current Implementation (MVP Phase)

- Session CRUD operations
- Content entity ingestion from multiple sources:
  - Web page scraping
  - Git repository cloning
  - PDF/document uploads
  - Plaintext pastes
  - Wiki article imports (via MCP)
- Async indexing job model with progress tracking
- Session-scoped vector search
- Chat interface for questions
- Generated TypeScript API client from OpenAPI schema
- Health check and version endpoints

### Planned Features (Phase 2+)

- Hybrid retrieval (vector + keyword search)
- Query reranking for improved relevance
- Result deduplication across sources
- Session TTL and automatic cleanup
- Token budgeting and "cheap vs deep mode" policies
- Warm session pools for reduced latency
- Multi-session analysis and cross-session insights
- Advanced audit logging and compliance tracking

---

## 4. API Contract (Current Endpoints)

### Health & Version Endpoints

**Health Check** - Verify service is running

```http
GET /health
```

Response (200 OK):

```json
{
  "status": "ok",
  "name": "research-mind-service",
  "version": "0.1.0",
  "git_sha": "abc1234"
}
```

**Service Version** - Get API version and build info

```http
GET /api/v1/version
```

Response (200 OK):

```json
{
  "name": "research-mind-service",
  "version": "0.1.0",
  "git_sha": "abc1234"
}
```

### OpenAPI Schema

Auto-generated OpenAPI specification available at:

```
GET /openapi.json
```

Complete API specification lives in:
**Source**: `/Users/mac/workspace/research-mind/docs/api-contract.md`
**Frontend Copy**: `/Users/mac/workspace/research-mind/research-mind-ui/docs/api-contract.md`

### Critical Development Rule: API Contract is FROZEN

The API contract is the single source of truth. All changes must flow:

1. Update contract in `research-mind-service/docs/api-contract.md`
2. Update backend models and routes
3. Copy contract to `research-mind-ui/docs/api-contract.md`
4. Regenerate TypeScript types: `make gen-client`
5. Update UI code
6. Deploy (backend first, then frontend with regenerated types)

---

## 5. Development Setup & Workflow

### Quick Start

```bash
# Install all dependencies
make install

# Start full stack (service + UI + database)
make dev

# Verify services are running
curl http://localhost:15010/health    # Backend health
open http://localhost:15000            # UI in browser
```

### Prerequisites

- Python 3.12+ (via asdf or system)
- Node.js 20+ (via asdf or system)
- Docker + Docker Compose
- Make

### Common Development Commands

```bash
make dev              # Start everything (service + UI + postgres)
make stop             # Stop everything
make test             # Run all tests (service + UI)
make lint             # Check code quality
make fmt              # Format code
make typecheck        # Type checking
make gen-client       # Regenerate TypeScript client from OpenAPI
make db-reset         # Drop and recreate database
make db-up            # Start just the database
make clean            # Clean up dependencies and volumes
```

### Development Guidelines

- **Database Migrations**: All schema changes via Alembic migrations
- **Type Safety**: Generate TypeScript types from OpenAPI (never hand-write)
- **Testing**: Every component requires at least one test
- **Environment Variables**: Use `.env.example` for defaults, never commit `.env`
- **Port Configuration**: Must differ between service (15010) and UI (15000)
- **Contract Changes**: Always update contract first, then code

### TypeScript Client Generation

The frontend auto-generates TypeScript types from the backend's OpenAPI schema:

```bash
# Workflow
1. Backend: Update models and endpoints
2. Backend: Run tests (must pass)
3. Root: npm run gen:api (in research-mind-ui/)
4. Frontend: Update components using new generated types
5. Frontend: Run tests
6. Deploy: Backend first, then frontend
```

---

## 6. Critical Architectural Decisions

### Decision: API Contract as Single Source of Truth

**Rationale**: Prevents divergence between backend and frontend
**Implementation**: Contract locked in both repos, TypeScript types auto-generated
**Governance**: All API changes require version bump + contract update

### Decision: Session-Scoped Isolation (Per-Session Collections)

**Rationale**: Prevents token contamination between sessions and ensures security
**Implementation**: Each session gets dedicated ChromaDB collection with mandatory session_id
**Enforcement**: Infrastructure-level path validation (not prompt-based)

### Decision: Wrapper Service for mcp-vector-search (Not Embedded REST)

**Rationale**: Avoids modifying reference project, enables clean separation of concerns
**Implementation**: FastAPI service imports mcp-vector-search as library, exposes REST endpoints
**Benefit**: mcp-vector-search remains reusable for other projects

### Decision: Infrastructure-Level Sandbox Containment

**Rationale**: Prompt-based isolation is insufficient for security
**Implementation**: 4-layer path validation, env isolation, network sandboxing, audit logging
**Impact**: Prevents claude-mpm from accessing files outside session directory

### Decision: Async Job Model for Indexing

**Rationale**: Large codebases can take minutes to index; users need progress feedback
**Implementation**: Job queue with status polling (not websocket for MVP)
**Future**: WebSocket streaming for real-time progress in Phase 2

---

## 7. Research Findings & Technical Analysis

### mcp-vector-search Assessment

**Status**: Production-ready semantic search system
**Architecture**: CLI-first, ChromaDB-based, 8 language parsers
**Key Strengths**:

- Connection pooling (13.6% performance improvement)
- Automatic file watching and reindexing
- Language-specific chunking strategies
- HNSW search index for fast similarity matching

**Gaps for Research-Mind**:

- No REST API (needs FastAPI wrapper)
- No session/multi-collection support (needs per-session collections)
- No job-based async indexing (needs task queue)
- Single-project focused design

**Recommendation**: Wrapper service approach recommended; core library is solid

### claude-mpm Assessment

**Status**: Sophisticated multi-agent orchestration framework
**Capabilities**: 47+ specialized agents, session resumption, MCP tool integration
**Key Strengths**:

- Session management with 30-day resumption window
- Auto-skill deployment based on agent role
- MCP integration for vector search and Google Workspace
- Real-time monitoring dashboard

**Critical Gap**: Sandbox isolation is PROMPT-BASED ONLY, not enforced
**Impact**: Requires infrastructure-level controls at Research-Mind service boundary
**Mitigation**: 4-layer path validation implemented in service (not relying on agent)

**Recommendation**: Use as agent runtime but add security layers at infrastructure level

### Combined System Assessment

**Feasibility**: TECHNICALLY SOUND ✓
**Production Readiness**: With proper containment (6-8 weeks MVP) ✓
**Cost Model**: $0.20/query baseline, reducible to $0.05 with optimizations ✓
**Latency Profile**: 7-13s baseline (MVP), reducible to 3-6s with warm pools ✓

---

## 8. Implementation Roadmap

### MVP Timeline: 2-3 Weeks

| Week    | Component                      | Status | Effort |
| ------- | ------------------------------ | ------ | ------ |
| **1**   | FastAPI wrapper + Session CRUD | -      | 5 days |
| **1-2** | Path validator + indexing glue | -      | 2 days |
| **2**   | Agent scaffolding              | -      | 3 days |
| **2**   | Integration tests              | -      | 4 days |

### Phase 2: Search Quality (Weeks 4-6)

- Hybrid retrieval (vector + BM25 keyword)
- Query reranking with cross-encoder models
- Advanced filtering and metadata search
- Result deduplication

### Phase 3: Production Polish (Weeks 7-9)

- Incremental indexing (80% cost savings)
- Batch embedding optimization (30% savings)
- Query result caching (40% savings)
- Comprehensive audit logging

### Phase 4: Scale Ready (Weeks 10-12)

- Warm session pools (0.1s cold start)
- Multi-instance deployment
- Kubernetes orchestration
- Advanced monitoring and alerting

---

## 9. Risk Analysis & Mitigations

### Risk Register (Top 8)

| #   | Risk                     | Severity | Mitigation                                       |
| --- | ------------------------ | -------- | ------------------------------------------------ |
| 1   | Session isolation breach | CRITICAL | Multi-layer path validation, server-side scoping |
| 2   | Token contamination      | HIGH     | Per-session collections, isolated embeddings     |
| 3   | Agent cost explosion     | HIGH     | Token budgeting, "cheap vs deep" modes           |
| 4   | Indexing crashes         | MEDIUM   | Error handling, resume capability                |
| 5   | ChromaDB corruption      | MEDIUM   | Connection pooling, recovery procedures          |
| 6   | Agent jailbreak          | MEDIUM   | Infrastructure enforcement, not prompts          |
| 7   | Deployment complexity    | MEDIUM   | Docker + docker-compose, clear runbooks          |
| 8   | Latency too high         | MEDIUM   | Warm pools, caching, incremental indexing        |

**Assessment**: All risks manageable with documented mitigations. None are show-stoppers.

---

## 10. Cost & Performance Projections

### Baseline (MVP)

- **Per-Query Cost**: ~$0.20 (typical claude-opus input + processing)
- **Latency**: 7-13 seconds (session cold start + search + agent reasoning)
- **Indexing**: ~30-60 seconds for 10K files

### With Phase 2-3 Optimizations

- **Per-Query Cost**: ~$0.05-0.08 (60-70% reduction)
- **Latency**: 3-6 seconds (70% improvement)
- **Indexing**: Incremental (avoid re-embedding unchanged files)

### Cost Reduction Strategies

1. **Incremental Indexing**: Only re-embed changed files (80% savings)
2. **Batch Embeddings**: Process multiple files in single call (30% savings)
3. **Query Caching**: Cache frequent queries and results (40% savings)
4. **Warm Pools**: Pre-warm session instances (eliminates 2-3s cold start)
5. **Token Budgeting**: Different modes (fast/cheap vs comprehensive/deep)

---

## 11. Success Criteria (MVP Definition of Done)

### Functional Requirements

- [ ] Create, read, update, delete research sessions
- [ ] Async indexing with progress tracking
- [ ] Search indexed content (<100ms response)
- [ ] Invoke agent with session context
- [ ] Get answers with citations
- [ ] All tests passing

### Security & Isolation

- [ ] Session isolation verified (no data leaks)
- [ ] Path validation enforced (100% coverage)
- [ ] Audit logging operational
- [ ] Agent containment tested with adversarial prompts

### Development Standards

- [ ] API contract documented and synced
- [ ] TypeScript types auto-generated
- [ ] All changes through contract-first workflow
- [ ] Code quality checks (lint, typecheck, format)
- [ ] Database migrations run cleanly

### Documentation

- [ ] Setup guide complete
- [ ] API contract locked
- [ ] Architecture decisions documented
- [ ] Integration guide for developers

---

## 12. Next Steps & Recommendations

### Immediate (Week 1)

1. **Review & Approve** this architectural roadmap with stakeholders
2. **Detailed Sprint Planning** for MVP development
3. **Repository Setup**:

   - Initialize `research-mind-service/` with FastAPI scaffold
   - Initialize `research-mind-ui/` with SvelteKit template
   - Configure Docker Compose and Makefile
   - Create API contract skeleton

4. **Team Onboarding**:
   - Share CLAUDE.md development guide
   - Run `make install && make dev` to verify setup
   - Review API contract workflow

### Short Term (Weeks 2-4)

1. **Implement FastAPI wrapper** around mcp-vector-search
2. **Build session management** (CRUD endpoints, storage)
3. **Develop path validator** for claude-mpm containment
4. **Create integration tests** for end-to-end flow
5. **Deploy MVP** to staging environment

### Medium Term (Weeks 5-8)

1. **Phase 2 features**: Hybrid retrieval, reranking
2. **Performance optimization**: Warm pools, caching
3. **Production hardening**: Error handling, monitoring
4. **Comprehensive testing**: Security, load, integration

### Long Term (Weeks 9+)

1. **Scale deployment**: Kubernetes, multi-region
2. **Advanced features**: Cross-session analysis, learning
3. **Monitoring & alerting**: Prometheus, Grafana
4. **Cost optimization**: Further token budgeting, deduplication

---

## 13. Key Documentation References

### Architecture & Design

- **Initial System Concept**: [docs/prompts/initial_system_idea.md](/Users/mac/workspace/research-mind/docs/prompts/initial_system_idea.md)
- **Research Prompt (v1)**: [docs/prompts/initial-research-prompt-v1.md](/Users/mac/workspace/research-mind/docs/prompts/initial-research-prompt-v1.md)
- **Monorepo Scaffolding**: [docs/prompts/scaffold-monorepo-fastapi-sveltekit.md](/Users/mac/workspace/research-mind/docs/prompts/scaffold-monorepo-fastapi-sveltekit.md)

### Technical Research (Deep Dives)

- **mcp-vector-search Capabilities**: [docs/research/mcp-vector-search-capabilities.md](/Users/mac/workspace/research-mind/docs/research/mcp-vector-search-capabilities.md) (680 lines)
- ~~**mcp-vector-search REST API Proposal**~~: (deleted - library-based approach was abandoned in favor of subprocess architecture)
- **claude-mpm Capabilities**: [docs/research/claude-mpm-capabilities.md](/Users/mac/workspace/research-mind/docs/research/claude-mpm-capabilities.md) (984 lines)
- **claude-mpm Containment Plan**: [docs/research/claude-mpm-sandbox-containment-plan.md](/Users/mac/workspace/research-mind/docs/research/claude-mpm-sandbox-containment-plan.md) (918 lines)
- **Combined Recommendations**: [docs/research/combined-architecture-recommendations.md](/Users/mac/workspace/research-mind/docs/research/combined-architecture-recommendations.md) (760 lines)

### Setup & Development

- **Development Setup**: [docs/SETUP.md](/Users/mac/workspace/research-mind/docs/SETUP.md)
- **API Contract**: [docs/api-contract.md](/Users/mac/workspace/research-mind/docs/api-contract.md)
- **Development Guide**: [CLAUDE.md](/Users/mac/workspace/research-mind/CLAUDE.md)

---

## 14. FAQ & Common Questions

**Q: Why not use Retrieval-Augmented Generation (RAG) directly?**
A: RAG is Approach A (Index → Embed → Retrieve → LLM). Research-Mind uses Approach B (Index + Embed → mcp-vector-search + sandbox content ← → claude-mpm). The difference is that claude-mpm can do iterative refinement, handle context expansion, and use agentic reasoning - leading to higher quality answers for complex topics.

**Q: Is sandbox isolation really necessary?**
A: Critical. Without infrastructure-level enforcement, agents can (intentionally or via prompt injection) access files outside the session directory. We assume agents are potentially adversarial and validate at the system level.

**Q: How long until we can go to production?**
A: MVP (functional system) in 2-3 weeks. Production-ready (hardened, monitored, performant) in 8-12 weeks. Recommend staged rollout with monitoring.

**Q: What about user authentication?**
A: Not in MVP scope. Current system is single-user. Authentication/RBAC planned for Phase 4.

**Q: Can this handle multiple concurrent sessions?**
A: Yes. Each session has dedicated ChromaDB collection, isolated filesystem, and separate agent runtime. Architecture supports hundreds of concurrent sessions (verified in research docs).

---

## 15. Final Recommendation

**Status**: BUILD ✓

Research-Mind is technically sound, feasible within 6-8 weeks for production readiness, and addresses a real problem in knowledge discovery. The architecture combines proven technologies (mcp-vector-search, claude-mpm, FastAPI, SvelteKit) in a novel way.

**Key Success Factors**:

1. Proper implementation of sandbox containment (infrastructure-level, not prompt-only)
2. Disciplined API contract management
3. Comprehensive testing (security, isolation, performance)
4. Staged rollout with monitoring from day one

**Investment**: 6-8 weeks engineering effort, ~$5-10K in initial infrastructure
**Payoff**: Significant time savings for teams doing frequent research and analysis

---

**Document Status**: Complete
**Last Updated**: 2026-01-31
**Total Research**: 4,357 lines of supporting documentation
**Research Completion**: 2026-01-30

For detailed technical information, see the research documents listed in Section 13.
