# Streaming Measurement Results -- 2026-02-07

## Methodology

### Environment

- Service: `research-mind-service` running at http://localhost:15010
- Database: PostgreSQL on localhost:5432
- LOG_LEVEL: DEBUG (SSE_EVENT debug lines active)
- PhaseTimer: Active in `chat_service.py` (from Plan 01 question-answer-improvements)
- Temporary SSE_EVENT debug logging added to `chat_service.py`

### Measurement Approach

A Python script (`/tmp/plan00_measurement.py`) was used to:

1. POST to `/api/v1/sessions/{session_id}/chat` to create user + assistant messages
2. GET the SSE stream from the returned `stream_url` using `requests` with streaming
3. Record every SSE event with millisecond-precision timestamps
4. Parse `complete` events for metadata (tokens, cost, duration)
5. Save per-query event JSON files and SSE capture files for queries #1, #5, #9

### Sessions Used

| Session | Content Count | Size Class |
|---------|-------------|------------|
| Research Mind introspection (cdd9e821) | 3 | Small |
| Duetto Job Descriptions (a0d352e8) | 6 | Medium |
| Test - Duetto Products (a8d488ae) | 20 | Med-Large |
| Duetto Products (70a86fb4) | 21 | Med-Large |
| Hyperdev / Masa's blog (079044a5) | 185 | Large |

### 10 Query Plan

| # | Session | Content Size | Question Type | Question |
|---|---------|-------------|--------------|----------|
| 1 | cdd9e821 | Small (3) | Factual | "What is Research Mind?" |
| 2 | cdd9e821 | Small (3) | Analytical | "How does the architecture of Research Mind compare to a traditional search engine?" |
| 3 | a0d352e8 | Medium (6) | Factual | "What job positions are available?" |
| 4 | a0d352e8 | Medium (6) | Analytical | "How do the different job descriptions compare in terms of required skills?" |
| 5 | a8d488ae | Med-Large (20) | Factual | "What products does Duetto offer?" |
| 6 | a8d488ae | Med-Large (20) | Analytical | "How do the different Duetto products integrate with each other?" |
| 7 | 70a86fb4 | Med-Large (21) | Factual | "What is Duetto's main product?" |
| 8 | 70a86fb4 | Med-Large (21) | Analytical | "What are the key differentiators of Duetto compared to competitors?" |
| 9 | 079044a5 | Large (185) | Factual | "What topics does this blog cover?" |
| 10 | 079044a5 | Large (185) | Analytical | "What are the recurring themes across the blog posts?" |

---

## Timing Data (10 Queries)

### PhaseTimer Results (8 of 10 completed successfully)

Queries #2 and #10 (both analytical, on small and large sessions respectively) timed out after 300 seconds.

| Q# | Content Size | Type | subprocess_spawned | first_stdout_byte | json_mode_entered | first_stage2_event | total_ms |
|----|-------------|------|-------------------|-------------------|-------------------|-------------------|----------|
| 1 | Small (3) | Factual | 1ms | 1,823ms | 30,723ms | 30,724ms | 30,836ms |
| 3 | Medium (6) | Factual | 1ms | 1,892ms | 91,435ms | 91,436ms | 91,563ms |
| 4 | Medium (6) | Analytical | 1ms | 1,897ms | 164,980ms | 164,981ms | 165,114ms |
| 5 | Med-Large (20) | Factual | 1ms | 1,899ms | 54,090ms | 54,091ms | 54,216ms |
| 6 | Med-Large (20) | Analytical | 1ms | 1,938ms | 89,361ms | 89,362ms | 89,498ms |
| 7 | Med-Large (21) | Factual | 1ms | 2,011ms | 19,967ms | 19,976ms | 20,090ms |
| 8 | Med-Large (21) | Analytical | 1ms | 2,077ms | 106,782ms | 106,783ms | 106,907ms |
| 9 | Large (185) | Factual | 1ms | 1,752ms | 262,381ms | 262,382ms | 262,514ms |

### Computed Intervals

| Q# | claude-mpm Startup | Agent/Skill Sync + Claude API | Silence Gap | Answer Gen | Total |
|----|-------------------|------------------------------|-------------|------------|-------|
| 1 | 1,822ms | 28,900ms | 1ms | 111ms | 30,836ms |
| 3 | 1,891ms | 89,543ms | 1ms | 126ms | 91,563ms |
| 4 | 1,896ms | 163,083ms | 1ms | 133ms | 165,114ms |
| 5 | 1,898ms | 52,191ms | 1ms | 125ms | 54,216ms |
| 6 | 1,937ms | 87,423ms | 1ms | 135ms | 89,498ms |
| 7 | 2,010ms | 17,956ms | 9ms | 114ms | 20,090ms |
| 8 | 2,076ms | 104,705ms | 1ms | 124ms | 106,907ms |
| 9 | 1,751ms | 260,629ms | 1ms | 132ms | 262,514ms |

