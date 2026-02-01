# Phase 1.3: Indexing Operations (Subprocess Orchestration)

**Subphase**: 1.3 of 8 (Phase 1)
**Duration**: 3-4 business days
**Effort**: 24-32 hours
**Team Size**: 1-2 FTE engineers
**Prerequisite**: Phase 1.1 (FastAPI + WorkspaceIndexer), Phase 1.0 (mcp-vector-search CLI installed)
**Blocking**: 1.7, 1.8
**Can Parallel With**: 1.2, 1.4
**Status**: CRITICAL - Core workspace indexing functionality

> **ARCHITECTURE NOTE (v2.0)**: This document reflects the subprocess-based architecture.
> mcp-vector-search runs as a CLI subprocess, NOT as an embedded Python library.
> Search functionality is COMPLETELY DEFERRED to a future phase (will use Claude Code MCP interface).
> This phase focuses exclusively on workspace indexing operations.
> See `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0) for details.

> **RENAMED**: This file was previously `01_1_3-VECTOR_SEARCH_API.md`. Renamed to
> reflect the subprocess-based indexing focus. Search is deferred to a future phase.

---

## Subphase Objective

Create REST API endpoints for workspace indexing operations using mcp-vector-search subprocess. Implement workspace registration and indexing trigger endpoints that orchestrate the two-step init + index subprocess flow.

**Success Definition**: Users can:

- Trigger workspace indexing with POST /api/v1/workspaces/{id}/index
- Check indexing status with GET /api/v1/workspaces/{id}/index/status
- Index artifacts created in workspace `.mcp-vector-search/` directory
- Multiple workspaces can be indexed independently
- Proper error handling for subprocess failures and timeouts

**Explicitly Out of Scope (Deferred to future phase)**:

- Search endpoints (POST /search) - will use Claude Code MCP interface
- Per-session ChromaDB collection management
- Search result formatting and pagination
- Agent-driven search queries

---

## Timeline & Effort

### Day 1-2: Indexing API Endpoints (12-16 hours)

- POST /api/v1/workspaces/{id}/index endpoint
- GET /api/v1/workspaces/{id}/index/status endpoint
- Subprocess orchestration with WorkspaceIndexer
- Error handling for exit codes and timeouts

### Day 3-4: Background Indexing & Testing (12-16 hours)

- Background task execution for long-running indexes
- Job status tracking
- Integration tests with real mcp-vector-search subprocess
- Multi-workspace isolation verification

---

## Deliverables

1. **research-mind-service/app/routes/indexing.py** (150-200 lines)

   - Indexing endpoints (trigger, check status)
   - Error handling for subprocess failures

2. **research-mind-service/app/schemas/indexing.py** (100-150 lines)

   - Pydantic models for indexing requests/responses
   - IndexRequest, IndexStatusResponse

3. **research-mind-service/app/services/indexing_service.py** (150-200 lines)

   - Indexing orchestration using WorkspaceIndexer
   - Background task management
   - Status tracking

4. **research-mind-service/tests/test_indexing.py** (new)
   - Tests for subprocess invocation and error cases

---

## Detailed Tasks

### Task 1.3.1: Create Indexing Schemas (3-4 hours)

**Objective**: Pydantic request/response models for indexing endpoints

#### Steps

1. **Create app/schemas/indexing.py**

```python
"""
Pydantic schemas for workspace indexing operations.

NOTE: Search schemas are deferred to a future phase.
This module covers indexing operations only.
"""

from pydantic import BaseModel, Field
from typing import Optional


class IndexWorkspaceRequest(BaseModel):
    """Request to trigger workspace indexing."""

    force: bool = Field(
        True,
        description="Force full reindex (recommended for first-time indexing)"
    )
    timeout: Optional[int] = Field(
        None,
        ge=10,
        le=600,
        description="Custom timeout in seconds (default: auto-selected based on project size)"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "force": True,
                "timeout": 60,
            }
        }


