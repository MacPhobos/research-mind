# Phase 1.3: Vector Search REST API (Wrapper)

**Subphase**: 1.3 of 8 (Phase 1)
**Duration**: 5-6 business days
**Effort**: 40-48 hours
**Team Size**: 2 FTE engineers
**Prerequisite**: Phase 1.1 (FastAPI + VectorSearchManager), Phase 1.0 (mcp-vector-search installed)
**Blocking**: 1.7, 1.8
**Can Parallel With**: 1.2, 1.4
**Status**: CRITICAL - Core indexing and search functionality

---

## Subphase Objective

Create REST wrapper around mcp-vector-search with per-session indexing and search. Implement SessionIndexer wrapper that manages session-scoped ChromaDB collections and provides job progress tracking for async indexing.

**Success Definition**: Users can:

- Start indexing jobs with POST /api/sessions/{id}/index
- Track job progress with GET /api/sessions/{id}/index/jobs/{job_id}
- Search indexed content with POST /api/sessions/{id}/search
- Results include file paths, line numbers, code snippets, relevance scores
- Multiple sessions maintain 100% isolated search results

---

## Timeline & Effort

### Day 1-2: SessionIndexer Wrapper (12-16 hours)

- Design SessionIndexer wrapper pattern
- Implement per-session collection management
- Job tracking data model
- Async indexing job execution

### Day 3-4: Indexing Endpoints (12-16 hours)

- POST /api/sessions/{id}/index endpoint
- GET /api/sessions/{id}/index/jobs/{job_id} endpoint
- GET /api/sessions/{id}/index/jobs endpoint
- Job status tracking and error handling

### Day 5-6: Search Endpoints & Testing (12-16 hours)

- POST /api/sessions/{id}/search endpoint
- GET /api/sessions/{id}/stats endpoint
- Per-session isolation verification
- Search result format and pagination

---

## Deliverables

1. **research-mind-service/app/core/session_indexer.py** (200-300 lines)

   - SessionIndexer wrapper around mcp-vector-search
   - Per-session collection management
   - Job tracking and progress reporting

2. **research-mind-service/app/models/indexing_job.py** (new)

   - Indexing job data model for tracking
   - Status, progress, timestamps, error tracking

3. **research-mind-service/app/routes/vector_search.py** (200-250 lines)

   - Indexing endpoints (start, get status, list jobs)
   - Search endpoints (search, statistics)
   - Error handling and validation

4. **research-mind-service/app/schemas/vector_search.py** (200+ lines)

   - Pydantic models for requests/responses
   - IndexRequest, JobStatusResponse, SearchRequest, SearchResultsResponse

5. **Database migration** (new)
   - Alembic migration for indexing_jobs table

---

## Detailed Tasks

### Task 1.3.1: Design and Implement SessionIndexer Wrapper (12-16 hours)

**Objective**: Create thin wrapper around mpc-vector-search that adds session scoping

**Key Architecture Decision** (from Phase 1.0 verification):

- Single global ChromaDB instance
- Per-session collections: `session_{session_id}`
- Concurrent write safety verified in Phase 1.0 testing
- VectorSearchManager singleton provides the indexer and search engine

#### Steps

1. **Create app/core/session_indexer.py**

