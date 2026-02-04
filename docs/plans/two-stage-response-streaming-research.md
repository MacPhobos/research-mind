# Two-Stage Response Streaming Implementation Plan

> **Version**: 1.3.0
> **Date**: 2026-02-04
> **Status**: DRAFT - Awaiting Approval
> **Research**: [two-stage-streaming-research-findings.md](../research/two-stage-streaming-research-findings.md)

---

## Problem Statement

Currently, the session chat interface streams the entire claude-mpm stdout to the UI, including:

- Hook initialization messages
- System startup noise
- Token-by-token streaming deltas
- The actual answer

**Goal**: Separate the output into two stages:

1. **Stage 1 (Expandable)**: Full process output in collapsible accordion, streams real-time
2. **Stage 2 (Primary)**: Clean final answer shown prominently, no noise

---

## Recommended Approach

**Two-Part Output Parsing** (Verified in Phase 0)

The claude-mpm output has **TWO distinct parts**:

1. **Plain text initialization** - claude-mpm banner, agent sync, skill deployment (NOT JSON)
2. **JSON streaming events** - structured events from Claude CLI (`system`, `assistant`, `result`)

**Parsing Strategy**:

1. Stream plain text lines as Stage 1 content (not persisted)
2. Detect JSON start (line begins with `{`)
3. Parse JSON events, classify into Stage 1 (system) or Stage 2 (assistant/result)
4. Extract final answer and metadata from `result` event
5. Persist only Stage 2 content to database

**Why This Approach**:

- Simple detection: `{` at line start = JSON mode
- Clean separation between event types
- Rich metadata from `result` event (token count, duration, cost)
- No fallback logic needed — JSON streaming is reliable

---

## Phase 0: Verification ✅ COMPLETED

**Verified on 2026-02-04** - claude-mpm pass-through works!

### Test Command

```bash
claude-mpm run --non-interactive --no-hooks --no-tickets -i "What is 2+2?" -- --output-format stream-json --verbose
```

### Actual Output Structure

**Part 1: Plain Text Initialization (Stage 1)**

```
✓ Found existing .claude-mpm/ directory...
╭─── Claude MPM v5.6.101 ────────────────────────╮
│      Welcome back mac!                          │
│      ...banner content...                       │
╰─────────────────────────────────────────────────╯
Syncing agents [████████████████████] 100%
Deploying agents [████████████████████] 100%
✓ Agents: 7 deployed / 40 cached
Syncing skill files [████████████████████] 100%
...more initialization...
⏳ Starting Claude Code...
```

**Part 2: JSON Streaming Events**

```json
{"type":"system","subtype":"hook_started","hook_id":"...","hook_name":"SessionStart:startup",...}
{"type":"system","subtype":"hook_response","hook_id":"...","outcome":"success",...}
{"type":"system","subtype":"init","cwd":"...","tools":[...],"model":"claude-opus-4-5-20251101",...}
{"type":"assistant","message":{"content":[{"type":"text","text":"2 + 2 = **4**"}],...},...}
{"type":"result","subtype":"success","result":"2 + 2 = **4**","duration_ms":3064,"total_cost_usd":0.17021,...}
```

### Key Findings

1. **Mixed output format**: Plain text THEN JSON (not pure JSON)
2. **JSON events confirmed**: `system`, `assistant`, `result` all present
3. **No `stream_event`**: Token-by-token deltas not observed (may require `--include-partial-messages`)
4. **Rich metadata**: `result` event includes `duration_ms`, `total_cost_usd`, `usage` breakdown
5. **Session management**: Events include `session_id` for correlation

### Verification Results

- [x] Command executes without error
- [x] JSON events start after plain text initialization
- [x] Contains distinct `system`, `assistant`, and `result` events
- [x] `result` event contains clean answer and metadata

---

## Phase 1: Backend Changes

### 1.1 Update API Contract

**File**: `research-mind-service/docs/api-contract.md`

Add new SSE event types:

```yaml
SSE Events:
  chat_stream:
    event_types:
      # Session lifecycle
      - start: Session started, message_id returned
      - error: Error occurred
      - heartbeat: Keep-alive ping

      # Stage 1: Expandable content (initialization + system)
      - init_text: Plain text initialization line (claude-mpm banner, agent sync, etc.)
      - system_init: JSON system initialization event (cwd, tools, model, etc.)
      - system_hook: JSON hook start/complete event
      - stream_token: Token-by-token streaming delta (if available)

      # Stage 2: Primary answer
      - assistant: Complete assistant message (may arrive before result)
      - result: Final answer with full metadata (tokens, duration, cost)

    stage_classification:
      expandable: [init_text, system_init, system_hook, stream_token]
      primary: [assistant, result]
```

### 1.2 Update Schemas

**File**: `research-mind-service/app/schemas/chat.py`

```python
from enum import Enum
from typing import Literal

class ChatStreamEventType(str, Enum):
    START = "start"
    INIT_TEXT = "init_text"      # Plain text initialization (Stage 1)
    SYSTEM_INIT = "system_init"  # JSON system init event (Stage 1)
    SYSTEM_HOOK = "system_hook"  # JSON hook events (Stage 1)
    STREAM_TOKEN = "stream_token"  # Token-by-token if available (Stage 1)
    ASSISTANT = "assistant"      # Complete assistant message (Stage 2)
    RESULT = "result"            # Final result with metadata (Stage 2)
    ERROR = "error"
    HEARTBEAT = "heartbeat"

class ChatStreamStage(int, Enum):
    EXPANDABLE = 1  # Full process output (plain text + system JSON)
    PRIMARY = 2     # Final answer (assistant + result)

class ChatStreamChunkEvent(BaseModel):
    content: str
    event_type: ChatStreamEventType
    stage: ChatStreamStage
    raw_json: dict | None = None  # Original JSON event for debugging

class ChatStreamResultMetadata(BaseModel):
    token_count: int | None = None      # output_tokens from usage
    input_tokens: int | None = None     # input_tokens from usage
    cache_read_tokens: int | None = None  # cache_read_input_tokens
    duration_ms: int | None = None      # Total duration
    duration_api_ms: int | None = None  # API call duration
    cost_usd: float | None = None       # total_cost_usd
    session_id: str | None = None       # Claude session ID
    num_turns: int | None = None        # Number of conversation turns

class ChatStreamCompleteEvent(BaseModel):
    """Final event sent when streaming completes. Only stage2 content is persisted."""
    message_id: str
    status: Literal["completed"] = "completed"
    content: str  # Final answer (stage2_content) - this is what gets persisted
    metadata: ChatStreamResultMetadata
```

### 1.3 Update Chat Service

**File**: `research-mind-service/app/services/chat_service.py`

Changes required:

1. Modify command to pass `-- --output-format stream-json --verbose`
2. Add **hybrid parsing** - plain text first, then JSON
3. Classify events into Stage 1 vs Stage 2
4. Accumulate content per stage
5. Extract metadata from `result` event

**New Command**:

```python
cmd = [
    claude_mpm_path,
    "run",
    "--non-interactive",
    "--no-hooks",
    "--no-tickets",
    "--launch-method", "subprocess",
    "-i", user_content,
    "--",  # Pass remaining args to native claude CLI
    "--output-format", "stream-json",
    "--verbose",
]
```

**Parsing Logic** (plain text init → JSON events):

