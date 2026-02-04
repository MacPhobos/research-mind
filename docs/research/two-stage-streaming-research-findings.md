# Two-Stage Response Streaming Research Findings

> **Date**: 2026-02-03
> **Purpose**: Research for implementing two-stage streaming in session chat
> **Researcher**: Research Agent (claude-opus-4-5-20251101)

---

## Executive Summary

The research-mind project needs a two-stage response streaming approach:

- **Stage 1 (Expandable)**: Full claude-mpm stdout - shown in collapsible accordion, streams in real-time
- **Stage 2 (Primary)**: Final answer only - shown prominently, no initialization noise

**Key Finding**: The native Claude CLI supports `--output-format stream-json` with `--include-partial-messages` which provides structured JSON streaming with clear event types. This enables clean separation between initialization noise, streaming content, and the final answer.

### Recommended Approach

**Option A (Recommended): Use native Claude CLI with structured JSON streaming**

Pass through claude-mpm's oneshot mode with native Claude CLI flags:

```bash
claude-mpm run --non-interactive --no-hooks --no-tickets -i "prompt" -- --output-format stream-json --verbose --include-partial-messages
```

This provides:

- Structured JSON events with distinct `type` fields
- Clear separation between `system`, `stream_event`, `assistant`, and `result` messages
- The `result` event contains the clean `result` field with final answer

**Option B (Fallback): Parse plain text output with heuristics**

Current implementation uses line-buffered stdout. Can enhance with pattern detection to identify "final answer" section.

---

## 1. Claude CLI Structured Output Analysis

### 1.1 Available Output Formats

From `claude --help`:

| Flag                          | Description                                           |
| ----------------------------- | ----------------------------------------------------- |
| `--output-format text`        | Plain text output (default)                           |
| `--output-format json`        | Single JSON result object                             |
| `--output-format stream-json` | Real-time JSON streaming (requires `--verbose`)       |
| `--include-partial-messages`  | Include token-by-token streaming (with `stream-json`) |

### 1.2 Stream-JSON Event Types

When using `--output-format stream-json --verbose`, the CLI outputs one JSON object per line with these event types:

#### System Events (Stage 1 - Expandable Content)

```json
{"type":"system","subtype":"hook_started","hook_id":"...","hook_name":"SessionStart:startup","hook_event":"SessionStart","uuid":"...","session_id":"..."}

{"type":"system","subtype":"hook_response","hook_id":"...","hook_name":"SessionStart:startup","hook_event":"SessionStart","output":"{\"continue\": true}\n","stdout":"...","stderr":"","exit_code":0,"outcome":"success","uuid":"...","session_id":"..."}

{"type":"system","subtype":"init","cwd":"/path","session_id":"...","tools":["Task","Bash","Glob"...],"mcp_servers":[...],"model":"claude-opus-4-5-20251101","permissionMode":"default","slash_commands":[...],"agents":[...],"skills":[...],"uuid":"..."}
```

#### Stream Events (Stage 1 - Expandable Content with Live Progress)

```json
{"type":"stream_event","event":{"type":"message_start","message":{"model":"...","id":"msg_...","type":"message","role":"assistant","content":[],"stop_reason":null,"usage":{...}}}}

{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}

{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Silicon"}}}

{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" thoughts"}}}

{"type":"stream_event","event":{"type":"content_block_stop","index":0}}

{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":21}}}

{"type":"stream_event","event":{"type":"message_stop"}}
```

#### Assistant Message (Stage 2 - Can Extract Answer)

```json
{"type":"assistant","message":{"model":"claude-opus-4-5-20251101","id":"msg_...","type":"message","role":"assistant","content":[{"type":"text","text":"Silicon thoughts flow\nLogic blooms in nested loops\nBugs hide, then are found"}],"stop_reason":null,"usage":{...},"context_management":null},"parent_tool_use_id":null,"session_id":"...","uuid":"..."}
```

#### Result Event (Stage 2 - Final Answer)

```json
{"type":"result","subtype":"success","is_error":false,"duration_ms":4246,"duration_api_ms":3237,"num_turns":1,"result":"Silicon thoughts flow\nLogic blooms in nested loops\nBugs hide, then are found","stop_reason":null,"session_id":"...","total_cost_usd":0.0111985,"usage":{...},"permission_denials":[],"uuid":"..."}
```