class IndexStatusResponse(BaseModel):
    """Response for workspace index status."""

    workspace_id: str = Field(..., description="Workspace/session identifier")
    is_indexed: bool = Field(
        ...,
        description="Whether .mcp-vector-search/ directory exists in workspace"
    )
    status: str = Field(
        ...,
        description="Index status: not_initialized, indexed, indexing, failed"
    )
    message: Optional[str] = Field(None, description="Additional status message")

    class Config:
        json_schema_extra = {
            "example": {
                "workspace_id": "550e8400-e29b-41d4-a716-446655440000",
                "is_indexed": True,
                "status": "indexed",
                "message": "Workspace indexed successfully in 3.9s",
            }
        }


class IndexResultResponse(BaseModel):
    """Response after triggering indexing."""

    workspace_id: str = Field(..., description="Workspace/session identifier")
    success: bool = Field(..., description="Whether indexing completed successfully")
    status: str = Field(..., description="Result status: success, failed, timeout")
    elapsed_seconds: float = Field(..., description="Time taken for indexing")
    stdout: Optional[str] = Field(None, description="Subprocess stdout (truncated)")
    stderr: Optional[str] = Field(None, description="Subprocess stderr (on failure)")

    class Config:
        json_schema_extra = {
            "example": {
                "workspace_id": "550e8400-e29b-41d4-a716-446655440000",
                "success": True,
                "status": "success",
                "elapsed_seconds": 3.89,
                "stdout": "Indexed 42 files",
                "stderr": None,
            }
        }
```

---

### Task 1.3.2: Create Indexing Service (6-8 hours)

**Objective**: Business logic for indexing operations using WorkspaceIndexer subprocess

#### Steps

1. **Create app/services/indexing_service.py**

```python
"""
Indexing service using mcp-vector-search subprocess.

Orchestrates the two-step init + index flow via WorkspaceIndexer.
Does NOT embed mcp-vector-search as a library.

Architecture:
  API Request → IndexingService → WorkspaceIndexer → subprocess.run()
    → mcp-vector-search init --force (cwd=workspace_dir)
    → mcp-vector-search index --force (cwd=workspace_dir)
    → Exit code 0 = success, 1 = failure
"""

import logging
from pathlib import Path
from typing import Optional

from app.core.workspace_indexer import WorkspaceIndexer, IndexingResult
from app.core.config import settings

logger = logging.getLogger(__name__)


class IndexingService:
    """Orchestrates workspace indexing via subprocess."""

    @staticmethod
    def index_workspace(
        workspace_path: str,
        force: bool = True,
        timeout: Optional[int] = None,
    ) -> IndexingResult:
        """
        Index a workspace using mcp-vector-search subprocess.

        Performs two-step flow:
        1. mcp-vector-search init --force (initialize workspace)
        2. mcp-vector-search index --force (index source files)

        Args:
            workspace_path: Path to workspace directory
            force: Force full reindex (default True)
            timeout: Custom timeout for index step (default: from settings)

        Returns:
            IndexingResult with success/failure and output

        Raises:
            ValueError: If workspace directory does not exist
        """
        workspace_dir = Path(workspace_path)

        if not workspace_dir.is_dir():
            raise ValueError(f"Workspace directory not found: {workspace_dir}")

        index_timeout = timeout or settings.indexing_index_timeout

        indexer = WorkspaceIndexer(workspace_dir)

        # Step 1: Initialize (creates .mcp-vector-search/ directory)
        logger.info(f"Initializing workspace: {workspace_dir}")
        init_result = indexer.initialize(timeout=settings.indexing_init_timeout)

        if not init_result.success:
            logger.error(f"Init failed: {init_result.stderr}")
            return init_result

        # Step 2: Index source files
        logger.info(f"Indexing workspace: {workspace_dir} (timeout={index_timeout}s)")
        index_result = indexer.index(timeout=index_timeout, force=force)

        if index_result.success:
            logger.info(
                f"Indexed workspace: {workspace_dir} "
                f"in {index_result.elapsed_seconds:.1f}s"
            )
        else:
            logger.error(f"Indexing failed: {index_result.stderr}")

        return index_result

    @staticmethod
    def check_index_status(workspace_path: str) -> dict:
        """
        Check if a workspace has been indexed.

        Determines status by checking for .mcp-vector-search/ directory
        in the workspace. This is the subprocess-based approach where
        index artifacts are managed by the CLI tool.

        Args:
            workspace_path: Path to workspace directory

        Returns:
            Dict with is_indexed, status, and message
        """
        workspace_dir = Path(workspace_path)

        if not workspace_dir.is_dir():
            return {
                "is_indexed": False,
                "status": "workspace_not_found",
                "message": f"Workspace directory not found: {workspace_dir}",
            }

        index_dir = workspace_dir / ".mcp-vector-search"

        if index_dir.is_dir():
            return {
                "is_indexed": True,
                "status": "indexed",
                "message": "Workspace has been indexed (.mcp-vector-search/ exists)",
            }
        else:
            return {
                "is_indexed": False,
                "status": "not_initialized",
                "message": "Workspace has not been indexed yet",
            }

    @staticmethod
    def check_index_health(workspace_path: str) -> dict:
        """
        Check index health via mcp-vector-search subprocess.

        Args:
            workspace_path: Path to workspace directory

        Returns:
            Dict with health status
        """
        workspace_dir = Path(workspace_path)

        if not workspace_dir.is_dir():
            return {"healthy": False, "error": "Workspace not found"}

        try:
            indexer = WorkspaceIndexer(workspace_dir)
            result = indexer.check_health(timeout=10)

            return {
                "healthy": result.success,
                "stdout": result.stdout,
                "stderr": result.stderr if not result.success else None,
            }
        except Exception as e:
            return {"healthy": False, "error": str(e)}