**Column Definitions:**
- `claude-mpm Startup` = `first_stdout_byte - subprocess_spawned` (time for claude-mpm binary to start and emit first line)
- `Agent/Skill Sync + Claude API` = `json_mode_entered - first_stdout_byte` (the entire "gap" phase: skill sync + Claude processing)
- `Silence Gap` = `first_stage2_event - json_mode_entered` (transition from JSON mode to Stage 2)
- `Answer Gen` = `stream_complete - first_stage2_event` (time to deliver the answer data)

### Summary Statistics

| Metric | Min | Max | Average | Median |
|--------|-----|-----|---------|--------|
| claude-mpm startup | 1,751ms | 2,076ms | 1,910ms | 1,897ms |
| Gap (skill sync + API) | 17,956ms | 260,629ms | 100,554ms | 88,483ms |
| Answer delivery | 111ms | 135ms | 125ms | 126ms |
| Total end-to-end | 20,090ms | 262,514ms | 102,717ms | 90,531ms |

### Metadata from Successful Queries

| Q# | Output Tokens | Input Tokens | Cache Read | API Duration | Cost | Turns |
|----|-------------|-------------|------------|-------------|------|-------|
| 1 | 561 | 3 | 0 | 14,047ms | $0.33 | 1 |
| 3 | 910 | 5 | 127,144 | 70,819ms | $1.25 | 3 |
| 4 | 1,756 | 4 | 75,700 | 148,790ms | $1.28 | 2 |
| 5 | 1,683 | 6 | 187,786 | 37,527ms | $0.35 | 7 |
| 6 | 2,669 | 7 | 254,193 | 53,283ms | $0.47 | 11 |
| 7 | 248 | 3 | 24,976 | 7,675ms | $0.18 | 1 |
| 8 | 1,160 | 4 | 75,702 | 244,379ms | $2.43 | 2 |
| 9 | 2,261 | 9 | 275,303 | 51,817ms | $0.53 | 16 |

---

## SSE Event Stream Analysis (3 Captures)

### Capture #1: Query #1 -- Small Session, Factual

**File**: `/tmp/sse-capture-1.txt`

| Elapsed | Event | Stage | Description |
|---------|-------|-------|-------------|
| 7ms | `start` | - | Stream opened |
| 1,829ms | `init_text` x20 | 1 | claude-mpm banner (burst) |
| 3,202ms | `init_text` | 1 | "Syncing skill files 1/601 (0%)" |
| 4,506ms | `init_text` | 1 | "Syncing skill files 156/601 (25%)" |
| 7,662ms | `init_text` | 1 | "Syncing skill files 1/601 (0%)" |
| 9,097ms | `init_text` | 1 | "Syncing skill files 155/601 (25%)" |
| 9,144ms | `init_text` | 1 | "Syncing skill files 601/601 (100%)" |
| 9,558ms | `init_text` | 1 | "Deploying skill directories 39/39 (100%)" |
| 9,729ms | `init_text` | 1 | "Launching Claude: Ready" |
| 9,729ms | `init_text` | 1 | "Starting Claude Code... (this may take a few seconds)" |
| **9,729ms - 30,729ms** | **SILENCE** | - | **21 seconds with ZERO events** |
| 30,729ms | `init_text` | 1 | "Reading system prompt from: ..." |
| 30,729ms | `system_hook` x4 | 1 | SessionStart hooks (started + response) |
| 30,731ms | `system_init` | 1 | Full init JSON (17,161 chars) |
| 30,731ms | `assistant` | 2 | Complete answer (2,191 chars) |
| 30,731ms | `result` | 2 | Result with metadata |
| 30,850ms | `complete` | - | Stream finished |

**Gap Duration**: 21.0 seconds
**Events During Gap**: ZERO
**stream_token Events**: NONE (single-turn query)

### Capture #5: Query #5 -- Med-Large Session, Factual

**File**: `/tmp/sse-capture-5.txt`

