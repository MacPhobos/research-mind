# Claude-MPM CLI Research Findings

> **Date**: 2026-02-03
> **Updated**: 2026-02-03 (v1.1 - claude-mpm exclusive integration)
> **Purpose**: Validate assumptions in session-chat-interface-implementation-plan.md
> **Source Codebase**: /Users/mac/workspace/research-mind/claude-mpm/
> **CRITICAL REQUIREMENT**: We MUST use `claude-mpm` executable exclusively. Never the native `claude` CLI.

---

## Executive Summary

**CRITICAL FINDING**: The implementation plan's CLI invocation assumptions were **largely incorrect**. `claude-mpm` is a **wrapper around Claude CLI**, not a direct replacement. Many flags assumed in the plan do not exist in `claude-mpm` itself - they are Claude CLI flags that get passed through.

**INTEGRATION STRATEGY**: Despite being a wrapper, we MUST use `claude-mpm` exclusively as per project requirements. This provides additional orchestration features (agents, hooks, monitoring) that enhance the research-mind session chat experience.

### Key Corrections Required

| Plan Assumption                  | Actual Behavior                                     | Impact                                    |
| -------------------------------- | --------------------------------------------------- | ----------------------------------------- |
| `claude-mpm --print`             | Does NOT exist in claude-mpm                        | HIGH - Use `--non-interactive -i` instead |
| `--output-format stream-json`    | Does NOT exist                                      | HIGH - Use line-buffered streaming        |
| `--include-partial-messages`     | Does NOT exist                                      | MEDIUM - Not needed for line streaming    |
| `--project-dir`                  | Does NOT exist (uses `CLAUDE_MPM_USER_PWD` env var) | MEDIUM - Set env var correctly            |
| `--dangerously-skip-permissions` | Passed through to underlying Claude CLI             | LOW - Handled automatically               |

---

## 1. CLI Architecture Overview

### 1.1 Entry Points

**Primary Entry Point**: `claude-mpm` (defined in `pyproject.toml`)

- Script location: `claude_mpm.cli:main`
- Bash wrapper: `scripts/claude-mpm`

**Architecture**: `claude-mpm` is a **wrapper/orchestration layer** around the native Claude CLI (`claude`), not a replacement.

```
User Command: claude-mpm run [options] [prompt]
                    |
                    v
         ┌─────────────────────┐
         │  claude-mpm CLI     │
         │  (Python argparse)  │
         └─────────────────────┘
                    |
                    v
         ┌─────────────────────┐
         │  ClaudeRunner       │
         │  (Orchestration)    │
         └─────────────────────┘
                    |
                    v
         ┌─────────────────────┐
         │  InteractiveSession │
         │  or OneshotSession  │
         └─────────────────────┘
                    |
                    v
         ┌─────────────────────┐
         │  Native Claude CLI  │
         │  (exec or subprocess)│
         └─────────────────────┘
```

### 1.2 Available Commands

The `claude-mpm` CLI supports the following commands (from `executor.py`):

| Command         | Description                               |
| --------------- | ----------------------------------------- |
| `run`           | Run orchestrated Claude session (default) |
| `run-guarded`   | Run with additional guardrails            |
| `tickets`       | Manage tickets                            |
| `info`          | Show system information                   |
| `agents`        | Manage agents                             |
| `agent-manager` | Agent manager operations                  |
| `memory`        | Memory management                         |
| `monitor`       | Monitoring interface                      |
| `dashboard`     | Dashboard interface                       |
| `config`        | Configuration management                  |
| `configure`     | Interactive configuration TUI             |
| `aggregate`     | Aggregate operations                      |
| `analyze-code`  | Code analysis                             |
| `cleanup`       | Memory cleanup                            |
| `mcp`           | MCP server management                     |
| `doctor`        | Diagnostic checks                         |
| `upgrade`       | Upgrade claude-mpm                        |
| `skills`        | Skills management                         |
| `debug`         | Debug operations                          |

---

## 2. Run Command Analysis

### 2.1 Run Command Arguments

From `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/cli/parsers/run_parser.py`:

**MPM-Specific Arguments** (NOT passed to Claude CLI):