```python
"""
SessionIndexer wrapper for mcp-vector-search with session scoping.

Do NOT re-implement indexing or job queue - use mpc-vector-search's
SemanticIndexer directly. This wrapper adds session scoping and REST interface.

Architecture:
- Global VectorSearchManager singleton provides indexer and search engine
- SessionIndexer wraps calls with session-scoped collection naming
- Per-session collections: session_{session_id}
- Concurrent write safety verified in Phase 1.0
"""

import asyncio
import logging
from pathlib import Path
from typing import Optional, Dict, List
import uuid
from datetime import datetime

from app.core.vector_search import VectorSearchManager

logger = logging.getLogger(__name__)


class SessionIndexer:
    """
    Session-scoped wrapper around mpc-vector-search.

    Provides:
    - Per-session ChromaDB collection management
    - Async indexing job tracking
    - Job progress reporting
    - Search scoped to session collection

    Note: The actual indexing implementation comes from mpc-vector-search's
    SemanticIndexer. This class adds session scoping and REST interface.
    """

    def __init__(self, session_id: str, workspace_root: Path):
        """
        Initialize SessionIndexer.

        Args:
            session_id: UUID of the session
            workspace_root: Session's workspace directory path
        """
        self.session_id = session_id
        self.workspace_root = Path(workspace_root)
        self.collection_name = f"session_{session_id}"

        # Get singleton manager
        self._vs_manager = VectorSearchManager()

        # In-memory job tracking (Phase 2 will move to database)
        self._jobs: Dict[str, dict] = {}

        logger.info(f"✓ Initialized SessionIndexer for session {session_id}")

    async def index_directory(self, directory_path: Path) -> Dict:
        """
        Start indexing a directory asynchronously.

        Args:
            directory_path: Path to directory containing files to index

        Returns:
            Dict with job_id and status

        Raises:
            ValueError: If directory doesn't exist or path validation fails
        """
        if not directory_path.exists():
            raise ValueError(f"Directory not found: {directory_path}")

        job_id = str(uuid.uuid4())

        # Create job tracking record
        job = {
            "job_id": job_id,
            "session_id": self.session_id,
            "status": "queued",
            "progress": 0,
            "started_at": None,
            "completed_at": None,
            "error": None,
            "file_count": 0,
            "chunk_count": 0,
        }
        self._jobs[job_id] = job

        # Start async indexing (don't wait)
        asyncio.create_task(
            self._run_indexing_job(job_id, directory_path)
        )

        logger.info(f"✓ Queued indexing job {job_id} for session {self.session_id}")
        return {
            "job_id": job_id,
            "status": "queued",
            "message": f"Indexing job {job_id} queued",
        }

    async def _run_indexing_job(self, job_id: str, directory_path: Path):
        """
        Execute indexing job.

        This calls mpc-vector-search's SemanticIndexer.
        """
        job = self._jobs[job_id]
        job["status"] = "running"
        job["started_at"] = datetime.utcnow().isoformat()

        try:
            logger.info(f"Starting indexing job {job_id} for {directory_path}")

            # Delegate to mpc-vector-search indexer with session scoping
            # The indexer will create/update the session_{session_id} collection
            result = await asyncio.to_thread(
                self._vs_manager.indexer.index_directory,
                path=str(directory_path),
                collection_name=self.collection_name,
                recursive=True,
            )

            # Update job with results
            job["status"] = "completed"
            job["completed_at"] = datetime.utcnow().isoformat()
            job["file_count"] = result.get("file_count", 0)
            job["chunk_count"] = result.get("chunk_count", 0)
            job["progress"] = 100

            logger.info(
                f"✓ Completed indexing job {job_id}: "
                f"{job['file_count']} files, {job['chunk_count']} chunks"
            )

        except Exception as e:
            logger.error(f"✗ Indexing job {job_id} failed: {e}")
            job["status"] = "failed"
            job["error"] = str(e)
            job["completed_at"] = datetime.utcnow().isoformat()

    def get_job_status(self, job_id: str) -> Optional[Dict]:
        """
        Get indexing job status.

        Args:
            job_id: Job identifier

        Returns:
            Job status dict or None if not found
        """
        return self._jobs.get(job_id)

    def list_jobs(self) -> List[Dict]:
        """List all indexing jobs for this session."""
        return list(self._jobs.values())

    async def search(self, query: str, top_k: int = 10) -> Dict:
        """
        Search within session's indexed content.

        Args:
            query: Search query
            top_k: Number of results to return

        Returns:
            Dict with results and metadata

        Raises:
            RuntimeError: If search fails or collection not indexed
        """
        try:
            # Delegate to mpc-vector-search search engine with session scoping
            results = await asyncio.to_thread(
                self._vs_manager.search_engine.search,
                query=query,
                collection_name=self.collection_name,
                top_k=top_k,
            )

            # Format results for REST API
            formatted_results = []
            for result in results:
                formatted_results.append({
                    "file_path": result.get("file_path"),
                    "line_number": result.get("line_number"),
                    "chunk_text": result.get("text", result.get("chunk_text")),
                    "relevance_score": result.get("score", result.get("relevance_score")),
                    "metadata": result.get("metadata", {}),
                })

            logger.info(
                f"✓ Search in session {self.session_id}: '{query}' → {len(results)} results"
            )

            return {
                "query": query,
                "results": formatted_results,
                "count": len(results),
                "session_id": self.session_id,
            }

        except Exception as e:
            logger.error(f"✗ Search failed in session {self.session_id}: {e}")
            raise RuntimeError(f"Search failed: {e}")

    def get_stats(self) -> Dict:
        """Get indexing statistics for this session."""
        # Get stats from ChromaDB collection (mpc-vector-search provides this)
        try:
            stats = self._vs_manager.search_engine.get_collection_stats(
                collection_name=self.collection_name
            )
            return {
                "session_id": self.session_id,
                "collection_name": self.collection_name,
                "indexed": True,
                **stats,
            }
        except Exception as e:
            logger.warning(f"Could not retrieve stats: {e}")
            return {
                "session_id": self.session_id,
                "collection_name": self.collection_name,
                "indexed": False,
                "error": str(e),
            }
```