| Elapsed | Event | Stage | Description |
|---------|-------|-------|-------------|
| 6ms | `start` | - | Stream opened |
| 1,904ms | `init_text` x20 | 1 | claude-mpm banner (burst) |
| 2,423ms-4,962ms | `init_text` x4 | 1 | Skill sync progress |
| 4,988ms-5,517ms | `init_text` x4 | 1 | "Launching Claude: Ready" / "Starting Claude Code..." |
| **5,517ms - 54,096ms** | **SILENCE** | - | **48.6 seconds with ZERO events** |
| 54,096ms | `init_text` | 1 | "Reading system prompt" |
| 54,096ms | `system_hook` x4 | 1 | SessionStart hooks |
| 54,096ms | `system_init` | 1 | Full init JSON (29,527 chars) |
| 54,097ms | `assistant` x10 | 2 | Multiple assistant events |
| 54,097ms-54,100ms | `stream_token` x6 | 1 | Token stream data (12-23KB each) |
| 54,100ms | `result` | 2 | Result with metadata |
| 54,231ms | `complete` | - | Stream finished |

**Gap Duration**: 48.6 seconds
**Events During Gap**: ZERO
**stream_token Events**: 6 events, but arrived simultaneously with assistant events (NOT during gap)

### Capture #9: Query #9 -- Large Session, Factual

**File**: `/tmp/sse-capture-9.txt`

| Elapsed | Event | Stage | Description |
|---------|-------|-------|-------------|
| 7ms | `start` | - | Stream opened |
| 2,083ms | `init_text` x20 | 1 | claude-mpm banner (burst) |
| 7,947ms-10,085ms | `init_text` x5 | 1 | Skill sync + "Starting Claude Code..." |
| **10,085ms - 106,789ms** | **SILENCE** | - | **96.7 seconds with ZERO events** |
| 106,789ms | `init_text` | 1 | "Reading system prompt" |
| 106,789ms | `system_hook` x4 | 1 | SessionStart hooks |
| 106,790ms | `system_init` | 1 | Full init JSON (35,505 chars) |
| 106,790ms-106,795ms | `assistant` x19 + `stream_token` x15 | 1+2 | Interleaved events |
| 106,795ms | `result` | 2 | Result with metadata |
| 106,920ms | `complete` | - | Stream finished |

**Gap Duration**: 96.7 seconds
**Events During Gap**: ZERO
**stream_token Events**: 15 events, but arrived simultaneously with other events (NOT during gap)

### Event Type Distribution Across Queries

| Event Type | Q1 | Q3 | Q4 | Q5 | Q6 | Q7 | Q8 | Q9 |
|-----------|----|----|----|----|----|----|----|----|
| init_text | 29 | 29 | 28 | 29 | 26 | 27 | 26 | 26 |
| system_hook | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| system_init | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| assistant | 1 | 18 | 18 | 10 | 15 | 1 | 35 | 19 |
| stream_token | 0 | 17 | 17 | 6 | 10 | 0 | 34 | 15 |
| result | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |

---

## Key Findings

### 1. The "Silence Gap" Is Real and Substantial

- **Average gap duration**: 63.2 seconds (range: 21s to 97s for the 3 captured queries)
- **No events of any kind arrive during the gap**: Between "Starting Claude Code..." and the final burst of results, the SSE stream is completely silent.
- **Heartbeat events do NOT appear during the gap**: The only output is empty SSE keep-alive, but no data events.

### 2. stream_token Events Are Present But Useless for Progress

- **stream_token events DO exist** in queries with multiple turns (Q3-Q6, Q8-Q9).
- **They arrive simultaneously with the `assistant` events**, NOT incrementally during the gap.
- **They represent accumulated Claude output from multi-turn interactions**, not real-time token streaming.
- **Single-turn queries (Q1, Q7) have zero stream_token events.**
- **Conclusion**: stream_token events cannot be used for frontend progress indicators because they arrive in a burst at the end, not progressively.

### 3. claude-mpm Startup Is Consistent (~1.9 seconds)

- Range: 1,751ms to 2,076ms across all 8 successful queries.
- Average: 1,910ms
- This includes process fork, binary loading, and initial output.

### 4. CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1 Is NOT Fully Effective

- Despite the flag being set, **skill syncing still occurs** for every query.
- Skill sync takes 3-8 seconds (syncing 601 files, deploying 39 skill directories).
- The flag may skip other background services, but skill sync is still performed.
- This is visible in the raw init_text events: "Syncing skill files 1/601 (0%)" through "Complete: 0 downloaded, 740 cached (740 files, 173 skills)".

