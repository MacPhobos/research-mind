# Plan 03: Backend Progress Events

**Tier**: 2 (Do Next)
**Scope**: research-mind-service (new SSE event type + API contract)
**Goal**: Add a `progress` SSE event type with 4 reliable phases so the UI can show meaningful status during the 18-261 second "silence gap" between query submission and answer delivery.
**Depends On**: Plan 00 (Measurement & Verification) -- timing data informs phase thresholds
**Effort**: 1-2 days
**Updated**: 2026-02-07 based on Plan 00 measurement results (see `docs/research/streaming-measurement-results-2026-02-07.md`)

---

## Rationale

The accordion currently shows "Starting Claude Code..." then goes silent for 18-261 seconds until the final answer arrives (Doc #06, Section 1.1). Users see a pulsing green dot but no information about what the system is doing.

Doc #07 proposes a `progress` SSE event type with 8 phases. Doc #10 (Critique 4) trims this to **3-4 reliably detectable phases**, warning that many proposed phases are either too fast to be visible (<100ms), unavailable because flags are disabled (`--no-hooks`, `CLAUDE_MPM_SKIP_BACKGROUND_SERVICES=1`), or synthetic (time-based guessing).

**Plan 00 measurement results (2026-02-07) revealed critical constraints** that reshape this plan's design:

1. **claude-mpm buffers ALL output and delivers it atomically.** During the 18-261 second processing gap, ZERO events are emitted. Everything (system_init, assistant, stream_token, result) arrives in a single burst at the end.
2. **`stream_token` events are NOT emitted during the gap.** They arrive in the final burst alongside `assistant` and `result` events.
3. **`system_init` arrives in the post-gap burst, not during initialization.** The original `connected` phase trigger (detecting `system_init`) is invalid.
4. **`init_text` events ARE emitted progressively during startup** (skill sync phases, ~3-8 seconds), providing the only real-time signal before the silence gap.
5. **The gap duration is 18-261 seconds** (avg 100s), strongly justifying progress indicators.

This plan implements **4 progress phases** -- 2 based on reliably detectable signals, 1 time-based during the silence gap, and 1 on the post-gap burst arrival.

---

## Plan 00 Measurement Results Summary

> Full report: `docs/research/streaming-measurement-results-2026-02-07.md`

Plan 00 measured 10 queries (8 successful, 2 timed out) across 5 sessions of varying size (3-185 content items). Key findings that reshape this plan:

| Finding | Data | Impact on This Plan |
|---------|------|-------------------|
| Silence gap duration | 18-261 seconds (avg 100s) | Users need feedback; strongly justifies this plan |
| Events during gap | ZERO (no events of any type) | Only synthetic/time-based progress is possible during gap |
| `system_init` arrival | In the post-gap burst, NOT during init | Original `connected` phase trigger is **invalid** |
| `stream_token` arrival | In the post-gap burst, NOT progressively | Cannot use token events for progress |
| First stage 2 event | Arrives simultaneously with ALL other burst events | Original `answering` phase trigger is **useless** (answer is already complete) |
| `init_text` during startup | Emitted progressively during first 3-8s | Only real-time signal available before the silence gap |
| Skill sync despite SKIP flag | 3-8 seconds, 601 files / 173 skills | Detectable via init_text parsing |
| claude-mpm startup | ~1.9s consistent | Subprocess spawn to first output |
| Answer delivery | 111-135ms burst | Everything arrives atomically at the end |

### Critical Invalidation: Original Phase Triggers

The original plan proposed detecting `system_init` for the `connected` phase and first stage 2 event for the `answering` phase. **Both are invalid:**

- **`system_init`** arrives at T+30.7s (Query #1) in the same burst as the answer, NOT during initialization. It cannot be used as a mid-stream progress signal.
- **First `assistant` event** arrives simultaneously with `system_init`, `result`, and `complete`. By the time we detect "answering", the answer is already complete and the stream is ending.

The only events that arrive **progressively** (not in a burst) are `init_text` events during the first 3-10 seconds of each query.

---

## Current State

### SSE Infrastructure

The SSE pipeline is mature (Doc #07 Section 1.2):

| Feature | Status | Location |
|---------|--------|----------|
| Event typing (6 types) | Implemented | `schemas/chat.py:17-44` |
| Stage classification | Implemented | `schemas/chat.py:47-61` |
| Heartbeat keep-alive (15s) | Implemented | `chat_service.py:636-645` |
| PhaseTimer instrumentation | Implemented | `chat_service.py:55-87` |
| Error event propagation | Implemented | `chat_service.py:903-943` |

### PhaseTimer Marks -- Updated Assessment from Plan 00

The `PhaseTimer` records timing at 10 points. Updated assessment based on measurement data:

| PhaseTimer Mark | Reliable Signal? | Proposed Progress Phase | Plan 00 Finding |
|----------------|-----------------|------------------------|-----------------|
| `subprocess_spawned` | Yes | "Starting..." | Consistent at T+1ms |
| `first_stdout_byte` | Yes | "Initializing..." | Consistent at ~T+1.9s; init_text events start here |
| `json_mode_entered` | **No (for progress)** | ~~"Connected"~~ | Arrives in post-gap burst; cannot be used as mid-stream signal |
| `first_stage2_event` | **No (for progress)** | ~~"Answering"~~ | Arrives simultaneously with answer; useless as progress indicator |
| `stream_complete` | Yes | (Not a separate phase) | 111-135ms after first_stage2_event |

### What Is NOT Reliably Detectable -- Updated from Plan 00

| Proposed Phase | Why Unreliable | Plan 00 Evidence |
|---------------|---------------|-----------------|
| "Preparing" | <100ms, users won't see it | Confirmed: subprocess_spawned at T+1ms |
| "Connected" (system_init) | Arrives in post-gap burst, NOT during initialization | Confirmed: system_init at T+30.7s in Q1, same timestamp as answer |
| "Answering" (first stage2) | Answer already complete when detected | Confirmed: all stage 2 events arrive in 5-10ms burst |
| "Searching" (hook events) | Hooks arrive in post-gap burst | Confirmed: system_hook events at same timestamp as answer |
| "Completing" | Instantaneous (~0ms) | Confirmed: 111-135ms from first stage2 to stream_complete |

### What IS Reliably Detectable -- From Plan 00

| Signal | Timing | How Detected |
|--------|--------|-------------|
| Subprocess spawned | T+1ms | `asyncio.create_subprocess_exec` returns |
| init_text: skill sync progress | T+2s to T+9s | Parse "Syncing skill files X/601 (Y%)" from stdout |
| init_text: "Starting Claude Code..." | T+5s to T+10s | Last init_text before silence gap |
| Silence gap begins | ~T+10s | Timeout on stdout readline (no more init_text events) |
| Post-gap burst arrives | T+20s to T+262s | Any event after the silence gap (system_init, assistant, etc.) |

---

## Implementation Plan

### Design: Four Progress Phases (Revised Per Plan 00 Findings)

| Phase | SSE Value | Detection Signal | Typical Duration | Human Message |
|-------|----------|-----------------|-----------------|---------------|
| `starting` | `"starting"` | After `subprocess_spawned` | ~1.9s | "Starting Claude Code..." |
| `initializing` | `"initializing"` | First `init_text` event parsed (skill sync) | 3-8s | "Initializing... syncing skills (25%)" |
| `thinking` | `"thinking"` | Timeout: no stdout for 5s after last `init_text` (silence gap entered) | 18-261s | "Thinking... (45s)" |
| `complete` | `"complete"` | First event after the silence gap (any burst event) | <1s | "Generating answer..." |

**Key design change from original plan**: The original `connected` and `answering` phases have been replaced with `initializing` and `complete`. The measurement data proves that `system_init` and first stage 2 events all arrive in a single atomic burst at the end -- they cannot serve as mid-stream progress triggers.

**Why `initializing` replaces `connected`**: The `init_text` events ARE emitted progressively during the first 3-10 seconds. They contain parseable skill sync progress ("Syncing skill files 156/601 (25%)") and phase transitions ("Launching Claude: Ready", "Starting Claude Code..."). These are the only real-time signals available before the silence gap.

**Why `thinking` is entered on silence, not on a timer after `connected`**: The original plan proposed entering `thinking` 8 seconds after `system_init`. Since `system_init` arrives in the post-gap burst, this is impossible. Instead, `thinking` is entered when `init_text` events stop arriving -- detected via a readline timeout. Once 5 seconds pass with no stdout from the subprocess, we know the silence gap has begun and Claude is processing the query.

**Why `complete` replaces `answering`**: By the time we detect the first stage 2 event, the entire answer has already been delivered in the burst. "Answering" is misleading -- the answer is already complete. The `complete` phase signals the UI to transition from the progress state to the answer display.

**Why only 4 phases**: Plan 00 confirms that only 2 signals are truly real-time (subprocess spawn, init_text events). The silence gap has zero events. The post-gap burst is atomic. Four phases correctly models reality without false precision.

### Elapsed Time Counter During `thinking` Phase

The silence gap (18-261 seconds) is the period where users most need reassurance. **The `thinking` phase should include periodic elapsed-time updates** to show the system is still working:

- Emit a `progress` event every 10 seconds during the `thinking` phase
- Each event updates `elapsed_ms` and the message: "Thinking... (15s)", "Thinking... (25s)", etc.
- This replaces the heartbeat keep-alive (which carries no semantic information) with meaningful progress updates

**Measurement justification**: The average gap is 100 seconds, with a maximum of 261 seconds. Without periodic updates, users see nothing for potentially 4+ minutes. A 10-second interval provides ~10-26 updates across the gap, giving continuous feedback that the system is alive.

### Step 1: Add ProgressPhase Enum and Schema

**File**: `research-mind-service/app/schemas/chat.py`

Add after the existing `ChatStreamEventType` enum:

```python
class ProgressPhase(str, Enum):
    STARTING = "starting"
    INITIALIZING = "initializing"
    THINKING = "thinking"
    COMPLETE = "complete"


class ChatStreamProgressEvent(BaseModel):
    """Structured progress update during Q&A streaming."""
    phase: ProgressPhase
    message: str                     # Human-readable description
    elapsed_ms: int                  # Milliseconds since stream started
```

Add `PROGRESS` to `ChatStreamEventType`:

```python
class ChatStreamEventType(str, Enum):
    START = "start"
    INIT_TEXT = "init_text"
    SYSTEM_INIT = "system_init"
    SYSTEM_HOOK = "system_hook"
    STREAM_TOKEN = "stream_token"
    ASSISTANT = "assistant"
    RESULT = "result"
    PROGRESS = "progress"          # NEW
    ERROR = "error"
    HEARTBEAT = "heartbeat"
```

### Step 2: Add Progress Event Emission to Streaming Generator

**File**: `research-mind-service/app/services/chat_service.py`

Add a helper function for constructing progress events:

```python
def _make_progress_event(
    phase: ProgressPhase,
    message: str,
    timer: PhaseTimer,
) -> dict:
    """Create a progress SSE event dict."""
    elapsed_ms = int((time.monotonic() - timer.start) * 1000)
    return {
        "event_type": ChatStreamEventType.PROGRESS,
        "stage": ChatStreamStage.EXPANDABLE,
        "content": json.dumps({
            "phase": phase.value,
            "message": message,
            "elapsed_ms": elapsed_ms,
        }),
    }
```

Then inject progress events at 4 locations in `stream_claude_mpm_response()`:

**Location 1: After subprocess_spawned** (Phase: `starting`)

```python
# After: process = await asyncio.create_subprocess_exec(...)
timer.mark("subprocess_spawned")
yield _make_progress_event(
    ProgressPhase.STARTING,
    "Starting Claude Code...",
    timer,
)
```

**Location 2: When init_text events are being parsed** (Phase: `initializing`)

Parse skill sync progress from `init_text` lines to generate informative progress messages.

```python
initializing_emitted = False
# Inside the stdout reading loop, when processing init_text lines:
if not initializing_emitted:
    # Detect skill sync or "Starting Claude Code..." in init_text
    if "Syncing skill files" in line_text or "Starting Claude Code" in line_text:
        initializing_emitted = True
        yield _make_progress_event(
            ProgressPhase.INITIALIZING,
            "Initializing environment...",
            timer,
        )

# Optionally, parse sync percentage for more detailed messages:
import re
sync_match = re.search(r"Syncing skill files \d+/\d+ \((\d+)%\)", line_text)
if sync_match and initializing_emitted:
    pct = sync_match.group(1)
    yield _make_progress_event(
        ProgressPhase.INITIALIZING,
        f"Initializing... syncing skills ({pct}%)",
        timer,
    )
```

**Location 3: Silence gap detection via readline timeout** (Phase: `thinking`)

The silence gap begins when `init_text` events stop and no more stdout arrives. Use `asyncio.wait_for()` with a 5-second timeout on readline to detect the gap entrance, then emit periodic elapsed-time updates every 10 seconds.

```python
thinking_entered = False
last_thinking_update_ms = 0

# Replace the blocking readline with a timeout-aware version:
try:
    line = await asyncio.wait_for(
        process.stdout.readline(),
        timeout=5.0 if initializing_emitted else None
    )
except asyncio.TimeoutError:
    # No stdout for 5 seconds after init_text stopped -- silence gap entered
    elapsed_ms = int((time.monotonic() - timer.start) * 1000)

    if not thinking_entered:
        thinking_entered = True
        last_thinking_update_ms = elapsed_ms
        yield _make_progress_event(
            ProgressPhase.THINKING,
            f"Thinking... ({elapsed_ms // 1000}s)",
            timer,
        )
    elif elapsed_ms - last_thinking_update_ms >= 10_000:
        # Periodic update every 10 seconds during the gap
        last_thinking_update_ms = elapsed_ms
        yield _make_progress_event(
            ProgressPhase.THINKING,
            f"Thinking... ({elapsed_ms // 1000}s)",
            timer,
        )
    continue  # Loop back to readline
```

**Why 5-second timeout for gap detection**: Plan 00 data shows init_text events arrive within the first 3-10 seconds, with the last one ("Starting Claude Code...") at T+5s to T+10s. A 5-second silence after the last init_text reliably indicates the gap has begun.

**Why 10-second periodic updates**: The gap averages 100 seconds (range 18-261s). A 10-second interval provides 2-26 updates across the gap without being excessive, giving users continuous reassurance. The message includes the elapsed time counter: "Thinking... (25s)", "Thinking... (35s)", etc.

**Location 4: When post-gap burst arrives** (Phase: `complete`)

The first event after the silence gap (any of: system_init, system_hook, assistant, result) signals that the answer has been delivered.

```python
# When any event arrives after the silence gap:
if thinking_entered and not complete_emitted:
    complete_emitted = True
    yield _make_progress_event(
        ProgressPhase.COMPLETE,
        "Generating answer...",
        timer,
    )
```

**Note on the `complete` phase**: This phase is brief (<200ms based on Plan 00 data showing 111-135ms answer delivery). It serves as a transition signal for the UI to switch from the progress display to the answer display. The UI may not even show this phase if the answer renders immediately.

### Step 3: Add Progress Event to classify_event()

**File**: `research-mind-service/app/services/chat_service.py`

Update `classify_event()` to handle the new `PROGRESS` event type. Since progress events are constructed internally (not from subprocess output), they bypass `classify_event()`. However, add the type to the classification for completeness:

```python
# In classify_event() or the event routing logic:
if event_type == ChatStreamEventType.PROGRESS:
    stage = ChatStreamStage.EXPANDABLE  # Always Stage 1
```

### Step 4: Update API Contract

**File**: `research-mind-service/docs/api-contract.md`

Add `progress` to the SSE Event Types table (around line 1530):

```
| `progress` | 1 | Structured progress update during processing |
```

Add the progress event schema after the Chunk Event Schema:

```typescript
interface ChatStreamProgressEvent {
  phase: "starting" | "initializing" | "thinking" | "complete";
  message: string;           // Human-readable status description
  elapsed_ms: number;        // Milliseconds since stream started
}
```

Add to the Example SSE Stream:

```
event: chunk
data: {"content":"{\"phase\":\"starting\",\"message\":\"Starting Claude Code...\",\"elapsed_ms\":487}","event_type":"progress","stage":1,"raw_json":null}

event: chunk
data: {"content":"{\"phase\":\"initializing\",\"message\":\"Initializing... syncing skills (25%)\",\"elapsed_ms\":4506}","event_type":"progress","stage":1,"raw_json":null}

event: chunk
data: {"content":"{\"phase\":\"thinking\",\"message\":\"Thinking... (15s)\",\"elapsed_ms\":14729}","event_type":"progress","stage":1,"raw_json":null}

event: chunk
data: {"content":"{\"phase\":\"thinking\",\"message\":\"Thinking... (25s)\",\"elapsed_ms\":24729}","event_type":"progress","stage":1,"raw_json":null}
```

Add changelog entry:
```
| 1.10.0 (or 1.11.0) | 2026-XX-XX | Added `progress` SSE event type with structured progress phases (starting, initializing, thinking, complete). Includes periodic elapsed-time updates during thinking phase. Progress events are Stage 1 (EXPANDABLE) and not persisted. |
```

**Note**: If this ships in the same release as Plan 02's citation enrichment, combine in a single version bump to 1.10.0.

### Step 5: Sync Contract to Frontend

1. Copy contract: `cp research-mind-service/docs/api-contract.md research-mind-ui/docs/api-contract.md`
2. Regenerate types: `make gen-client`

The frontend handling of progress events is covered in Plan 04 (UI Progress Display).

---

## Files Modified

| File | Changes |
|------|---------|
| `research-mind-service/app/schemas/chat.py` | Add `ProgressPhase` enum, `ChatStreamProgressEvent` model, `PROGRESS` to `ChatStreamEventType` |
| `research-mind-service/app/services/chat_service.py` | Add `_make_progress_event()` helper; inject 4 progress yields in `stream_claude_mpm_response()` |
| `research-mind-service/docs/api-contract.md` | Add `progress` event type documentation, version bump |
| `research-mind-ui/docs/api-contract.md` | Sync from service |

---

## API Contract Impact

**Version bump**: Minor (new optional event type, backward compatible)

**Backward compatibility**: The `progress` event is a new SSE event type. Existing clients that only listen for `start`, `chunk`, `complete`, `error`, and `heartbeat` will ignore `progress` events. No breaking changes.

**Stage classification**: Progress events are Stage 1 (EXPANDABLE) -- they are ephemeral status updates, NOT persisted to the database.

---

## Acceptance Criteria

1. SSE stream includes `progress` events with the 4 defined phases (`starting`, `initializing`, `thinking`, `complete`)
2. `starting` event fires within 1 second of stream beginning
3. `initializing` event fires when first skill sync `init_text` event is parsed (~2-3 seconds)
4. `thinking` event fires when silence gap is detected (5s of no stdout after last `init_text`)
5. During the `thinking` phase, periodic progress events are emitted every 10 seconds with updated elapsed time
6. `complete` event fires when the first post-gap burst event arrives (system_init, assistant, or result)
7. Each progress event includes `phase`, `message`, and `elapsed_ms`
8. `thinking` phase messages include the elapsed time counter: "Thinking... (25s)"
9. Progress events are classified as Stage 1 (EXPANDABLE)
10. Progress events are NOT persisted to the database
11. Existing SSE consumers (UI) are not broken by the new event type

---

## Validation

1. Start the service and submit a query through the UI
2. Use `curl -N` to capture the raw SSE stream
3. Verify progress events appear in the stream:
   ```
   event: chunk
   data: {..., "event_type": "progress", "stage": 1, ...}
   ```
4. Verify timing against Plan 00 baselines:
   - `starting` appears within 1 second of stream start
   - `initializing` appears at ~2-3 seconds (when skill sync begins)
   - `thinking` appears at ~10-15 seconds (5s after last init_text)
   - Periodic `thinking` updates appear every ~10 seconds during the gap
   - `complete` appears when the answer burst arrives (18-261 seconds based on Plan 00 data)
5. Verify the UI doesn't break (existing code ignores unknown event types)
6. Run 5 queries across different session sizes and verify:
   - Small sessions (3 items): gap ~21s, expect 1-2 thinking updates
   - Medium sessions (6 items): gap ~119s avg, expect ~10 thinking updates
   - Large sessions (185 items): gap ~97s+, expect ~8+ thinking updates
7. Verify that 2+ minute queries (analytical on large sessions) show continuous progress updates

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `asyncio.wait_for` timeout on readline disrupts stdout parsing | Medium | High | Test thoroughly; ensure timeout only applies after `initializing_emitted`; handle `TimeoutError` to continue loop |
| Periodic thinking updates create excessive SSE events | Low | Low | 10-second interval produces max ~26 events for longest query (261s); negligible overhead |
| Silence gap detection fires too early (5s may be too short) | Low | Medium | Plan 00 data shows init_text events cluster in 2-10s range; 5s after last event is reliable. Can increase to 8s if needed |
| Progress events interleave with init_text in unexpected order | Low | Low | Progress events are separate from init_text; UI handles both independently |
| Subprocess terminates before thinking timer fires | Low | Low | The `complete` phase pre-empts `thinking`; short queries skip directly to complete |
| `init_text` format changes across claude-mpm versions | Medium | Medium | Use loose regex matching; fall back to generic "Initializing..." message if sync pattern not found |
| Elapsed time in "Thinking..." message drifts from wall clock | Low | Low | `elapsed_ms` is computed from PhaseTimer start, not wall clock; monotonic and consistent |

### Risks Retired from Original Plan

| Original Risk | Status | Why Retired |
|--------------|--------|------------|
| Timer threshold (8s) is wrong for actual workloads | **Resolved** | Plan 00 data confirms init_text stops at 5-10s; 5s silence timeout validated against real data |
| "Connected" phase based on system_init detection | **Invalidated** | system_init arrives in post-gap burst; replaced with `initializing` phase based on init_text |
| "Answering" phase useful for UI transition | **Invalidated** | Answer arrives atomically; `complete` phase replaces it as a burst-arrival signal |

---

## Design Decisions

### Why 5 seconds for the silence gap detection timeout?

Plan 00 data shows `init_text` events cluster in the T+2s to T+10s range across all 8 successful queries. The last `init_text` event before the gap ("Starting Claude Code...") arrives at T+5s to T+10s. A 5-second silence after the last `init_text` reliably indicates the gap has begun:

- Query #1: Last init_text at T+9.7s, gap starts (5s later would be T+14.7s, gap actually T+9.7s to T+30.7s)
- Query #5: Last init_text at T+5.5s, gap starts (5s later would be T+10.5s, gap actually T+5.5s to T+54.1s)
- Query #9: Last init_text at T+10.1s, gap starts (5s later would be T+15.1s, gap actually T+10.1s to T+106.8s)

In all cases, 5 seconds of silence is well within the gap and does not produce false positives.

### Why periodic 10-second updates during thinking?

The silence gap averages 100 seconds (range 18-261s based on Plan 00 data). Without periodic updates, users see a static message for potentially 4+ minutes. The 10-second interval balances:
- **User reassurance**: Frequent enough that the counter visibly increments
- **Event overhead**: Max ~26 events for the longest query (negligible)
- **Elapsed time display**: "Thinking... (25s)" -> "Thinking... (35s)" gives tangible evidence the system is alive

### Why not parse stream_token events for progress?

**Plan 00 confirms**: `stream_token` events are NOT emitted during the gap. They arrive in the final burst alongside `assistant` and `result` events. Doc #06 "Approach A" (frontend token parsing) is **invalid** -- there are no tokens to parse during the gap. This was previously a theoretical concern (Doc #10 Critique 1); Plan 00 provides definitive proof.

### Why not use `--include-partial-messages`?

Doc #10 (Critique 7) explains that `--include-partial-messages` produces **answer token deltas**, not progress indicators. These are useful for incremental answer display (a separate feature) but are not appropriate for progress phases. See Plan 05 for deferred token streaming. Additionally, since claude-mpm buffers all output atomically (Plan 00 finding), partial messages would likely also arrive in the burst rather than progressively.

### Why Stage 1 (EXPANDABLE)?

Progress events are ephemeral indicators of system state, not part of the answer. They belong in the accordion area (Stage 1), not the primary answer area (Stage 2). They should NOT be persisted to the database.

### Why `initializing` instead of `connected`?

The original `connected` phase was designed to fire when `system_init` was received, implying that the system had connected to Claude. Plan 00 reveals that `system_init` arrives in the post-gap burst -- the "connection" happens silently during the gap with no detectable signal. The `initializing` phase is based on what IS detectable: the `init_text` events showing skill sync progress. This is honest -- it describes what the system is actually doing during those 3-8 seconds.

### Why `complete` instead of `answering`?

The original `answering` phase implied the system was in the process of generating an answer. Plan 00 shows the answer arrives atomically in a single burst (111-135ms). There is no "answering" period visible to the stream consumer. `complete` accurately signals "the answer has arrived" rather than falsely suggesting an ongoing generation process.

---

## Relationship to Other Plans

- **Plan 00 (Measurement)**: **COMPLETED 2026-02-07.** Provided timing data that fundamentally reshaped this plan. Key findings: 18-261s silence gap with zero events; `system_init` and stage 2 events arrive in a post-gap burst; `init_text` events are the only real-time signals. See `docs/research/streaming-measurement-results-2026-02-07.md`.
- **Plan 04 (UI Progress Display)**: Consumes the progress events from this plan and displays them in the accordion toggle bar. Plan 04 has been updated to reflect the new phase model (`starting` -> `initializing` -> `thinking` -> `complete`) and the emphasis on elapsed time counters during the thinking phase.
- **Plan 05 (Future)**: Token streaming (`--include-partial-messages`) is a separate, complementary feature that could coexist with progress events. Plan 00 suggests partial messages may also be buffered by claude-mpm, requiring investigation before Plan 05 proceeds.

---

## Research References

- **Plan 00 Measurement Report**: `docs/research/streaming-measurement-results-2026-02-07.md` -- definitive timing data for all phases; see "Key Findings" and "Implications for Plans 01-04" sections
- Doc #07 Section 1.5: "Proposed Progress Event Design" -- original 8-phase design (superseded by this plan)
- Doc #07 Section 1.6: "API Contract Implications" -- backward compatibility analysis (still valid)
- Doc #07 Section 1.7: "Implementation Approach" -- effort estimate and file list (still valid)
- Doc #10 Critique 4: "Progress Phase Detection Is Mostly Guesswork" -- trims to 3-4 reliable phases (validated by Plan 00)
- Doc #10 Recommended Implementation Order, Tier 1, #3: "Backend progress events (simplified)"
- Doc #08 Section 1.9: "Recommendation for Streaming Progress" -- recommends synthetic progress as short-term solution (validated by Plan 00: synthetic is the ONLY option during the gap)
