# Combined Architecture Recommendations

**Document Version**: 1.1
**Date**: 2026-01-31
**Status**: Final Recommendations & Implementation Strategy

---

## Correction Note (v1.1)

**Date**: 2026-01-31

A critical architectural correction was made during design review:

- **Initial assumption**: Custom SemanticIndexer service would orchestrate indexing
- **Correction**: mcp-vector-search provides complete indexing and search APIs
- **Impact**:
  - Removes ~200 lines of custom job queue code
  - Reduces MVP timeline from 3-4 weeks to ~10-12 days
  - Increases reliability (uses proven mcp-vector-search implementation)
  - Simplifies architecture (thin wrappers, not orchestrators)

All sections below reflect this corrected architecture.

---

## Executive Summary

**Research-Mind** is technically feasible as a session-sandbox system combining mcp-vector-search (indexing/search) with claude-mpm (agentic analysis). However, success requires significant work on sandbox containment and integration glue code.

**Tell it like it is**:

- ✓ Architecture is sound in principle
- ✓ Both reference projects are production-capable
- ✗ No "out of the box" solution exists
- ✗ 6-8 weeks of engineering required for MVP
- ✓ Cost reduction likely through caching + warm pools
- ✗ Latency will be high initially (session startup 2-3s)

**Recommendation**: Build MVP with clear scoping, plan incremental improvements, invest in sandbox containment early.

---

## 1. What to Build First: MVP Scope

### 1.1 Minimal End-to-End Flow (Week 1-2)

```
User: "Create research session on OAuth2 auth module"
  │
  └─→ Research-Mind Service:
      ├─ Create session directory
      ├─ Create .mcp-vector-search config
      └─ Return session_id

User: "Index the codebase"
  │
  └─→ Research-Mind Service:
      ├─ Trigger mcp-vector-search indexing (async)
      ├─ Poll job status
      └─ Report completion

User: "What does token refresh do?"
  │
  └─→ Research-Mind Service:
      ├─ Vector search: "token refresh"
      ├─ Pass results to claude-mpm agent
      ├─ Agent synthesizes answer with code references
      └─ Return findings with citations
```

### 1.2 MVP Components

**What's included**:

1. FastAPI wrapper around mcp-vector-search ✓ (from REST API proposal)
2. Basic session management ✓ (simple JSON storage)
3. Path validator for claude-mpm ✓ (from containment plan)
4. Minimal audit logging ✓ (basic file logging)
5. Session-scoped collections in ChromaDB ✓ (param exists)
6. Pre-built "research-analyst" agent (new)

**What's NOT included**:

- Auth/RBAC
- Distributed job queuing
- Advanced filtering
- Rate limiting
- WebSocket progress streams
- Multi-region deployment

### 1.3 MVP Implementation Plan

| Week      | Component         | Effort      | Dependencies              |
| --------- | ----------------- | ----------- | ------------------------- |
| **1**     | FastAPI wrapper   | 2 days      | mcp-vector-search library |
| **1**     | Session CRUD      | 3 days      | Database (SQLite ok)      |
| **1-2**   | Path validator    | 2 days      | -none-                    |
| **2**     | Agent scaffolding | 3 days      | claude-mpm installation   |
| **2**     | Integration tests | 4 days      | All above                 |
| **2**     | Docs + deployment | 2 days      | All above                 |
| **Total** |                   | ~10-12 days | -                         |

---

## 2. What to Avoid (Anti-Patterns)

### 2.1 DO NOT: Embed REST in mcp-vector-search

**Why**:

- Would require core modifications
- Harder to version/upgrade
- Mixing concerns (CLI tool vs. library)

**DO**: Wrapper service importing mcp-vector-search as library ✓

### 2.2 DO NOT: Rely on Prompts for Sandbox Isolation

**Why**:

- Prompt-based restrictions are not enforceable
- Agent could be compromised/jailbroken
- Serious security risk in multi-tenant scenario

**DO**: Infrastructure-level path validation ✓

### 2.3 DO NOT: Single Global ChromaDB Collection

**Why**:

