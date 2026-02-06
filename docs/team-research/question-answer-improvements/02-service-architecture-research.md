# Service Architecture Research: claude-mpm Process Launching in research-mind-service

> **Researcher**: Service Architecture Agent
> **Date**: 2026-02-06
> **Scope**: Process lifecycle, sandbox management, CLAUDE.md usage, performance bottlenecks, optimization opportunities
> **Key Files Analyzed**: 12 source files, 4 sandbox directories, configuration/deployment artifacts

---

## 1. Current Architecture Diagram

```
                        ┌─────────────────────────────────────────────┐
                        │          FastAPI Application (main.py)       │
                        │  Port 15010 | Lifespan: verify CLI tools     │
                        └──────────┬──────────────────────────────────┘
                                   │
               ┌───────────────────┼──────────────────────┐
               │                   │                      │
    ┌──────────▼──────────┐  ┌─────▼──────────┐  ┌───────▼────────────┐
    │  POST /chat         │  │ GET /stream/    │  │  POST /index       │
    │  (routes/chat.py)   │  │ {message_id}    │  │  (routes/indexing)  │
    │  Creates user msg + │  │ SSE streaming   │  │  Triggers mcp-vec   │
    │  assistant msg (DB)  │  │ endpoint        │  │  search subprocess  │
    └──────────┬──────────┘  └─────┬──────────┘  └───────┬────────────┘
               │                   │                      │
               │            ┌──────▼──────────────┐       │
               │            │  chat_service.py     │       │
               │            │  stream_claude_mpm   │       │
               │            │  _response()         │       │
               │            └──────┬──────────────┘       │
               │                   │                      │
               │      ┌────────────▼────────────────┐     │
               │      │  asyncio.create_subprocess   │     │
               │      │  _exec()                     │     │
               │      │                              │     │
               │      │  CMD: claude-mpm run         │     │
               │      │    --non-interactive          │     │
               │      │    --no-hooks                 │     │
               │      │    --no-tickets               │     │
               │      │    --launch-method subprocess  │     │
               │      │    -i <user_prompt>           │     │
               │      │    -- --output-format         │     │
               │      │       stream-json             │     │
               │      │    --verbose                  │     │
               │      └────────────┬────────────────┘     │
               │                   │                      │
               │      ┌────────────▼────────────────┐     │  ┌──────────────────────┐
               │      │     claude-mpm process       │     │  │ WorkspaceIndexer     │
               │      │                              │     │  │ (workspace_indexer.py)│
               │      │  1. Agent/skill sync         │     │  │                      │
               │      │  2. CLAUDE.md loading         │     │  │ subprocess.run(      │
               │      │  3. .mcp.json MCP servers     │     │  │   "mcp-vector-search │
               │      │  4. Claude API call           │     │  │   init --force"      │
               │      │  5. Stream JSON output        │     │  │ )                    │
               │      └────────────┬────────────────┘     │  └──────────┬───────────┘
               │                   │                      │             │
    ┌──────────▼──────────────────▼──────────────────────▼─────────────▼──────────┐
    │                        Session Sandbox Directory                             │
    │  content_sandboxes/{session_id}/                                            │
    │                                                                              │
    │  ├── CLAUDE.md                    ← Research assistant prompt (2 lines)      │
    │  ├── .claude/                     ← Claude Code project config               │
    │  │   ├── settings.local.json      ← Hooks, permissions, MCP server config    │
    │  │   ├── agents/                  ← 7 agent definitions (172KB total)        │
    │  │   │   ├── research.md          ← 59KB                                    │
    │  │   │   ├── ticketing.md         ← 49KB                                    │
    │  │   │   ├── web-qa.md            ← 27KB                                    │
    │  │   │   ├── documentation.md     ← 14KB                                    │
    │  │   │   ├── ops.md               ← 10KB                                    │
    │  │   │   ├── qa.md                ← 9KB                                     │
    │  │   │   └── engineer.md          ← 4KB                                     │
    │  │   └── skills/                  ← 60 skill directories (2.1MB, 229 files)  │
    │  ├── .claude-mpm/                 ← claude-mpm state (176KB)                 │
    │  │   ├── configuration.yaml       ← Skills registry (53 agent-referenced)    │
    │  │   ├── cache/deployment_state   ← Deployment hash + agent count            │
    │  │   ├── memories/                ← Agent memory files                       │
    │  │   ├── logs/prompts/            ← System prompt + agent prompt logs        │
    │  │   └── pm_skills_registry.yaml  ← Full skills registry                    │
    │  ├── .mcp.json                    ← MCP server config (mcp-vector-search)    │
    │  ├── .mcp-vector-search/          ← Vector index (44MB chroma.sqlite3)       │
    │  ├── .mcp-browser/                ← Browser MCP state                        │
    │  └── {content_id}/                ← Content directories (user-added content) │
    │      ├── {content_id_1}/          │
    │      ├── {content_id_2}/          │
    │      └── ...                      │
    └──────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Process Lifecycle Analysis

### 2.1 Session Creation Flow

**File**: `app/services/session_service.py:69-94`

```
1. Generate UUID session_id
2. Compute workspace_path = content_sandbox_root + "/" + session_id
   (Default: ./content_sandboxes/{session_id}/)
