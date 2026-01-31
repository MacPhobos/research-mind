# Claude MPM: Capabilities & Architecture

**Document Version**: 1.0
**Date**: 2026-01-30
**Status**: Research Complete

## Executive Summary

Claude MPM (Multi-Project Manager) is a sophisticated agent orchestration framework for Claude Code CLI that provides multi-agent workflows, session management, and real-time monitoring. For Research-Mind integration, key capabilities are session management, tool configuration, and filesystem access patterns.

Key strengths: Session resumption, agent deployment system, skills framework, MCP integration.
Key gaps: No inherent sandbox isolation (relies on prompts), limited filesystem scoping, no built-in audit logging.

---

## 1. How to Run Claude MPM

### 1.1 Installation

**Prerequisites**: Claude Code CLI v2.1.3+ (required)

```bash
# Install via pipx (recommended)
pipx install "claude-mpm[monitor]"

# Or via homebrew
brew install claude-mpm --with-monitor

# Verify installation
claude-mpm --version
claude --version
```

### 1.2 Running Modes

**Interactive Mode**:

```bash
claude-mpm
# Starts interactive prompt where you can type tasks
# Agent delegation happens automatically
# Session preserved for future invocations
```

**One-Shot Mode**:

```bash
claude-mpm run "Research the authentication module"
# Executes single task and exits
# Session can be resumed later with --resume
```

**With Monitoring**:

```bash
claude-mpm run --monitor
# Starts web dashboard at http://localhost:8000
# Real-time view of agent activity
```

**Resume Previous Session**:

```bash
claude-mpm run --resume
# Loads previous session from disk
# Continues with same context and conversation
```

### 1.3 Configuration Files

**Location**: `~/.claude-mpm/` (user home directory)

```
~/.claude-mpm/
├── configuration.yaml           # Main configuration
├── sessions/
│   ├── session_id_1.json       # Session data (resumption)
│   └── session_id_2.json
├── agents/                      # 47+ deployed agents
│   ├── python-expert/
│   ├── rust-expert/
│   └── [other agents]
├── skills/                      # Bundled skills
│   ├── git/
│   ├── testing/
│   └── [other skills]
└── agent-sources.yaml           # Registered agent repositories
```

**Configuration structure** (`configuration.yaml`):

```yaml
claude_code_cli:
  version: "2.1.3+"
  path: /usr/local/bin/claude

agents:
  deployment_path: ~/.claude/agents
  auto_deploy: true
  repositories:
    - name: "anthropic-official"
      url: "https://github.com/anthropic/claude-mpm-agents"
      enabled: true
    - name: "custom-org"
      url: "https://github.com/myorg/agents"
      enabled: true

session:
  default_context: "pm_orchestration"
  resume_timeout_minutes: 720 # 30 days
  session_dir: ~/.claude-mpm/sessions
  max_token_budget: 100000

monitoring:
  enabled: false
  dashboard_port: 8000
  real_time_updates: true

skills:
  path: ~/.claude/skills
  bundled: true
  auto_link: true
```

---

## 2. Session Management

### 2.1 Session Types

**Location**: `/src/claude_mpm/core/session_manager.py`

```python
class SessionManager:
    """Manages session lifecycle and resumption."""

    def create_session(self, context: str = "default") -> str:
        """Create new session ID (UUID)."""
        session_id = str(uuid.uuid4())
        self.active_sessions[session_id] = {
            "id": session_id,
            "context": context,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "last_used": datetime.now(timezone.utc).isoformat(),
            "use_count": 0,
            "agents_run": [],
        }
        return session_id

    def get_or_create_session(
        self, context: str = "default", max_age_minutes: int = 30
    ) -> str:
        """Get existing session or create new one."""
        # Reuses sessions within max_age
```