- Sessions would contaminate each other
- Search results from wrong sessions
- Impossible to delete session data cleanly

**DO**: Per-session collections (session\_{session_id}) ✓

### 2.4 DO NOT: Build Custom Indexing When mcp-vector-search Provides It

**Why**:

- mcp-vector-search already has complete indexing APIs
- Custom job queue code = unnecessary complexity and maintenance
- Re-implementing proven functionality increases bugs
- Better to use proven, tested implementation

**DO**: Use mcp-vector-search's built-in async indexing APIs directly ✓

Our wrapper becomes a thin adapter that:

- Calls `mcp_vector_search.index()` for indexing
- Calls `mcp_vector_search.search()` for searching
- Manages session scoping (collection names, paths)
- Provides job tracking via mcp-vector-search's job model
- Logs and audits operations

### 2.5 DO NOT: Trust Agent to Respect filesystem Restrictions

**Why**:

- Agents are powerful; can escape restrictions
- No way to know what agent will do next

**DO**: Validate every filesystem access at wrapper layer ✓

---

## 3. Cost & Latency Reduction Strategies

### 3.1 Cost Reduction

**Indexing Costs**:
| Strategy | Savings | Effort | Impact |
|----------|---------|--------|--------|
| Incremental indexing | 80% | Medium | Large |
| Batch embeddings | 30% | Low | Medium |
| Caching query results | 40% | Low | Medium |
| Model quantization | 20% | High | Medium |
| Total | ~70% | Medium | Large |

**Detailed strategies**:

1. **Incremental Indexing** (MVP +2 weeks)

   - Track file hashes
   - Only reindex changed files
   - Use git to detect changes
   - Saves: 80% of compute for small changes

2. **Batch Embeddings** (MVP baseline)

   - mcp-vector-search already batches
   - Verify batch size tuning
   - Saves: 30% network overhead

3. **Query Caching** (MVP +1 week)

   - Cache search results per query
   - TTL: 1 hour per session
   - Saves: 40% of search requests

4. **Warm Pools** (MVP +2 weeks)
   - Keep Claude subprocess warm
   - Reuse for multiple queries
   - Saves: 2 seconds startup per query

**Estimated savings**: 60-70% of indexing cost, 40-50% of search cost

### 3.2 Latency Reduction

**Baseline latencies**:

- Cold session start: 2-3 seconds
- Warm session reuse: <100ms
- Vector search: <100ms
- Agent response: 5-10 seconds
- **Total**: 7-13 seconds first query, 5-10 seconds subsequent

**Optimization targets**:

| Component       | Current | Target | Strategy           |
| --------------- | ------- | ------ | ------------------ |
| Session startup | 2-3s    | 0.1s   | Warm pools         |
| Vector search   | <100ms  | <50ms  | Connection pooling |
| Agent startup   | 2-3s    | 0.5s   | Session reuse      |
| Agent response  | 5-10s   | 3-5s   | Token budgets      |
| **Total**       | 7-13s   | 3-6s   | All above          |

**MVP baseline**: 7-13 seconds (acceptable for first version)
**With optimizations**: 3-6 seconds (production quality)

---

## 4. MVP Slice: Smallest End-to-End Feature

### 4.1 Single Research Query End-to-End

```
POST /api/sessions
  ↓
{
  "session_id": "abc-123",
  "workspace": "/var/lib/research-mind/sessions/abc-123"
}

POST /api/sessions/abc-123/add-content
  body: {repository_path: "/path/to/app"}
  ↓
[Files copied to workspace]

POST /api/sessions/abc-123/index
  ↓
[Calls mcp-vector-search.index() with collection=session_abc123]
  ↓
{
  "job_id": "idx_456",
  "status": "pending"
}

GET /api/sessions/abc-123/index/jobs/idx_456
  ↓
[Poll 5-10 times until "completed"]
[Job tracking delegated to mcp-vector-search; FastAPI wrapper polls and returns status]

POST /api/sessions/abc-123/search
  body: {"query": "OAuth2 token refresh"}
  ↓
[Calls mcp-vector-search.search() with collection=session_abc123]
  ↓
{
  "results": [
    {
      "file": "src/auth/oauth2.py",
      "line": 42-67,
      "code": "def refresh_token(...)...",
      "relevance": 0.94
    }
  ]
}

POST /api/sessions/abc-123/analyze
  body: {"question": "How does token refresh work?", "agent": "research-analyst"}
  ↓
{
  "answer": "Token refresh works by...",
  "evidence": [
    {"source": "src/auth/oauth2.py:42-67", "code": "..."}
  ]
}
```

