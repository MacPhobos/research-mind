# Plan 00: Measurement & Verification

**Tier**: 1 (Do Immediately)
**Scope**: research-mind-service only
**Goal**: Verify PhaseTimer data from Plan 01 (question-answer-improvements series), capture live SSE event streams, and confirm what happens during the "silence gap" before building any new features.
**Depends On**: None
**Effort**: 2-3 hours

---

## Rationale

The devil's advocate analysis (Doc #10, "CC-4: The Prior Devil's Advocate Recommendations Are Being Ignored") establishes that **nobody has verified what actually happens during a Q&A query**. All four research documents (#06-#09) build proposals on assumptions about `stream_token` events and timing data that have not been validated with live queries.

Specifically, three critical unknowns must be resolved before implementing Plans 01-04:

1. **Are `stream_token` events emitted during the processing gap?** Doc #06 assumes yes; Doc #10 warns the current command may NOT produce them.
2. **How long is the actual gap between `system_init` and `assistant`?** Doc #08 reveals `CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1` is already set, so the gap may be smaller than the 5-30s assumed.
3. **Does the existing PhaseTimer (from Plan 01 of question-answer-improvements) produce usable data?** Plan 01 was implemented, but the timing data has not been analyzed.

---

## Current State

### PhaseTimer Already Exists

Plan 01 of the question-answer-improvements series (`docs/plans/question-answer-improvements/01-instrument-timing-logs.md`) added a `PhaseTimer` class to `chat_service.py` with 10 timing marks:

| # | Phase Name | What It Measures |
|---|-----------|------------------|
| 1 | `function_entry` | Baseline (0ms) |
| 2 | `cli_path_resolved` | CLI discovery time |
| 3 | `env_prepared` | Environment setup time |
| 4 | `command_built` | Command construction time |
| 5 | `subprocess_spawned` | Process fork+exec time |
| 6 | `first_stdout_byte` | Time to first output |
| 7 | `json_mode_entered` | Plain text phase duration |
| 8 | `first_stage2_event` | Time to first answer content |
| 9 | `stream_complete` | Total stream duration |
| 10 | `response_finalized` | Post-processing overhead |

These produce `TIMING SUMMARY` log lines in JSON format.

### SSE Event Type Classification