```python
# Run options
--no-hooks              # Disable hook service
--no-tickets            # Disable automatic ticket creation
--intercept-commands    # Enable command interception
--no-native-agents      # Disable Claude Code native agents
--launch-method         # "exec" (default) or "subprocess"
--monitor               # Enable monitoring interface
--websocket-port        # WebSocket server port (default: 8765)
--force                 # Force operations with warnings
--reload-agents         # Force rebuild system agents
--mpm-resume            # Resume MPM session (different from --resume)

# Dependency options
--no-check-dependencies     # Skip agent dependency checking
--force-check-dependencies  # Force dependency checking
--no-prompt                 # Never prompt for dependency installation
--force-prompt              # Force interactive prompting

# Input/output options
-i, --input             # Input text or file path (non-interactive mode)
--non-interactive       # Run in non-interactive mode
```

**Pass-through Arguments** (passed to Claude CLI):

```python
--resume                # Resume last conversation (Claude CLI flag)
--chrome                # Enable Chrome integration
--no-chrome             # Disable Chrome integration
claude_args             # Any additional arguments after --
```

### 2.2 How Arguments Are Filtered

From `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/cli/commands/run.py`:

```python
def filter_claude_mpm_args(args: list) -> list:
    """
    Filter out claude-mpm specific arguments from the command line.
    These are arguments that should NOT be passed to the underlying Claude CLI.
    """
    mpm_flags = [
        "--monitor", "--websocket-port", "--no-hooks", "--no-tickets",
        "--intercept-commands", "--no-native-agents", "--launch-method",
        "--mpm-resume", "--reload-agents", "--no-check-dependencies",
        "--force-check-dependencies", "--no-prompt", "--force-prompt",
        "--input", "--non-interactive", "--debug", "--logging",
        "--log-dir", "--framework-path", "--agents-dir", "--version",
        "-i", "-d", "--force-sync"
    ]
    # Note: --resume is NOT filtered - it passes through to Claude CLI
```

### 2.3 Actual Claude CLI Invocation

From `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/core/interactive_session.py` and `oneshot_session.py`:

**Interactive Mode Command Build**:

```python
def _build_claude_command(self) -> list:
    # Check for --resume flag
    has_resume = self.runner.claude_args and "--resume" in self.runner.claude_args

    if has_resume:
        # Resume mode - minimal command
        cmd = ["claude"]
        if self.runner.claude_args:
            cmd.extend(self.runner.claude_args)
        return cmd

    # Normal mode - full command with enhancements
    cmd = ["claude", "--dangerously-skip-permissions"]

    # Add custom arguments
    if self.runner.claude_args:
        cmd.extend(self.runner.claude_args)

    # Add --agents flag if native agents mode enabled
    if getattr(self.runner, "use_native_agents", False):
        agents_flag = self._build_agents_flag()
        if agents_flag:
            cmd.extend(agents_flag)

    # Add system instructions via file-based caching
    if system_prompt:
        # Uses --system-prompt-file or --append-system-prompt
        cmd.extend(["--system-prompt-file", str(cache_file)])

    return cmd
```

**Oneshot Mode Command Build** (from `oneshot_session.py`):

```python
def _build_command(self) -> list:
    cmd = ["claude", "--dangerously-skip-permissions"]

    # Add custom arguments
    if self.runner.claude_args:
        cmd.extend(self.runner.claude_args)

    # Add --agents flag if native agents mode enabled
    if getattr(self.runner, "use_native_agents", False):
        agents_flag = self._build_agents_flag()
        if agents_flag:
            cmd.extend(agents_flag)

    return cmd

def _build_final_command(self, prompt, context, infrastructure) -> list:
    full_prompt = f"{context}\n\n{prompt}" if context else prompt
    cmd = infrastructure["cmd"] + ["--print", full_prompt]

    if system_prompt:
        cmd.extend(["--system-prompt-file", temp_path])

    return cmd
```

---

## 3. Key Findings for Session Chat Implementation

### 3.1 Non-Interactive Mode

**Available Options**:

1. **Oneshot Session via `-i` flag**:

   ```bash
   claude-mpm run --non-interactive -i "User question here"
   ```

   This runs `OneshotSession` which invokes:

   ```bash
   claude --dangerously-skip-permissions --print "User question here"
   ```