### 4.2 What's NOT in MVP Slice

- Auth/login
- Rate limiting
- Advanced filtering
- Multiple agents
- WebSocket progress
- Distributed queue
- Cost estimation

### 4.3 MVP Success Criteria

- [ ] Can create session
- [ ] Can index content (async job)
- [ ] Can search indexed content
- [ ] Can invoke agent with context
- [ ] Can get answer with citations
- [ ] Session isolation working
- [ ] No data leaks between sessions
- [ ] Basic audit logging

---

## 5. Next Slice: Incremental Improvements

### 5.1 Phase 2: Search Enhancements (Weeks 4-6)

**Hybrid Retrieval**:

- Vector search + keyword (BM25) fallback
- Re-rank results by relevance
- Deduplication across similar results
- Complexity: Medium (2 weeks)
- Impact: 30% better search quality

**Advanced Metadata Filtering**:

- Filter by language, chunk_type, complexity
- Range queries on line numbers
- Hierarchical filtering (functions in class X)
- Complexity: Medium (2 weeks)
- Impact: 20% better precision

**Query Understanding**:

- Intent recognition (architectural vs. bug fix)
- Multi-part queries
- Implicit context from conversation history
- Complexity: Medium (2 weeks)
- Impact: 40% fewer irrelevant results

### 5.2 Phase 3: Reranking & Deduplication (Weeks 7-9)

**Semantic Reranking**:

- LLM-based relevance scoring (not just cosine similarity)
- Consider code structure (public API vs. internal)
- Boost recent code, penalize deprecated
- Complexity: High (3 weeks)
- Impact: 50% better precision

**Deduplication**:

- Hash-based across sessions
- Similarity-based (similar functions in different files)
- Prevent duplicate search results
- Complexity: Low (1 week)
- Impact: Cleaner UX

### 5.3 Phase 4: Operations & Scale (Weeks 10-12)

**TTL Pruning**:

- Automatic cleanup of old sessions
- Archive to long-term storage
- Cost reduction
- Complexity: Low (1 week)
- Impact: 30% storage reduction

**Multi-Instance Deployment**:

- Horizontal scaling
- Load balancing across instances
- Shared ChromaDB cluster
- Complexity: High (3 weeks)
- Impact: 10x throughput

### 5.4 Recommended Sequence

1. **MVP** (Weeks 1-3): Core flow, isolation, logging
2. **Phase 2** (Weeks 4-6): Hybrid search, filtering, quality
3. **Phase 3** (Weeks 7-9): Reranking, deduplication, UX
4. **Phase 4** (Weeks 10-12): Operations, scale, cost optimization

---

## 6. Risk Register (Top 8 Risks)

### Risk 1: Session Isolation Breach (CRITICAL)

**Risk**: Agents access files outside session directory despite validation.

**Likelihood**: Medium (agent intelligence unpredictable)
**Impact**: CRITICAL (data exfiltration)
**Mitigation**:

- ✓ Multi-layer path validation (3 levels: middleware, service, subprocess)
- ✓ Comprehensive audit logging
- ✓ Regular security audits
- ✓ Fuzzing tests for path traversal
  **Residual Risk**: Low (with mitigations in place)

---

### Risk 2: Vector Search Token Contamination (HIGH)

**Risk**: Multiple sessions' embeddings mixed in same collection.

**Likelihood**: Low (parameterized collection names)
**Impact**: HIGH (search results from wrong session)
**Mitigation**:

- ✓ Per-session collection names enforced
- ✓ Middleware validates session_id before search
- ✓ Test suite for cross-session isolation
  **Residual Risk**: Low

---