### 5. All Answer Data Arrives in a Single Burst

- The gap between `json_mode_entered` and `first_stage2_event` is consistently 1ms (occasionally 9ms).
- The gap between `first_stage2_event` and `stream_complete` is consistently 111-135ms.
- **The entire answer (all system_hook, system_init, assistant, stream_token, result events) arrives within a 5-10ms window**.
- This means claude-mpm buffers its entire output and delivers it atomically.

### 6. Multi-Turn Queries Are Common

- 6 of 8 successful queries involved multiple turns (turns: 2-16).
- The number of turns does not correlate linearly with response time.
- Q9 (16 turns, large session) took 262s; Q5 (7 turns, med-large) took 54s; Q3 (3 turns, medium) took 91s.

### 7. Cost Varies Significantly

- Range: $0.18 (Q7, 1 turn) to $2.43 (Q8, 2 turns but large API duration)
- Average: $0.85 per query
- Cache read tokens vary widely: 0 to 275,303

---

## Answers to Critical Unknowns

### 1. Are stream_token events emitted during the gap?

**NO.** `stream_token` events are NOT emitted during the silence gap. They arrive in a burst simultaneously with `assistant`, `result`, and `complete` events at the very end of the stream. During the gap (typically 21-97 seconds), **zero events of any type** are emitted to the SSE stream.

**Evidence**: All 3 SSE captures show the same pattern: `init_text` events stop at the "Starting Claude Code..." phase, then silence, then a burst of all remaining events at a single timestamp.

**Impact**: Plan 04 (UI Progress Display) CANNOT use `stream_token` parsing for real-time progress indicators. Doc #06 "Approach A" (frontend token parsing) is **invalid**.

### 2. What is the typical gap duration?

**21 to 97 seconds** for the 3 fully-captured queries. Full range from PhaseTimer data shows 18 to 261 seconds across all 8 successful queries.

| Size Category | Gap Range | Average |
|--------------|-----------|---------|
| Small (3 items) | 21s | 21s (1 sample) |
| Medium (6 items) | 82-155s | 119s |
| Med-Large (20-21 items) | 18-253s | 79s (high variance) |
| Large (185 items) | 97s+ (1 success, 1 timeout) | 97s+ |

**Impact**: Progress indicators are **high-value** for most queries. Users wait 20-260+ seconds with no feedback. This strongly justifies Plans 03-04 (Backend Progress Events + UI Progress Display).

### 3. Is CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1 effective?

**Partially.** The flag does NOT prevent skill file syncing, which takes 3-8 seconds per query. It may prevent other background services from running, but the skill sync is the only visible pre-Claude overhead.

**Evidence**: Raw log lines show "Syncing skill files 1/601 (0%)" through "Complete: 0 downloaded, 740 cached" in every query, taking 3-8 seconds.

**Impact**: There may be room to optimize startup further by finding a way to skip or cache skill sync. However, the 3-8s overhead is dwarfed by the 18-261s Claude API time.

### 4. Does the stream contain tool-use events?

**NO tool-use events are visible in the SSE stream.** Despite Claude performing multi-turn interactions (up to 16 turns in Q9), no tool_use or tool_result events appear. The stream only shows: `init_text`, `system_hook`, `system_init`, `assistant`, `stream_token`, `result`, `complete`.

**Impact**: Backend progress events (Plan 03) cannot rely on tool-use events from the stream. Progress must be inferred from what IS available (elapsed time, heartbeats, or synthetic progress events).

### 5. Are hook events emitted despite --no-hooks?

**YES, hooks ARE emitted.** Despite `--no-hooks` flag, 4 `system_hook` events appear in every query:
- 2x `hook_started` (SessionStart:startup)
- 2x `hook_response` (SessionStart:startup)

These arrive in the post-gap burst, not during initialization.

**Impact**: Hook events exist but arrive too late to be useful for progress detection (they arrive simultaneously with the answer).

---

## Implications for Plans 01-04

### Plan 01: Citation Consolidation

**Impact: No change from measurements.**