3. Create Session ORM record in PostgreSQL
4. os.makedirs(workspace_path, exist_ok=True)
5. Write CLAUDE.md from SANDBOX_CLAUDE_MD_TEMPLATE (2-line template)
```

**Timing estimate**: <50ms (DB write + filesystem mkdir + file write)

### 2.2 Content Addition Flow

**File**: `app/services/content_service.py:63-155`

```
1. Validate session exists
2. Generate content_id UUID
3. Create ContentItem record (status=processing)
4. Create target_dir = content_sandbox_root/{session_id}/{content_id}/
5. Get retriever for content_type (url, git_repo, text, file_upload, document)
6. retriever.retrieve(source, target_dir)
7. Update ContentItem with result (status=ready or error)
```

**Timing**: Varies greatly by content type:
- Text: <100ms
- URL: 2-30s (network + extraction + JS rendering retry)
- Git repo: 5-120s (clone + depth=1)
- Document upload: <2s (PDF/DOCX extraction)

### 2.3 Indexing Flow (Pre-requisite for Chat)

**File**: `app/services/indexing_service.py:26-102` and `app/core/workspace_indexer.py`

```
1. PathValidator.validate_workspace_for_subprocess(workspace_path)
2. WorkspaceIndexer(workspace_path)
3. Step 1: subprocess.run("mcp-vector-search init --force", cwd=workspace_path)
   - Creates .mcp-vector-search/ directory
   - Timeout: 30s (subprocess_timeout_init)
4. Step 2: subprocess.run("mcp-vector-search index --force", cwd=workspace_path)
   - Builds chroma.sqlite3 vector index (~44MB for moderate content)
   - Timeout: 60s (subprocess_timeout_index, configurable up to 600s)
