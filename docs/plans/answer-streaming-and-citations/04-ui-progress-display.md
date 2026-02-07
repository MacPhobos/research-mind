# Plan 04: UI Progress Display

**Tier**: 3 (After Sprint 2)
**Scope**: research-mind-ui only
**Goal**: Consume backend `progress` SSE events (from Plan 03) and display meaningful status in the accordion toggle bar, replacing the generic "Full Process Output" label and pulsing green dot with actionable progress information. Emphasis on elapsed time counter during the 18-261 second silence gap.
**Depends On**: Plan 03 (Backend Progress Events) -- must have `progress` event type in the SSE stream
**Effort**: 1 day
**Updated**: 2026-02-07 based on Plan 00 measurement results (see `docs/research/streaming-measurement-results-2026-02-07.md`)

---

## Rationale

Plan 03 adds structured `progress` events to the SSE stream with 4 phases: `starting`, `initializing`, `thinking`, `complete`. These events carry human-readable messages and elapsed time. The UI currently ignores them -- the accordion toggle shows "Full Process Output" with a pulsing green dot regardless of what the system is doing (Doc #06, Section 1.3).

This plan wires the progress events into the UI so users see:
```
Before: [>] Full Process Output  (green dot)
After:  [>] Full Process Output  (green dot)  Thinking... (45s)
```

This follows Doc #06 Approach A ("Progress Ticker in Accordion Toggle Bar"), identified as the best balance of informativeness, simplicity, and non-intrusiveness.

### Plan 00 Measurement Context

> Full report: `docs/research/streaming-measurement-results-2026-02-07.md`

Plan 00 measurements revealed that **the UI MUST rely entirely on backend-generated progress events** for progress display. The key constraints:

1. **`stream_token` events do NOT exist during the silence gap.** They arrive in the final burst with the answer. Doc #06 "Approach A" (frontend token parsing) is **confirmed invalid**.
2. **The silence gap is 18-261 seconds** (avg 100s). During this entire period, ZERO SSE events arrive. The UI has no data source for progress other than what Plan 03 synthetically generates.
3. **All answer data arrives in a single atomic burst** (5-10ms window). The transition from "thinking" to "answer displayed" is nearly instantaneous from the UI perspective.
4. **The `thinking` phase with elapsed time counter is the most important UI element**, since users spend 90%+ of their wait time in this phase.

**Frontend token parsing is NOT an option.** This was previously a theoretical concern; Plan 00 provides definitive proof. The UI is a pure consumer of Plan 03's backend progress events.

---

## Current State

### Accordion Toggle (ChatMessage.svelte)

**File**: `research-mind-ui/src/lib/components/chat/ChatMessage.svelte` (lines 172-203)

```svelte
{#if !isUser && hasExpandableContent}
  <div class="expandable-section">
    <button class="expand-toggle" onclick={() => (expanded = !expanded)}>
      <span class="toggle-icon">
        {#if expanded}<ChevronDown />{:else}<ChevronRight />{/if}
      </span>
      <span class="toggle-text">Full Process Output</span>
      {#if isStreaming}
        <span class="streaming-dot" aria-label="Streaming"></span>
      {/if}
    </button>
    ...
  </div>
{/if}
```

The toggle label is static ("Full Process Output") and the green dot provides no specifics.

### useChatStream Hook

**File**: `research-mind-ui/src/lib/hooks/useChatStream.svelte.ts` (319 lines)

The `createChatStream()` hook handles all SSE event types in `handleEvent()`. It currently handles:
- `INIT_TEXT` -> appends to `stage1Content`
- `SYSTEM_INIT` / `SYSTEM_HOOK` -> formats and appends to `stage1Content`
- `STREAM_TOKEN` -> appends to `stage1Content`
- `ASSISTANT` -> sets `stage2Content`
- `RESULT` -> extracts metadata, sets `stage2Content`

It does NOT handle `PROGRESS` events (they don't exist yet).

### ChatStreamEventType Enum

**File**: `research-mind-ui/src/lib/types/chat.ts`

```typescript
export enum ChatStreamEventType {
  START = 'start',
  INIT_TEXT = 'init_text',
  SYSTEM_INIT = 'system_init',
  SYSTEM_HOOK = 'system_hook',
  STREAM_TOKEN = 'stream_token',
  ASSISTANT = 'assistant',
  RESULT = 'result',
}
```

`PROGRESS` will need to be added here after Plan 03 updates the API contract.

---

## Implementation Plan

### Step 1: Add PROGRESS to ChatStreamEventType

**File**: `research-mind-ui/src/lib/types/chat.ts`

Add the new event type:

```typescript
export enum ChatStreamEventType {
  START = 'start',
  INIT_TEXT = 'init_text',
  SYSTEM_INIT = 'system_init',
  SYSTEM_HOOK = 'system_hook',
  STREAM_TOKEN = 'stream_token',
  ASSISTANT = 'assistant',
  RESULT = 'result',
  PROGRESS = 'progress',      // NEW
}
```

Add the progress event interface:

```typescript
export interface ProgressEvent {
  phase: 'starting' | 'initializing' | 'thinking' | 'complete';
  message: string;
  elapsed_ms: number;
}
```

### Step 2: Add Progress State to useChatStream

**File**: `research-mind-ui/src/lib/hooks/useChatStream.svelte.ts`

Add a new reactive state variable for the latest progress event:

```typescript
let latestProgress = $state<ProgressEvent | null>(null);
```

Add a handler for `PROGRESS` events in `handleEvent()`:

```typescript
case ChatStreamEventType.PROGRESS: {
  try {
    const progressData = JSON.parse(data.content as string) as ProgressEvent;
    latestProgress = progressData;
  } catch {
    // Ignore malformed progress events
  }
  // Also append to stage1Content for the accordion body
  stage1Content += `[${data.content}]\n`;
  break;
}
```

Reset progress on stream completion:

```typescript
// In the cleanup/complete handler:
latestProgress = null;
```

Add `latestProgress` to the returned object:

```typescript
return {
  // ... existing getters ...
  get latestProgress() {
    return latestProgress;
  },
};
```

### Step 3: Pass Progress to ChatMessage Component

**File**: `research-mind-ui/src/lib/components/chat/SessionChat.svelte`

Pass the new prop to ChatMessage where stream state is passed:

```svelte
<ChatMessage
  {message}
  {sessionId}
  isStreaming={stream.isStreaming && message.message_id === stream.messageId}
  stage1Content={message.message_id === stream.messageId ? stream.stage1Content : ''}
  stage2Content={message.message_id === stream.messageId ? stream.stage2Content : ''}
  streamMetadata={message.message_id === stream.messageId ? stream.metadata : null}
  latestProgress={message.message_id === stream.messageId ? stream.latestProgress : null}
/>
```

### Step 4: Display Progress in Accordion Toggle Bar

**File**: `research-mind-ui/src/lib/components/chat/ChatMessage.svelte`

Add the prop:

```typescript
interface Props {
  // ... existing props ...
  latestProgress?: ProgressEvent | null;
}

let { /* ... existing destructuring ... */, latestProgress = null }: Props = $props();
```

Update the accordion toggle to show progress:

```svelte
<button class="expand-toggle" onclick={() => (expanded = !expanded)}>
  <span class="toggle-icon">
    {#if expanded}<ChevronDown />{:else}<ChevronRight />{/if}
  </span>
  <span class="toggle-text">Full Process Output</span>
  {#if isStreaming}
    <span class="streaming-dot" aria-label="Streaming"></span>
    {#if latestProgress}
      <span class="progress-status" aria-live="polite">
        {latestProgress.message}
        {#if latestProgress.phase !== 'thinking'}
          <span class="progress-elapsed">
            ({(latestProgress.elapsed_ms / 1000).toFixed(0)}s)
          </span>
        {/if}
      </span>
    {/if}
  {/if}
</button>
```

**Note on elapsed time display**: During the `thinking` phase, the elapsed time is already embedded in the message from the backend (e.g., "Thinking... (45s)") and updates every 10 seconds via new progress events. For other phases, the UI appends the elapsed time from `elapsed_ms`. This ensures the elapsed counter is always visible and updating -- critical given the 18-261 second silence gap where users most need reassurance.

### Step 5: Add CSS for Progress Status

**File**: `research-mind-ui/src/lib/components/chat/ChatMessage.svelte` (styles section)

```css
.progress-status {
  font-size: var(--font-size-xs, 0.75rem);
  color: var(--text-muted);
  max-width: 350px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  margin-left: var(--space-2, 0.5rem);
  opacity: 0.85;
  transition: opacity 0.3s ease;
}

.progress-elapsed {
  color: var(--text-muted);
  opacity: 0.6;
  font-variant-numeric: tabular-nums;
}

/* Animate phase transitions */
.progress-status {
  animation: fadeIn 0.3s ease-in;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateX(-4px); }
  to { opacity: 0.85; transform: translateX(0); }
}
```

### Step 6: Accessibility

Add `aria-live="polite"` to the progress status span (already included in Step 4). This ensures screen readers announce progress changes without interrupting the user.

Add a descriptive `aria-label` to the streaming dot:

```svelte
<span class="streaming-dot" aria-label="Response in progress: {latestProgress?.message || 'Processing'}"></span>
```

---

## Files Modified

| File | Changes |
|------|---------|
| `research-mind-ui/src/lib/types/chat.ts` | Add `PROGRESS` to enum, add `ProgressEvent` interface |
| `research-mind-ui/src/lib/hooks/useChatStream.svelte.ts` | Add `latestProgress` state, handle `PROGRESS` events, expose getter |
| `research-mind-ui/src/lib/components/chat/SessionChat.svelte` | Pass `latestProgress` prop to ChatMessage |
| `research-mind-ui/src/lib/components/chat/ChatMessage.svelte` | Add `latestProgress` prop, display in toggle bar, add CSS |

No API contract changes (contract was updated in Plan 03). No backend changes. No database changes.

---

## API Contract Impact

None. This plan only consumes events defined in Plan 03. No new contract changes.

---

## Acceptance Criteria

1. During a query, the accordion toggle bar shows the current progress phase message
2. Progress messages update as new progress events arrive (`starting` -> `initializing` -> `thinking` -> `complete`)
3. Elapsed time counter is visible throughout the query, especially during the `thinking` phase
4. During the `thinking` phase, the elapsed counter updates every ~10 seconds (from backend progress events): "Thinking... (15s)" -> "Thinking... (25s)" -> "Thinking... (35s)"
5. Progress is visible with the accordion **collapsed** (the primary use case)
6. Progress information clears when the stream completes and the answer is displayed
7. No visual glitches or layout shifts when progress text changes (especially during periodic thinking updates)
8. Screen readers announce progress changes via `aria-live="polite"`
9. If no progress events arrive (backward compatibility), the accordion shows "Full Process Output" with the pulsing dot as before
10. The UI does NOT attempt to parse `stream_token` events for progress (confirmed invalid by Plan 00)
11. All progress display relies ENTIRELY on backend-generated `progress` SSE events from Plan 03

---

## Validation

1. Submit a query through the UI
2. Observe the accordion toggle bar during the wait:
   - "Starting Claude Code..." appears first (~0-2s)
   - "Initializing... syncing skills (25%)" appears during skill sync (~2-5s)
   - "Thinking... (15s)" appears after silence gap detected (~10-15s)
   - "Thinking..." counter increments every ~10 seconds: (15s) -> (25s) -> (35s) -> etc.
   - Answer appears when the burst arrives (18-261s based on Plan 00 data)
3. Verify the progress text is truncated with ellipsis if too long for the toggle bar width
4. Verify that expanding the accordion doesn't conflict with the progress display
5. **Elapsed time counter test**: Submit a query on a medium-large session (20+ items). Verify the "Thinking..." counter visibly increments at least 3 times during the wait. Plan 00 shows these queries take 54-165 seconds on average, so expect 4-16 counter updates.
6. Submit a query with the accordion expanded and verify progress also appears in the toggle bar
7. **Fast query test**: Submit a query on a small session (3 items). Plan 00 data shows ~21s for these. Verify `thinking` phase appears and counter increments at least once.
8. **Long query test**: Submit an analytical query on a large session. Plan 00 data shows these can take 100-261+ seconds. Verify the counter continues incrementing throughout and the UI remains responsive.

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Progress text causes layout shifts in the toggle bar | Medium | Low | Use `max-width` and `text-overflow: ellipsis`; fixed layout container. "Thinking... (XXs)" is a consistent-width pattern with `tabular-nums` |
| `aria-live` announcements too frequent during thinking phase | Medium | Low | Periodic thinking updates arrive every 10 seconds (max ~26 per query). Use `aria-live="polite"` and consider `aria-relevant="text"` to reduce chattiness |
| Progress events arrive out of order | Low | Low | Always display the latest event; order doesn't matter for display |
| `JSON.parse` fails on malformed progress content | Low | Low | Try-catch around parsing; fall back to no progress display |
| Existing tests fail with new prop | Medium | Low | Add default value (`null`) for the new prop |
| Counter appears stuck between 10s updates | Low | Medium | Plan 03 emits thinking events every 10 seconds. Consider adding a client-side interpolation timer that ticks every second between backend updates (e.g., "Thinking... (16s)" locally while waiting for next "Thinking... (25s)" from backend). This is an enhancement, not a blocker. |

### Risks Retired from Original Plan

| Original Risk | Status | Why Retired |
|--------------|--------|------------|
| Frontend token parsing complexity | **Invalidated** | Plan 00 confirms `stream_token` events arrive in post-gap burst; frontend parsing is not possible. The UI is a pure consumer of backend progress events. |

---

## Design Decisions

### Why the accordion toggle bar and not a separate component?

Doc #06 evaluated three approaches:
- **Approach A (Toggle Bar)**: Non-intrusive, works with accordion collapsed, minimal visual change -- **chosen**
- **Approach B (Dedicated Progress Bar)**: More space but visual clutter
- **Approach C (Animated Primary Placeholder)**: Distracting, conflicts with answer arrival

The toggle bar approach is the least disruptive to the existing layout and provides progress visibility without requiring the user to expand the accordion.

### Why is the elapsed time counter so important?

Plan 00 data shows the silence gap averages 100 seconds (range 18-261s). During this entire period, the UI has no data to display. The elapsed time counter ("Thinking... (45s)") is the primary mechanism for:

1. **Liveness indication**: The incrementing counter proves the system has not frozen
2. **Expectation calibration**: Users learn that queries typically take 30-120 seconds
3. **Patience management**: Seeing "Thinking... (95s)" is much better than a static spinner for 95 seconds

Without the elapsed time counter, users experience a 100-second average wait with zero feedback -- a severe UX gap that Plan 00 quantified.

### Why the elapsed time is embedded in the backend message, not computed by the UI

For the `thinking` phase, the elapsed time is included in the `message` field from the backend (e.g., "Thinking... (45s)"). This ensures the counter updates are driven by actual backend events arriving over SSE, not by a client-side timer that could drift or suggest activity that is not happening.

The UI could optionally add a client-side interpolation timer that ticks every second between the 10-second backend updates (e.g., locally showing "Thinking... (46s)" through "Thinking... (54s)" before the next backend "Thinking... (55s)" arrives). This is an optional enhancement for smoother UX.

### Why not parse stream_token events for progress? (Confirmed Invalid)

**Plan 00 definitively proves this is not possible.** `stream_token` events are NOT emitted during the silence gap. They arrive in the final burst alongside `assistant` and `result` events at the very end. Doc #06 "Approach A" (frontend token parsing) is invalid. This was previously a theoretical concern (Doc #10 Critique 1); Plan 00 provides conclusive evidence with 8 measured queries.

### Why not update the primary "Generating response..." placeholder?

The primary placeholder (between accordion and answer area) is already handled by the Stage 2 content flow. Modifying it with progress information risks conflicting with the answer's arrival. The accordion toggle bar is a safe, dedicated space for progress. Additionally, Plan 00 shows the answer arrives in a single atomic burst (5-10ms window), so the transition from placeholder to answer is nearly instantaneous -- there is no visible "generating" period.

---

## Relationship to Other Plans

- **Plan 00 (Measurement)**: **COMPLETED 2026-02-07.** Provided the data that reshaped this plan. Key UI-relevant findings: 18-261s silence gap, `stream_token` events arrive in burst (not progressively), all answer data arrives atomically. See `docs/research/streaming-measurement-results-2026-02-07.md`.
- **Plan 03 (Backend Progress Events)**: Provides the `progress` SSE events consumed by this plan. Updated to use 4 phases: `starting` -> `initializing` -> `thinking` (with periodic elapsed-time updates) -> `complete`. Plan 03 drives all progress display; this plan is a pure consumer.
- **Plan 05 (Future)**: Incremental answer display (token streaming) would modify the primary answer area; this plan keeps progress in the toggle bar, avoiding conflicts. Plan 00 suggests that `--include-partial-messages` output may also be buffered by claude-mpm, so Plan 05 requires further investigation.

---

## Research References

- **Plan 00 Measurement Report**: `docs/research/streaming-measurement-results-2026-02-07.md` -- definitive timing data; see "Implications for Plans 01-04" section for UI-specific findings
- Doc #06 Section 1.4, Approach A: "Progress Ticker in Accordion Toggle Bar" -- the UX design this plan implements
- Doc #06 Section 1.5: "Component Changes Required" -- file-by-file implementation guide
- Doc #06 Section 1.6: "Complexity Assessment" -- effort and risk analysis
- Doc #06 Section 5.5 (Cross-Cutting Concerns): Accessibility requirements for progress display
- Doc #10 Tier 2, #8: "Frontend progress display" -- rated as 1-day effort
- Doc #10 Critique 1: "`stream_token` Events During Processing are Unverified" -- **now verified as invalid by Plan 00**