### Risk 3: Agent Cost Explosion (HIGH)

**Risk**: Agents use too many tokens, cost becomes prohibitive.

**Likelihood**: Medium (agents are verbose)
**Impact**: HIGH (budget overrun)
**Mitigation**:

- ✓ Token budgeting in SessionAgent
- ✓ Automatic summarization at 70% threshold
- ✓ Costs logged per session
- ✓ Session-level cost caps
  **Residual Risk**: Medium (needs monitoring)

---

### Risk 4: Indexing Job Crashes (MEDIUM)

**Risk**: Large repository indexing fails silently or times out.

**Likelihood**: Medium (large codebases common)
**Impact**: MEDIUM (session stuck, user frustrated)
**Mitigation**:

- ✓ Timeout per indexing job (configurable)
- ✓ Error handling with partial results
- ✓ Incremental progress tracking
- ✓ Checkpoint after each file
- ✓ Resume capability
  **Residual Risk**: Low

---

### Risk 5: ChromaDB Corruption (MEDIUM)

**Risk**: Concurrent writes to shared ChromaDB cause index corruption.

**Likelihood**: Low (ChromaDB has locking)
**Impact**: MEDIUM (index unusable)
**Mitigation**:

- ✓ Connection pooling with mutex
- ✓ Stale lock cleanup on startup
- ✓ Corruption detection in CollectionManager
- ✓ Corruption recovery mechanism
- ✓ Regular index validation
  **Residual Risk**: Low

---

### Risk 6: Agent Jailbreak (MEDIUM)

**Risk**: Agent escapes instructions, ignores session scope.

**Likelihood**: Low (LLM is generally compliant)
**Impact**: MEDIUM (containment breach)
**Mitigation**:

- ✓ Infrastructure-level enforcement (not prompt-only)
- ✓ Tool call interception
- ✓ Command whitelisting
- ✓ Network isolation
- ✓ Extensive logging
  **Residual Risk**: Low (mitigations are code-level)

---

### Risk 7: Deployment Complexity (MEDIUM)

**Risk**: Multiple services (FastAPI, mcp-vector-search, claude-mpm) hard to deploy.

**Likelihood**: Medium (many moving parts)
**Impact**: MEDIUM (operations burden)
**Mitigation**:

- ✓ Docker Compose for local dev
- ✓ Kubernetes manifests for production
- ✓ Health checks on all services
- ✓ Automated scaling
- ✓ Monitoring/alerting
  **Residual Risk**: Medium (requires DevOps investment)

---

### Risk 8: Session Latency Too High (MEDIUM)

**Risk**: 7-13 second response times unacceptable to users.

**Likelihood**: Medium (baseline is slow)
**Impact**: MEDIUM (product unusable)
**Mitigation**:

- ✓ Warm pools for agent reuse (2-3s → 0.1s)
- ✓ Session caching (repeat queries <100ms)
- ✓ Progressive UI (show results as they arrive)
- ✓ Concurrent search + analysis
- ✓ Query optimization (semantic reranking Phase 3)
  **Residual Risk**: Medium initially, Low after Phase 2

---

## 7. Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│                    UI Layer (SvelteKit)                     │
│          (research-mind-ui)                                 │
├────────────────────────────────────────────────────────────┤
│ - Session creation                                          │
│ - Content upload                                            │
│ - Search interface                                          │
│ - Results display with citations                           │
└──────────────────────┬─────────────────────────────────────┘
                       │ REST API calls
┌──────────────────────▼─────────────────────────────────────┐
│          API Layer (FastAPI Service)                        │
│      (research-mind-service)                                │
├────────────────────────────────────────────────────────────┤
│ - Session CRUD                                              │
│ - Path validation (sandbox)                                 │
│ - Audit logging                                             │
└──────────┬──────────────────────┬────────────────────────┬──┘
           │                      │                        │
        [Search]             [Indexing]              [Analysis]
           │                      │                        │