**Session storage**:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "context": "pm_orchestration",
  "created_at": "2026-01-30T16:00:00Z",
  "last_used": "2026-01-30T16:15:30Z",
  "use_count": 3,
  "agents_run": [
    {
      "agent": "python-expert",
      "task": "Analyze authentication module",
      "timestamp": "2026-01-30T16:00:05Z"
    }
  ],
  "conversation_history": [
    {
      "role": "user",
      "content": "Research OAuth2 implementation",
      "timestamp": "2026-01-30T16:00:05Z"
    }
  ],
  "context_data": {
    "working_directory": "/path/to/project",
    "environment": {}
  }
}
```

### 2.2 Session Lifecycle

```
[Create Session]
│
└─→ Assign UUID session_id
    └─→ Initialize conversation_history: []
        └─→ Set context (pm_orchestration, agent_delegation, etc.)
            └─→ Store to ~/.claude-mpm/sessions/{session_id}.json
                │
                └─→ [User submits first task]
                    │
                    └─→ Agent routing (PM agent delegates)
                        │
                        └─→ [Session resumed or continued]
                            │
                            └─→ Append to conversation_history
                                └─→ Add to agents_run log
                                    └─→ Persist session
                                        │
                                        └─→ [User exits]
                                            │
                                            └─→ Session remains active
                                                └─→ Can be resumed within max_age_minutes
```

### 2.3 Resume Behavior

When resuming a session:

1. Load `~/.claude-mpm/sessions/{session_id}.json`
2. Restore conversation_history
3. Restore context_data (working directory, env vars)
4. Create "session resumed" log entry
5. Continue with new prompt or task

**Resume timeout**: Default 30 days (configurable)

```python
def should_reuse_session(session_data, max_age_minutes: int = 30):
    last_used = datetime.fromisoformat(session_data["last_used"])
    age = datetime.now(timezone.utc) - last_used
    return age.total_seconds() < (max_age_minutes * 60)
```

---

## 3. Tool Configuration & Access

### 3.1 Tool Types in Claude MPM

**Location**: `/src/claude_mpm/tools/`

```
Tool Categories:
├── Filesystem Tools
│   ├── read_file
│   ├── write_file
│   ├── list_directory
│   └── search_files
├── Git Tools
│   ├── git_status
│   ├── git_diff
│   ├── git_log
│   └── git_clone
├── Execution Tools
│   ├── run_command
│   ├── run_tests
│   └── execute_script
├── Code Analysis Tools
│   ├── analyze_code
│   ├── find_functions
│   └── extract_imports
└── MCP Tools
    ├── vector_search (if mcp-vector-search configured)
    ├── gmail_search (if google-workspace-mpm configured)
    └── [other MCP tools]
```

### 3.2 Tool Access Configuration

**Defined in**: Agent definitions (`.claude/agents/{agent}/AGENT.md`)

```markdown
# Agent Definition Format

## Tools Available

- file-read: Read source files
- file-write: Write to project files
- git: Full git access
- execute: Run shell commands
- search: Semantic code search (if mcp-vector-search available)

## Constraints

- Working Directory: `{WORKSPACE_DIR}` (restricted to project root)
- Can only read/write files within project
- Network: Disabled by default
- Command execution: Sandboxed via Claude CLI
```

### 3.3 Filesystem Access Patterns

**Current behavior** (NOT sandbox-enforced):

```python
# From agent instructions, not enforced by system
# "You have access to files in the project directory only"
# But this is prompt-based, not enforced

class FileAccessTool:
    def read_file(self, path: str):
        # No path validation!
        # Just reads whatever path is given
        with open(path, 'r') as f:
            return f.read()

    def list_directory(self, path: str):
        # No restriction to project root
        return os.listdir(path)
```

**Implicit scoping** (prompt-based):

- Agents are told "work within project directory"
- No code-level enforcement
- Relies on agent following instructions

---

## 4. Agent & Skill System

### 4.1 Agent Architecture

**Location**: `/src/claude_mpm/agents/`

47+ deployed agents including:

- Python Expert
- Rust Expert
- TypeScript Expert
- Security Analyst
- QA Engineer
- DevOps Engineer
- [And 40+ others]

**Agent structure**:

```
~/.claude/agents/python-expert/
├── AGENT.md                    # Agent definition
├── BASE-AGENT.md              # Inherited base template
├── context/
│   ├── knowledge.md           # Domain knowledge
│   ├── patterns.md            # Common patterns
│   └── examples/
│       └── *.md               # Example workflows
└── skills/                    # Linked skill references
```

### 4.2 Agent Definition Format

**AGENT.md structure**:

```markdown
# Python Expert Agent

## Identity

Name: python-expert
Role: Python development specialist
Expertise: Python 3.9+, FastAPI, async patterns, testing

## Capabilities

- Analyze Python code for quality and performance
- Suggest refactoring patterns
- Write comprehensive tests
- Debug complex issues