---

### Task 1.3.2: Create Indexing Job Model (4-5 hours)

**Objective**: Database model for job tracking

#### Steps

1. **Create app/models/indexing_job.py**

```python
"""
Indexing job persistent storage (Phase 1.3).

Tracks async indexing job lifecycle: queued → running → completed/failed
"""

from datetime import datetime
from uuid import uuid4
from sqlalchemy import Column, String, Integer, DateTime, JSON, Float

Base = declarative_base()


class IndexingJob(Base):
    """Indexing job tracking."""

    __tablename__ = "indexing_jobs"

    job_id = Column(String(36), primary_key=True, default=lambda: str(uuid4()))
    session_id = Column(String(36), nullable=False)  # Foreign key to sessions
    status = Column(String(50), nullable=False, default="queued")  # queued, running, completed, failed
    progress = Column(Integer, nullable=False, default=0)  # 0-100
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    # Results
    file_count = Column(Integer, nullable=False, default=0)
    chunk_count = Column(Integer, nullable=False, default=0)
    total_size_bytes = Column(Integer, nullable=False, default=0)
    duration_seconds = Column(Float, nullable=True)
    error = Column(String(2048), nullable=True)
```

---

### Task 1.3.3: Create Pydantic Schemas (5-6 hours)

**Objective**: Request/response models for vector search endpoints

#### Steps

1. **Create app/schemas/vector_search.py**

```python
"""
Pydantic schemas for vector search operations.
"""

from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class IndexRequest(BaseModel):
    """Request to start indexing a directory."""

    directory_path: str = Field(..., description="Path to directory to index")

    class Config:
        json_schema_extra = {
            "example": {
                "directory_path": "/var/lib/research-mind/sessions/550e8400-e29b-41d4-a716-446655440000/content/src"
            }
        }


class JobStatusResponse(BaseModel):
    """Response for job status query."""

    job_id: str = Field(..., description="Unique job identifier")
    session_id: str = Field(..., description="Session this job belongs to")
    status: str = Field(..., description="Job status: queued, running, completed, failed")
    progress: int = Field(..., description="Progress percentage (0-100)")
    started_at: Optional[str] = Field(None, description="Job start time (ISO 8601)")
    completed_at: Optional[str] = Field(None, description="Job completion time (ISO 8601)")
    error: Optional[str] = Field(None, description="Error message if failed")
    file_count: int = Field(..., description="Number of files indexed")
    chunk_count: int = Field(..., description="Number of text chunks indexed")


class SearchRequest(BaseModel):
    """Request to search indexed content."""

    query: str = Field(..., min_length=1, description="Search query")
    limit: int = Field(10, ge=1, le=100, description="Max results (1-100)")

    class Config:
        json_schema_extra = {
            "example": {
                "query": "how to handle authentication",
                "limit": 10,
            }
        }


class SearchResult(BaseModel):
    """Single search result."""

    file_path: str = Field(..., description="Path to file containing result")
    line_number: int = Field(..., description="Line number in file")
    chunk_text: str = Field(..., description="Text excerpt from search result")
    relevance_score: float = Field(..., ge=0, le=1, description="Relevance score (0-1)")
    metadata: dict = Field(default_factory=dict, description="Additional metadata")


class SearchResultsResponse(BaseModel):
    """Response from search query."""

    query: str = Field(..., description="The search query")
    results: List[SearchResult] = Field(..., description="Search results")
    count: int = Field(..., description="Number of results returned")
    session_id: str = Field(..., description="Session this search was performed in")


class IndexStatsResponse(BaseModel):
    """Response with indexing statistics."""

    session_id: str = Field(..., description="Session identifier")
    collection_name: str = Field(..., description="ChromaDB collection name")
    indexed: bool = Field(..., description="Has this session been indexed?")
    file_count: Optional[int] = Field(None, description="Number of indexed files")
    chunk_count: Optional[int] = Field(None, description="Number of indexed chunks")
    total_size_bytes: Optional[int] = Field(None, description="Total size of indexed content")
```