```python
async def stream_claude_mpm_response(...):
    stage2_content = ""  # Primary answer (persisted)
    metadata = None
    json_mode = False  # Track when we enter JSON streaming

    async for line in process.stdout:
        line_str = line.decode("utf-8").rstrip()
        if not line_str:
            continue

        # Detect JSON mode start (line begins with '{')
        if not json_mode and line_str.startswith("{"):
            json_mode = True

        if json_mode:
            # Parse JSON events
            event = json.loads(line_str)
            event_type, stage = classify_event(event)

            if stage == ChatStreamStage.EXPANDABLE:
                # Stage 1: System events go to expandable (not persisted)
                yield format_sse_event(event_type, format_system_event(event), stage=1)
            else:
                # Stage 2: Assistant/Result events (persisted)
                if event_type == ChatStreamEventType.ASSISTANT:
                    content = extract_assistant_content(event)
                    stage2_content = content
                    yield format_sse_event(event_type, content, stage=2)
                elif event_type == ChatStreamEventType.RESULT:
                    stage2_content = event.get("result", "")
                    metadata = extract_metadata(event)
                    yield format_sse_event(event_type, stage2_content, stage=2, metadata=metadata)
        else:
            # Plain text mode (initialization) - Stage 1 (not persisted)
            yield format_sse_event(ChatStreamEventType.INIT_TEXT, line_str, stage=1)


def extract_metadata(result_event: dict) -> dict:
    """Extract metadata from result event."""
    usage = result_event.get("usage", {})
    return {
        "duration_ms": result_event.get("duration_ms"),
        "duration_api_ms": result_event.get("duration_api_ms"),
        "cost_usd": result_event.get("total_cost_usd"),
        "session_id": result_event.get("session_id"),
        "num_turns": result_event.get("num_turns"),
        "token_count": usage.get("output_tokens"),
        "input_tokens": usage.get("input_tokens"),
        "cache_read_tokens": usage.get("cache_read_input_tokens"),
    }


def extract_assistant_content(assistant_event: dict) -> str:
    """Extract text content from assistant message."""
    message = assistant_event.get("message", {})
    content_blocks = message.get("content", [])
    text_parts = []
    for block in content_blocks:
        if block.get("type") == "text":
            text_parts.append(block.get("text", ""))
    return "".join(text_parts)
```

**Event Classification Logic**:

```python
def classify_event(event: dict) -> tuple[ChatStreamEventType, ChatStreamStage]:
    event_type = event.get("type")

    if event_type == "system":
        subtype = event.get("subtype")
        if subtype in ("hook_started", "hook_response"):
            return (ChatStreamEventType.SYSTEM_HOOK, ChatStreamStage.EXPANDABLE)
        return (ChatStreamEventType.SYSTEM_INIT, ChatStreamStage.EXPANDABLE)

    elif event_type == "stream_event":
        return (ChatStreamEventType.STREAM_TOKEN, ChatStreamStage.EXPANDABLE)

    elif event_type == "assistant":
        return (ChatStreamEventType.ASSISTANT, ChatStreamStage.PRIMARY)

    elif event_type == "result":
        return (ChatStreamEventType.RESULT, ChatStreamStage.PRIMARY)

    return (ChatStreamEventType.STREAM_TOKEN, ChatStreamStage.EXPANDABLE)
```

### 1.4 Database Schema

**Decision**: Do NOT persist `stage1_content`. Only store the final answer.

**No changes needed** to `chat_messages` table schema. The existing `content` column stores `stage2_content` (the final answer).

`stage1_content` is:

- Streamed to UI in real-time via SSE
- NOT persisted to database
- Ephemeral (only available during active streaming)

This keeps the database lean and avoids storing verbose initialization logs.

### Acceptance Criteria - Phase 1

- [ ] API contract updated with new event types
- [ ] Schemas include `event_type`, `stage`, `metadata` fields
- [ ] Chat service parses JSON events correctly
- [ ] Fallback text parsing works when JSON fails
- [ ] SSE events emitted with correct stage classification
- [ ] `result` event contains token count, duration, cost
- [ ] All existing backend tests pass
- [ ] New unit tests for event classification

---

## Phase 2: Frontend Changes

### 2.1 Update Types

**File**: `research-mind-ui/src/lib/api/types.ts` (or regenerate from OpenAPI)

```typescript
export enum ChatStreamEventType {
  START = "start",
  INIT_TEXT = "init_text", // Plain text initialization (Stage 1)
  SYSTEM_INIT = "system_init", // JSON system init (Stage 1)
  SYSTEM_HOOK = "system_hook", // JSON hook events (Stage 1)
  STREAM_TOKEN = "stream_token", // Token streaming if available (Stage 1)
  ASSISTANT = "assistant", // Complete assistant message (Stage 2)
  RESULT = "result", // Final result with metadata (Stage 2)
  ERROR = "error",
  HEARTBEAT = "heartbeat",
}

export enum ChatStreamStage {
  EXPANDABLE = 1, // Plain text + system JSON → collapsible accordion
  PRIMARY = 2, // Assistant answer + result → main display
}

export interface ChatStreamChunk {
  content: string;
  event_type: ChatStreamEventType;
  stage: ChatStreamStage;
  raw_json?: Record<string, unknown>; // Original JSON for debugging/formatting
  metadata?: ChatResultMetadata; // Only present on RESULT events
}

export interface ChatResultMetadata {
  token_count?: number; // output_tokens
  input_tokens?: number; // input_tokens
  cache_read_tokens?: number; // cache_read_input_tokens
  duration_ms?: number; // Total duration
  duration_api_ms?: number; // API call duration
  cost_usd?: number; // total_cost_usd
  session_id?: string; // Claude session ID
  num_turns?: number; // Number of turns
}
```