## Tools Available

- read/write files
- execute python scripts
- run pytest
- semantic code search (mcp-vector-search)

## Constraints

- Working directory: Limited to project root (prompt-based)
- No external network access (prompt-based)
- Focus on Python files (\*.py)

## Skills

- git-workflow
- testing-tdd
- code-review

## Decision Model

- Ask clarifying questions before major refactoring
- Suggest tests first, implementation second
- Provide multiple solution options for complex problems
```

### 4.3 Skills System

**Location**: `/src/claude_mpm/skills/`

17 bundled skills:

- git-workflow
- testing-tdd
- docker-workflow
- api-documentation
- code-review
- debugging
- [and more]

**Skill structure**:

```
~/.claude/skills/testing-tdd/
├── SKILL.md                   # Skill definition
├── workflows/
│   ├── test-first.md          # TDD workflow
│   └── test-debugging.md      # Debug via tests
├── examples/
│   ├── python/
│   ├── typescript/
│   └── rust/
└── patterns/
    └── common-patterns.md
```

### 4.4 Agent-to-Skill Linking

**Auto-linking** (from configuration):

```python
# claude-mpm automatically links relevant skills
# Based on agent role and problem domain

agent_skill_map = {
    "python-expert": [
        "git-workflow",
        "testing-tdd",
        "code-review",
        "debugging"
    ],
    "rust-expert": [
        "git-workflow",
        "testing-tdd",
        "systems-programming"
    ],
    "security-analyst": [
        "code-review",
        "vulnerability-scanning",
        "threat-modeling"
    ]
}
```

---

## 5. MCP Integration in Claude MPM

### 5.1 MCP Tool Discovery

**Location**: `/src/claude_mpm/mcp/`

Claude MPM automatically discovers configured MCP servers:

```python
class MCPIntegration:
    def discover_mcp_servers(self):
        """Scan for configured MCP servers."""
        # Reads from ~/.mcp.json or claude's native config
        servers = [
            {
                "name": "mcp-vector-search",
                "command": "uv run python -m mcp_vector_search.mcp.server",
                "args": ["{PROJECT_ROOT}"],
                "tools": ["search_code", "index_project", "get_status"]
            },
            {
                "name": "google-workspace-mpm",
                "command": "google-workspace-mcp",
                "tools": ["search_gmail", "get_events", "search_drive"]
            }
        ]
        return servers
```

### 5.2 Tool Registration

**MCP tools available to agents** (if configured):

```python
available_mcp_tools = {
    "vector_search": {
        "handler": "mcp-vector-search",
        "operation": "search_code",
        "params": ["query", "limit", "similarity_threshold"]
    },
    "index_project": {
        "handler": "mcp-vector-search",
        "operation": "index_project",
        "params": ["force", "extensions"]
    },
    "gmail_search": {
        "handler": "google-workspace-mpm",
        "operation": "search_gmail_messages",
        "params": ["query", "max_results"]
    }
}
```

### 5.3 Tool Call Flow

```
User requests something (via agent)
│
└─→ Agent routing (PM agent)
    │
    └─→ Specialized agent (e.g., python-expert)
        │
        └─→ Decides to use tool (e.g., "search code for auth patterns")
            │
            └─→ FormatsToolCall → {"tool": "search_code", "args": {...}}
                │
                └─→ Claude MPM calls MCP server
                    │
                    └─→ MCP server (mcp-vector-search) executes
                        │
                        └─→ Returns results
                            │
                            └─→ Agent receives results
                                │
                                └─→ Agent synthesizes response
```

---

## 6. Filesystem Access Mechanisms

### 6.1 Current Implementation (Prompt-Based)

**Problem**: NOT enforced at code level

```python
# From agent AGENT.md (prompt)
"""
## Constraints
- You can only access files within the project directory
- You cannot read files outside ~/
- Do not modify configuration files without permission
"""

# But in code (from tools/code_tree_builder.py):
def build_code_tree(root_path: str):
    # No validation that root_path is within project!
    for file in os.walk(root_path):
        yield file