2. **Direct stdin input**:
   ```bash
   echo "User question" | claude-mpm run --non-interactive
   ```

**NOT Available**:

- `claude-mpm --print` (no such flag - `--print` is passed to underlying Claude CLI)
- `claude-mpm --output-format stream-json` (does not exist)
- `claude-mpm --include-partial-messages` (does not exist)
- `claude-mpm --project-dir` (does not exist)

### 3.2 Project Directory Handling

**How it actually works**:

1. Environment variable: `CLAUDE_MPM_USER_PWD`

   - Set by the bash wrapper before launching Python
   - Stores the user's original working directory
   - Used to change back to user's project after claude-mpm setup

2. Code from `interactive_session.py`:

   ```python
   def _change_to_user_directory(self, env: dict) -> None:
       if "CLAUDE_MPM_USER_PWD" in env:
           user_pwd = env["CLAUDE_MPM_USER_PWD"]
           env["CLAUDE_WORKSPACE"] = user_pwd
           os.chdir(user_pwd)
   ```

3. For subprocess invocation, the `cwd` parameter should be set directly.

### 3.3 Output Streaming

**Available mechanisms**:

1. **PTY-based streaming** (subprocess mode):

   - Uses `pty.openpty()` for pseudo-terminal
   - Streams output character by character
   - Used when `--launch-method subprocess`

2. **Direct stdout capture** (oneshot mode):
   - Uses `subprocess.run(capture_output=True)`
   - Waits for full completion, then returns
   - Output in `result.stdout`

**NOT Available in claude-mpm**:

- `--output-format stream-json` (would need to be added to native Claude CLI)
- JSONL streaming output format
- Partial message streaming

### 3.4 Permission Handling

**Key Flag**: `--dangerously-skip-permissions`

- Always added by claude-mpm in normal mode (not resume mode)
- Required for non-interactive/automated operation
- Passed directly to underlying Claude CLI

From `interactive_session.py` and `oneshot_session.py`:

```python
cmd = ["claude", "--dangerously-skip-permissions"]
```

---

## 4. Corrected Implementation Strategy (claude-mpm Exclusive)

**REQUIREMENT**: We MUST use `claude-mpm` executable exclusively. Never the native `claude` CLI.

### 4.1 Recommended: claude-mpm Oneshot Mode

Use claude-mpm's oneshot capability with proper environment configuration:

```python
import asyncio
import os
import shutil

async def invoke_claude_mpm(
    session_workspace_path: str,
    user_question: str,
) -> tuple[str, str, int]:
    """
    Invoke claude-mpm in non-interactive oneshot mode.

    Args:
        session_workspace_path: Absolute path to session sandbox directory
        user_question: User's chat message

    Returns:
        Tuple of (stdout, stderr, return_code)
    """
    # Verify claude-mpm is available
    claude_mpm_path = shutil.which("claude-mpm")
    if not claude_mpm_path:
        raise RuntimeError("claude-mpm CLI not found in PATH")

    # Build command
    cmd = [
        claude_mpm_path,
        "run",
        "--non-interactive",       # Oneshot mode
        "--no-hooks",              # Skip hook service (faster)
        "--no-tickets",            # Skip ticket creation
        "--launch-method", "subprocess",  # Use subprocess for output capture
        "-i", user_question,       # Input prompt
    ]

    # Set environment variables
    env = os.environ.copy()
    env["CLAUDE_MPM_USER_PWD"] = session_workspace_path  # Working directory
    env["DISABLE_TELEMETRY"] = "1"                        # Privacy

    # Execute subprocess
    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env,
        cwd=session_workspace_path,  # Also set cwd for safety
    )

    stdout, stderr = await process.communicate()
    return (
        stdout.decode("utf-8") if stdout else "",
        stderr.decode("utf-8") if stderr else "",
        process.returncode or 0,
    )
```

### 4.2 Streaming Implementation with Line Buffering

For real-time streaming, use line-buffered stdout reading:

```python
async def stream_claude_mpm_response(
    session_workspace_path: str,
    user_question: str,
) -> AsyncGenerator[str, None]:
    """
    Stream response from claude-mpm line-by-line.

    Yields lines as they arrive for SSE streaming to frontend.
    """
    claude_mpm_path = shutil.which("claude-mpm")
    if not claude_mpm_path:
        raise RuntimeError("claude-mpm CLI not found in PATH")

    cmd = [
        claude_mpm_path,
        "run",
        "--non-interactive",
        "--no-hooks",
        "--no-tickets",
        "--launch-method", "subprocess",
        "-i", user_question,
    ]

    env = os.environ.copy()
    env["CLAUDE_MPM_USER_PWD"] = session_workspace_path
    env["DISABLE_TELEMETRY"] = "1"

    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env,
        cwd=session_workspace_path,
    )

    # Stream stdout line-by-line
    TIMEOUT_SECONDS = 300  # 5 minutes max

    try:
        while True:
            try:
                line = await asyncio.wait_for(
                    process.stdout.readline(),
                    timeout=TIMEOUT_SECONDS
                )
            except asyncio.TimeoutError:
                process.kill()
                raise TimeoutError("claude-mpm response timed out")

            if not line:
                break

            yield line.decode("utf-8")

        await process.wait()

        if process.returncode != 0:
            stderr = await process.stderr.read()
            error_msg = stderr.decode("utf-8") if stderr else "Unknown error"
            raise RuntimeError(f"claude-mpm failed (exit {process.returncode}): {error_msg}")

    except asyncio.CancelledError:
        process.kill()
        raise
```

### 4.3 Alternative: Use claude-mpm WebSocket Monitoring

For enhanced real-time updates, use claude-mpm's monitoring interface:

```python
# Start with monitoring enabled
cmd = [
    "claude-mpm", "run",
    "--non-interactive",
    "--no-hooks",
    "--no-tickets",
    "--monitor",                    # Enable monitoring
    "--websocket-port", "8765",     # WebSocket port
    "-i", user_question,
]

# Then connect to WebSocket for real-time updates
# ws://localhost:8765/socket.io
```

**Note**: WebSocket monitoring adds complexity but provides richer progress information.

---

## 5. claude-mpm Complete CLI Reference

### 5.1 Run Command Options

From source analysis of `/claude-mpm/src/claude_mpm/cli/parsers/run_parser.py`:

**Run Options** (claude-mpm specific):

| Flag                       | Type   | Description                                       |
| -------------------------- | ------ | ------------------------------------------------- |
| `--no-hooks`               | flag   | Disable hook service (recommended for automation) |
| `--no-tickets`             | flag   | Disable automatic ticket creation                 |
| `--intercept-commands`     | flag   | Enable /mpm: command interception                 |
| `--no-native-agents`       | flag   | Disable Claude Code native agents                 |
| `--launch-method`          | choice | `exec` (default) or `subprocess`                  |
| `--monitor`                | flag   | Enable WebSocket monitoring (port 8765)           |
| `--websocket-port`         | int    | Custom WebSocket port                             |
| `--force`                  | flag   | Force operations with warnings                    |
| `--reload-agents`          | flag   | Force rebuild system agents                       |
| `--mpm-resume`             | string | Resume MPM session by ID                          |
| `--resume`                 | flag   | Pass --resume to Claude CLI                       |
| `--chrome` / `--no-chrome` | flag   | Chrome integration control                        |

**Input/Output Options**:

| Flag                | Type   | Description                               |
| ------------------- | ------ | ----------------------------------------- |
| `-i`, `--input`     | string | Input text or file path (non-interactive) |
| `--non-interactive` | flag   | Run in non-interactive mode               |

**Dependency Options**:

| Flag                         | Type | Description                    |
| ---------------------------- | ---- | ------------------------------ |
| `--no-check-dependencies`    | flag | Skip agent dependency checking |
| `--force-check-dependencies` | flag | Force dependency check         |
| `--no-prompt`                | flag | Never prompt for installation  |
| `--force-prompt`             | flag | Force prompting                |

### 5.2 Environment Variables

| Variable              | Purpose                       | Required        |
| --------------------- | ----------------------------- | --------------- |
| `CLAUDE_MPM_USER_PWD` | Working directory for session | YES             |
| `ANTHROPIC_API_KEY`   | Claude API authentication     | YES (inherited) |
| `DISABLE_TELEMETRY`   | Disable analytics             | Recommended     |
| `CLAUDE_WORKSPACE`    | Set by claude-mpm internally  | No              |