```

**Timing**: 10-60s depending on content volume. Creates ~44MB vector index.

### 2.4 Chat/Q&A Flow (The Critical Path)

**File**: `app/routes/chat.py:54-421` and `app/services/chat_service.py:442-809`

#### Step 1: Message Creation (POST /api/v1/sessions/{id}/chat)
```
1. Verify session exists (DB query)
2. Verify session.is_indexed() (checks .mcp-vector-search/ dir exists)
3. Create user ChatMessage (status=pending, persisted to DB)
4. Create assistant ChatMessage (status=pending, persisted to DB)
5. Return user message + stream_url pointing to assistant message
```
**Timing**: ~20ms (2 DB writes)

#### Step 2: SSE Streaming (GET /api/v1/sessions/{id}/chat/stream/{message_id})
```
1. Verify session exists
2. Get assistant message, verify status is pending/streaming
3. Find preceding user message
4. Update assistant status → streaming
5. Extract workspace_path, user_content from ORM objects (BEFORE generator)
6. Start event_generator() → StreamingResponse
```

#### Step 3: claude-mpm Subprocess Launch (Inside event_generator)

This is the **most performance-critical section**:

```python
# File: app/services/chat_service.py:502-516
cmd = [
    claude_mpm_path,
    "run",
    "--non-interactive",            # Oneshot mode
    "--no-hooks",                   # Skip hooks for speed
    "--no-tickets",                 # Skip ticket creation
    "--launch-method", "subprocess", # Required for output capture
    "-i", user_content,             # Input prompt
    "--",                           # Pass remaining args to native claude CLI
    "--output-format", "stream-json", # Enable JSON streaming output
    "--verbose",                    # Include verbose system events
]
```

**Environment preparation** (`_prepare_claude_mpm_environment`):
```python
env = os.environ.copy()
env["CLAUDE_MPM_USER_PWD"] = workspace_path  # Sets claude-mpm working directory
env["DISABLE_TELEMETRY"] = "1"
```

**Subprocess creation**:
```python
process = await asyncio.create_subprocess_exec(
    *cmd,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
    env=env,
    cwd=workspace_path,  # Also set cwd for safety
    limit=10 * 1024 * 1024,  # 10MB buffer for large tool results
)
```

#### Step 4: Two-Stage Response Streaming

**Stage 1 (EXPANDABLE)** - NOT persisted to DB:
- Plain text: claude-mpm banner, agent sync progress, initialization messages
- JSON system events: `{"type": "system", "subtype": "init"|"hook_started"|"hook_response"}`
- Stream tokens: `{"type": "stream_event"}` (if --include-partial-messages)

**Stage 2 (PRIMARY)** - Persisted to DB:
- Assistant event: `{"type": "assistant", "message": {"content": [{"type": "text", "text": "..."}]}}`
- Result event: `{"type": "result", "result": "...", "usage": {...}, "total_cost_usd": ...}`

**Content extraction logic**:
1. Assistant event → `extract_assistant_content()` → Concatenate text blocks
2. Result event → `event.get("result", "")` → Final answer + `extract_metadata()`
3. Fallback: If no ASSISTANT/RESULT events, join all plain text output

#### Step 5: Persistence (in finally block)

```python
# Uses a NEW database session (async context, original session closed)
SessionLocal = get_session_local()
with SessionLocal() as final_db:
    if error_occurred:
        chat_service.fail_message(final_db, final_message, error_message)
    else:
        chat_service.complete_message(final_db, final_message, final_content, ...)
    # Also mark user message as completed
