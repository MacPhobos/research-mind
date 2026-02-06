# Claude-MPM Internals Research

**Date**: 2026-02-06
**Researcher**: Research Agent (Task #3)
**Scope**: claude-mpm startup sequence, sync mechanisms, configuration, CLAUDE.md processing, and optimization opportunities

---

## 1. Executive Summary

claude-mpm (v5.6.97) is a Python CLI wrapper around Claude Code that adds multi-agent orchestration, skill management, hook integration, and custom instruction injection. When launched, it performs extensive initialization (agent/skill sync, hook deployment, migrations, MCP checks, update checks) before finally `exec`-ing into the Claude Code process. The startup sequence involves **multiple network calls** to GitHub for agent and skill synchronization, **file system operations** for deployment, and **service initialization**. Understanding this pipeline is essential for optimizing Research Mind's question-answering response time.

---

## 2. Startup Sequence Diagram

```
claude-mpm CLI invocation
    |
    v
[1] setup_early_environment()          ~1ms
    - Suppress all logging (CRITICAL+1)
    - Set DISABLE_TELEMETRY=1
    - Process argv
    |
    v
[2] create_parser() + parse_args()     ~5ms
    - Build argparse from modular parsers/
    - Preprocess args (alias expansion)
    |
    v
[3] has_configuration_file()            ~1ms
    - Check .claude-mpm/configuration.yaml
    - If missing: prompt for configure (interactive)
    |
    v
[4] setup_mcp_server_logging()          ~2ms
    - Configure logging level based on user preference
    |
    v
[5] ensure_directories()                ~1ms
    - Create required directory structure
    |
    v
[6] run_migrations()                    ~5-50ms
    - Check ~/.claude-mpm/migrations.yaml
    - Run any pending migrations (idempotent)
    |
    v
[7] display_startup_banner()            ~10ms
    - Show ASCII art, version, git info
    - Display migration results
    |
    v
[8] run_background_services()           ~5-30 SECONDS (bottleneck!)
    |
    +--[8a] sync_deployment_on_startup()
    |   +-- sync_hooks_on_startup()       ~50-200ms
    |   |   - Cleanup stale user-level hooks
    |   |   - Install project hooks to .claude/settings.local.json
    |   |
    |   +-- sync_remote_agents_on_startup()  ~2-10 SECONDS
    |   |   - Load profile manager
    |   |   - Phase 1: GitHub API Tree call to discover files
    |   |   - Phase 1: Download agents via raw.githubusercontent.com
    |   |   - ETag caching (JSON file) for 95%+ cache hits
    |   |   - Phase 2: perform_startup_reconciliation()
    |   |   - Phase 2: Deploy agents to .claude/agents/
    |   |   - Phase 3: Cleanup orphaned agents
    |   |   - Phase 4: Cleanup legacy cache directories
    |   |   - Save deployment state hash
    |   |
    |   +-- show_agent_summary()           ~10ms
    |
    +--[8b] initialize_project_registry()  ~10ms
    |   - Track project metadata across sessions
    |
    +--[8c] check_mcp_auto_configuration() ~100ms-10s
    |   - Check if MCP configured for pipx installs
    |   - May prompt user (10s timeout)
    |
    +--[8d] verify_mcp_gateway_startup()   ~async (background thread)
    |   - Verify MCP gateway config
    |   - Background thread, non-blocking
    |
    +--[8e] check_for_updates_async()      ~async (background thread)
    |   - Check PyPI/npm for updates
    |   - Background thread, non-blocking
    |
    +--[8f] deploy_bundled_skills()        ~50-200ms
    |   - Deploy skills from package bundled/ dir
    |   - Respects auto_deploy config setting
    |
    +--[8g] sync_remote_skills_on_startup() ~3-15 SECONDS
    |   - Phase 1: GitHub Tree API discovery for skill files
    |   - Phase 1: Download skill files (markdown, JSON)
    |   - ETag caching for bandwidth reduction
    |   - Phase 2: Scan agents for skill requirements
    |   - Phase 3: Resolve which skills to deploy
    |   - Phase 4: Apply profile filtering
    |   - Phase 5: Deploy to .claude/skills/
    |
    +--[8h] discover_and_link_runtime_skills() ~50ms
    |   - Discover user-added skills in .claude/skills/
    |
    +--[8i] show_skill_summary()           ~10ms
    |
    +--[8j] verify_and_show_pm_skills()    ~50ms
    |   - Verify 8 required PM skills
    |   - Auto-repair if missing/corrupted
    |
    +--[8k] deploy_output_style_on_startup() ~50ms
    |   - Deploy claude-mpm.md, teacher, research styles
    |
    +--[8l] auto_install_chrome_devtools()  ~100ms
        - Install chrome-devtools-mcp if enabled
    |
    v
[9] "Starting Claude Code..." message
    |
    v
[10] execute_command("run", args)
    |
    v
[11] ClaudeRunner.__init__()            ~200-500ms
    - Initialize config via DI container
    - Register services (deployment, hooks, memory, etc.)
    - Load system instructions (PM_INSTRUCTIONS.md + custom)
    - Deploy output style
    |
    v
[12] run_session_legacy(args)
    - StartupCheckerService health checks
    - Session management (create/resume)
    - Dependency checking
    - Monitor setup (optional)
    |
    v
[13] _build_claude_command()
    - Build: claude --dangerously-skip-permissions [args...]
    - Assemble system prompt from instructions
    - Cache instructions to file (hash-based invalidation)
    - Add --system-prompt-file <cache_file>
    - OR fallback: --append-system-prompt <inline>
    |
    v
[14] os.execvpe("claude", cmd, env)     PROCESS REPLACED
    - Replaces claude-mpm process with Claude Code
    - Claude Code handles its own initialization (~3-5 seconds)
    |
    v
[Claude Code is now running - user sees interactive prompt]
```

---

## 3. Sync Mechanism Analysis

### 3.1 Agent Sync (Most Significant Startup Cost)

**File**: `src/claude_mpm/services/agents/startup_sync.py`
**File**: `src/claude_mpm/services/agents/sources/git_source_sync_service.py`
**File**: `src/claude_mpm/cli/startup.py:679-866`

**Mechanism**:
1. Load agent source configuration from `~/.claude-mpm/config/agent_sources.yaml`
2. Default source: `https://github.com/bobmatnyc/claude-mpm-agents` (branch: main)
3. For each source:
   - Call GitHub Tree API to discover all files in repo
   - Check ETag cache (JSON file at `~/.claude-mpm/cache/agents/<owner>/<repo>/.etag_cache.json`)
   - Download changed files via `raw.githubusercontent.com`
   - Store in local cache: `~/.claude-mpm/cache/agents/<owner>/<repo>/agents/`
4. After sync: `perform_startup_reconciliation()` deploys configured agents to `.claude/agents/`

**Timing Estimates**:
| Scenario | Duration | Notes |
|----------|----------|-------|
| First run (cold cache) | 5-10s | Downloads all agent files (~30 agents) |
| Normal run (cached, no changes) | 1-3s | ETag checks only, HTTP 304 responses |
| Normal run (some changes) | 2-5s | Download changed files + deploy |
| All cached (no network) | <1s | Local file checks only |

**ETag Caching**:
- `ETagCache` class (line 44-97 in `git_source_sync_service.py`)
- JSON file-based storage per repository
- Stores: etag, last_modified, file_size per URL
- 95%+ bandwidth reduction after initial sync
- Cache location: `~/.claude-mpm/cache/agents/<owner>/<repo>/.etag_cache.json`

### 3.2 Skill Sync (Second Largest Startup Cost)

**File**: `src/claude_mpm/cli/startup.py:874-1212`
**File**: `src/claude_mpm/services/skills/git_skill_source_manager.py`

**Mechanism**:
1. Load skill source configuration from `~/.claude-mpm/config/skill_sources.yaml`
2. Default sources: `bobmatnyc/claude-mpm-skills` (priority 0) + `anthropics/skills` (priority 1)
3. Phase 1: GitHub Tree API discovery + file sync with ETag caching
4. Phase 2: Scan deployed agents for skill requirements (`get_required_skills_from_agents()`)
5. Phase 3: Resolve which skills to deploy (user_defined vs agent_referenced)
6. Phase 4: Apply profile filtering
7. Phase 5: Deploy resolved skills to `.claude/skills/`

**Timing Estimates**:
| Scenario | Duration | Notes |
|----------|----------|-------|
| First run | 10-15s | Download all skill files (~80+ skills) |
| Normal run (cached) | 3-5s | ETag checks + scan agents + deploy |
| All cached, no changes | 1-2s | Quick checks only |

### 3.3 Deployment State Tracking

**File**: `src/claude_mpm/cli/startup.py:591-676` + `src/claude_mpm/core/claude_runner.py:216-333`

The system uses a deployment state file at `.claude-mpm/cache/deployment_state.json`:
```json
{
    "version": "5.6.97",
    "agent_count": 15,
    "deployment_hash": "sha256:...",
    "deployed_at": 1234567890.123
}
```

`ClaudeRunner.setup_agents()` checks this state to skip re-deployment if:
- Version matches current package version
- Agent count and content hash match

This prevents duplicate deployment during `ClaudeRunner.__init__()` after startup reconciliation already ran.

---

## 4. Configuration Reference Table

### 4.1 Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| `configuration.yaml` | `.claude-mpm/configuration.yaml` (project) or `~/.claude-mpm/configuration.yaml` (user) | Main configuration |
| `agent_sources.yaml` | `~/.claude-mpm/config/agent_sources.yaml` | Agent Git repository sources |
| `skill_sources.yaml` | `~/.claude-mpm/config/skill_sources.yaml` | Skill Git repository sources |
| `migrations.yaml` | `~/.claude-mpm/migrations.yaml` | Tracks completed startup migrations |
| `deployment_state.json` | `.claude-mpm/cache/deployment_state.json` | Agent deployment hash/version |
| `.etag_cache.json` | `~/.claude-mpm/cache/agents/<owner>/<repo>/` | Per-repo ETag cache |
| `settings.local.json` | `.claude/settings.local.json` | Claude Code settings + hooks |

### 4.2 Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_MPM_FORCE_SYNC` | `"0"` | Force agent/skill sync (bypass ETag cache) |
| `CLAUDE_MPM_SKIP_CLEANUP` | `"0"` | Skip log cleanup on startup |
| `DISABLE_TELEMETRY` | `"1"` | Disable telemetry |
| `CLAUDE_MPM_USER_PWD` | (unset) | Override user working directory |
| `GITHUB_TOKEN` / `GH_TOKEN` | (unset) | GitHub auth for private repos |

### 4.3 CLI Flags

| Flag | Purpose |
|------|---------|
| `--force-sync` | Force refresh agents/skills from remote repos (bypass ETag) |
| `--resume` | Resume previous Claude session |
| `--no-native-agents` | Skip agent deployment |
| `--no-hooks` | Skip hook installation |
| `--no-tickets` | Disable ticket extraction |
| `--headless` | Headless mode for orchestrators |
| `--headless --resume` | Skip ALL background services (fastest path) |
| `--logging OFF/DEBUG/INFO` | Control logging level (default: OFF) |
| `--launch-method exec/subprocess` | Process launch method |

### 4.4 Config Sections (configuration.yaml)

| Section | Key Settings |
|---------|--------------|
| `agent_sync.enabled` | Enable/disable agent sync (default: `true`) |
| `agent_sync.sources[]` | List of agent sources with url, branch, enabled |
| `skills.auto_deploy` | Enable/disable bundled skill deployment (default: `true`) |
| `updates.check_enabled` | Enable update checks (default: `true`) |
| `updates.check_frequency` | "daily", "weekly", "never" |
| `updates.auto_upgrade` | Auto-upgrade when update found (default: `false`) |
| `chrome_devtools.auto_install` | Auto-install chrome-devtools MCP (default: `true`) |
| `active_profile` | Name of active agent/skill profile |

---

## 5. CLAUDE.md Processing Pipeline

### 5.1 Instruction Loading Chain

**Files**:
- `src/claude_mpm/core/framework_loader.py` - Main framework loader
- `src/claude_mpm/core/framework/loaders/instruction_loader.py` - Instruction file loading
- `src/claude_mpm/core/framework/loaders/file_loader.py` - File I/O operations
- `src/claude_mpm/core/framework/loaders/packaged_loader.py` - Bundled instruction loading
- `src/claude_mpm/core/interactive_session.py:379-493` - Command building with instructions

**Loading Order** (via `InstructionLoader.load_all_instructions()`):

```
1. load_custom_instructions()
   - Search: .claude-mpm/INSTRUCTIONS.md (project level)
   - Search: ~/.claude-mpm/INSTRUCTIONS.md (user level)
   - Stored as: content["custom_instructions"]

2. load_framework_instructions()
   Priority chain:
   a. .claude-mpm/PM_INSTRUCTIONS_DEPLOYED.md (compiled version)
      - Version check against source (PM_INSTRUCTIONS_VERSION:XXXX)
      - If stale: falls through to source
   b. src/claude_mpm/agents/PM_INSTRUCTIONS.md (development)
   c. Packaged version (pip/pipx installs)
   - Stored as: content["framework_instructions"]

3. load_workflow_instructions()
   - Search: .claude-mpm/WORKFLOW.md
   - Stored as: content["workflow"]

4. load_memory_instructions()
   - Search: .claude-mpm/MEMORY.md
   - Stored as: content["memory"]
```

### 5.2 How CLAUDE.md Fits

CLAUDE.md is NOT loaded by claude-mpm directly. Instead:
- **Claude Code** natively reads CLAUDE.md from the project root
- claude-mpm adds **supplementary instructions** via `--system-prompt-file` or `--append-system-prompt`
- These supplementary instructions include PM_INSTRUCTIONS.md, custom INSTRUCTIONS.md, WORKFLOW.md, MEMORY.md
- The combined content is ~152 KB (exceeds Linux ARG_MAX of 128 KB), so file-based loading is used

### 5.3 System Prompt Assembly

**File**: `src/claude_mpm/core/interactive_session.py:414-481`

```
_create_system_prompt()
    |
    +-- FrameworkLoader.get_full_context()
    |   - Combines all loaded instructions
    |   - Includes agent capabilities
    |   - Includes memory context
    |
    +-- InstructionCacheService.update_cache()
    |   - Hash-based invalidation (SHA-256)
    |   - Cache file: .claude-mpm/cache/instruction_cache.md
    |   - Updates only when content hash changes
    |
    +-- Command generation:
        - Preferred: --system-prompt-file <cache_file>
        - Fallback: --append-system-prompt <inline_content>
```

### 5.4 Custom Instruction Injection Methods

| Method | Location | How It Works |
|--------|----------|--------------|
| CLAUDE.md | Project root | Natively read by Claude Code (not claude-mpm) |
| INSTRUCTIONS.md | `.claude-mpm/INSTRUCTIONS.md` | Loaded by InstructionLoader, injected via --system-prompt-file |
| PM_INSTRUCTIONS.md | `.claude-mpm/PM_INSTRUCTIONS.md` | Framework instructions for PM behavior |
| WORKFLOW.md | `.claude-mpm/WORKFLOW.md` | Workflow instructions |
| MEMORY.md | `.claude-mpm/MEMORY.md` | Memory/context instructions |
| Output styles | `.claude/output-styles/claude-mpm.md` | Claude Code native output style system |
| Skills | `.claude/skills/*/skill.md` | Claude Code native skill system |
| Agents | `.claude/agents/*.md` | Claude Code native agent system |
| Hooks | `.claude/settings.local.json` | Claude Code hook system (pre/post tool use) |

---

## 6. Optimization Opportunities

### 6.1 HIGH IMPACT: Skip Sync When Cached (Headless + Resume Pattern)

**Current**: `should_skip_background_services()` returns `true` only for `--headless --resume`.

**Opportunity**: Extend skip logic to detect when cache is fresh and deployment state matches. This would eliminate the 5-30 second sync overhead on subsequent launches.

**Implementation**:
```python
# In startup.py, add to should_skip_background_services():
def _is_cache_fresh() -> bool:
    state_file = Path.cwd() / ".claude-mpm" / "cache" / "deployment_state.json"
    if state_file.exists():
        state = json.loads(state_file.read_text())
        # Skip if same version and deployed within last N minutes
        from claude_mpm import __version__
        if state.get("version") == __version__:
            age = time.time() - state.get("deployed_at", 0)
            if age < 300:  # 5 minutes
                return True
    return False
```

**Expected Impact**: Eliminates 5-30s of startup time for rapid re-launches.

### 6.2 HIGH IMPACT: Parallel Sync of Agents and Skills

**Current**: Agent sync and skill sync run sequentially in `run_background_services()`.

**Opportunity**: Run agent sync and skill sync concurrently since they are independent operations.

**Implementation**: Use `concurrent.futures.ThreadPoolExecutor` to parallelize:
- `sync_remote_agents_on_startup()`
- `sync_remote_skills_on_startup()`

**Expected Impact**: Reduces combined sync time from sequential (agent_time + skill_time) to max(agent_time, skill_time). Potential 30-50% reduction in startup time.

### 6.3 MEDIUM IMPACT: Lazy/Deferred Sync

**Current**: All sync happens synchronously before Claude Code launches.

**Opportunity**: Defer non-critical sync to background threads:
- Skill sync can run after Claude Code launches (skills are already deployed from cache)
- Update checks already run in background (good pattern to follow)
- MCP gateway verification already runs in background thread

**Expected Impact**: Reduces blocking startup time by 3-15 seconds.

### 6.4 MEDIUM IMPACT: TTL-Based Sync Skip

**Current**: Every startup triggers ETag checks against GitHub, even if last sync was seconds ago.

**Opportunity**: Add a configurable TTL (time-to-live) for sync freshness:
```yaml
# configuration.yaml
agent_sync:
  freshness_ttl: 3600  # seconds (1 hour)
skills:
  freshness_ttl: 3600
```

If last sync was within TTL, skip network calls entirely. The deployment state file already has `deployed_at` timestamp.

**Expected Impact**: Eliminates network latency entirely for repeated launches within TTL window.

### 6.5 MEDIUM IMPACT: Direct Claude Code Invocation (Bypass claude-mpm)

For Research Mind's Q&A system, the most aggressive optimization:

**Approach**: Launch Claude Code directly (not through claude-mpm) with pre-built instructions.

```bash
claude --dangerously-skip-permissions \
  --system-prompt-file /path/to/prebuilt-instructions.md \
  -p "user question here" \
  --output-format json
```

**Requirements**:
- Pre-deploy agents/skills once (via `claude-mpm run` initially)
- Pre-build instruction cache (one-time operation)
- Skip all sync/hook/migration overhead

**Expected Impact**: Eliminates ALL claude-mpm startup overhead (5-30s). Claude Code itself starts in ~3-5 seconds.

### 6.6 LOW IMPACT: Reduce GitHub API Calls

**Current**: Tree API call + individual file downloads for each source.

**Opportunity**: Use GitHub's tarball/zipball download for bulk operations on cold cache, reducing from N+1 HTTP calls to 2 (tree discovery + tarball).

**Expected Impact**: Faster cold-cache startup (first run only).

### 6.7 LOW IMPACT: Instruction Cache Optimization

**Current**: InstructionCacheService uses hash-based invalidation, which is already efficient.

**Opportunity**: Pre-compute instruction cache during `make install` or a dedicated init step, so runtime never needs to assemble instructions.

**Expected Impact**: Saves ~100-200ms per launch.

---

## 7. Internal Architecture for Query Processing

### 7.1 Process Model

```
[Research Mind Service]  --HTTP-->  [claude-mpm CLI process]
                                         |
                                    os.execvpe()
                                         |
                                    [Claude Code process]
                                         |
                                    [Anthropic API]
```

claude-mpm does NOT persist as a daemon. It:
1. Initializes (sync, deploy, configure)
2. Builds command with instructions
3. **Replaces itself** with Claude Code via `os.execvpe()`
4. Claude Code handles all subsequent interaction

### 7.2 Launch Modes

| Mode | Method | Use Case |
|------|--------|----------|
| Interactive (`exec`) | `os.execvpe("claude", cmd, env)` | Default: replaces process |
| Subprocess | `subprocess.run()` with PTY | More control, monitoring |
| Oneshot | Subprocess + `-p` flag | Non-interactive Q&A |
| Headless | `--headless` flag | Orchestrator integration |

### 7.3 Instruction Injection into Claude Code

The command built by claude-mpm before exec:

```bash
claude \
  --dangerously-skip-permissions \
  [user claude_args...] \
  --system-prompt-file .claude-mpm/cache/instruction_cache.md
```

The instruction cache file contains:
- PM_INSTRUCTIONS.md (PM behavioral framework)
- Custom INSTRUCTIONS.md (user overrides)
- WORKFLOW.md (workflow patterns)
- MEMORY.md (context memory)
- Agent capabilities summary
- Output style injection (legacy fallback)

Total size: ~152 KB (hence file-based loading to avoid ARG_MAX).

### 7.4 For Research Mind Q&A Specifically

The Research Mind service likely invokes claude-mpm in one of these patterns:

1. **Interactive mode**: `claude-mpm run` (user-facing, full startup)
2. **Oneshot mode**: `claude -p "question" --output-format json` (API-driven)
3. **Headless mode**: `claude-mpm --headless --resume` (orchestrator pattern, skips init)

For Q&A optimization, the **oneshot/headless** patterns are most relevant since they can skip the full sync overhead.

---

## 8. Key File Reference

| Component | File Path | Lines |
|-----------|-----------|-------|
| CLI entry point | `src/claude_mpm/cli/__init__.py` | Main `main()` function |
| Startup services | `src/claude_mpm/cli/startup.py` | All background service init (1882 lines) |
| Run command | `src/claude_mpm/cli/commands/run.py` | Session launch logic |
| ClaudeRunner | `src/claude_mpm/core/claude_runner.py` | Agent deployment + config |
| Interactive session | `src/claude_mpm/core/interactive_session.py` | Command building + exec |
| Oneshot session | `src/claude_mpm/core/oneshot_session.py` | Non-interactive execution |
| Agent sync | `src/claude_mpm/services/agents/startup_sync.py` | Agent sync orchestration |
| Git sync service | `src/claude_mpm/services/agents/sources/git_source_sync_service.py` | ETag caching + HTTP |
| Instruction loader | `src/claude_mpm/core/framework/loaders/instruction_loader.py` | CLAUDE.md pipeline |
| Framework loader | `src/claude_mpm/core/framework_loader.py` | Full instruction assembly |
| Config singleton | `src/claude_mpm/core/config.py` | Thread-safe config loading |
| Unified config | `src/claude_mpm/core/unified_config.py` | Pydantic config models |
| Shared config loader | `src/claude_mpm/core/shared/config_loader.py` | YAML/env config loading |
| Agent sources config | `src/claude_mpm/config/agent_sources.py` | Git repo configuration |
| Skill sources config | `src/claude_mpm/config/skill_sources.py` | Git repo configuration |
| Startup display | `src/claude_mpm/cli/startup_display.py` | Banner + ASCII art |
| Startup migrations | `src/claude_mpm/cli/startup_migrations.py` | Migration registry |
| Deployment reconciler | `src/claude_mpm/services/agents/deployment/deployment_reconciler.py` | Agent reconciliation |

---

## 9. Summary of Findings

### What Makes Startup Slow

1. **Agent sync** (2-10s): GitHub API calls + file downloads + reconciliation deployment
2. **Skill sync** (3-15s): GitHub API calls + file downloads + agent scanning + deployment
3. **Sequential execution**: Agent sync and skill sync run one after another
4. **No TTL**: Every launch triggers network checks, even seconds after last sync
5. **ClaudeRunner init** (200-500ms): Heavy DI container setup with many services

### What's Already Optimized

1. **ETag caching**: 95%+ bandwidth reduction after initial sync
2. **Deployment state hashing**: Skip re-deployment when hash matches
3. **Background threads**: Update checks + MCP verification run asynchronously
4. **Headless+resume**: Complete skip of background services for orchestrators
5. **Instruction caching**: Hash-based invalidation avoids redundant assembly
6. **File-based prompt loading**: Avoids ARG_MAX limits on Linux/Windows

### Critical Path for Q&A Optimization

For Research Mind's Q&A system, the fastest path is:
1. **One-time setup**: Run `claude-mpm run` once to deploy agents/skills/hooks
2. **Q&A queries**: Launch Claude Code directly, bypassing claude-mpm entirely:
   ```bash
   claude --dangerously-skip-permissions \
     --system-prompt-file .claude-mpm/cache/instruction_cache.md \
     -p "user question" \
     --output-format json
   ```
3. **Periodic maintenance**: Run full `claude-mpm run` periodically to refresh agents/skills

This eliminates the 5-30 second claude-mpm startup overhead while preserving all the instruction injection and agent/skill availability.