```

---

### Task 1.3.3: Create Indexing Routes (6-8 hours)

**Objective**: REST endpoints for workspace indexing operations

#### Steps

1. **Create app/routes/indexing.py**

```python
"""
Workspace indexing REST endpoints.

Provides:
- Trigger indexing (POST /api/v1/workspaces/{id}/index)
- Check index status (GET /api/v1/workspaces/{id}/index/status)

NOTE: Search endpoints are DEFERRED to a future phase.
Search will use Claude Code's MCP interface to mcp-vector-search.
"""

import logging
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session as DBSession

from app.schemas.indexing import (
    IndexWorkspaceRequest,
    IndexStatusResponse,
    IndexResultResponse,
)
from app.services.indexing_service import IndexingService
from app.services.session_service import SessionService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/workspaces", tags=["indexing"])


@router.post("/{workspace_id}/index", response_model=IndexResultResponse)
async def index_workspace(
    workspace_id: str,
    request: IndexWorkspaceRequest = IndexWorkspaceRequest(),
    db: DBSession = Depends(get_db),
):
    """
    Trigger indexing for a workspace via mcp-vector-search subprocess.

    Performs two-step subprocess flow:
    1. `mcp-vector-search init --force` (initialize workspace)
    2. `mcp-vector-search index --force` (index source files)

    **Path Parameters**:
    - `workspace_id`: Session/workspace identifier

    **Request Body** (optional):
    - `force`: Force full reindex (default: true)
    - `timeout`: Custom timeout in seconds (default: auto)

    **Returns**: Indexing result with success/failure status

    **Status Codes**:
    - 200: Indexing completed (check success field)
    - 404: Workspace/session not found
    - 500: Unexpected server error
    """
    # Verify session exists
    session = SessionService.get_session(db, workspace_id)
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Workspace {workspace_id} not found",
        )

    try:
        result = IndexingService.index_workspace(
            workspace_path=session.workspace_path,
            force=request.force,
            timeout=request.timeout,
        )

        return IndexResultResponse(
            workspace_id=workspace_id,
            success=result.success,
            status="success" if result.success else "failed",
            elapsed_seconds=result.elapsed_seconds,
            stdout=result.stdout[:500] if result.stdout else None,  # Truncate
            stderr=result.stderr[:500] if not result.success and result.stderr else None,
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    except Exception as e:
        logger.error(f"Indexing failed unexpectedly: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Indexing failed unexpectedly",
        )


@router.get("/{workspace_id}/index/status", response_model=IndexStatusResponse)
async def get_index_status(
    workspace_id: str,
    db: DBSession = Depends(get_db),
):
    """
    Check if a workspace has been indexed.

    Determines status by checking if `.mcp-vector-search/` directory
    exists in the workspace directory.

    **Path Parameters**:
    - `workspace_id`: Session/workspace identifier

    **Returns**: Index status with is_indexed boolean

    **Status Codes**:
    - 200: Status retrieved
    - 404: Workspace/session not found
    """
    session = SessionService.get_session(db, workspace_id)
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Workspace {workspace_id} not found",
        )

    status_info = IndexingService.check_index_status(session.workspace_path)

    return IndexStatusResponse(
        workspace_id=workspace_id,
        **status_info,
    )