```

### 2.5 Full Q&A Timing Breakdown

```
Phase                           │ Estimated Time  │ Notes
────────────────────────────────┼─────────────────┼──────────────────────
POST /chat (message creation)   │ ~20ms           │ 2 DB writes
GET /stream (validation)        │ ~10ms           │ DB queries + status check
claude-mpm process spawn        │ ~200-500ms      │ Python process startup
claude-mpm agent/skill sync     │ ~3-15s          │ THE BOTTLENECK (see §5)
claude-mpm CLAUDE.md loading    │ ~50ms           │ Minimal 2-line template
claude-mpm .mcp.json parsing    │ ~100ms          │ MCP server config load
MCP server startup (vector-search)│ ~2-5s         │ uv run mcp-vector-search mcp
Claude API call                 │ ~5-30s          │ LLM inference (varies by query)
Response parsing + SSE          │ ~100ms          │ JSON parsing + event emission
DB persistence (finally)        │ ~20ms           │ Update assistant + user messages
────────────────────────────────┼─────────────────┼──────────────────────
TOTAL                           │ ~10-50s         │ Agent sync dominates cold start
```

---

## 3. Current CLAUDE.md Content Analysis

### 3.1 Template Definition

**File**: `app/services/session_service.py:21-23`

```python
SANDBOX_CLAUDE_MD_TEMPLATE = """You are a research assistant responsible for answering questions based on the content stored in this sandbox directory.
Use the content to provide accurate and relevant answers.
"""
```

### 3.2 Analysis

**Current state**: The CLAUDE.md is **extremely minimal** - just 2 lines (178 bytes).

**What it does**:
- Sets the role: "research assistant"
- Gives a vague directive: "answering questions based on content"

**What it does NOT do**:
- No guidance on how to use the vector search MCP server
- No instructions on content structure or where to find files
- No output format guidance (citations, confidence levels, etc.)
- No tool usage guidance (which tools to prefer)
- No context about session structure (content_id directories, etc.)
- No instructions about scope limitations (stay within sandbox content)
- No guidance on handling ambiguous queries
- No mention of mcp-vector-search for semantic search

### 3.3 Sandbox CLAUDE.md Instances Found

| Sandbox | CLAUDE.md Size | Content |
|---------|---------------|---------|
| `cdd9e821...` | 178 bytes | Template only (2 lines) |
| `079044a5...` | ~178 bytes | Template only (from `ls` showing CLAUDE.md exists) |
| `70a86fb4...` | ~178 bytes | Template only |
| `a0d352e8...` | ~178 bytes | Template only |

All sandboxes use the same minimal template. None have been enhanced with richer instructions.

### 3.4 Contrast: What claude-mpm Adds

When claude-mpm launches inside a sandbox, it deploys its full infrastructure:

**`.claude/settings.local.json`** (1,759 bytes):
- Hooks for PreToolUse, PostToolUse, Stop, SubagentStop, SessionStart, UserPromptSubmit
- References `claude-hook-fast.sh` from claude-mpm's installation
- Note: The `--no-hooks` flag in the chat command SHOULD bypass these

**`.claude/agents/`** (7 agents, 172KB total):
- research.md (59KB) - Full research agent instructions
- ticketing.md (49KB) - Ticketing integration
- web-qa.md (27KB) - Web QA testing
- documentation.md (14KB) - Documentation generation
- ops.md (10KB) - Infrastructure operations
- qa.md (9KB) - Quality assurance
- engineer.md (4KB) - Engineering tasks

**`.claude/skills/`** (60 directories, 229 files, 2.1MB):
- Full claude-mpm skill ecosystem synced to sandbox
- Each skill: SKILL.md + metadata.json + .etag_cache.json + optional references/

**`.claude-mpm/`** (176KB):
- configuration.yaml with 53 agent-referenced skills
- deployment_state.json tracking sync hash
- memories/, logs/, sessions/ directories

---

## 4. Environment Variables and Configuration

### 4.1 Service Configuration (`app/core/config.py`)

| Setting | Default | Purpose |
|---------|---------|---------|
| `claude_mpm_timeout_seconds` | 300 (5 min) | Max wait for claude-mpm response |
| `claude_mpm_cli_path` | None (uses PATH) | Explicit path to claude-mpm binary |
| `sse_heartbeat_interval_seconds` | 15 | Keep-alive interval for SSE |
| `subprocess_stream_buffer_limit` | 10MB | Prevents LimitOverrunError on large outputs |
| `content_sandbox_root` | `./content_sandboxes` | Root for all sandbox directories |
| `subprocess_timeout_init` | 30s | mcp-vector-search init timeout |
| `subprocess_timeout_index` | 60s | mcp-vector-search index timeout |
| `enable_agent_integration` | False | Feature flag (unused currently) |
| `enable_caching` | False | Feature flag (unused currently) |
| `enable_warm_pools` | False | Feature flag (unused currently) |

### 4.2 Environment Variables Passed to Subprocess

```python
env = os.environ.copy()                    # Inherits ALL env vars
env["CLAUDE_MPM_USER_PWD"] = workspace_path  # claude-mpm working directory
env["DISABLE_TELEMETRY"] = "1"              # Privacy
```

Key inherited variables:
- `ANTHROPIC_API_KEY` - Required for Claude API
- `PATH` - Must include claude-mpm and mcp-vector-search
- `HOME` - For ~/.config/claude-mpm and other user configs

### 4.3 MCP Server Configuration (`.mcp.json`)

```json
{
  "mcpServers": {
    "mcp-vector-search": {
      "type": "stdio",
      "command": "uv",
      "args": ["run", "mcp-vector-search", "mcp"],
      "env": {
        "MCP_ENABLE_FILE_WATCHING": "true"
      }
    }
  }
}
```

This gets created during indexing and tells claude-mpm to launch an MCP server for vector search.

---

## 5. Performance Bottleneck Analysis

### 5.1 Agent/Skill Sync (THE PRIMARY BOTTLENECK)

**Problem**: Every time claude-mpm launches in a sandbox, it syncs agents and skills from the global claude-mpm installation to the sandbox's `.claude/` directory.

**Evidence from sandbox `cdd9e821...`**:
- 7 agents deployed: 172KB across 7 `.md` files
- 60 skill directories: 2.1MB across 229 files
- Total `.claude/` directory: 2.3MB
- Total `.claude-mpm/` directory: 176KB

**How the sync works**:
1. claude-mpm reads its global agent/skill registry
2. Computes a deployment hash of current agent/skill state
3. Compares with `.claude/agents/.mpm_deployment_state` hash
4. If different: syncs all agents and skills (copies files)
5. Updates deployment_state.json with new hash

**Estimated sync time**: 3-15 seconds per launch
- First launch (cold): 10-15s (full copy of all agents/skills)
- Subsequent launches with no changes: 3-5s (hash comparison + verification)
- After claude-mpm update: 10-15s (re-sync all)

**Impact**: This happens on EVERY chat question because the service spawns a fresh subprocess each time. There is no process reuse or connection pooling.

### 5.2 MCP Server Startup

**Problem**: The `.mcp.json` configures `mcp-vector-search` as an MCP server that claude-mpm must launch.

```
uv run mcp-vector-search mcp
```

This involves:
1. `uv` resolving the Python environment
2. Importing mcp-vector-search
3. Loading the chroma.sqlite3 index (~44MB)
4. Starting the stdio MCP server protocol

**Estimated time**: 2-5 seconds per question

### 5.3 Process Spawn Overhead

**Per-question subprocess creation**:
```
Fork + exec claude-mpm Python process: ~200-500ms
Python interpreter startup + imports: ~300-500ms
claude-mpm CLI argument parsing: ~50ms
```

**Total**: ~500ms-1s per question just for process creation.

### 5.4 No Process Reuse

The current architecture spawns a **completely new** claude-mpm process for each question:

```python
# chat_service.py:540-547
process = await asyncio.create_subprocess_exec(
    *cmd,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
    env=env,
    cwd=workspace_path,
    limit=settings.subprocess_stream_buffer_limit,
)
```

After the response completes, the process exits. The next question starts from scratch.

### 5.5 Large Sandbox Disk Footprint

| Component | Size | Per-Session? |
|-----------|------|-------------|
| .claude/agents/ | 172KB | Yes (synced on each launch) |
| .claude/skills/ | 2.1MB | Yes (synced on each launch) |
| .claude-mpm/ | 176KB | Yes (state + config) |
| .mcp-vector-search/ | ~44MB | Yes (vector index) |
| Content files | varies | Yes (user content) |
| **TOTAL overhead per session** | **~46.5MB** | **Before any user content** |

With 191 content items in sandbox `079044a5...`, the sandbox is 69MB total.

---

## 6. Sandbox Creation and Population

### 6.1 Directory Structure Creation

**Session creation** (`session_service.py:87-90`):
```python
os.makedirs(session.workspace_path, exist_ok=True)  # Create sandbox dir
create_sandbox_claude_md(session.workspace_path)       # Write CLAUDE.md
```

**Content addition** (`content_service.py:97-99`):
```python
target_dir = Path(settings.content_sandbox_root) / session_id / content_id
target_dir.mkdir(parents=True, exist_ok=True)
```

### 6.2 claude-mpm Artifacts (Created on First Chat)

The `.claude/` and `.claude-mpm/` directories are NOT created by the service. They are created by claude-mpm itself when it first runs in the sandbox:

1. **First chat question** → claude-mpm launches in sandbox
2. claude-mpm detects no `.claude/agents/` or `.claude/skills/` → deploys all
3. Creates `.claude-mpm/configuration.yaml`, `cache/deployment_state.json`
4. Creates `.claude/settings.local.json` with hooks
5. All subsequent launches check deployment hash and potentially re-sync

### 6.3 .mcp.json (Created During Indexing)

**File**: Not created by the service directly. The `.mcp.json` appears to be created during the indexing process by mcp-vector-search or manually configured.

---

## 7. Optimization Recommendations

### 7.1 CRITICAL: Pre-populate .claude/ During Session Creation (Expected Impact: -5-10s per first question)

**Current**: `.claude/agents/` and `.claude/skills/` are synced on first claude-mpm launch.
**Proposed**: Pre-copy agents and skills when creating the session sandbox.

```python
# In session_service.py:create_session()
def create_session(db, request):
    # ... existing code ...
    os.makedirs(workspace_path, exist_ok=True)
    create_sandbox_claude_md(workspace_path)

    # NEW: Pre-populate claude-mpm artifacts
    pre_populate_claude_artifacts(workspace_path)
