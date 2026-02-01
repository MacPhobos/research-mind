# Phase 1.5: Minimal Audit Logging

**Subphase**: 1.5 of 8 (Phase 1)
**Duration**: 2-3 business days
**Effort**: 16-24 hours
**Team Size**: 1 FTE engineer
**Prerequisite**: Phase 1.2 (sessions), Phase 1.3 (search)
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
    action = Column(String(50), nullable=False)  # search, index_start, index_complete, session_create, failed_request
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

## Integration Points

Audit logging integrates with:

- **Phase 1.3**: Log every search operation
- **Phase 1.3**: Log every indexing job
- **Phase 1.2**: Log session creation/deletion
- **Phase 1.4**: Log blocked path traversal attempts
- **Phase 1.6**: Log agent invocations

---

## Acceptance Criteria

- [ ] AuditLog model created
- [ ] AuditService implements all logging methods
- [ ] Database migration applies successfully
- [ ] Searches logged with query and result count
- [ ] Indexing jobs logged
- [ ] Failed attempts logged
- [ ] Audit logs queryable by session_id
- [ ] <5ms performance overhead per operation

---

## Summary

**Phase 1.5** delivers minimal but comprehensive audit trail for:

- Accountability (what was searched, indexed)
- Security (failed attempts, path traversal blocks)
- Debugging (latency measurements, error tracking)

This foundation enables Phase 2 analysis and Phase 4 compliance requirements.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Parent**: 01-PHASE_1_FOUNDATION.md
