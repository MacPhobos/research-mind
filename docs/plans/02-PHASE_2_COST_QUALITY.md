# Phase 2: Cost & Quality Optimization

**Phase Duration**: 3 weeks (Weeks 4-6)
**Timeline**: After Phase 1 MVP complete
**Status**: OPTIMIZATION - Building on Phase 1 foundation
**Team Size**: 1.5 FTE engineers
**Total Effort**: 60-72 hours

---

## Phase Objective

Improve search quality to 90%+ precision and reduce inference costs by 40-50% through incremental indexing, caching, filtering, and warm agent pools.

**Success Definition**:

- Search quality: 90%+ precision (manual evaluation)
- Cost: $0.05 per query (40% reduction from baseline)
- Latency: <5s for agent analysis
- Cache hit rate: >40% for typical usage

---

## Key Deliverables

### 2.1: Incremental Indexing (1 week)

**Problem**: Reindexing entire codebase is expensive (80% of content unchanged)

**Solution**:

- Track file content hashes in session metadata
- Use git to detect changed files when available
- Only process deltas in indexing jobs
- Preserve ChromaDB collections between runs

**Impact**: 80% cost savings for small changes, 50% faster reindex

---

### 2.2: Query Caching (3-4 days)

**Problem**: Same queries repeated waste tokens

**Solution**:

- Cache key: `hash(session_id + query_text)`
- TTL: 1 hour (configurable)
- Invalidate on reindex
- Monitor cache hit rate

**Impact**: 40% request reduction, 2-3s latency improvement

---

### 2.3: Advanced Filtering (3-4 days)

**Problem**: Results contain irrelevant code

**Solution**: Filter by language, chunk type, complexity

```json
POST /api/sessions/{id}/search
{
  "query": "authentication",
  "filters": {
    "language": ["python"],
    "chunk_type": ["function"],
    "file_pattern": "auth/**"
  }
}
```

**Impact**: More precise results, better UX

---

### 2.4: Warm Session Pools (1 week)

**Problem**: Agent startup slow (2-3 seconds per query)

**Solution**:

- Maintain pool of pre-started agents (3-5 agents)
- Reuse warm sessions for queries
- Monitor pool health, respawn as needed

**Impact**: 90% latency reduction for follow-up queries

---

### 2.5: Cost Optimization (Ongoing)

**Strategies**:

- Token budgets per session
- Auto-summarization at thresholds (70%/85%/95%)
- Embeddings caching per session
- Cost monitoring dashboard

**Impact**: 40-50% total cost reduction

---

## Research References

**docs/research/combined-architecture-recommendations.md** (Section 6)

- Cost optimization strategies
- Token budget implementation
- Warm pool architecture

**docs/research/mcp-vector-search-rest-api-proposal.md** (Section 3)

- Advanced filtering specifications
- Caching strategy

---

## Phase 2 Success Criteria

- [ ] Incremental indexing working (80% faster for small changes)
- [ ] Query cache operational (40% hit rate on typical usage)
- [ ] Advanced filtering available
- [ ] Warm pools reducing latency by 90%
- [ ] Cost monitoring showing 40-50% reduction
- [ ] Manual evaluation shows 90%+ precision

---

## Go/No-Go Criteria

**GO to Phase 3** if:

- [ ] Cost per query reduced to $0.05 (40% improvement)
- [ ] Search quality 90%+ precision verified
- [ ] Cache hit rate >40%
- [ ] Latency <5s for agent queries
- [ ] All tests passing

---

## Summary

**Phase 2** transforms Phase 1 MVP into production-ready system by:

- Reducing costs 40-50%
- Improving search quality to 90%+
- Reducing latency through caching and warm pools
- Adding advanced filtering for better UX

Foundation for Phase 3 polish and Phase 4 scale.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Next Phase**: Phase 3 (Reranking & UX Polish)