```

This would copy the `.claude/agents/`, `.claude/skills/`, and `.claude-mpm/` from a template directory, avoiding the sync on first launch.

### 7.2 CRITICAL: Enhanced CLAUDE.md Template (Expected Impact: Better answer quality, +10-30% accuracy)

Replace the minimal 2-line template with a purpose-built research assistant prompt:

```markdown
# Research Assistant

You are a research assistant for a curated knowledge base. Answer questions
using ONLY the content in this directory.

## Available Tools
- mcp-vector-search: Use for semantic search across indexed content
- Read: Use to read specific files when you know the path

## Content Structure
Content is organized in subdirectories by content_id (UUID format).
Each subdirectory contains extracted/retrieved content files.

## Response Guidelines
1. Always cite your sources with file paths
2. If content doesn't cover the question, say so explicitly
3. Prefer semantic search (mcp-vector-search) for broad questions
4. Use direct file reading for specific/targeted lookups
5. Keep answers concise and evidence-based
```

### 7.3 HIGH: Skip Agent/Skill Sync with --skip-sync Flag (Expected Impact: -3-10s per question)

If claude-mpm supports it (or could be patched to support it):
```python
cmd = [
    claude_mpm_path,
    "run",
    "--non-interactive",
    "--no-hooks",
    "--no-tickets",
    "--skip-sync",          # NEW: Skip agent/skill sync
    "--launch-method", "subprocess",
    "-i", user_content,
    "--",
    "--output-format", "stream-json",
    "--verbose",
]
```

The sync is unnecessary for Q&A because:
- Agents are not used (oneshot mode, no team/delegation)
- Skills are not needed for answering questions about content
- The overhead is pure waste in this use case

### 7.4 HIGH: Deployment Hash Pre-seeding (Expected Impact: -3-5s cold, -1-3s warm)

Pre-create `.claude/agents/.mpm_deployment_state` and `.claude-mpm/cache/deployment_state.json` with the correct deployment hash during session creation. This way, when claude-mpm checks the hash on launch, it finds a match and skips the full sync.

```python
def pre_seed_deployment_state(workspace_path: str):
    """Copy deployment state from current global claude-mpm state."""
    global_state = Path.home() / ".claude-mpm" / "cache" / "deployment_state.json"
    if global_state.exists():
        target = Path(workspace_path) / ".claude-mpm" / "cache"
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy2(global_state, target / "deployment_state.json")
```

### 7.5 MEDIUM: Process Pool / Warm Subprocess (Expected Impact: -2-5s per question)

Instead of spawning a new process per question, maintain a pool of pre-warmed claude-mpm processes:

```python
class ClaudeMpmPool:
    """Pool of pre-warmed claude-mpm processes, one per session."""

    def __init__(self, max_size: int = 5):
        self._pool: dict[str, asyncio.subprocess.Process] = {}
        self._max_size = max_size

    async def get_process(self, session_id: str, workspace_path: str):
        if session_id in self._pool:
            return self._pool[session_id]
        # Spawn new process in interactive mode
        # Reuse for multiple questions