### 2.2 Update SSE Hook

**File**: `research-mind-ui/src/lib/hooks/useSessionChat.ts` (or similar)

```typescript
// State
let stage1Content = $state(""); // Expandable accordion (plain text + system JSON)
let stage2Content = $state(""); // Primary display (assistant answer)
let metadata = $state<ChatResultMetadata | null>(null);
let isJsonMode = $state(false); // Track when JSON streaming starts

// Event handler
function handleSSEEvent(data: ChatStreamChunk) {
  switch (data.event_type) {
    case ChatStreamEventType.START:
      stage1Content = "";
      stage2Content = "";
      metadata = null;
      isJsonMode = false;
      break;

    // Stage 1: Expandable content
    case ChatStreamEventType.INIT_TEXT:
      // Plain text initialization (before JSON mode)
      stage1Content += data.content + "\n";
      break;

    case ChatStreamEventType.SYSTEM_INIT:
    case ChatStreamEventType.SYSTEM_HOOK:
    case ChatStreamEventType.STREAM_TOKEN:
      // JSON system events
      isJsonMode = true;
      stage1Content += formatSystemEvent(data) + "\n";
      break;

    // Stage 2: Primary answer
    case ChatStreamEventType.ASSISTANT:
      // Set primary content (may be updated by result)
      stage2Content = data.content;
      break;

    case ChatStreamEventType.RESULT:
      // Final answer with metadata
      stage2Content = data.content;
      metadata = data.metadata;
      break;

    case ChatStreamEventType.ERROR:
      // Handle error
      break;
  }
}

// Format system events for display in expandable section
function formatSystemEvent(data: ChatStreamChunk): string {
  if (data.event_type === ChatStreamEventType.SYSTEM_HOOK) {
    const raw = data.raw_json;
    if (raw?.subtype === "hook_started") {
      return `[Hook] ${raw.hook_name} started`;
    } else if (raw?.subtype === "hook_response") {
      return `[Hook] ${raw.hook_name} ${raw.outcome}`;
    }
  }
  if (data.event_type === ChatStreamEventType.SYSTEM_INIT) {
    return `[Init] Session initialized (model: ${data.raw_json?.model})`;
  }
  return data.content;
}
```

### 2.3 Update Chat Message Component

**File**: `research-mind-ui/src/lib/components/ChatMessage.svelte`