┌──────────▼──────┐    ┌──────────▼──────┐    ┌───────────▼─────────┐
│ Search Wrapper  │    │ Index Wrapper   │    │ Claude MPM Agent    │
│ (thin adapter)  │    │ (thin adapter)  │    │ (subprocess)        │
├─────────────────┤    ├─────────────────┤    ├─────────────────────┤
│ mcp-vector-     │    │ mcp-vector-     │    │ research-analyst    │
│ search library  │    │ search library  │    │ agent               │
│ (search API)    │    │ (index API)     │    │                     │
└──────────┬──────┘    └────────┬────────┘    └────────┬────────────┘
           │                    │                      │
           └────────┬───────────┴──────────────────────┘
                    │
        ┌───────────▼──────────────────┐
        │  ChromaDB Vector Database    │
        │  (managed by mcp-vector-     │
        │   search, session collections)
        │  - session_abc123            │
        │  - session_def456            │
        └───────────┬──────────────────┘
                    │
        ┌───────────▼──────────────────┐
        │  Persistent Storage          │
        ├──────────────────────────────┤
        │ - Session DB (SQLite)        │
        │ - Audit logs (SQLite)        │
        │ - Session workspaces (disk)  │
        │ - .mcp-vector-search/ dirs   │
        │   (index metadata)           │
        └──────────────────────────────┘
```

---

## 8. Implementation Priorities

### Must Have (MVP)

- [ ] Session management (CRUD)
- [ ] Vector search REST API (wrapper around mcp-vector-search)
- [ ] Indexing REST API (wrapper around mcp-vector-search)
- [ ] Path validation (sandbox)
- [ ] Agent invocation with context
- [ ] Basic audit logging

### Should Have (Phase 2)

- [ ] Incremental indexing
- [ ] Query caching
- [ ] Advanced filtering
- [ ] Warm session pools
- [ ] Multi-file context

### Nice to Have (Phase 3+)

- [ ] Hybrid search (keyword + vector)
- [ ] Semantic reranking
- [ ] Cost estimation
- [ ] Auth/RBAC
- [ ] Multi-region deployment

---

## 9. Deployment Strategy

### Local Development

```bash
docker-compose up -d

# Services started:
# - FastAPI (8000)
# - ChromaDB (implicit, in Python)
# - Claude code (requires installed CLI)

# Test MVP
curl -X POST http://localhost:8000/api/sessions \
  -d '{"name": "test"}'
```

### Single-Server Production

```dockerfile
# Dockerfile
FROM python:3.11
RUN pip install fastapi uvicorn mcp-vector-search
COPY . /app
WORKDIR /app
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0"]
```

```bash
# Deploy
docker build -t research-mind-service .
docker run -d -p 8000:8000 \
  -v /var/lib/research-mind:/var/lib/research-mind \
  research-mind-service
```

### Kubernetes (Phase 4)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: research-mind-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: research-mind-service
  template:
    metadata:
      labels:
        app: research-mind-service
    spec:
      containers:
        - name: service
          image: research-mind-service:latest
          ports:
            - containerPort: 8000
          volumeMounts:
            - name: sessions
              mountPath: /var/lib/research-mind
      volumes:
        - name: sessions
          persistentVolumeClaim:
            claimName: research-mind-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: research-mind-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
```

---

## 10. Success Metrics

### MVP Success Criteria

| Metric            | Target         | How to Measure    |
| ----------------- | -------------- | ----------------- |
| Session creation  | <1s            | Log timestamps    |
| Indexing speed    | >500 files/min | Job metrics       |
| Search latency    | <100ms         | API metrics       |
| Agent response    | <10s           | Session logs      |
| Search precision  | >0.8           | Manual evaluation |
| Session isolation | 100%           | Security audit    |
| Uptime            | 99%+           | Monitoring system |
| Cost per query    | <$0.10         | Token tracking    |

### Phase 2 Targets

- Search quality: 90% precision (hybrid + reranking)
- Latency: <5s for agent analysis
- Cost: $0.05 per query (40% reduction)
- Throughput: 100 QPS (warm pools)

---

## 11. Open Questions & Unknowns

1. **ChromaDB concurrent write safety**: How safe is concurrent write to same collection from multiple indexing jobs?

   - **Answer needed before Phase 2**