```

2. **Register routes in app/main.py**
   ```python
   from app.routes.indexing import router as indexing_router
   app.include_router(indexing_router)
   ```

---

### Task 1.3.4: Testing & Verification (6-8 hours)

**Objective**: Verify subprocess invocation and error handling

#### Steps

1. **Create tests/test_indexing.py**

```python
"""
Tests for workspace indexing operations.

Tests subprocess invocation, exit code handling,
timeout management, and multi-workspace isolation.
"""

import pytest
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

from app.services.indexing_service import IndexingService
from app.core.workspace_indexer import WorkspaceIndexer, IndexingResult


def test_index_status_not_initialized():
    """Test status check for uninitialized workspace."""
    with tempfile.TemporaryDirectory() as tmpdir:
        status = IndexingService.check_index_status(tmpdir)
        assert status["is_indexed"] is False
        assert status["status"] == "not_initialized"


def test_index_status_initialized():
    """Test status check for initialized workspace."""
    with tempfile.TemporaryDirectory() as tmpdir:
        # Simulate mcp-vector-search init
        (Path(tmpdir) / ".mcp-vector-search").mkdir()

        status = IndexingService.check_index_status(tmpdir)
        assert status["is_indexed"] is True
        assert status["status"] == "indexed"


def test_index_status_workspace_not_found():
    """Test status check for missing workspace."""
    status = IndexingService.check_index_status("/nonexistent/path")
    assert status["is_indexed"] is False
    assert status["status"] == "workspace_not_found"


@patch("app.core.workspace_indexer.subprocess.run")
def test_index_workspace_success(mock_run):
    """Test successful workspace indexing."""
    mock_run.return_value = MagicMock(returncode=0, stdout="OK", stderr="")

    with tempfile.TemporaryDirectory() as tmpdir:
        result = IndexingService.index_workspace(tmpdir)
        assert result.success is True
        # Should be called twice: init + index
        assert mock_run.call_count == 2