### 5.3 Flags Passed Through to Claude CLI

These flags are NOT handled by claude-mpm but passed to the underlying `claude` binary:

| Flag                             | Purpose                                        |
| -------------------------------- | ---------------------------------------------- |
| `--print`                        | Non-interactive mode (added by OneshotSession) |
| `--dangerously-skip-permissions` | Skip permission prompts (added automatically)  |
| `--system-prompt-file <path>`    | Load system prompt from file                   |
| `--append-system-prompt <text>`  | Append to system prompt                        |
| `--agents <json>`                | Native agents configuration                    |
| `--model <name>`                 | Model selection                                |

### 5.4 Internal Command Building

From `oneshot_session.py`, the actual claude command built is:

```python
# Base command (always added)
cmd = ["claude", "--dangerously-skip-permissions"]

# Add custom arguments
if self.runner.claude_args:
    cmd.extend(self.runner.claude_args)

# Add --agents flag if native agents mode
if use_native_agents:
    cmd.extend(["--agents", agents_json])

# Final command with prompt
cmd = infrastructure["cmd"] + ["--print", full_prompt]

# Add system instructions
if system_prompt:
    cmd.extend(["--system-prompt-file", temp_path])
```

**Key insight**: claude-mpm internally uses `--print` when running in non-interactive mode.

---

## 6. Implementation Plan Updates (claude-mpm Exclusive)

### 6.1 Required Changes to Implementation Plan

**Section 7: Claude CLI Integration** must be updated to use claude-mpm exclusively.

**OLD (v1.0.1 - INCORRECT)**:

```python
# Uses native claude CLI directly
cmd = [
    claude_path,
    "--dangerously-skip-permissions",
    "--print",
    user_content,
]
process = await asyncio.create_subprocess_exec(
    *cmd,
    cwd=workspace_path,
)
```

**NEW (v1.1.0 - CORRECT)**:

```python
# Uses claude-mpm exclusively
cmd = [
    "claude-mpm",
    "run",
    "--non-interactive",
    "--no-hooks",
    "--no-tickets",
    "--launch-method", "subprocess",
    "-i", user_content,
]

env = os.environ.copy()
env["CLAUDE_MPM_USER_PWD"] = workspace_path
env["DISABLE_TELEMETRY"] = "1"

process = await asyncio.create_subprocess_exec(
    *cmd,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
    env=env,
    cwd=workspace_path,
)
```

### 6.2 Streaming Strategy (Recommended)

**Use line-buffered stdout streaming** with claude-mpm subprocess mode:

| Strategy               | Pros                          | Cons                   | Recommended |
| ---------------------- | ----------------------------- | ---------------------- | ----------- |
| Line-buffered stdout   | Simple, works with claude-mpm | Lines not characters   | YES         |
| claude-mpm + WebSocket | Rich progress info            | Complex setup          | Future      |
| Poll completion        | Simplest                      | No progressive updates | Fallback    |

### 6.3 Integration with research-mind-service

**Session Model Reference** (`/research-mind-service/app/models/session.py`):

- `session.workspace_path`: Absolute path to session sandbox
- `session.is_indexed()`: Returns True if `.mcp-vector-search/` exists

**Chat Service Integration**:

```python
# app/services/chat_service.py

async def stream_claude_response(
    session: SessionModel,
    user_content: str,
    assistant_message_id: str,
) -> AsyncGenerator[str, None]:
    """Stream response from claude-mpm."""
    workspace_path = session.workspace_path

    # Verify claude-mpm is available
    claude_mpm_path = shutil.which("claude-mpm")
    if not claude_mpm_path:
        raise ClaudeMpmNotAvailableError(
            "claude-mpm CLI is not available on PATH"
        )

    # Build command (claude-mpm exclusive)
    cmd = [
        claude_mpm_path,
        "run",
        "--non-interactive",
        "--no-hooks",
        "--no-tickets",
        "--launch-method", "subprocess",
        "-i", user_content,
    ]

    # Set environment
    env = os.environ.copy()
    env["CLAUDE_MPM_USER_PWD"] = workspace_path
    env["DISABLE_TELEMETRY"] = "1"

    # Yield SSE events (implementation continues...)
```