2. **Agent consistency**: Does claude-mpm guarantee deterministic responses given same input?

   - **Impact**: Caching strategy

3. **Token usage patterns**: How predictable are agent token costs?

   - **Impact**: Cost modeling

4. **Embedding model performance**: Does all-MiniLM-L6-v2 perform well for code semantics?

   - **Mitigation**: Support pluggable models (Phase 2)

5. **Session resumption reliability**: What percentage of sessions fail to resume?
   - **Impact**: Session management strategy

---

## 12. Final Recommendation

### Decision: Build Research-Mind as Specified

**Rationale**:

1. Architecture is technically sound ✓
2. Both reference projects are production-ready ✓
3. Sandbox containment is achievable with proper engineering ✓
4. Cost reduction strategies are straightforward ✓
5. Latency is initially high but acceptable (7-13s) ✓

### Go/No-Go Decision: GO

**Conditions**:

- [ ] Team commits to sandbox containment as non-negotiable
- [ ] Path validation implemented before any agent access
- [ ] Comprehensive audit logging from day 1
- [ ] Security review before Phase 2 (when accessing real data)

### Timeline: 12 Weeks to Production

| Phase       | Duration    | Deliverable                         |
| ----------- | ----------- | ----------------------------------- |
| **MVP**     | Weeks 1-3   | Core research loop working          |
| **Phase 2** | Weeks 4-6   | 90% search quality, $0.05 per query |
| **Phase 3** | Weeks 7-9   | Reranking, deduplication, UX polish |
| **Phase 4** | Weeks 10-12 | Multi-instance, scaling, ops ready  |

### Resource Requirements

- Backend: 1 Senior + 1 Junior Python engineer (full-time)
- DevOps: 0.5 engineer (part-time, Phase 3+)
- QA: 0.5 engineer (part-time, comprehensive security testing)
- PM: 0.5 (coordination, requirements refinement)
- **Total**: ~2-2.5 FTE for 12 weeks

---

## References

### Key Documents

- `mcp-vector-search-capabilities.md` - Technical deep dive
- `mcp-vector-search-rest-api-proposal.md` - API design
- `claude-mpm-capabilities.md` - Agent runtime details
- `claude-mpm-sandbox-containment-plan.md` - Security architecture

### Code Structure

```
research-mind/
├── research-mind-service/
│   ├── app/
│   │   ├── main.py                 # FastAPI app
│   │   ├── routes/
│   │   │   ├── sessions.py         # Session CRUD
│   │   │   ├── index.py            # Indexing endpoints
│   │   │   ├── search.py           # Search endpoints
│   │   │   └── analyze.py          # Analysis endpoints
│   │   ├── services/
│   │   │   ├── session_manager.py
│   │   │   ├── indexer.py
│   │   │   ├── search_client.py
│   │   │   └── agent_runner.py
│   │   ├── sandbox/
│   │   │   ├── path_validator.py
│   │   │   ├── session_validator.py
│   │   │   ├── network_isolation.py
│   │   │   └── tool_interceptor.py
│   │   └── models/
│   │       └── audit_log.py
│   ├── tests/
│   │   ├── test_sandbox_containment.py
│   │   ├── test_isolation.py
│   │   └── test_integration.py
│   └── Dockerfile
├── research-mind-ui/
│   ├── src/
│   │   ├── lib/
│   │   │   └── api.ts             # Calls to service
│   │   ├── routes/
│   │   │   ├── +page.svelte       # Home
│   │   │   ├── sessions/          # Session UI
│   │   │   └── research/          # Research UI
│   │   └── components/
│   └── Dockerfile
├── docs/
│   ├── research/
│   │   ├── mcp-vector-search-capabilities.md ✓
│   │   ├── mcp-vector-search-rest-api-proposal.md ✓
│   │   ├── claude-mpm-capabilities.md ✓
│   │   ├── claude-mpm-sandbox-containment-plan.md ✓
│   │   └── combined-architecture-recommendations.md ✓
│   └── api-contract.md
└── docker-compose.yml
```

---

**Status**: Ready for implementation ✓