@patch("app.core.workspace_indexer.subprocess.run")
def test_index_workspace_init_failure(mock_run):
    """Test handling of init subprocess failure."""
    mock_run.return_value = MagicMock(
        returncode=1, stdout="", stderr="Permission denied"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        result = IndexingService.index_workspace(tmpdir)
        assert result.success is False
        assert "Permission denied" in result.stderr
        # Only init should be called (index skipped on failure)
        assert mock_run.call_count == 1


@patch("app.core.workspace_indexer.subprocess.run")
def test_index_workspace_timeout(mock_run):
    """Test handling of subprocess timeout."""
    import subprocess
    mock_run.side_effect = subprocess.TimeoutExpired(cmd="test", timeout=60)

    with tempfile.TemporaryDirectory() as tmpdir:
        result = IndexingService.index_workspace(tmpdir, timeout=60)
        assert result.success is False
        assert "Timeout" in result.stderr


def test_index_workspace_not_found():
    """Test indexing non-existent workspace."""
    with pytest.raises(ValueError, match="not found"):
        IndexingService.index_workspace("/nonexistent/path")


@patch("app.core.workspace_indexer.subprocess.run")
def test_multi_workspace_isolation(mock_run):
    """Test that multiple workspaces can be indexed independently."""
    mock_run.return_value = MagicMock(returncode=0, stdout="OK", stderr="")

    with tempfile.TemporaryDirectory() as ws1, \
         tempfile.TemporaryDirectory() as ws2:

        result1 = IndexingService.index_workspace(ws1)
        result2 = IndexingService.index_workspace(ws2)

        assert result1.success is True
        assert result2.success is True

        # Verify cwd was set differently for each
        calls = mock_run.call_args_list
        cwd_values = [c[1]["cwd"] for c in calls]
        assert str(Path(ws1).resolve()) in cwd_values
        assert str(Path(ws2).resolve()) in cwd_values
```

2. **Run tests**
   ```bash
   pytest tests/test_indexing.py -v --cov=app
   ```

---

## Future Phase Design Notes: Search Integration

> **IMPORTANT**: Search functionality is DEFERRED to a future phase.
>
> In a future phase, search queries will flow through Claude Code's MCP interface
> to mcp-vector-search, NOT through a REST API wrapper in research-mind-service.
>
> The architecture will be:
>
> ```
> User Query → Claude Code → MCP Protocol → mcp-vector-search
>                                            (reads .mcp-vector-search/ index)
> ```
>
> Phase 1 focuses on ensuring workspaces are properly indexed so that
> Future search functionality can find content.

---

## Research References

### Primary References

**docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md** (v2.0)

- Subprocess invocation pattern (subprocess.run() with cwd)
- Two-step init + index flow
- Exit code handling (0=success, 1=failure)
- WorkspaceIndexer class template
- Error handling and recovery patterns

**docs/research2/RESEARCH_SUMMARY.md**

- Quick reference of verified subprocess behavior
- Performance baselines (3.89s for 2-file project)

### Secondary References

- **IMPLEMENTATION_ROADMAP.md** - Master roadmap for Phase 1
- **01-PHASE_1_FOUNDATION.md** - Indexing operations overview

---

## Acceptance Criteria

### API Functionality (MUST COMPLETE)

- [ ] POST /api/v1/workspaces/{id}/index triggers subprocess indexing
- [ ] GET /api/v1/workspaces/{id}/index/status returns index status
- [ ] Status correctly reflects .mcp-vector-search/ directory existence
- [ ] All invalid workspace IDs return 404
- [ ] Subprocess exit codes properly translated to API responses

### Subprocess Handling (MUST COMPLETE)

- [ ] Two-step init + index flow executed correctly
- [ ] Exit code 0 mapped to success response
- [ ] Exit code 1 mapped to failure response with stderr details
- [ ] Timeout handled gracefully with appropriate error message
- [ ] cwd parameter correctly set to workspace directory

### Error Handling (MUST COMPLETE)

- [ ] Timeout returns clear error message
- [ ] Permission denied returns clear error message
- [ ] Missing CLI returns clear error message
- [ ] Corrupted index handled (recommend re-init)

### Testing (MUST COMPLETE)

- [ ] All endpoints tested
- [ ] Subprocess invocation tested (mocked)
- [ ] Exit code handling tested (success + failure)
- [ ] Timeout handling tested
- [ ] Multi-workspace isolation verified
- [ ] > 90% test coverage

---

## Go/No-Go Criteria

**GO to Phase 1.4** if:

- [ ] All indexing endpoints working
- [ ] Subprocess invocation reliable
- [ ] Error handling comprehensive
- [ ] All tests passing
- [ ] Tech lead approves implementation

---

## Summary

**Phase 1.3** delivers:

- REST API endpoints for workspace indexing via mcp-vector-search subprocess
- Two-step init + index subprocess orchestration
- Index status checking via .mcp-vector-search/ directory existence
- Comprehensive error handling for subprocess failures and timeouts
- Foundation for future search integration via Claude Code MCP interface

Search functionality is explicitly deferred to a future phase where it will use Claude Code's native MCP interface to mcp-vector-search.

---

**Document Version**: 2.0
**Last Updated**: 2026-02-01
**Architecture**: Subprocess-based (replaces v1.0 library embedding approach)
**Renamed From**: 01_1_3-VECTOR_SEARCH_API.md
**Next Phase**: Phase 1.4 (Path Validator), 1.5 (Audit Logging)
**Parent**: 01-PHASE_1_FOUNDATION.md