### 1.3 Event Classification for Two-Stage Display

| Event Type                           | Stage   | Display Behavior                         |
| ------------------------------------ | ------- | ---------------------------------------- |
| `system` (subtype: `hook_started`)   | Stage 1 | Expandable - Hook initialization         |
| `system` (subtype: `hook_response`)  | Stage 1 | Expandable - Hook completion             |
| `system` (subtype: `init`)           | Stage 1 | Expandable - Session initialization      |
| `stream_event` (message_start)       | Stage 1 | Expandable - Streaming started indicator |
| `stream_event` (content_block_delta) | Stage 1 | Expandable - Real-time streaming tokens  |
| `stream_event` (message_stop)        | Stage 1 | Expandable - Streaming complete          |
| `assistant`                          | Stage 2 | Primary - Complete assistant message     |
| `result`                             | Stage 2 | Primary - Final answer with metadata     |

---

## 2. Current Implementation Analysis

### 2.1 Current Streaming Architecture

**Location**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/chat_service.py`

The current implementation:

1. Uses claude-mpm with `--non-interactive --no-hooks --no-tickets --launch-method subprocess -i <prompt>`
2. Streams stdout line-by-line as plain text
3. Emits SSE events: `start`, `chunk` (per line), `complete`, `error`, `heartbeat`
4. Accumulates all content into `accumulated_content`
5. Returns the entire stdout as the final content

**Current Command**:

```python
cmd = [
    claude_mpm_path,
    "run",
    "--non-interactive",  # Oneshot mode
    "--no-hooks",  # Skip hooks for speed
    "--no-tickets",  # Skip ticket creation
    "--launch-method", "subprocess",  # Required for output capture
    "-i", user_content,  # Input prompt
]
```

### 2.2 Current SSE Event Schema

**Location**: `/Users/mac/workspace/research-mind/research-mind-service/app/schemas/chat.py`

```python
class ChatStreamStartEvent(BaseModel):
    message_id: str
    status: Literal["streaming"] = "streaming"

class ChatStreamChunkEvent(BaseModel):
    content: str

class ChatStreamCompleteEvent(BaseModel):
    message_id: str
    status: Literal["completed"] = "completed"
    content: str
    token_count: int | None = None
    duration_ms: int | None = None

class ChatStreamErrorEvent(BaseModel):
    message_id: str
    status: Literal["error"] = "error"
    error: str
```

### 2.3 Limitations of Current Implementation

1. **No event type differentiation**: All stdout lines are treated as content chunks
2. **Includes initialization noise**: Hook outputs, system init, etc. all go to UI
3. **No structured metadata**: Token count is estimated (word count), not from API
4. **Single-stage output**: Everything is accumulated into one `content` field

---

## 3. Recommended Implementation Strategy

### 3.1 Option A: Enhanced Structured JSON Streaming (Recommended)

**Modify the claude-mpm invocation to use native Claude CLI's structured output**:

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
    "--include-partial-messages",
]
```

**New SSE Event Schema**:

```python
class ChatStreamEventType(str, Enum):
    START = "start"
    SYSTEM_INIT = "system_init"       # Stage 1
    SYSTEM_HOOK = "system_hook"       # Stage 1
    STREAM_TOKEN = "stream_token"     # Stage 1
    ASSISTANT_MESSAGE = "assistant"   # Stage 2
    RESULT = "result"                 # Stage 2 (final)
    ERROR = "error"
    HEARTBEAT = "heartbeat"

class ChatStreamChunkEvent(BaseModel):
    content: str
    event_type: ChatStreamEventType
    stage: Literal[1, 2]  # Which display stage
    raw_event: dict | None = None  # Original JSON for debugging
```

**Parsing Logic**:

```python
async def stream_claude_mpm_response(...):
    # ... subprocess setup ...

    stage1_content = ""  # Expandable accordion
    stage2_content = ""  # Primary display

    while True:
        line = await process.stdout.readline()
        if not line:
            break

        line_str = line.decode("utf-8").strip()
        if not line_str:
            continue

        try:
            event = json.loads(line_str)
            event_type = event.get("type")

            if event_type == "system":
                # Stage 1: System initialization
                stage1_content += f"[{event.get('subtype')}] {line_str}\n"
                yield format_sse_event("system_init", line_str, stage=1)

            elif event_type == "stream_event":
                # Stage 1: Streaming tokens
                inner_event = event.get("event", {})
                if inner_event.get("type") == "content_block_delta":
                    delta_text = inner_event.get("delta", {}).get("text", "")
                    stage1_content += delta_text
                    yield format_sse_event("stream_token", delta_text, stage=1)

            elif event_type == "assistant":
                # Stage 2: Complete assistant message
                content = event.get("message", {}).get("content", [])
                if content and content[0].get("type") == "text":
                    stage2_content = content[0].get("text", "")
                    yield format_sse_event("assistant", stage2_content, stage=2)

            elif event_type == "result":
                # Stage 2: Final result with metadata
                result_text = event.get("result", "")
                token_count = event.get("usage", {}).get("output_tokens")
                duration_ms = event.get("duration_ms")
                cost_usd = event.get("total_cost_usd")

                # Emit final result with all metadata
                yield format_sse_event("result", result_text, stage=2, metadata={
                    "token_count": token_count,
                    "duration_ms": duration_ms,
                    "cost_usd": cost_usd,
                    "session_id": event.get("session_id"),
                })

        except json.JSONDecodeError:
            # Fallback for non-JSON lines (shouldn't happen with stream-json)
            stage1_content += line_str + "\n"
            yield format_sse_event("stream_token", line_str, stage=1)
```

### 3.2 Option B: Heuristic-Based Text Parsing (Fallback)

If the `--output-format stream-json` pass-through doesn't work through claude-mpm, use pattern-based detection:

**Heuristic Patterns for Detecting "Final Answer"**:

1. **Response length stabilization**: When no new content arrives for 2+ seconds
2. **Content markers**: Look for conclusion patterns like "In summary", "To answer your question"
3. **Structure detection**: If response contains markdown headers, the content after the last header is often the answer
4. **Code block completion**: Track open/close of code fences to identify complete sections

**Implementation**:

```python
class OutputClassifier:
    INIT_PATTERNS = [
        r"^Starting Claude",
        r"^Loading agents",
        r"^Initializing session",
        r"^\[Hook\]",
    ]

    ANSWER_START_PATTERNS = [
        r"^Based on my analysis",
        r"^Here's what I found",
        r"^The answer is",
        r"^In summary",
        r"^##\s+Summary",
        r"^##\s+Answer",
    ]

    def classify_line(self, line: str, context: list[str]) -> tuple[int, str]:
        """Returns (stage, classified_content)"""
        for pattern in self.INIT_PATTERNS:
            if re.match(pattern, line):
                return (1, line)  # Stage 1: Initialization

        for pattern in self.ANSWER_START_PATTERNS:
            if re.match(pattern, line):
                return (2, line)  # Stage 2: Answer starts

        # Default: Use context to determine stage
        if self._is_likely_answer_section(line, context):
            return (2, line)
        return (1, line)
```

### 3.3 Hybrid Approach (Best of Both)

Combine structured JSON parsing with fallback heuristics:

```python
async def stream_claude_mpm_response_hybrid(...):
    use_json_parsing = True

    async for line in process.stdout:
        line_str = line.decode("utf-8").strip()

        if use_json_parsing:
            try:
                event = json.loads(line_str)
                # Use structured parsing
                yield from parse_json_event(event)
            except json.JSONDecodeError:
                # Fall back to heuristic parsing
                use_json_parsing = False
                yield from parse_text_line(line_str)
        else:
            yield from parse_text_line(line_str)
```

---

## 4. Frontend Integration Considerations

### 4.1 Two-Panel UI Design

```
+--------------------------------------------------+
|  User Message                                     |
|  "What are the authentication patterns used?"    |
+--------------------------------------------------+
|                                                  |
|  +--------------------------------------------+  |
|  | [v] Full Process Output (Click to expand)  |  |
|  +--------------------------------------------+  |
|  | [Hook] SessionStart: startup               |  |
|  | [Init] Session d22f89de initialized        |  |
|  | [Token] Based...                           |  |
|  | [Token] on...                              |  |
|  | [Token] my...                              |  |
|  +--------------------------------------------+  |
|                                                  |
|  +--------------------------------------------+  |
|  |            Assistant Response              |  |
|  +--------------------------------------------+  |
|  | Based on my analysis of the codebase,      |  |
|  | the authentication patterns include:       |  |
|  |                                            |  |
|  | 1. JWT token validation in auth/middleware |  |
|  | 2. Session-based auth fallback             |  |
|  | 3. OAuth2 integration for external APIs    |  |
|  +--------------------------------------------+  |
|                                                  |
|  Duration: 3.2s | Tokens: 542 | Cost: $0.01     |
+--------------------------------------------------+
```