### 6.4 Error Handling Updates

**New Error Codes** (add to api-contract.md):

| Code                       | HTTP Status | Description                               |
| -------------------------- | ----------- | ----------------------------------------- |
| `CLAUDE_MPM_NOT_AVAILABLE` | 500         | claude-mpm CLI not found on PATH          |
| `CLAUDE_MPM_TIMEOUT`       | 500         | claude-mpm response timed out             |
| `CLAUDE_MPM_FAILED`        | 500         | claude-mpm process returned non-zero exit |

### 6.5 Configuration Updates

**Environment Variables Required** (add to `.env.example`):

```bash
# claude-mpm must be on PATH
# Typically installed via: pipx install "claude-mpm[monitor]"
# Verify with: claude-mpm --version

# ANTHROPIC_API_KEY must be set for Claude authentication
ANTHROPIC_API_KEY=sk-...
```

**Subprocess Timeout** (configurable):

```python
CLAUDE_MPM_TIMEOUT_SECONDS = int(os.getenv("CLAUDE_MPM_TIMEOUT", "300"))  # 5 minutes
```

---

## 7. Source Files Referenced

| File                                                                                                   | Purpose                    |
| ------------------------------------------------------------------------------------------------------ | -------------------------- |
| `/Users/mac/workspace/research-mind/claude-mpm/pyproject.toml`                                         | Entry point definition     |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/cli/__init__.py`                         | CLI main module            |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/cli/executor.py`                         | Command routing            |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/cli/parsers/run_parser.py`               | Run command arguments      |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/cli/commands/run.py`                     | Run command implementation |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/core/claude_runner.py`                   | Core orchestration         |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/core/interactive_session.py`             | Interactive session        |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/core/oneshot_session.py`                 | Oneshot session            |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/services/subprocess_launcher_service.py` | Subprocess with PTY        |
| `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/services/session_management_service.py`  | Session orchestration      |

---

## 8. Next Steps

1. **Verify native Claude CLI capabilities**:

   ```bash
   claude --help
   ```

2. **Test streaming support**:

   ```bash
   claude --print --output-format json "test" 2>&1
   ```

3. **Update implementation plan** with corrected CLI invocation strategy

4. **Consider hybrid approach**:
   - Use native Claude CLI for simple non-interactive queries
   - Use claude-mpm's monitoring WebSocket for progress updates

---

## 9. Complete Integration Specification

### 9.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     research-mind Session Chat                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Frontend (SvelteKit)                                                   │
│  ┌───────────────┐    ┌────────────────┐    ┌─────────────────────┐    │
│  │ Chat Input    │───▶│ POST /chat     │───▶│ EventSource (SSE)   │    │
│  │ (user types)  │    │ (create msg)   │    │ (stream response)   │    │
│  └───────────────┘    └────────────────┘    └─────────────────────┘    │
│                                │                      │                │
└────────────────────────────────┼──────────────────────┼────────────────┘
                                 │                      │
                                 ▼                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     Backend (FastAPI)                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌────────────────────┐         ┌───────────────────────────────┐      │
│  │ Chat Router        │────────▶│ Chat Service                  │      │
│  │ POST /chat         │         │ - create_user_message()       │      │
│  │ GET  /chat/stream  │         │ - stream_claude_response()    │      │
│  └────────────────────┘         └───────────────────────────────┘      │
│                                            │                            │
│                                            ▼                            │
│  ┌──────────────────────────────────────────────────────────────┐      │
│  │                  Subprocess Invocation                        │      │
│  │                                                               │      │
│  │  cmd = ["claude-mpm", "run",                                  │      │
│  │         "--non-interactive",                                  │      │
│  │         "--no-hooks", "--no-tickets",                         │      │
│  │         "--launch-method", "subprocess",                      │      │
│  │         "-i", user_question]                                  │      │
│  │                                                               │      │
│  │  env["CLAUDE_MPM_USER_PWD"] = session.workspace_path          │      │
│  │  cwd = session.workspace_path                                 │      │
│  │                                                               │      │
│  └──────────────────────────────────────────────────────────────┘      │
│                                            │                            │
└────────────────────────────────────────────┼────────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     claude-mpm (Subprocess)                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Reads CLAUDE_MPM_USER_PWD environment variable                      │
│  2. Changes to session workspace directory                              │
│  3. Deploys agents and skills                                          │
│  4. Builds internal command:                                           │
│     ["claude", "--dangerously-skip-permissions", "--print", ...]       │
│  5. Executes subprocess, captures output                               │
│  6. Returns output via stdout                                          │
│                                                                         │
│  Working Directory: /research-mind-service/content_sandboxes/          │
│                     {research_id}/{session_id}/repo/                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 9.2 Exact CLI Invocation

