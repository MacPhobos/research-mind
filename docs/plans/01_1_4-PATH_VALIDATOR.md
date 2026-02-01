# Phase 1.4: Path Validator (Sandbox Layer 1)

**Subphase**: 1.4 of 8 (Phase 1)
**Duration**: 2-3 business days
**Effort**: 16-24 hours
**Team Size**: 1 FTE engineer
**Prerequisite**: Phase 1.1 (FastAPI), Phase 1.0 (sandbox directory)
**Blocking**: 1.7 (security tests)
**Can Parallel With**: 1.2, 1.3
**Status**: CRITICAL SECURITY - Prevents data exfiltration

---

## Subphase Objective

Implement infrastructure-level path validation preventing directory traversal and unauthorized access. This is the first layer of defense protecting session isolation and preventing agents from escaping sandbox constraints.

**Success Definition**:

- All path traversal attempts blocked (100% detection rate)
- Hidden files/directories blocked (dotfiles, .ssh, .env, etc.)
- System paths blocked (/etc, /root, /home/_/._)
- Session ID validation on every request
- Audit logging of all blocked attempts

---

## Timeline & Effort

### Day 1: Path Validation Logic (8 hours)

- Implement PathValidator class
- Validate path allowlist
- Test common attack patterns

### Day 2-3: Middleware Integration & Testing (8-16 hours)

- FastAPI middleware integration
- Session ID validation on all routes
- Comprehensive security fuzzing tests

---

## Deliverables

1. **research-mind-service/app/sandbox/path_validator.py** (100-150 lines)

   - PathValidator class with validation logic
   - safe_read, safe_list_dir, validate_path methods
   - Logging of blocked attempts

2. **research-mind-service/app/middleware/session_validation.py** (60-80 lines)
   - FastAPI middleware for session_id validation
   - Enforces validation on every request
   - Integrates with audit logging

---

## Detailed Tasks

### Task 1.4.1: Implement PathValidator (8-10 hours)

Create **app/sandbox/path_validator.py**:

```python
"""
Infrastructure-level path validation for session isolation.

Prevents:
- Directory traversal attacks (../, symlinks)
- Access to hidden files (.env, .ssh, etc.)
- Access to system paths (/etc, /root, /var, etc.)
- Access outside session workspace

This is the FIRST line of defense against agent escape attempts.
"""

import logging
from pathlib import Path
from typing import List, Optional
import os

logger = logging.getLogger(__name__)


class PathValidator:
    """Validates file access requests for session isolation."""

    # Blocked hidden directories and files
    BLOCKED_PATTERNS = {
        ".*",  # Any dotfile (.env, .ssh, etc.)
        "__pycache__",
        ".git",
        ".env",
        ".env.*",
        ".ssh",
        ".aws",
        ".kube",
        "credentials.json",
        "secret*",
    }

    # Blocked system paths
    BLOCKED_PATHS = {
        "/etc",
        "/root",
        "/home",
        "/var",
        "/sys",
        "/proc",
        "/dev",
        "/usr/bin",
        "/usr/sbin",
        "/bin",
        "/sbin",
    }

    def __init__(self, session_workspace: Path):
        """
        Initialize path validator for a session.

        Args:
            session_workspace: Session's root workspace directory
        """
        self.session_workspace = Path(session_workspace).resolve()
        logger.info(f"PathValidator initialized for: {self.session_workspace}")

    def validate_path(self, requested_path: str) -> bool:
        """
        Validate that a path is safe and within session workspace.

        Args:
            requested_path: Path to validate

        Returns:
            True if safe, False if blocked

        Raises:
            ValueError: If path traversal attempt detected
        """
        try:
            requested = Path(requested_path).resolve()
        except (ValueError, OSError) as e:
            logger.warning(f"Invalid path syntax: {requested_path}: {e}")
            return False

        # Check 1: Path must be within session workspace
        try:
            requested.relative_to(self.session_workspace)
        except ValueError:
            logger.warning(f"✗ Path outside session workspace: {requested_path}")
            return False

        # Check 2: Block hidden files and directories
        for part in requested.parts:
            if part.startswith("."):
                logger.warning(f"✗ Hidden file blocked: {requested_path}")
                return False

        # Check 3: Block system paths
        path_str = str(requested)
        for blocked in self.BLOCKED_PATHS:
            if path_str.startswith(blocked):
                logger.warning(f"✗ System path blocked: {requested_path}")
                return False

        # Check 4: No symlinks (prevent escape via symlink)
        if requested.is_symlink():
            logger.warning(f"✗ Symlink blocked: {requested_path}")
            return False

        logger.info(f"✓ Path validated: {requested_path}")
        return True

    def safe_read(self, path: str) -> str:
        """
        Safely read file content with validation.

        Args:
            path: File path to read

        Returns:
            File content

        Raises:
            PermissionError: If path validation fails
            FileNotFoundError: If file doesn't exist
        """
        if not self.validate_path(path):
            raise PermissionError(f"Access denied: {path}")

        with open(path, "r") as f:
            return f.read()

    def safe_list_dir(self, path: str) -> List[str]:
        """
        Safely list directory contents with validation.

        Args:
            path: Directory path

        Returns:
            List of filenames (excluding hidden files)

        Raises:
            PermissionError: If path validation fails
        """
        if not self.validate_path(path):
            raise PermissionError(f"Access denied: {path}")

        dir_path = Path(path)
        if not dir_path.is_dir():
            raise NotADirectoryError(f"Not a directory: {path}")

        # Return only visible (non-hidden) entries
        return [
            f.name
            for f in dir_path.iterdir()
            if not f.name.startswith(".")
        ]
```