---

### Task 1.3.4: Create Search Routes (8-10 hours)

**Objective**: REST endpoints for indexing and search

#### Steps

1. **Create app/routes/vector_search.py**

```python
"""
Vector search REST endpoints.

Provides:
- Indexing job management (start, status, list)
- Search operations (with per-session isolation)
- Index statistics
"""

import logging
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session as DBSession

from app.main import get_vector_search_manager
from app.schemas.vector_search import (
    IndexRequest,
    JobStatusResponse,
    SearchRequest,
    SearchResultsResponse,
    IndexStatsResponse,
)
from app.services.session_service import SessionService
from app.core.session_indexer import SessionIndexer

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/sessions", tags=["vector-search"])


@router.post("/{session_id}/index", response_model=dict, status_code=status.HTTP_202_ACCEPTED)
async def start_indexing(
    session_id: str,
    request: IndexRequest,
    db: DBSession = Depends(get_db),
):
    """
    Start an async indexing job for a session.

    **Path Parameters**:
    - `session_id`: Session to index

    **Request Body**:
    - `directory_path`: Path to directory to index

    **Returns**: Job ID and status (202 Accepted)

    **Status Codes**:
    - 202: Indexing job created and queued
    - 404: Session not found
    - 400: Invalid directory path
    """
    # Verify session exists
    session = SessionService.get_session(db, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    try:
        # Create session indexer
        indexer = SessionIndexer(session_id, session.workspace_path)

        # Start indexing job
        result = await indexer.index_directory(request.directory_path)

        return {
            "job_id": result["job_id"],
            "status": result["status"],
            "session_id": session_id,
        }

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Indexing failed: {e}")
        raise HTTPException(status_code=500, detail="Indexing failed")


@router.get("/{session_id}/index/jobs/{job_id}", response_model=JobStatusResponse)
async def get_job_status(
    session_id: str,
    job_id: str,
    db: DBSession = Depends(get_db),
):
    """
    Get status of an indexing job.

    **Path Parameters**:
    - `session_id`: Session identifier
    - `job_id`: Job identifier

    **Returns**: Job status with progress

    **Status Codes**:
    - 200: Job found
    - 404: Session or job not found
    """
    session = SessionService.get_session(db, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    indexer = SessionIndexer(session_id, session.workspace_path)
    job = indexer.get_job_status(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    return JobStatusResponse(**job)


@router.get("/{session_id}/index/jobs", response_model=list)
async def list_jobs(
    session_id: str,
    db: DBSession = Depends(get_db),
):
    """
    List all indexing jobs for a session.

    **Path Parameters**:
    - `session_id`: Session identifier

    **Returns**: List of jobs

    **Status Codes**:
    - 200: Jobs retrieved
    - 404: Session not found
    """
    session = SessionService.get_session(db, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    indexer = SessionIndexer(session_id, session.workspace_path)
    return indexer.list_jobs()


@router.post("/{session_id}/search", response_model=SearchResultsResponse)
async def search(
    session_id: str,
    request: SearchRequest,
    db: DBSession = Depends(get_db),
):
    """
    Search indexed content in a session.

    **Path Parameters**:
    - `session_id`: Session to search in

    **Request Body**:
    - `query`: Search query text
    - `limit`: Max results (default 10)

    **Returns**: Search results with relevance scores

    **Status Codes**:
    - 200: Search completed
    - 404: Session not found
    - 400: Invalid query
    - 503: Collection not indexed
    """
    session = SessionService.get_session(db, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    try:
        indexer = SessionIndexer(session_id, session.workspace_path)
        result = await indexer.search(request.query, request.limit)
        return SearchResultsResponse(**result)

    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Search failed: {e}")
        raise HTTPException(status_code=500, detail="Search failed")


@router.get("/{session_id}/stats", response_model=IndexStatsResponse)
async def get_stats(
    session_id: str,
    db: DBSession = Depends(get_db),
):
    """
    Get indexing statistics for a session.

    **Path Parameters**:
    - `session_id`: Session identifier

    **Returns**: Index statistics

    **Status Codes**:
    - 200: Stats retrieved
    - 404: Session not found
    """
    session = SessionService.get_session(db, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    indexer = SessionIndexer(session_id, session.workspace_path)
    stats = indexer.get_stats()
    return IndexStatsResponse(**stats)
```