```

### 6.2 Recommended Enforcement (Infrastructure-Level)

**For Research-Mind sandboxing**:

```python
class SandboxedFilesystem:
    def __init__(self, session_root: Path):
        self.allowed_root = session_root
        self.allowed_root = self.allowed_root.resolve()

    def validate_path(self, requested_path: Path) -> bool:
        """Validate path is within allowed root."""
        requested = Path(requested_path).resolve()

        # Check path is within allowed root
        try:
            requested.relative_to(self.allowed_root)
            return True
        except ValueError:
            # Path is outside allowed root
            return False

    def read_file(self, path: str) -> str:
        if not self.validate_path(path):
            raise PermissionError(f"Access denied: {path}")
        with open(path, 'r') as f:
            return f.read()

    def list_directory(self, path: str) -> List[str]:
        if not self.validate_path(path):
            raise PermissionError(f"Access denied: {path}")
        return os.listdir(path)
```

### 6.3 Tool Call Interception

**Intercept at Claude CLI level**:

```python
# research-mind-service/app/claude_integration.py

class SandboxedClaudeRunner:
    def __init__(self, session_id: str, session_root: Path):
        self.session_id = session_id
        self.session_root = session_root
        self.allowed_paths = {session_root}  # Restrict to session

    def execute_agent_task(self, agent: str, task: str):
        """Execute agent with path restrictions."""
        env = os.environ.copy()
        env['SESSION_DIR'] = str(self.session_root)
        env['SESSION_ID'] = self.session_id

        # Pass environment to claude subprocess
        result = subprocess.run(
            ['claude', 'run', '--agent', agent, task],
            env=env,
            cwd=str(self.session_root),
            capture_output=True
        )

        return result.stdout.decode()
```

---

## 7. Latency & Cost Controls

### 7.1 Session Warm Pools

**Concept**: Keep Claude Code subprocess running between requests

**Current**: Sessions are kept warm if not expired (max_age_minutes: 30 days)

**For Research-Mind**:

```python
class WarmSessionPool:
    def __init__(self, pool_size: int = 3):
        self.pool_size = pool_size
        self.active_sessions = {}  # Keep these running
        self.idle_sessions = []     # Available to reuse

    def get_session(self) -> str:
        """Get warm session or create new."""
        if self.idle_sessions:
            session_id = self.idle_sessions.pop()
            # Session already running, minimal startup cost
        else:
            session_id = self.create_new_session()
        return session_id

    def return_session(self, session_id: str):
        """Return session to warm pool."""
        self.idle_sessions.append(session_id)
```

**Latency impact**:

- Cold start (new session): ~2-3 seconds
- Warm session reuse: <100ms

### 7.2 Token Budgeting

**Conversation token tracking**:

```python
class TokenBudget:
    def __init__(self, max_tokens: int = 100000):
        self.max_tokens = max_tokens
        self.used_tokens = 0

    def can_continue(self, estimated_new_tokens: int) -> bool:
        return (self.used_tokens + estimated_new_tokens) <= self.max_tokens

    def add_tokens(self, count: int):
        self.used_tokens += count

    def get_remaining(self) -> int:
        return self.max_tokens - self.used_tokens

    def is_at_threshold(self, threshold: float = 0.8) -> bool:
        return self.used_tokens >= (self.max_tokens * threshold)
```

**Automated actions at thresholds** (from claude-mpm docs):

- 70% token usage: Start summarization
- 85% token usage: Create resume log
- 95% token usage: Force new session

### 7.3 Caching Strategies

**Not currently implemented** in claude-mpm, but recommended for Research-Mind:

```python
class ResearchCache:
    """Cache research results within a session."""

    def __init__(self, ttl_minutes: int = 60):
        self.cache = {}
        self.ttl_minutes = ttl_minutes

    def cache_search_results(self, query: str, results: List[Dict]):
        """Cache semantic search results."""
        self.cache[query] = {
            "results": results,
            "timestamp": datetime.utcnow(),
            "ttl": self.ttl_minutes
        }

    def get_cached_results(self, query: str) -> Optional[List[Dict]]:
        """Get cached results if not expired."""
        if query not in self.cache:
            return None

        cached = self.cache[query]
        age_minutes = (datetime.utcnow() - cached["timestamp"]).total_seconds() / 60
        if age_minutes > cached["ttl"]:
            del self.cache[query]
            return None

        return cached["results"]
