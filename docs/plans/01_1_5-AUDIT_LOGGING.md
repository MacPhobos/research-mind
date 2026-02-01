# Phase 1.5: Minimal Audit Logging

**Subphase**: 1.5 of 8 (Phase 1)
**Duration**: 2-3 business days
**Effort**: 16-24 hours
**Team Size**: 1 FTE engineer
**Prerequisite**: Phase 1.2 (sessions), Phase 1.3 (indexing operations)
**Can Parallel With**: 1.6
**Status**: IMPORTANT - Security and accountability

---

## Subphase Objective

Implement audit trail for all session operations and searches. Capture what happened, when, and by which session for forensics and accountability.

**Success Definition**:

- All search queries logged with results count and latency
- All indexing jobs logged (start, progress, completion)
- Session creation/deletion logged
- Failed attempts (path traversal, invalid sessions) logged as warnings
- Audit logs queryable by session_id
- Minimal performance overhead (<5ms per operation)

---

## Deliverables

1. **research-mind-service/app/models/audit_log.py** (new)

   - AuditLog SQLAlchemy model
   - Fields: timestamp, session_id, action, query, result_count, duration_ms, status, error

2. **research-mind-service/app/services/audit_service.py** (new)

   - AuditService for logging operations
   - Methods: log_search, log_index, log_session_create, log_failed_request

3. **Database migration** (new)
   - Alembic migration for audit_logs table
   - Index on session_id and timestamp for fast queries

---

## Detailed Implementation

### Create app/models/audit_log.py

```python
"""Audit logging for all operations."""

from datetime import datetime
from sqlalchemy import Column, String, DateTime, Integer, JSON, Index
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()


class AuditLog(Base):
    """Audit trail for all operations."""

    __tablename__ = "audit_logs"
    __table_args__ = (
        Index("idx_audit_session_id", "session_id"),
        Index("idx_audit_timestamp", "timestamp"),
    )

    id = Column(Integer, primary_key=True)
    timestamp = Column(DateTime, nullable=False, default=datetime.utcnow)
    session_id = Column(String(36), nullable=False)
    action = Column(String(50), nullable=False)  # subprocess_spawn, subprocess_complete, subprocess_error, index_start, index_complete, session_create, failed_request
    query = Column(String(2048), nullable=True)  # For search operations
    result_count = Column(Integer, nullable=True)
    duration_ms = Column(Integer, nullable=True)  # Operation duration
    status = Column(String(50), nullable=False, default="success")  # success, failed
    error = Column(String(2048), nullable=True)
    metadata = Column(JSON, nullable=True)  # Additional data


class AuditService:
    """Audit logging service."""

    @staticmethod
    def log_search(db, session_id: str, query: str, result_count: int, duration_ms: int):
        """Log search operation."""
        log = AuditLog(
            session_id=session_id,
            action="search",
            query=query,
            result_count=result_count,
            duration_ms=duration_ms,
            status="success",
        )
        db.add(log)
        db.commit()

    @staticmethod
    def log_index_start(db, session_id: str, directory_path: str):
        """Log indexing job start."""
        log = AuditLog(
            session_id=session_id,
            action="index_start",
            metadata={"directory_path": directory_path},
        )
        db.add(log)
        db.commit()

    @staticmethod
    def log_index_complete(db, session_id: str, file_count: int, chunk_count: int, duration_ms: int):
        """Log indexing job completion."""
        log = AuditLog(
            session_id=session_id,
            action="index_complete",
            result_count=chunk_count,
            duration_ms=duration_ms,
            metadata={"file_count": file_count},
        )
        db.add(log)
        db.commit()

    @staticmethod
    def log_failed_request(db, session_id: str, action: str, error: str):
        """Log failed request (blocked path, invalid session, etc.)."""
        log = AuditLog(
            session_id=session_id,
            action=action,
            status="failed",
            error=error,
        )
        db.add(log)
        db.commit()
```

---

## Subprocess Audit Events

The subprocess-based mcp-vector-search integration requires specific audit logging for subprocess lifecycle events. Every subprocess invocation MUST be logged for security accountability and debugging.

### Event Types

| Event Type          | Action                | When Logged                          | Key Fields                            |
| ------------------- | --------------------- | ------------------------------------ | ------------------------------------- |
| Subprocess Spawn    | `subprocess_spawn`    | When `subprocess.run()` is called    | command, workspace_path, timestamp    |
| Subprocess Complete | `subprocess_complete` | When subprocess exits with code 0    | exit_code, elapsed_ms, stdout summary |
| Subprocess Error    | `subprocess_error`    | When subprocess exits with code != 0 | exit_code, elapsed_ms, stderr summary |
| Subprocess Timeout  | `subprocess_timeout`  | When subprocess exceeds timeout      | timeout_seconds, workspace_path       |

