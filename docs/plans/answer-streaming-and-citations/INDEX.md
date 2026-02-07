# Answer Streaming & Citations Improvement Plans

**Date**: 2026-02-07
**Series**: answer-streaming-and-citations
**Scope**: Backend progress events during Q&A streaming, and citation consolidation/enrichment
**Research Base**: `docs/team-research/question-answer-improvements/` documents #06-#10
**Last Updated**: 2026-02-07 (Plans 03-04 updated based on Plan 00 measurement results)

---

## Problem Statement

The Q&A system has two user experience gaps:

1. **Streaming Progress**: After submitting a question, the user sees "Starting Claude Code..." then nothing for 18-261 seconds until the final answer appears. The system is working, but provides no feedback. *(Gap duration validated by Plan 00 measurement: avg 100s, range 18-261s)*

2. **Source Citations**: Two parallel citation mechanisms exist (inline markdown Sources section + structured SourceCitation metadata panel), neither links to actual content, and both showing simultaneously creates confusion.

## Guiding Principle: Subtract Before You Add

The devil's advocate analysis (Doc #10) established a core principle: **measure first, consolidate existing mechanisms, then add new features**. These plans follow that order.

## Research Documents

| # | Document | Key Findings |
|---|----------|-------------|
| 06 | `06-streaming-citations-ui-ux-research.md` | Two-stage accordion architecture, `stream_token` content unknown, two parallel citation displays |
| 07 | `07-streaming-citations-service-research.md` | Mature SSE infrastructure (6 event types), PhaseTimer exists, citation enrichment via DB lookup feasible |
| 08 | `08-streaming-citations-mpm-research.md` | claude-mpm has zero citation awareness, `CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1` already set, no claude-mpm changes needed |
| 09 | `09-streaming-citations-ecosystem-research.md` | No built-in progress/citation support in skills/agents, skill-based approach unreliable for structured output |
| 10 | `10-streaming-citations-devils-advocate.md` | `stream_token` events unverified, only 3-4 backend phases reliably detectable, consolidate to ONE citation approach |

## Devil's Advocate Constraints (from Doc #10)

These constraints shaped every plan:

- **No claude-mpm changes needed** -- all work is service-side or UI-side
- **No new skills/agent modifications needed** -- the regex extraction + DB enrichment approach is more reliable than LLM-structured citations
- **`stream_token` events during processing are UNVERIFIED** -- do not build UI features on unverified data
- **Only 3-4 progress phases are reliably detectable** from subprocess output
- **Pick ONE citation approach** -- structured SourceCitation with DB enrichment, not both markdown and structured
- **File-serving endpoint is over-engineered for now** -- defer to future plan

## Plan 00 Completion -- Key Findings (2026-02-07)

> Full report: `docs/research/streaming-measurement-results-2026-02-07.md`

Plan 00 (Measurement & Verification) is **COMPLETE**. 10 queries were measured across 5 sessions (8 successful, 2 timed out at 300s). The findings fundamentally reshaped Plans 03 and 04:

| Finding | Impact |
|---------|--------|
| **Silence gap: 18-261 seconds, ZERO events** | Strongly justifies Plans 03-04; users need progress feedback |
| **claude-mpm buffers ALL output atomically** | `system_init`, `assistant`, `stream_token`, and `result` arrive in a single burst at the end |
| **`stream_token` events NOT emitted during gap** | Doc #06 "Approach A" (frontend token parsing) is **invalid** |
| **`init_text` events ARE emitted progressively (3-8s)** | Only real-time signal available; used for `initializing` phase in Plan 03 |
| **Skill sync runs despite SKIP flag** | 601 files / 173 skills synced in 3-8s per query |
| **Average total query time: 103 seconds** | Range 20-263s; analytical queries on large sessions take longest |

**Plans 03-04 have been updated** to reflect these findings:
- Plan 03: Phases changed from `starting/connected/thinking/answering` to `starting/initializing/thinking/complete`. Added periodic elapsed-time updates every 10 seconds during the `thinking` phase.
- Plan 04: Confirmed that UI must rely ENTIRELY on backend progress events. Emphasis on elapsed time counter. Frontend token parsing confirmed invalid.

## Plan Index

| Plan | Title | Scope | Depends On | Effort | Status |
|------|-------|-------|------------|--------|--------|
| [00](00-measurement-and-verification.md) | Measurement & Verification | Service | None | 2-3 hours | **COMPLETE** |
| [01](01-citation-consolidation.md) | Citation Consolidation | Service + UI | None | 0.5-1 day | |
| [02](02-citation-enrichment.md) | Citation Enrichment via DB | Service + UI | Plan 01 | 2-3 days | |
| [03](03-backend-progress-events.md) | Backend Progress Events | Service | Plan 00 | 1-2 days | Updated per Plan 00 |
| [04](04-ui-progress-display.md) | UI Progress Display | UI | Plan 03 | 1 day | Updated per Plan 00 |
| [05](05-future-deferred.md) | Future / Deferred Items | Reference | Plans 01-04 | N/A | |

## Dependency Graph

```
Plan 00 (Measure) ──────────────> Plan 03 (Backend Progress) ──> Plan 04 (UI Progress)
                                          |
Plan 01 (Consolidate Citations) ──> Plan 02 (Enrich Citations)
                                          |
                                    Plan 05 (Future: file serving, previews, token streaming)
```

Plans 00 and 01 have no dependencies and can run in parallel. Plans 02, 03, and 04 are sequential within their respective tracks. Plan 05 is a reference document for future work.

## Implementation Order

**Sprint 1** (immediate, parallel):
- ~~Plan 00: Verify PhaseTimer data and capture live SSE events (2-3 hours)~~ **COMPLETE** -- see measurement report
- Plan 01: Consolidate to one citation approach (0.5-1 day)

**Sprint 2** (after Sprint 1):
- Plan 02: Enrich citations with DB metadata (2-3 days)
- Plan 03: Add backend progress events (1-2 days) -- can start as soon as Plan 00 data is collected

**Sprint 3** (after Sprint 2):
- Plan 04: UI progress display (1 day)

**Deferred** (evaluate after Sprint 3):
- Plan 05: Content file serving, expandable previews, incremental answer display

## API Contract Impact

| Plan | Contract Change | Version Bump |
|------|----------------|-------------|
| 00 | None | None |
| 01 | None (may update CLAUDE.md template) | None |
| 02 | Extend `SourceCitation` with 3 new optional fields | 1.9.0 -> 1.10.0 (minor) |
| 03 | Add `progress` SSE event type | 1.10.0 -> 1.11.0 (minor) -- or combine with Plan 02 in 1.10.0 |
| 04 | None (UI consumes existing events) | None |
| 05 | TBD (new endpoint for content text) | Future minor bump |

## Total Estimated Effort

| Track | Plans | Estimated Days | Status |
|-------|-------|---------------|--------|
| Measurement | 00 | 0.5 | **COMPLETE** |
| Citations | 01 + 02 | 3-4 | Pending |
| Progress | 03 + 04 | 2-3 | Plans updated per measurement |
| **Total** | **00-04** | **5.5-7.5 days** | |

---

*Plans created 2026-02-07 based on research documents #06-#10. Plans 03-04 updated 2026-02-07 based on Plan 00 measurement results. Each plan is standalone and contains all context needed for implementation.*