2. **Register routes in app/main.py**
   ```python
   from app.routes.vector_search import router as vs_router
   app.include_router(vs_router)
   ```

---

### Task 1.3.5: Testing & Isolation Verification (4-6 hours)

**Objective**: Verify search results are per-session isolated

#### Steps

1. **Create tests/test_vector_search.py**

```python
"""
Tests for vector search and per-session isolation.
"""

import pytest
from fastapi.testclient import TestClient


def test_index_directory(client, test_session_id, test_directory):
    """Test starting an indexing job."""
    response = client.post(
        f"/api/sessions/{test_session_id}/index",
        json={"directory_path": str(test_directory)},
    )
    assert response.status_code == 202
    data = response.json()
    assert "job_id" in data


def test_get_job_status(client, test_session_id, test_job_id):
    """Test retrieving job status."""
    response = client.get(
        f"/api/sessions/{test_session_id}/index/jobs/{test_job_id}"
    )
    assert response.status_code == 200
    data = response.json()
    assert data["job_id"] == test_job_id


def test_search(client, test_session_id):
    """Test searching indexed content."""
    response = client.post(
        f"/api/sessions/{test_session_id}/search",
        json={"query": "authentication", "limit": 10},
    )
    assert response.status_code == 200
    data = response.json()
    assert "results" in data
    assert "query" in data


def test_session_isolation():
    """Test that search results are per-session isolated."""
    # Create two sessions
    session1 = client.post("/api/sessions", json={"name": "Session 1"}).json()
    session2 = client.post("/api/sessions", json={"name": "Session 2"}).json()

    # Index different content in each
    # (would need test directories for this)

    # Search in session1 should not return results from session2
    # (test implementation depends on test fixture setup)
    pass
```

---

## Research References

### Primary References

**docs/research/mcp-vector-search-rest-api-proposal.md** (Sections 2.2, 2.3)

- Indexing API specification with async job model
- Search API specification with per-session isolation
- Exact request/response schemas to implement

**docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md** (Section 4)

- SessionIndexer wrapper architecture (exact template used)
- Code example for delegating to mpc-vector-search
- Session collection naming pattern

**docs/research/mcp-vector-search-capabilities.md** (Sections 2, 3)

- SemanticIndexer and SearchEngine from mpc-vector-search
- How to properly scope collections

### Secondary References

- **IMPLEMENTATION_PLAN.md** - Phase 1.3 section (lines 259-340)
- **01-PHASE_1_FOUNDATION.md** - Vector search API overview

---

## Acceptance Criteria

### API Functionality (MUST COMPLETE)

- [ ] POST /api/sessions/{id}/index returns 202 with job_id
- [ ] GET /api/sessions/{id}/index/jobs/{job_id} returns job status
- [ ] GET /api/sessions/{id}/index/jobs returns list of jobs
- [ ] POST /api/sessions/{id}/search returns search results
- [ ] GET /api/sessions/{id}/stats returns index statistics
- [ ] All invalid session IDs return 404

### Search Quality (MUST COMPLETE)

- [ ] Search results include file_path, line_number, code_snippet, relevance_score
- [ ] Results ordered by relevance (highest first)
- [ ] Per-session isolation verified (search in session 1 only returns session 1 results)
- [ ] Multiple sessions can index and search independently

### Testing (MUST COMPLETE)

- [ ] All endpoints tested
- [ ] Session isolation tests pass
- [ ] Error cases handled (missing session, invalid path)
- [ ] > 90% test coverage

---

## Go/No-Go Criteria

**GO to Phase 1.4** if:

- [ ] All search endpoints working
- [ ] Per-session isolation verified
- [ ] Job tracking functional
- [ ] All tests passing
- [ ] Tech lead approves implementation

---

## Summary

**Phase 1.3** delivers:

- SessionIndexer wrapper providing thin REST layer over mpc-vector-search
- Per-session indexing with collection naming isolation
- Async job tracking with progress reporting
- Search endpoint with per-session result isolation
- Foundation for agent analysis in Phase 1.6

The search API is the critical bridge between document indexing and agent analysis.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Next Phase**: Phase 1.4 (Path Validator), 1.5 (Audit Logging), 1.6 (Agent Integration)
**Parent**: 01-PHASE_1_FOUNDATION.md