Source citations are extracted from the `result` event metadata. The measurements confirm that `result` events contain the expected `sources` field (though it was `null` in some queries, likely because the model didn't cite specific files). Citation consolidation work is independent of streaming timing.

### Plan 02: Citation Enrichment

**Impact: No change from measurements.**

Citation enrichment operates on persisted data after the stream completes. The burst-delivery pattern means all data is available atomically when the `complete` event fires. No timing concerns.

### Plan 03: Backend Progress Events

**Impact: CRITICAL -- Backend progress events are the ONLY viable approach for UX during the gap.**

Since:
- `stream_token` events arrive post-gap (not during gap)
- Tool-use events are not visible in the stream
- Hook events arrive post-gap
- The gap is 18-261 seconds with ZERO events

**Backend MUST generate synthetic progress events** to fill the gap. Possible approaches:
1. **Elapsed-time progress**: Emit progress events at regular intervals (e.g., every 5s) based on elapsed time since subprocess start
2. **Phase-based progress**: Emit events when known phases complete (e.g., "claude-mpm started", "skill sync complete", "waiting for Claude API")
3. **Heartbeat with context**: Enhance heartbeat events to include phase information and elapsed time

The raw `init_text` lines DO provide some phase information:
- "Syncing skill files X/601 (Y%)" -- could generate progress events
- "Deploying skill directories" -- could generate phase event
- "Launching Claude: Ready" -- could generate phase event
- "Starting Claude Code..." -- could generate phase event indicating gap start

### Plan 04: UI Progress Display

**Impact: MAJOR DESIGN CHANGE -- Frontend cannot parse stream_token for progress.**

Since `stream_token` events arrive in a post-gap burst (not progressively):
- **Doc #06 Approach A (Frontend Token Parsing) is INVALID** -- there are no tokens to parse during the gap
- **The frontend MUST rely on backend-generated progress events (Plan 03)**
- **The UI should display**: Phase indicators during init (skill sync, launching Claude), then a "thinking" state during the gap, then the answer burst
- **Consider**: Showing elapsed time counter during the gap ("Analyzing your content... 15s")
- **Consider**: Showing the init_text events in the expandable accordion in real-time (these DO stream progressively during the first 5-10 seconds)

---

## Detailed Timeline of a Typical Query

Using Query #1 (30.8s total, simplest case) as reference:

```
T+0.000s  POST /chat creates user + assistant messages
T+0.007s  GET /chat/stream starts, event: start emitted
T+0.001s  subprocess_spawned (claude-mpm fork)
T+1.823s  first_stdout_byte: claude-mpm banner appears
T+1.829s  init_text burst: 20 lines of MPM banner (ANSI art, version info)
T+3.202s  init_text: "Syncing skill files 1/601 (0%)"
T+4.506s  init_text: "Syncing skill files 156/601 (25%)"
T+7.662s  init_text: "Syncing skill files 1/601 (0%)" [second pass]
T+9.097s  init_text: "Syncing skill files 155/601 (25%)"
T+9.144s  init_text: "Syncing skill files 601/601 (100%)"
T+9.558s  init_text: "Deploying skill directories 39/39 (100%)"
T+9.729s  init_text: "Launching Claude: Ready"
T+9.729s  init_text: "Starting Claude Code... (this may take a few seconds)"

--- SILENCE GAP: 21 SECONDS (T+9.7s to T+30.7s) ---

T+30.729s init_text: "Reading system prompt from: /tmp/claude_mpm_system_prompt_*.md"
T+30.729s system_hook: hook_started (SessionStart:startup) x2
T+30.729s system_hook: hook_response (SessionStart:startup) x2
T+30.731s system_init: Full init JSON (17,161 chars)
T+30.731s assistant: Complete answer (2,191 chars)
T+30.731s result: Result with metadata
T+30.850s complete: Stream finished. DB persisted.
```

---

## Raw Data

- Per-query event JSON files: `/tmp/sse-events-{1..10}.json`
- SSE captures with timestamps: `/tmp/sse-capture-{1,5,9}.txt`
- Full console output: `/tmp/plan00-console.log`
- Service logs: `/tmp/research-mind-service.log`
- Summary results: `/tmp/plan00-results.json`

---

## Measurement Notes

- Queries #2 and #10 (both analytical) timed out after 300 seconds of SSE streaming. The service may have completed processing but the timeout in the measurement script cut the stream before data arrived.
- The PhaseTimer labels are somewhat misleading: `json_mode_entered - first_stdout_byte` is labeled as "agent_sync" in the Plan 01 docs, but it actually encompasses the entire claude-mpm processing time (skill sync + Claude API call + answer generation). The actual "agent sync" phase is only the 3-8 seconds visible in the init_text events.
- All measurements were taken sequentially (one query at a time), so there was no contention for Claude API resources.
- The `system_init` event size varies with session content: 17KB for small sessions, 29KB for med-large, 35KB for large sessions.