```svelte
<script lang="ts">
  import { slide } from 'svelte/transition';

  interface Props {
    stage1Content: string;
    stage2Content: string;
    metadata: ChatResultMetadata | null;
    isStreaming: boolean;
  }

  let { stage1Content, stage2Content, metadata, isStreaming }: Props = $props();
  let expanded = $state(false);
</script>

<div class="chat-message assistant">
  <!-- Stage 1: Expandable Process Output -->
  {#if stage1Content}
    <div class="expandable-section">
      <button
        class="expand-toggle"
        onclick={() => expanded = !expanded}
        aria-expanded={expanded}
      >
        <span class="toggle-icon">{expanded ? '▼' : '▶'}</span>
        Full Process Output
        {#if isStreaming}
          <span class="streaming-indicator">●</span>
        {/if}
      </button>

      {#if expanded}
        <pre
          class="stage1-content"
          transition:slide={{ duration: 200 }}
        >{stage1Content}</pre>
      {/if}
    </div>
  {/if}

  <!-- Stage 2: Primary Answer -->
  <div class="primary-answer">
    {#if stage2Content}
      <div class="stage2-content">
        {@html renderMarkdown(stage2Content)}
      </div>
    {:else if isStreaming}
      <div class="loading-placeholder">
        Generating response...
      </div>
    {/if}
  </div>

  <!-- Metadata Footer -->
  {#if metadata && !isStreaming}
    <div class="metadata-footer">
      {#if metadata.duration_ms}
        <span>Duration: {(metadata.duration_ms / 1000).toFixed(1)}s</span>
      {/if}
      {#if metadata.token_count}
        <span>Tokens: {metadata.token_count}</span>
      {/if}
      {#if metadata.cost_usd}
        <span>Cost: ${metadata.cost_usd.toFixed(4)}</span>
      {/if}
    </div>
  {/if}
</div>

<style>
  .expandable-section {
    margin-bottom: 1rem;
    border: 1px solid var(--border-color);
    border-radius: 4px;
  }

  .expand-toggle {
    width: 100%;
    padding: 0.5rem 1rem;
    background: var(--bg-subtle);
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .streaming-indicator {
    color: var(--accent-color);
    animation: pulse 1s infinite;
  }

  .stage1-content {
    padding: 1rem;
    background: var(--bg-code);
    font-family: monospace;
    font-size: 0.85rem;
    max-height: 300px;
    overflow-y: auto;
    white-space: pre-wrap;
  }

  .primary-answer {
    padding: 1rem 0;
  }

  .metadata-footer {
    display: flex;
    gap: 1rem;
    padding-top: 0.5rem;
    border-top: 1px solid var(--border-color);
    font-size: 0.8rem;
    color: var(--text-muted);
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }
</style>
```

### Acceptance Criteria - Phase 2

- [ ] Types updated for new event structure
- [ ] SSE hook handles all event types
- [ ] Expandable accordion shows Stage 1 content
- [ ] Primary display shows Stage 2 content
- [ ] Real-time streaming in expandable section
- [ ] Metadata (tokens, duration, cost) displayed after completion
- [ ] Accordion is keyboard-navigable (accessibility)
- [ ] All existing frontend tests pass
- [ ] New component tests for two-stage display

---

## Phase 3: Integration Testing

### 3.1 Backend Integration Tests

```python
async def test_streaming_json_events():
    """Test that streaming returns properly classified events."""
    async with client.stream("POST", "/api/v1/sessions/{id}/chat/stream", ...) as response:
        events = []
        async for line in response.aiter_lines():
            if line.startswith("data:"):
                event = json.loads(line[5:])
                events.append(event)

        # Verify event types present
        event_types = {e["event_type"] for e in events}
        assert "start" in event_types
        assert "result" in event_types

        # Verify result has metadata
        result_event = next(e for e in events if e["event_type"] == "result")
        assert result_event["metadata"]["token_count"] is not None

async def test_streaming_fallback_to_text():
    """Test graceful fallback when JSON parsing fails."""
    # Mock claude-mpm to return plain text
    # Verify events still classified (Stage 1 default)
```

### 3.2 E2E Tests (Playwright)

```typescript
test("two-stage streaming display", async ({ page }) => {
  await page.goto("/sessions/123");

  // Send a message
  await page.fill('[data-testid="chat-input"]', "What is 2+2?");
  await page.click('[data-testid="send-button"]');

  // Verify expandable section appears during streaming
  await expect(page.locator(".expand-toggle")).toBeVisible();
  await expect(page.locator(".streaming-indicator")).toBeVisible();

  // Wait for completion
  await expect(page.locator(".streaming-indicator")).not.toBeVisible();

  // Verify primary answer displayed
  await expect(page.locator(".stage2-content")).toContainText("4");

  // Verify metadata displayed
  await expect(page.locator(".metadata-footer")).toContainText("Duration");

  // Expand accordion
  await page.click(".expand-toggle");
  await expect(page.locator(".stage1-content")).toBeVisible();
});
```

### Acceptance Criteria - Phase 3

- [ ] Integration tests verify event classification
- [ ] Integration tests verify metadata extraction
- [ ] E2E tests verify two-stage UI display
- [ ] E2E tests verify accordion expand/collapse
- [ ] E2E tests verify real-time streaming in Stage 1

---

## Phase 4: Documentation & Cleanup

### 4.1 Update API Contract