```

---

## 8. Integration Points for Research-Mind

### 8.1 Session Wrapper

**Location**: `research-mind-service/app/claude_integration.py`

```python
class ResearchSessionAgent:
    """Wrapper around Claude MPM for Research-Mind."""

    def __init__(self, session_id: str, session_root: Path):
        self.session_id = session_id
        self.session_root = session_root
        self.token_budget = TokenBudget(max_tokens=100000)

    def ask(self, question: str, mode: str = "comprehensive") -> str:
        """Ask research question with isolated session."""
        # 1. Validate session exists
        # 2. Load or create Claude MPM session
        # 3. Restrict filesystem to session_root
        # 4. Instantiate agent (e.g., "research-analyst")
        # 5. Execute agent task
        # 6. Track tokens
        # 7. Log results

        agent = "research-analyst"  # Custom agent for research

        result = self.execute_agent(
            agent=agent,
            task=question,
            tools=[
                "vector_search",      # From mcp-vector-search
                "read_files",
                "list_directory"
            ]
        )

        self.log_research_query(question, result)
        return result

    def execute_agent(self, agent: str, task: str, tools: List[str]):
        """Execute agent with session scoping."""
        # Call claude-mpm with restricted environment
        env = os.environ.copy()
        env['SESSION_DIR'] = str(self.session_root)
        env['SESSION_ID'] = self.session_id
        env['ALLOWED_PATHS'] = str(self.session_root)

        subprocess.run(
            ['claude-mpm', 'run', '--agent', agent, '--resume', task],
            env=env,
            cwd=str(self.session_root)
        )
```

### 8.2 Agent Customization

**Custom Research Agent** for Research-Mind:

```markdown
# ~/.claude/agents/research-analyst/AGENT.md

## Identity

Name: research-analyst
Role: Research session specialist
Expertise: Analyzing codebases, extracting knowledge, synthesizing findings

## Capabilities

- Read and understand source code in multiple languages
- Identify architectural patterns and design decisions
- Find relationships between code components
- Synthesize findings into coherent explanations
- Ask clarifying questions

## Tools Available

- **File Access**: Read files, list directories (within session only)
- **Vector Search**: Semantic search (mcp-vector-search)
- **Analysis**: Code structure analysis

## Constraints

- Session Scoping: CRITICAL - Only access files in SESSION_DIR
- Network: Disabled (no external API calls)
- Modifications: Read-only mode (no file writes)

## Decision Model

1. Always start with vector search to find relevant code
2. Read full context from source files
3. Identify relationships and patterns
4. Synthesize findings with evidence
5. Provide citations to code locations
6. Ask user before investigating sensitive areas

## Skills

- code-analysis
- documentation
- research-synthesis
```

---

## 9. Key Modules & File Paths

| Module             | Path                                          | Purpose                       |
| ------------------ | --------------------------------------------- | ----------------------------- |
| SessionManager     | `/src/claude_mpm/core/session_manager.py`     | Session lifecycle, resumption |
| InteractiveSession | `/src/claude_mpm/core/interactive_session.py` | Interactive prompt handling   |
| OneShotSession     | `/src/claude_mpm/core/oneshot_session.py`     | One-shot execution            |
| AgentRegistry      | `/src/claude_mpm/core/agent_registry.py`      | Agent discovery, loading      |
| SkillsSystem       | `/src/claude_mpm/skills/`                     | Skills management             |
| ToolCodeTree       | `/src/claude_mpm/tools/code_tree_builder.py`  | File/directory access         |
| MCPIntegration     | `/src/claude_mpm/mcp/`                        | MCP server integration        |

---

## 10. Risks & Unknowns

### 10.1 Sandbox Isolation (CRITICAL)

**Problem**: Current implementation is prompt-based, NOT enforced

```
User tells agent: "Only access files in the project directory"
Agent promises: "I will only access files in the project directory"

But at code level:
- No filesystem restriction
- No path validation
- Agent could (theoretically) access any file
```

**For Research-Mind**: Requires infrastructure-level enforcement:

1. Pass SESSION_DIR as cwd to Claude subprocess
2. Validate all file paths before access
3. Intercept tool calls at wrapper layer
4. Audit all filesystem access

### 10.2 Token Management

**Unknown**: How does claude-mpm handle token overflow in practice?

- ✓ Documented: Summaries at 70%, 85%, 95%
- ✓ Implemented: Resume log system
- ?: How does agent behave when hitting token limit?

### 10.3 Tool Call Atomicity

**Question**: If agent calls vector_search and mcp-vector-search fails, how is error handled?

- Probably: Exception propagated to agent
- Unknown: Retry logic, timeout handling

### 10.4 Session Persistence

**Question**: What happens if Claude Code subprocess crashes during session?

- Session data: Persisted to disk (should survive)
- Conversation state: May be lost if not flushed
- Recommendation: Explicit checkpoint after major operations

---

## 11. Recommended Architecture for Research-Mind

### 11.1 Integration Layer

```python
# research-mind-service/app/claude_integration.py