### Log Format Examples

```python
# Subprocess spawn
AuditService.log_subprocess_spawn(
    db, session_id=session_id,
    command="mcp-vector-search init --force",
    workspace_path="/path/to/workspace"
)

# Subprocess completion
AuditService.log_subprocess_complete(
    db, session_id=session_id,
    command="mcp-vector-search index --force",
    exit_code=0,
    elapsed_ms=3890,
    stdout_summary="Indexed 42 files"
)

# Subprocess error
AuditService.log_subprocess_error(
    db, session_id=session_id,
    command="mcp-vector-search index --force",
    exit_code=1,
    elapsed_ms=150,
    stderr_summary="Error: Permission denied: /path/to/workspace/.mcp-vector-search"
)

# Subprocess timeout
AuditService.log_subprocess_timeout(
    db, session_id=session_id,
    command="mcp-vector-search index --force",
    timeout_seconds=60,
    workspace_path="/path/to/workspace"
)
```

### AuditService Subprocess Methods

```python
class AuditService:
    # ... existing methods ...

    @staticmethod
    def log_subprocess_spawn(db, session_id: str, command: str, workspace_path: str):
        """Log when mcp-vector-search subprocess is spawned."""
        log = AuditLog(
            session_id=session_id,
            action="subprocess_spawn",
            metadata={"command": command, "workspace_path": workspace_path},
        )
        db.add(log)
        db.commit()

    @staticmethod
    def log_subprocess_complete(db, session_id: str, command: str, exit_code: int, elapsed_ms: int, stdout_summary: str = ""):
        """Log subprocess successful completion."""
        log = AuditLog(
            session_id=session_id,
            action="subprocess_complete",
            duration_ms=elapsed_ms,
            status="success",
            metadata={"command": command, "exit_code": exit_code, "stdout_summary": stdout_summary[:500]},
        )
        db.add(log)
        db.commit()

    @staticmethod
    def log_subprocess_error(db, session_id: str, command: str, exit_code: int, elapsed_ms: int, stderr_summary: str = ""):
        """Log subprocess failure (exit code != 0)."""
        log = AuditLog(
            session_id=session_id,
            action="subprocess_error",
            duration_ms=elapsed_ms,
            status="failed",
            error=stderr_summary[:500],
            metadata={"command": command, "exit_code": exit_code},
        )
        db.add(log)
        db.commit()

    @staticmethod
    def log_subprocess_timeout(db, session_id: str, command: str, timeout_seconds: int, workspace_path: str):
        """Log subprocess timeout."""
        log = AuditLog(
            session_id=session_id,
            action="subprocess_timeout",
            status="failed",
            error=f"Subprocess timed out after {timeout_seconds}s",
            metadata={"command": command, "timeout_seconds": timeout_seconds, "workspace_path": workspace_path},
        )
        db.add(log)
        db.commit()
```

---

## Integration Points

Audit logging integrates with:

- **Phase 1.3 (Indexing Operations)**: Log every subprocess spawn, completion, and error for indexing
- **Phase 1.2**: Log session creation/deletion
- **Phase 1.4**: Log blocked path traversal attempts (including invalid workspace paths before subprocess invocation)
- **Phase 1.6**: Log agent invocations (deferred to Phase 2)

---

## Acceptance Criteria

- [ ] AuditLog model created
- [ ] AuditService implements all logging methods (including subprocess audit methods)
- [ ] Database migration applies successfully
- [ ] Subprocess spawns logged with command and workspace path
- [ ] Subprocess completions logged with exit code and elapsed time
- [ ] Subprocess errors logged with stderr summary
- [ ] Subprocess timeouts logged
- [ ] Indexing jobs logged (start, completion)
- [ ] Failed attempts logged
- [ ] Audit logs queryable by session_id
- [ ] <5ms performance overhead per operation

---

## Summary

**Phase 1.5** delivers minimal but comprehensive audit trail for:

- Accountability (what was indexed, which subprocesses were spawned)
- Security (failed attempts, path traversal blocks, subprocess errors)
- Debugging (subprocess exit codes, elapsed times, stderr capture)
- Subprocess lifecycle tracking (spawn, complete, error, timeout)

This foundation enables Phase 2 analysis and Phase 4 compliance requirements.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Parent**: 01-PHASE_1_FOUNDATION.md
