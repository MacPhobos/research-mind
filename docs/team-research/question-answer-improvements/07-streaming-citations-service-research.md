# Service Architecture Research: Streaming Progress Events & Citation Linking

> **Researcher**: Service Architecture Agent
> **Date**: 2026-02-07
> **Scope**: Streaming progress events for UI feedback, citation linking to scraped sandbox content
> **Key Files Analyzed**: 15+ source files across routes, services, schemas, models, sandbox, and config
> **Builds On**: `02-service-architecture-research.md`, `06-source-citations-in-ui.md`, `plan06-source-citations-file-audit-2026-02-06.md`

---

## Table of Contents

1. [Item 1: Streaming Progress Events](#item-1-streaming-progress-events)
   - [1.1 Current Query Execution Architecture](#11-current-query-execution-architecture)
   - [1.2 Current SSE Infrastructure](#12-current-sse-infrastructure)
   - [1.3 claude-mpm Subprocess Output Analysis](#13-claude-mpm-subprocess-output-analysis)
   - [1.4 Identifiable Progress Stages](#14-identifiable-progress-stages)
   - [1.5 Proposed Progress Event Design](#15-proposed-progress-event-design)
   - [1.6 API Contract Implications](#16-api-contract-implications)
   - [1.7 Implementation Approach](#17-implementation-approach)
2. [Item 2: Citation Linking to Scraped Content](#item-2-citation-linking-to-scraped-content)
   - [2.1 Sandbox File Structure Analysis](#21-sandbox-file-structure-analysis)
   - [2.2 Current Citation Extraction (Plan 06 Status)](#22-current-citation-extraction-plan-06-status)
   - [2.3 Content Serving Gap Analysis](#23-content-serving-gap-analysis)
   - [2.4 Proposed Citation Enrichment Design](#24-proposed-citation-enrichment-design)
   - [2.5 Security Considerations](#25-security-considerations)
   - [2.6 API Contract Changes for Citation Linking](#26-api-contract-changes-for-citation-linking)
3. [Complexity Assessment](#complexity-assessment)
4. [Key Code References](#key-code-references)

---

## Item 1: Streaming Progress Events

### 1.1 Current Query Execution Architecture

The query execution pipeline is a synchronous chain orchestrated by two files:

**Entry point**: `app/routes/chat.py:53-121` — `send_chat_message()`
- POST creates user message + placeholder assistant message in DB
- Returns `stream_url` pointing to the SSE endpoint

**SSE endpoint**: `app/routes/chat.py:124-432` — `stream_chat_response()`
- Validates session and message states
- Delegates to `event_generator()` async generator
- Wraps in `StreamingResponse` with SSE headers

**Core streaming**: `app/services/chat_service.py:517-943` — `stream_claude_mpm_response()`
- Builds and launches claude-mpm subprocess
- Reads stdout line-by-line
- Classifies each line into Stage 1 (EXPANDABLE) or Stage 2 (PRIMARY)
- Yields SSE events

**Current subprocess command** (`chat_service.py:581-595`):
```python
cmd = [
    claude_mpm_path,
    "run",
    "--non-interactive",
    "--no-hooks",
    "--no-tickets",
    "--launch-method", "subprocess",
    "-i", user_content,
    "--",
    "--output-format", "stream-json",
    "--verbose",
]
```

### 1.2 Current SSE Infrastructure

The SSE infrastructure is **mature and well-designed**. Key capabilities:

| Feature | Status | Location |
|---------|--------|----------|
| Two-stage event classification | Implemented | `chat_service.py:339-373` `classify_event()` |
| Event typing (6 types) | Implemented | `schemas/chat.py:17-44` `ChatStreamEventType` |
| Stage classification (2 stages) | Implemented | `schemas/chat.py:47-61` `ChatStreamStage` |
| Heartbeat keep-alive | Implemented | `chat_service.py:636-645` (15s interval) |
| PhaseTimer instrumentation | Implemented | `chat_service.py:55-87` |
| Error event propagation | Implemented | `chat_service.py:903-943` |
| Typed Pydantic event schemas | Implemented | `schemas/chat.py:106-183` |

**Current event types and their stages:**

| Event Type | Stage | Persisted | Description |
|-----------|-------|-----------|-------------|
| `start` | - | No | Streaming session started |
| `init_text` | 1 (EXPANDABLE) | No | Plain text from claude-mpm (banner, sync) |
| `system_init` | 1 (EXPANDABLE) | No | JSON system init event |
| `system_hook` | 1 (EXPANDABLE) | No | JSON hook start/response events |
| `stream_token` | 1 (EXPANDABLE) | No | Token-by-token delta (if available) |
| `assistant` | 2 (PRIMARY) | Yes | Complete assistant message |
| `result` | 2 (PRIMARY) | Yes | Final result with metadata |
| `complete` | - | - | Stream finished, metadata attached |
| `error` | - | - | Error occurred |
| `heartbeat` | - | No | 15-second keep-alive |

### 1.3 claude-mpm Subprocess Output Analysis

The subprocess output follows a predictable pattern with two phases:

**Phase A: Plain Text Initialization** (Stage 1)
```
claude-mpm run v3.x.x
Syncing agents... (7 agents, 60 skills)
Loading CLAUDE.md...
Starting MCP servers...
```

**Phase B: JSON Streaming Events** (entered when first `{` is detected)
```json
{"type": "system", "subtype": "init", "cwd": "...", "tools": [...]}
{"type": "system", "subtype": "hook_started", ...}
{"type": "system", "subtype": "hook_response", ...}
{"type": "assistant", "message": {"content": [{"type": "text", "text": "..."}]}}
{"type": "result", "result": "...", "usage": {...}, "total_cost_usd": ...}
```

**Key observation**: The transition from plain text to JSON is detected by checking if a line starts with `{` (`chat_service.py:679`). This is the "json_mode" flag.

**PhaseTimer marks** already recorded:
1. `function_entry`
2. `cli_path_resolved`
3. `env_prepared`
4. `command_built`
5. `subprocess_spawned`
6. `first_stdout_byte`
7. `json_mode_entered`
8. `first_stage2_event`
9. `stream_complete`
10. `response_finalized`

### 1.4 Identifiable Progress Stages

Based on the subprocess output pattern and PhaseTimer marks, these stages can be detected and communicated to the UI:

| Stage | Detection Method | Typical Duration | Current SSE Event |
|-------|-----------------|-----------------|-------------------|
| **Preparing** | Before subprocess_spawned | 50-100ms | `start` event only |
| **Launching** | After subprocess_spawned, before first_stdout_byte | 200-500ms | None (gap) |
| **Syncing** | Plain text lines containing "Syncing" / "Loading" | 3-15s | `init_text` events |
| **Connecting** | `system_init` JSON event | 1-2s | `system_init` event |
| **Thinking** | After system_init, before first assistant/result | 5-30s | `system_hook` / `stream_token` events |
| **Answering** | `assistant` event received | <1s | `assistant` event |
| **Completing** | `result` event received | <1s | `result` event |

**Critical insight**: The "Starting Claude Code..." stall happens because:
1. The `start` event fires immediately (before subprocess launches)
2. No events fire during the 3-15 second agent/skill sync phase
3. The first `init_text` events only arrive after sync completes
4. Even then, they're plain text that the UI just appends to the accordion

### 1.5 Proposed Progress Event Design

Add a new `progress` SSE event type that provides structured status updates:

```typescript
interface ChatStreamProgressEvent {
  phase: ProgressPhase;
  message: string;           // Human-readable description
  elapsed_ms: number;        // Time since stream started
  detail?: string;           // Optional detail (e.g., "7 agents, 60 skills")
}

enum ProgressPhase {
  PREPARING = "preparing",       // Building command, env setup
  LAUNCHING = "launching",       // Subprocess spawning
  INITIALIZING = "initializing", // Agent/skill sync, CLAUDE.md load
  CONNECTING = "connecting",     // MCP server startup, Claude API connection
  SEARCHING = "searching",       // Vector search / content retrieval
  THINKING = "thinking",         // Claude API call in progress
  ANSWERING = "answering",       // Response received, streaming answer
  COMPLETING = "completing",     // Finalizing, extracting citations
}
```

**Detection logic additions** (in `stream_claude_mpm_response()`):

```python
# After subprocess_spawned:
yield progress_event("launching", "Starting Claude Code...")

# When first_stdout_byte arrives:
yield progress_event("initializing", "Loading workspace...")

# When plain text contains sync keywords:
if "syncing" in line_str.lower() or "loading" in line_str.lower():
    yield progress_event("initializing", line_str.strip())

# When json_mode_entered (system_init):
yield progress_event("connecting", "Connected to Claude API")

# When system_hook events arrive:
if event.get("subtype") == "hook_started":
    yield progress_event("searching", "Searching content...")

# When no stage2 event yet and significant time has passed:
yield progress_event("thinking", "Analyzing your question...")

# When first stage2 event:
yield progress_event("answering", "Generating answer...")

# Before complete event:
yield progress_event("completing", "Finalizing response...")
```

### 1.6 API Contract Implications

**Version bump**: 1.9.0 → 1.10.0 (minor: new optional event type)

**New event type**: `progress` added to SSE Event Types table

**New schema**:

```typescript
interface ChatStreamProgressEvent {
  phase: string;             // ProgressPhase enum value
  message: string;           // Human-readable status
  elapsed_ms: number;        // Milliseconds since stream start
  detail?: string;           // Optional additional context
}
```

**Backwards compatible**: The `progress` event is a new SSE event type. Existing clients that only listen for `start`, `chunk`, `complete`, `error`, and `heartbeat` will simply ignore `progress` events. No breaking changes.

### 1.7 Implementation Approach

**Effort**: Low-Medium (1-2 days)

**Backend changes:**

1. **`schemas/chat.py`**: Add `ChatStreamProgressEvent` model and `ProgressPhase` enum
2. **`chat_service.py`**: Add `_emit_progress()` helper, inject progress events at key transition points in `stream_claude_mpm_response()`
3. **`api-contract.md`**: Add `progress` event documentation

**No new infrastructure needed** — the existing SSE pipeline, heartbeat system, and event classification handle everything. Progress events use the existing `yield` mechanism.

**Critical design decision**: Progress events should be Stage 1 (EXPANDABLE) — they are ephemeral status updates for the accordion/progress UI, NOT persisted to the database.

---

## Item 2: Citation Linking to Scraped Content

### 2.1 Sandbox File Structure Analysis

Each session sandbox has this structure:

```
content_sandboxes/{session_id}/
├── CLAUDE.md                           ← Research assistant prompt
├── .claude/                            ← Claude Code project config
│   ├── settings.local.json
│   ├── agents/                         ← Agent definitions
│   └── skills/                         ← Skill definitions
├── .claude-mpm/                        ← claude-mpm state
├── .mcp.json                           ← MCP server config (vector-search)
├── .mcp-vector-search/                 ← Vector index (~44MB)
└── {content_id}/                       ← Content directories (one per item)
    ├── content.md (or content.txt)     ← Extracted/retrieved content
    └── metadata.json                   ← Source metadata
```

**Content directory naming**: Each content item gets a UUID subdirectory (`{content_id}/`) under the session sandbox.

**File types stored** (from URL retriever analysis):
- `content.md` — Markdown-extracted text from URLs (via trafilatura/newspaper4k)
- `content.txt` — Plain text content
- `metadata.json` — Source metadata (URL, title, word count, extraction method, timestamp)

**Example `metadata.json`**:
```json
{
  "url": "https://hyperdev.matsuoka.com/p/i-tracked-every-token",
  "title": "I Tracked Every Token",
  "word_count": 2789,
  "extraction_method": "trafilatura",
  "extraction_time_ms": 42.6,
  "retrieved_at": "2026-02-05T01:50:59.366398+00:00",
  "source_url": "https://hyperdev.matsuoka.com/sitemap/2025"
}
```

**Content item database record** (`content_items` table):
- `content_id` — UUID (matches directory name)
- `session_id` — Parent session UUID
- `content_type` — "text" | "file_upload" | "url" | "git_repo" | "mcp_source" | "document"
- `title` — Display name
- `source_ref` — Original URL/source
- `storage_path` — Relative path within content dir (e.g., "content.md")
- `status` — "pending" | "processing" | "ready" | "error"
- `mime_type` — MIME type
- `metadata_json` — Flexible metadata dict

### 2.2 Current Citation Extraction (Plan 06 Status)

**Plan 06 has been partially implemented.** Here's the current state:

**Already done (API contract v1.9.0):**

1. **`SourceCitation` schema** (`schemas/chat.py:106-115`):
```python
class SourceCitation(BaseModel):
    file_path: str           # "uuid/filename" or "8hex/filename"
    content_id: str | None   # UUID or 8-hex prefix
    title: str               # Filename portion
```

2. **`sources` field on metadata** (`schemas/chat.py:132`):
```python
sources: list[SourceCitation] | None = None  # In ChatStreamResultMetadata
```

3. **`extract_citations()` function** (`chat_service.py:402-436`):
```python
def extract_citations(content: str) -> list[SourceCitation]:
    # Matches backtick-wrapped paths: `uuid/filename` or `8hex/filename`
    uuid_short = r"[0-9a-f]{8}"
    uuid_full = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
    path_pattern = rf"`((?:{uuid_full}|{uuid_short})/[^`]+)`"
```

4. **Citations integrated into stream** (`chat_service.py:863-885`):
```python
citations = extract_citations(stage2_content) if stage2_content else []
if citations:
    if metadata is not None:
        metadata.sources = citations
    else:
        metadata = ChatStreamResultMetadata(sources=citations)
```

5. **API contract updated** (v1.9.0, 2026-02-06): `SourceCitation` schema and `sources` field documented.

**What exists**: Backend extraction of file path patterns from answer text → structured `SourceCitation` objects in the SSE `complete` event metadata.

**What's missing for citation *linking***: The ability to link a citation to its actual scraped content — i.e., serve the underlying file, show the original URL, provide a content snippet, etc.

### 2.3 Content Serving Gap Analysis

**Current state**: The service has NO endpoint to serve sandbox file content.

Evidence: Grep for `FileResponse`, `StaticFiles`, `send_file`, `serve.*file` across `app/` — zero matches.

**What the UI currently knows about content items**:
- Via `GET /api/v1/sessions/{session_id}/content` — list of `ContentItemResponse` objects
- Each response includes: `content_id`, `title`, `source_ref` (original URL), `storage_path`, `mime_type`, `metadata_json`

**What the UI does NOT have**:
1. An API endpoint to read the actual content file (e.g., `content.md`)
2. An API endpoint to read the `metadata.json` from the sandbox
3. A way to correlate a `SourceCitation.content_id` (8-hex or full UUID) with a `ContentItem` record

**Correlation gap**: The `extract_citations()` function extracts `content_id` as the first path segment (UUID or 8-hex prefix). The 8-hex prefix case is problematic because:
- Content IDs in the database are full UUIDs (36 chars)
- Claude's answer may reference files as `079044a5/content.md` (8-hex prefix) or `079044a5-8a3e-43c4-9c58-6967bfe6f59a/content.md` (full UUID)
- The extraction handles both patterns, but **resolving an 8-hex prefix to a full UUID requires a database lookup**

### 2.4 Proposed Citation Enrichment Design

Two complementary approaches:

#### Approach A: Enrich Citations at Extraction Time (Backend)

After `extract_citations()` runs, look up each citation's `content_id` in the database to add:
- `source_url` — The original URL (from `content_items.source_ref`)
- `content_title` — The content item's title (from `content_items.title`)
- `content_type` — "url", "document", etc. (from `content_items.content_type`)

**Enhanced `SourceCitation` schema**:
```python
class SourceCitation(BaseModel):
    file_path: str                    # "uuid/filename" (as extracted from answer)
    content_id: str | None = None     # Full UUID of content item
    title: str                        # Filename portion of path
    source_url: str | None = None     # Original URL (from content_items.source_ref)
    content_title: str | None = None  # Content item title (from content_items.title)
    content_type: str | None = None   # "url", "document", etc.
```

**Implementation**: Add a `_enrich_citations()` function that:
1. Collects all `content_id` values from citations
2. For 8-hex prefixes, does a `LIKE` query: `WHERE content_id LIKE '{prefix}%' AND session_id = '{session_id}'`
3. For full UUIDs, does a direct lookup
4. Populates `source_url`, `content_title`, `content_type` from the DB record

**Challenge**: The `stream_claude_mpm_response()` function currently operates without a database session (it's an async generator called from the route handler). The DB enrichment would need to happen either:
- In the route handler's `event_generator()` after parsing the `complete` event
- Or by passing a session factory into the streaming function

#### Approach B: New Endpoint to Serve Sandbox Content

Add a file-serving endpoint:

```
GET /api/v1/sessions/{session_id}/content/{content_id}/file
GET /api/v1/sessions/{session_id}/content/{content_id}/file/{filename}
```

This would:
1. Validate session exists and content item exists
2. Construct the file path: `{content_sandbox_root}/{session_id}/{content_id}/{filename}`
3. Validate the path with `PathValidator` (prevent traversal)
4. Serve the file with `FileResponse`

**Benefits**:
- UI can fetch actual scraped content for preview/display
- Citations become clickable links to real content
- Enables "view source" for any citation

**Security**: The existing `PathValidator` (`sandbox/path_validator.py`) provides robust protection:
- Directory traversal prevention (path resolution + workspace root check)
- Symlink blocking
- System path blocking
- **However**: Current `PathValidator.validate_path()` blocks hidden files (lines starting with `.`), which would need adjustment or a separate validation for content serving

### 2.5 Security Considerations

| Concern | Risk Level | Mitigation |
|---------|-----------|------------|
| Directory traversal via filename | High | PathValidator already handles this |
| Serving hidden files (.claude/, .mcp.json) | Medium | Content serving endpoint should ONLY serve files within `{content_id}/` subdirs, not session root |
| Large file serving (DoS) | Low | Set Content-Length limit; existing `max_upload_bytes` = 50MB |
| Serving binary files | Low | Check MIME type; only serve text/markdown/JSON |
| Cross-session access | High | Always validate `session_id` matches content's `session_id` in DB |
| Path injection via content_id | Medium | Validate content_id is valid UUID format before path construction |

**Recommended security model for file serving**:
1. Content ID must be a valid UUID (regex validation)
2. Content item must exist in DB with matching session_id
3. Constructed file path must resolve within `{sandbox_root}/{session_id}/{content_id}/`
4. Only serve files with allowed MIME types (`text/*`, `application/json`)
5. Maximum response size limit

### 2.6 API Contract Changes for Citation Linking

**Version bump**: 1.9.0 → 1.10.0 (or combined with progress events in same release)

**Schema changes**:

1. **Enrich `SourceCitation`** (extend existing schema):

```typescript
interface SourceCitation {
  file_path: string;           // Existing: "uuid/filename" or "8hex/filename"
  content_id?: string;         // Existing: UUID or 8-hex prefix
  title: string;               // Existing: filename portion
  // NEW fields:
  source_url?: string;         // Original URL of the content item
  content_title?: string;      // Human-readable title of the content item
  content_type?: string;       // "url", "document", "text", etc.
}
```

2. **New endpoint** (optional, for content preview):

```
GET /api/v1/sessions/{session_id}/content/{content_id}/file/{filename}
```

**Response**: Raw file content with appropriate Content-Type header

**Backwards compatible**: New fields on `SourceCitation` are optional. New endpoint is additive.

---

## Complexity Assessment

### Item 1: Streaming Progress Events

| Aspect | Assessment |
|--------|-----------|
| **Effort** | Low-Medium (1-2 days) |
| **Risk** | Low — extends existing SSE pipeline |
| **API contract change** | Minor version bump (new optional event type) |
| **Backend changes** | 2 files: `schemas/chat.py` + `chat_service.py` |
| **Breaking changes** | None — new event type ignored by existing clients |
| **Testing** | Unit tests for progress emission at each phase; integration test for full stream |
| **Key challenge** | Detecting "thinking" vs "searching" phases reliably from subprocess output |

### Item 2: Citation Linking

| Aspect | Assessment |
|--------|-----------|
| **Effort** | Medium (2-3 days) |
| **Risk** | Low-Medium — enrichment is straightforward, file serving needs security review |
| **API contract change** | Minor version bump (new optional fields + new endpoint) |
| **Backend changes** | 3-4 files: `schemas/chat.py`, `chat_service.py`, `routes/content.py`, possibly new route file |
| **Breaking changes** | None — new fields are optional, new endpoint is additive |
| **Testing** | Unit tests for citation enrichment; integration tests for file serving with security scenarios |
| **Key challenges** | (1) 8-hex prefix to full UUID resolution; (2) DB access in async streaming context; (3) PathValidator adjustment for content files |

### Combined Implementation Priority

| Priority | Work Item | Dependencies |
|----------|-----------|-------------|
| P0 | Progress events (backend) | None |
| P0 | Progress events (frontend) | Backend progress events |
| P1 | Citation enrichment with DB lookup | Existing `extract_citations()` |
| P1 | Citation enrichment (frontend) | Backend citation enrichment |
| P2 | Content file serving endpoint | PathValidator adjustment |
| P2 | Clickable citation links (frontend) | Content file serving endpoint |

---

## Key Code References

### Streaming Progress Events

| File | Lines | Purpose |
|------|-------|---------|
| `app/schemas/chat.py` | 17-44 | `ChatStreamEventType` enum — add `PROGRESS` |
| `app/schemas/chat.py` | 47-61 | `ChatStreamStage` — progress uses EXPANDABLE |
| `app/services/chat_service.py` | 339-373 | `classify_event()` — reference for event routing |
| `app/services/chat_service.py` | 517-943 | `stream_claude_mpm_response()` — inject progress yields |
| `app/services/chat_service.py` | 55-87 | `PhaseTimer` — reuse timing data for progress elapsed_ms |
| `app/services/chat_service.py` | 614-615 | Start event yield — pattern for progress yield |
| `app/services/chat_service.py` | 636-645 | Heartbeat yield — pattern for periodic events |
| `app/core/config.py` | 123-133 | Claude-mpm settings (timeout, heartbeat interval) |

### Citation Linking

| File | Lines | Purpose |
|------|-------|---------|
| `app/schemas/chat.py` | 106-115 | `SourceCitation` model — extend with new fields |
| `app/schemas/chat.py` | 118-132 | `ChatStreamResultMetadata` — already has `sources` field |
| `app/services/chat_service.py` | 402-436 | `extract_citations()` — working extraction logic |
| `app/services/chat_service.py` | 863-885 | Citation integration point in stream |
| `app/services/content_service.py` | 66-158 | `add_content()` — content creation with target_dir |
| `app/services/content_service.py` | 182-207 | `get_content()` — DB lookup by content_id |
| `app/models/content_item.py` | 47-101 | ContentItem ORM model — fields available for enrichment |
| `app/routes/content.py` | 15-139 | Content routes — add file serving endpoint here |
| `app/sandbox/path_validator.py` | 41-258 | PathValidator — security layer for file access |
| `app/core/config.py` | 75 | `content_sandbox_root` — base path for all sandboxes |

### API Contract

| File | Section | Purpose |
|------|---------|---------|
| `docs/api-contract.md:1526-1612` | Stream Chat Response | SSE event documentation |
| `docs/api-contract.md:1540-1558` | SSE Event Types table | Add `progress` event type |
| `docs/api-contract.md:1571-1589` | ChatStreamResultMetadata | Extend SourceCitation |
| `docs/api-contract.md:1885-1899` | Changelog | Add new version entry |

---

## Summary of Key Findings

### Item 1: Streaming Progress Events

1. **The SSE infrastructure is already robust** — two-stage classification, typed events, heartbeat, PhaseTimer instrumentation. Adding progress events is a natural extension.
2. **The "Starting Claude Code..." stall** is caused by a 3-15 second gap between the `start` event and the first `init_text` event (agent/skill sync happens before any stdout output).
3. **Solution**: Emit `progress` events at key subprocess lifecycle transitions (spawned → first byte → JSON mode → stage 2), mapped to human-readable phase names.
4. **No new infrastructure needed** — uses existing `yield` mechanism in the async generator.
5. **Backend: ~100-150 lines of new code** (new schema + progress emission logic).

### Item 2: Citation Linking to Scraped Content

1. **Plan 06 Phase 2 (structured citations) is already implemented** on the backend — `SourceCitation` schema, `extract_citations()` function, and `sources` field in metadata all exist in API contract v1.9.0.
2. **The missing piece is enrichment** — citations currently contain only `file_path`, `content_id` (possibly 8-hex prefix), and `title` (filename). They lack `source_url`, `content_title`, and `content_type`.
3. **Content file serving does NOT exist** — no endpoint serves sandbox files. This is needed for clickable "view source" on citations.
4. **Sandbox structure is clean and predictable** — `{session_id}/{content_id}/content.md` + `metadata.json`. Each content dir has exactly 2 files.
5. **Security is well-covered** by existing `PathValidator`, with minor adjustment needed for serving content files (hidden file restriction).
6. **8-hex prefix resolution** requires a `LIKE` query against the `content_items` table — this is the main complexity for enrichment.
7. **Backend: ~200-300 lines of new code** (enrichment function + file serving endpoint + security validation).

---

*Research completed. Both items are feasible with existing infrastructure. Streaming progress events are lower risk and can be implemented first. Citation linking builds on Plan 06's existing implementation and adds enrichment + file serving.*