```bash
# Command to execute
claude-mpm run \
  --non-interactive \
  --no-hooks \
  --no-tickets \
  --launch-method subprocess \
  -i "User's question about the session content"

# Environment variables
export CLAUDE_MPM_USER_PWD="/Users/mac/workspace/research-mind/research-mind-service/content_sandboxes/{research_id}/{session_id}/repo"
export DISABLE_TELEMETRY="1"
# ANTHROPIC_API_KEY must be inherited from parent environment

# Working directory (set via subprocess cwd parameter)
cwd="/Users/mac/workspace/research-mind/research-mind-service/content_sandboxes/{research_id}/{session_id}/repo"
```

### 9.3 Output Format

claude-mpm with `--non-interactive` outputs plain text response via stdout:

```
Based on my analysis of the session content, I found:

1. Authentication patterns:
   - JWT token validation in auth/middleware.py
   - Session-based auth fallback

2. Database access patterns:
   - Repository pattern with SQLAlchemy ORM
   - Connection pooling configured

[Response continues...]
```

**Important**: Output is plain text, NOT JSON. Parse line-by-line for SSE streaming.

### 9.4 Session Workspace Structure

From research-mind-service Session model:

```
content_sandboxes/
└── {research_id}/
    └── {session_id}/
        ├── repo/                      # Cloned/copied content
        │   ├── .mcp-vector-search/    # Vector index (when indexed)
        │   ├── src/
        │   └── ...
        └── metadata.json              # Session metadata
```

- `session.workspace_path` = Full path to `repo/` directory
- `session.is_indexed()` = True if `.mcp-vector-search/` exists

### 9.5 SSE Event Format

```
event: start
data: {"message_id": "uuid", "status": "streaming"}

event: chunk
data: {"content": "Based on my analysis"}

event: chunk
data: {"content": " of the session content..."}

event: complete
data: {"message_id": "uuid", "status": "completed", "token_count": 542, "duration_ms": 3200}
```

### 9.6 Error Scenarios

| Scenario             | Detection                       | SSE Event                                     |
| -------------------- | ------------------------------- | --------------------------------------------- |
| claude-mpm not found | `shutil.which()` returns None   | `error` event with `CLAUDE_MPM_NOT_AVAILABLE` |
| Process timeout      | `asyncio.TimeoutError`          | `error` event with `CLAUDE_MPM_TIMEOUT`       |
| Non-zero exit        | `process.returncode != 0`       | `error` event with `CLAUDE_MPM_FAILED`        |
| Session not indexed  | `session.is_indexed() == False` | 400 before stream starts                      |

---

## 10. Implementation Checklist

### Backend Tasks

- [ ] Update `chat_service.py` to use `claude-mpm` instead of native `claude`
- [ ] Change subprocess command from `["claude", "--print", ...]` to `["claude-mpm", "run", "--non-interactive", ...]`
- [ ] Add `CLAUDE_MPM_USER_PWD` environment variable
- [ ] Update error codes in `api-contract.md`
- [ ] Add `claude-mpm` availability check at startup
- [ ] Update unit tests with mocked claude-mpm subprocess

### Frontend Tasks

- [ ] No changes required (SSE streaming unchanged)
- [ ] Update error message display for new error codes

### Documentation Tasks

- [ ] Update implementation plan v1.1.0 with claude-mpm integration
- [ ] Add claude-mpm installation requirement to deployment docs
- [ ] Update `.env.example` with claude-mpm notes

---

_Research conducted: 2026-02-03_
_Updated: 2026-02-03 (v1.1 - claude-mpm exclusive integration)_
_Source: /Users/mac/workspace/research-mind/claude-mpm/_