Sync contract to frontend:

```bash
cp research-mind-service/docs/api-contract.md research-mind-ui/docs/api-contract.md
```

### 4.2 Update README/Docs

Document:

- New SSE event types
- Two-stage display behavior
- Metadata fields available

### 4.3 Regenerate Frontend Types

```bash
cd research-mind-ui && make gen-client
```

### Acceptance Criteria - Phase 4

- [ ] API contracts synced between repos
- [ ] Documentation updated
- [ ] Types regenerated from OpenAPI

---

## Risk Assessment

| Risk                                             | Likelihood | Impact   | Mitigation                                            |
| ------------------------------------------------ | ---------- | -------- | ----------------------------------------------------- |
| ~~claude-mpm doesn't support `--` pass-through~~ | ~~Medium~~ | ~~High~~ | ✅ **RESOLVED** - Verified working in Phase 0         |
| JSON parsing performance overhead                | Low        | Low      | JSON parsing is fast; negligible impact               |
| Stage classification false positives             | Low        | Low      | Clear boundary: `{` at line start = JSON mode         |
| ~~Breaking existing SSE consumers~~              | ~~Medium~~ | ~~High~~ | ✅ **RESOLVED** - No backwards compatibility required |
| Long initialization output floods Stage 1        | Medium     | Low      | Consider UI truncation/virtualization for long logs   |

---

## Timeline Estimate

| Phase                  | Estimated Effort | Status      |
| ---------------------- | ---------------- | ----------- |
| Phase 0: Verification  | 1 hour           | ✅ COMPLETE |
| Phase 1: Backend       | 4-6 hours        | Pending     |
| Phase 2: Frontend      | 4-6 hours        | Pending     |
| Phase 3: Testing       | 2-3 hours        | Pending     |
| Phase 4: Documentation | 1 hour           | Pending     |
| **Total Remaining**    | **11-16 hours**  |             |

---

## Decision Points

1. ~~**Phase 0 Result**: If claude-mpm pass-through fails, pivot to Option B~~ ✅ **RESOLVED** - Pass-through works, proceeding with hybrid JSON approach
2. ~~**Database Schema**: Decide whether to persist stage-separated content~~ ✅ **RESOLVED** - Do NOT persist `stage1_content`; only store `stage2_content` (final answer)
3. ~~**Backwards Compatibility**: Decide deprecation timeline for old event format~~ ✅ **RESOLVED** - No backwards compatibility required; replace old events with new schema

---

## Approval Checklist

- [x] Phase 0 verification completed ✅
- [ ] Technical approach approved (two-part parsing, no fallback)
- [ ] Timeline acceptable (~11-16 hours remaining)
- [ ] Risk mitigations acceptable
- [x] Database schema decision ✅ — Do NOT persist `stage1_content`
- [x] Backwards compatibility decision ✅ — No backwards compatibility, replace old events
- [x] Fallback parsing decision ✅ — No fallback needed, JSON streaming is reliable

---

## Summary of Changes (v1.3.0)

Based on Phase 0 verification output and user decisions:

### Technical Updates (v1.1.0)

1. **Two-Part Output Parsing**: Output has TWO parts (plain text THEN JSON), not pure JSON
2. **New `INIT_TEXT` Event Type**: For plain text initialization lines before JSON mode
3. **JSON Mode Detection**: Parser switches to JSON mode when line starts with `{`
4. **Rich Metadata Extraction**: Full usage breakdown from `result` event (tokens, cost, duration)
5. **Updated Risk Assessment**: Pass-through risk resolved, added UI truncation consideration

### Design Decisions (v1.2.0)

6. **Database Schema**: Do NOT persist `stage1_content` — only store final answer in existing `content` column
7. **No Backwards Compatibility**: Replace old SSE event format entirely (no deprecation period)

### Simplifications (v1.3.0)

8. **No Fallback Parsing**: Removed heuristic text classification fallback — JSON streaming is reliable

---

_Plan created: 2026-02-04_
_Plan updated: 2026-02-04 (v1.3.0 - Simplified, no fallback needed)_
_Based on research: [two-stage-streaming-research-findings.md](../research/two-stage-streaming-research-findings.md)_