### 4.2 SSE Event Handling in Frontend

```typescript
// Frontend event handler
eventSource.onmessage = (event) => {
  const data = JSON.parse(event.data);

  switch (data.event_type) {
    case "start":
      setIsStreaming(true);
      break;

    case "system_init":
    case "system_hook":
    case "stream_token":
      // Stage 1: Append to expandable section
      setStage1Content((prev) => prev + data.content);
      break;

    case "assistant":
      // Stage 2: Set primary content (may update during streaming)
      setStage2Content(data.content);
      break;

    case "result":
      // Stage 2 final: Set primary content with metadata
      setStage2Content(data.content);
      setMetadata({
        tokenCount: data.metadata?.token_count,
        durationMs: data.metadata?.duration_ms,
        costUsd: data.metadata?.cost_usd,
      });
      setIsStreaming(false);
      break;

    case "error":
      setError(data.error);
      setIsStreaming(false);
      break;
  }
};
```

---

## 5. Implementation Checklist

### Backend Changes

- [ ] **Test claude-mpm pass-through**: Verify `claude-mpm ... -- --output-format stream-json` works
- [ ] **Update chat_service.py**: Add JSON event parsing
- [ ] **New SSE event types**: Add `system_init`, `stream_token`, `assistant`, `result` events
- [ ] **Update schemas**: Add `event_type`, `stage`, `raw_event`, `metadata` fields
- [ ] **Error handling**: Graceful fallback to text parsing if JSON fails
- [ ] **Update API contract**: Document new event types and stages

### Frontend Changes

- [ ] **Two-panel component**: Create expandable Stage 1 section
- [ ] **Event type handling**: Switch on new event types
- [ ] **Metadata display**: Show token count, duration, cost from result event
- [ ] **Loading states**: Different indicators for Stage 1 vs Stage 2
- [ ] **Accessibility**: Ensure accordion is keyboard-navigable

### Testing

- [ ] **Unit tests**: Event classification logic
- [ ] **Integration tests**: Full streaming flow with mock claude-mpm
- [ ] **E2E tests**: UI displays both stages correctly

---

## 6. Verification: claude-mpm Pass-Through Test

Need to verify that claude-mpm passes `--` arguments to underlying claude CLI.

**Test Command**:

```bash
claude-mpm run --non-interactive --no-hooks --no-tickets -i "What is 2+2?" -- --output-format stream-json --verbose
```

**Expected Outcome**: JSON streaming output similar to native claude CLI

**If This Fails**: Fall back to Option B (heuristic parsing) or investigate claude-mpm source for pass-through capability.

---

## 7. Source Files Referenced

| File                                                                                    | Purpose                          |
| --------------------------------------------------------------------------------------- | -------------------------------- |
| `/Users/mac/workspace/research-mind/research-mind-service/app/services/chat_service.py` | Current streaming implementation |
| `/Users/mac/workspace/research-mind/research-mind-service/app/schemas/chat.py`          | SSE event schemas                |
| `/Users/mac/workspace/research-mind/research-mind-service/app/routes/chat.py`           | Chat endpoint handlers           |
| `/Users/mac/workspace/research-mind/docs/research/claude-mpm-cli-research.md`           | Claude-mpm CLI research          |
| `/Users/mac/workspace/research-mind/docs/research/claude-mpm-capabilities.md`           | Claude-mpm capabilities          |

---

## 8. Conclusion

The two-stage streaming implementation is feasible with **Option A (Structured JSON Streaming)** being the recommended approach. The native Claude CLI's `--output-format stream-json` with `--include-partial-messages` provides clean separation between:

1. **Stage 1 (Expandable)**: System events, hooks, token-by-token streaming
2. **Stage 2 (Primary)**: `assistant` message with complete content and `result` event with metadata

The key implementation step is verifying that claude-mpm correctly passes through the `--output-format` and `--include-partial-messages` flags to the underlying Claude CLI. If this works, the parsing becomes straightforward JSON event classification.

---

_Research completed: 2026-02-03_
_Researcher: Research Agent (claude-opus-4-5-20251101)_