### Task 1.4.2: Create Session Validation Middleware (6-8 hours)

Create **app/middleware/session_validation.py**:

```python
"""
FastAPI middleware for session validation on every request.

Ensures every request to /api/sessions/{session_id}/* endpoints
has a valid session that exists in the database.
"""

import logging
from fastapi import Request, HTTPException, status
from starlette.middleware.base import BaseHTTPMiddleware
from sqlalchemy.orm import Session as DBSession

from app.models.session import Session

logger = logging.getLogger(__name__)


class SessionValidationMiddleware(BaseHTTPMiddleware):
    """Validates session_id on every request to session endpoints."""

    PROTECTED_PATHS = ["/api/sessions/"]

    async def dispatch(self, request: Request, call_next):
        """Validate session before processing request."""

        # Check if this is a protected endpoint
        if not any(request.url.path.startswith(p) for p in self.PROTECTED_PATHS):
            return await call_next(request)

        # Extract session_id from path: /api/sessions/{session_id}/...
        path_parts = request.url.path.strip("/").split("/")
        if len(path_parts) < 3:
            return await call_next(request)

        session_id = path_parts[2]

        # Validate session_id format (UUID)
        if not self._is_valid_uuid(session_id):
            logger.warning(f"✗ Invalid session_id format: {session_id}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid session_id format",
            )

        # Verify session exists in database
        # Note: This requires db dependency injection
        # (Implementation depends on how DB session is managed)

        logger.info(f"✓ Session {session_id} validated")
        return await call_next(request)

    @staticmethod
    def _is_valid_uuid(val: str) -> bool:
        """Check if string is valid UUID v4."""
        import uuid
        try:
            uuid.UUID(val, version=4)
            return True
        except ValueError:
            return False
```

### Task 1.4.3: Security Testing - Path Traversal Fuzzing (4-6 hours)

Create **tests/test_security_path_traversal.py**:

```python
"""
Security tests for path traversal prevention.
"""

import pytest
from app.sandbox.path_validator import PathValidator
from pathlib import Path


@pytest.fixture
def validator():
    """Create validator for test session."""
    workspace = Path("/tmp/test_session")
    workspace.mkdir(exist_ok=True)
    return PathValidator(workspace)


class TestPathTraversalAttacks:
    """Test prevention of common path traversal attacks."""

    def test_parent_directory_blocked(self, validator):
        """../../../etc/passwd should be blocked."""
        assert not validator.validate_path("../../../etc/passwd")
        assert not validator.validate_path("content/../../etc/passwd")

    def test_dotfile_blocked(self, validator):
        """.env and other dotfiles should be blocked."""
        assert not validator.validate_path(".env")
        assert not validator.validate_path(".ssh/id_rsa")
        assert not validator.validate_path("content/.env.local")

    def test_system_path_blocked(self, validator):
        """/etc, /root, etc. should be blocked."""
        assert not validator.validate_path("/etc/passwd")
        assert not validator.validate_path("/root/.ssh")

    def test_valid_path_allowed(self, validator):
        """Valid paths within workspace should be allowed."""
        (validator.session_workspace / "content").mkdir(exist_ok=True)
        (validator.session_workspace / "content" / "test.py").touch()
        assert validator.validate_path("content/test.py")

    def test_symlink_blocked(self, validator):
        """Symlinks should be blocked."""
        # Create symlink pointing outside
        (validator.session_workspace / "link").symlink_to("/etc")
        assert not validator.validate_path("link")
```

---

## Research References

**docs/research/claude-ppm-sandbox-containment-plan.md** (Section 2)

- Detailed path validator design and threat model
- Code examples for implementation
- Security testing recommendations

**docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md** (Section 5)

- Sandbox directory setup for path validator

---

## Acceptance Criteria

- [ ] PathValidator class implemented
- [ ] Path traversal attempts blocked (100% detection)
- [ ] Hidden files blocked
- [ ] System paths blocked
- [ ] Session validation middleware working
- [ ] All security tests passing
- [ ] Fuzzing tests with 20+ attack patterns

---

## Summary

**Phase 1.4** delivers:

- Infrastructure-level path validation
- Middleware for session validation on every request
- Comprehensive security testing
- Foundation for Phase 1.6 agent isolation

This is CRITICAL for preventing data exfiltration and cross-session contamination.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Parent**: 01-PHASE_1_FOUNDATION.md