The service classifies events into types (see Doc #07 Section 1.2):
- `init_text` -- Plain text initialization (Stage 1)
- `system_init` -- JSON system init event (Stage 1)
- `system_hook` -- JSON hook events (Stage 1)
- `stream_token` -- Token streaming if available (Stage 1)
- `assistant` -- Complete assistant message (Stage 2)
- `result` -- Final result with metadata (Stage 2)

The open question is whether `stream_token` events actually arrive between `system_init` and `assistant`.

---

## Implementation Plan

### Step 1: Collect PhaseTimer Data from 10 Live Queries

Run 10 queries through the UI against sessions with varying content sizes, and collect the `TIMING SUMMARY` log lines.

**Procedure**:

1. Ensure `LOG_LEVEL=INFO` in `.env` (already the default)
2. Start the service: `make dev`
3. Run 10 queries covering:
   - 2 queries on a session with small content (1-3 items)
   - 2 queries on a session with medium content (5-10 items)
   - 2 queries on a session with large content (15+ items)
   - 2 short factual questions ("What is X?")
   - 2 analytical questions ("How does X compare to Y?")
4. Collect `TIMING SUMMARY` lines from the service log
5. Record in a table:

| Query # | Content Size | Question Type | subprocess_spawned | first_stdout_byte | json_mode_entered | first_stage2_event | total_ms |
|---------|-------------|--------------|-------------------|-------------------|-------------------|-------------------|----------|
| 1 | small | factual | ? | ? | ? | ? | ? |
| ... | | | | | | | |

**Key metrics to extract**:
- `first_stdout_byte - subprocess_spawned` = claude-mpm startup time
- `json_mode_entered - first_stdout_byte` = agent/skill sync time (should be near-zero with `CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1`)
- `first_stage2_event - json_mode_entered` = Claude API thinking time (the "silence gap")
- `total_ms` = end-to-end latency

### Step 2: Capture Raw SSE Event Stream

For 3 of the 10 queries, capture the complete SSE event stream to see exactly what events arrive and when.

**Procedure**:

1. After the POST `/api/v1/sessions/{session_id}/chat` returns the `stream_url`, use curl to capture the raw SSE stream:

```bash
curl -N "http://localhost:15010/api/v1/sessions/{session_id}/chat/stream/{message_id}" \
  2>/dev/null | while IFS= read -r line; do
  echo "$(date +%H:%M:%S.%3N) $line"
done > /tmp/sse-capture-{n}.txt
```

2. Alternatively, add temporary debug logging to `stream_claude_mpm_response()` that logs each raw SSE event with a timestamp before yielding:

**File**: `app/services/chat_service.py`

Add temporarily in the event yield section:
```python
# TEMPORARY: Log raw events for analysis
logger.debug(
    "SSE_EVENT [%s] type=%s stage=%s content_len=%d",
    assistant_message_id[:8],
    event_type.value,
    stage.value if stage else "none",
    len(content_str) if content_str else 0,
)
```

3. Set `LOG_LEVEL=DEBUG` temporarily to capture these events
4. Save the output for analysis

### Step 3: Analyze the Gap Period

From the captured SSE streams, answer these questions:

| Question | How to Determine | Impact on Plans |
|----------|-----------------|-----------------|
| Are `stream_token` events emitted during the gap? | Check SSE capture between `system_init` and `assistant` events | If NO: Plan 04 cannot use frontend token parsing (Doc #06 Approach A is invalid) |
| What is the typical gap duration? | `first_stage2_event - json_mode_entered` from PhaseTimer | If <5s: Progress indicators have low impact; if >15s: high impact |
| Is `json_mode_entered` close to `first_stdout_byte`? | Compare the two times | If yes: `CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1` is effective |
| Does `--verbose` produce tool-use events? | Check for tool call JSON in the stream | If yes: could parse for progress; if no: confirms Doc #10's warning |
| Are hook events emitted despite `--no-hooks`? | Check for `system_hook` events in the stream | If no: confirms that hook-based progress detection is impossible |

### Step 4: Document Findings

Create a brief analysis document:

**File**: `docs/research/streaming-measurement-results-{date}.md`

Structure:
```markdown
# Streaming Measurement Results

## Timing Data (10 queries)
[Table of PhaseTimer results]

## Key Findings
- Average gap duration: Xms
- stream_token events during gap: Yes/No
- claude-mpm startup overhead: Xms
- Agent sync overhead: Xms (expected ~0 with SKIP_BACKGROUND_SERVICES)

## Implications for Plans 01-04
- [What changes, if anything]
```

---

## Acceptance Criteria

1. PhaseTimer data collected from at least 10 live queries
2. Raw SSE event stream captured for at least 3 queries
3. The three critical unknowns are resolved:
   - `stream_token` events during gap: confirmed present or absent
   - Actual gap duration: measured (with variance)
   - `CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1` effect: confirmed
4. Findings documented with data, not assumptions

---

## Files Modified

| File | Changes |
|------|---------|
| `app/services/chat_service.py` | Temporary debug logging (remove after measurement) |
| `docs/research/streaming-measurement-results-{date}.md` | New analysis document |

No API contract changes. No database changes. No UI changes. No permanent code changes.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| PhaseTimer from Plan 01 was not actually implemented | Low | High | Check `chat_service.py` for `PhaseTimer` class before starting |
| Service logs are too noisy to find TIMING lines | Low | Low | Use `grep TIMING` to filter |
| 10 queries insufficient for statistical significance | Medium | Low | Focus on identifying patterns, not precise averages |

---

## How This Informs Other Plans

| Finding | Impact |
|---------|--------|
| `stream_token` events present during gap | Plan 04 can use frontend token parsing (Doc #06 Approach A) |
| `stream_token` events absent during gap | Plan 04 must rely entirely on backend progress events (Plan 03) |
| Gap < 5 seconds | Progress indicators have low UX impact; consider deprioritizing Plans 03-04 |
| Gap > 15 seconds | Progress indicators are high-value; prioritize Plans 03-04 |
| Agent sync time near zero | Confirms `CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1` is effective; no need to optimize startup |
| Agent sync time > 3 seconds | `CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1` may not be working as expected |