```

**Note**: This requires claude-mpm to support a "pipe" mode where it accepts multiple prompts on stdin. The current `--non-interactive` flag runs one question then exits. The feature flags `enable_warm_pools` exist but are unused.

### 7.6 MEDIUM: Minimal Agent Set for Q&A (Expected Impact: Reduced sync time, smaller sandbox)

Currently, ALL 7 agents and ALL 60 skills are synced to every sandbox. For Q&A, only a minimal set is needed:

**Required**: None (claude-mpm's base model can answer questions without custom agents)
**Optional**: A lightweight "research-qa" agent focused on document Q&A

This could reduce:
- Agent sync: 172KB → <5KB (or 0 if custom Q&A agent in CLAUDE.md)
- Skill sync: 2.1MB → 0 (not needed for Q&A)
- Sync time: 3-15s → <1s

### 7.7 LOW: Reduce .mcp.json Server Startup (Expected Impact: -1-3s per question)

The MCP server config uses `uv run mcp-vector-search mcp` which has startup overhead. Options:
- Use a direct Python path instead of `uv run`
- Pre-start MCP servers as persistent processes (shared across questions)
- Use native file search instead of MCP when content is small

### 7.8 LOW: Utilize Feature Flags (Expected Impact: Framework for future optimization)

The config already has unused feature flags:
```python
enable_agent_integration: bool = False
enable_caching: bool = False
enable_warm_pools: bool = False
```

These could be connected to actual optimization implementations.

---

## 8. Key Code References

| File | Line(s) | Purpose |
|------|---------|---------|
| `app/services/chat_service.py` | 390-409 | `_get_claude_mpm_path()` - CLI discovery |
| `app/services/chat_service.py` | 412-439 | `_prepare_claude_mpm_environment()` - env setup |
| `app/services/chat_service.py` | 442-809 | `stream_claude_mpm_response()` - subprocess + streaming |
| `app/services/chat_service.py` | 502-516 | Command construction (THE critical lines) |
| `app/services/chat_service.py` | 540-547 | `asyncio.create_subprocess_exec()` |
| `app/services/chat_service.py` | 306-338 | `classify_event()` - two-stage routing |
| `app/routes/chat.py` | 128-421 | `stream_chat_response()` - SSE endpoint |
| `app/routes/chat.py` | 219-411 | `event_generator()` - async SSE generator |
| `app/services/session_service.py` | 21-35 | CLAUDE.md template + creation |
| `app/services/session_service.py` | 69-94 | `create_session()` - sandbox creation |
| `app/core/config.py` | 123-133 | claude-mpm settings |
| `app/core/workspace_indexer.py` | 54-232 | WorkspaceIndexer subprocess management |
| `app/models/session.py` | 49-54 | `is_indexed()` check |
| `app/exceptions.py` | 1-152 | Custom exception hierarchy |

---

## 9. Security Considerations

### 9.1 Path Validation
- `PathValidator` (`app/sandbox/path_validator.py`) prevents directory traversal
- All subprocess `cwd` paths validated against sandbox root
- Symlink chains blocked
- System paths (/etc, /root, etc.) blocked

### 9.2 Subprocess Isolation
- Each claude-mpm process runs in the sandbox directory (cwd + CLAUDE_MPM_USER_PWD)
- Inherits full user environment (ANTHROPIC_API_KEY, etc.)
- **Risk**: The process has access to the full filesystem via inherited environment
- **Mitigation**: `--non-interactive` limits what claude-mpm can do

### 9.3 Input Sanitization
- User content limited to 10,000 chars (SendChatMessageRequest validation)
- Passed directly as `-i` argument - no shell injection risk (subprocess_exec, not shell=True)

---

## 10. Summary of Findings

### What Works Well
1. **Two-stage streaming architecture** is well-designed for separating init noise from answers
2. **Async subprocess management** with proper timeout handling
3. **SSE heartbeat** prevents proxy disconnection
4. **Path validation** provides strong sandbox isolation
5. **Feature flags** exist for future optimization (though unused)

### Critical Issues
1. **Agent/skill sync overhead**: 3-15 seconds per question for unnecessary agent deployment
2. **No process reuse**: Fresh subprocess per question, no warmup or pooling
3. **Minimal CLAUDE.md**: 2-line template gives poor guidance to the LLM
4. **MCP server cold start**: Vector search MCP server starts from scratch each time
5. **Large sandbox overhead**: ~46.5MB of overhead files per session before user content

### Recommended Priority

| Priority | Optimization | Expected Impact | Effort |
|----------|-------------|----------------|--------|
| P0 | Enhanced CLAUDE.md template | +10-30% answer quality | Low (1 hour) |
| P0 | Skip agent/skill sync (--skip-sync or pre-populate) | -5-15s per question | Medium (1-2 days) |
| P1 | Deployment hash pre-seeding | -3-5s cold start | Low (2-4 hours) |
| P1 | Minimal agent set for Q&A | -2-5s sync + smaller disk | Medium (1 day) |
| P2 | Process pool / warm subprocess | -2-5s per question | High (3-5 days) |
| P2 | MCP server persistence | -2-3s per question | High (3-5 days) |
| P3 | Feature flag wiring | Framework for A/B testing | Medium (1 day) |