class ResearchSession:
    """Research-Mind session wrapping Claude MPM."""

    def __init__(self, session_id: str, session_root: Path):
        self.session_id = session_id
        self.session_root = session_root
        self.mpm_session_id = None
        self.agent_name = "research-analyst"

    async def ask_question(self, question: str) -> Dict[str, Any]:
        """Ask research question, get results with citations."""
        # 1. Vector search for relevant code
        search_results = await self.vector_search(question)

        # 2. Pass to agent with context
        agent_input = f"""
        Based on this research context, please answer the question.

        Question: {question}

        Relevant code found:
        {self.format_search_results(search_results)}

        Now synthesize your findings with citations.
        """

        # 3. Execute agent in scoped session
        response = await self.execute_agent(agent_input)

        # 4. Parse citations and track for auditability
        findings = self.parse_findings_with_citations(response)

        # 5. Log and cache
        await self.log_research_query(question, findings)

        return findings

    async def vector_search(self, query: str) -> List[Dict]:
        """Search mcp-vector-search for relevant code."""
        # Call vector_search REST API (from previous proposal)
        return await self.vector_search_client.search(
            session_id=self.session_id,
            query=query,
            limit=10
        )

    async def execute_agent(self, task: str) -> str:
        """Execute agent with scoped filesystem access."""
        env = os.environ.copy()
        env['SESSION_DIR'] = str(self.session_root)
        env['SESSION_ID'] = self.session_id
        env['ALLOWED_PATHS'] = str(self.session_root)

        result = subprocess.run(
            ['claude-mpm', 'run', '--agent', self.agent_name, task],
            env=env,
            cwd=str(self.session_root),
            capture_output=True
        )

        return result.stdout.decode()
```

### 11.2 Sandbox Enforcement

```python
# research-mind-service/app/sandbox/filesystem_guard.py

class FilesystemGuard:
    """Enforce session-scoped filesystem access."""

    def __init__(self, allowed_root: Path):
        self.allowed_root = allowed_root.resolve()

    def validate_access(self, requested_path: Path) -> bool:
        requested = Path(requested_path).resolve()
        try:
            # Succeeds only if requested is within allowed_root
            requested.relative_to(self.allowed_root)
            return True
        except ValueError:
            return False

    def safe_read(self, path: str) -> str:
        if not self.validate_access(path):
            raise PermissionError(f"Access denied: {path}")
        with open(path, 'r') as f:
            return f.read()
```

---

## 12. Summary

| Aspect            | Details                                                                  |
| ----------------- | ------------------------------------------------------------------------ |
| **How to run**    | `claude-mpm run` or interactive mode                                     |
| **Sessions**      | UUID-based, 30-day resumption window by default                          |
| **Tools**         | Filesystem, git, execution, analysis, MCP integration                    |
| **Agents**        | 47+ deployed, skills-based, customizable                                 |
| **Sandbox**       | **Prompt-based (NOT enforced)** - requires infrastructure-level controls |
| **Filesystem**    | No code-level restriction - requires wrapper validation                  |
| **Caching**       | Not implemented - recommended for Research-Mind                          |
| **Token control** | Automatic summaries at thresholds (70%, 85%, 95%)                        |
| **Audit logging** | Not built-in - required for Research-Mind                                |

---

## References

### Code Locations

- Session manager: `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/core/session_manager.py`
- Agents: `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/agents/`
- Skills: `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/skills/`
- MCP integration: `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/mcp/`
- Tools: `/Users/mac/workspace/research-mind/claude-mpm/src/claude_mpm/tools/`

### Documentation

- README: `/Users/mac/workspace/research-mind/claude-mpm/README.md`
- Getting Started: `/Users/mac/workspace/research-mind/claude-mpm/docs/getting-started/`
- Developer Guide: `/Users/mac/workspace/research-mind/claude-mpm/docs/developer/`
