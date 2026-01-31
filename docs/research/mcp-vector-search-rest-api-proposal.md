# MCP Vector Search: REST API Proposal

**Document Version**: 1.0
**Date**: 2026-01-30
**Status**: Architectural Proposal

## Executive Summary

This document proposes a REST API wrapper around mcp-vector-search for Research-Mind's session-scoped indexing and search requirements. The wrapper is implemented as a separate FastAPI service that imports mcp-vector-search as a library, manages session isolation, async job queuing, and audit logging.

**Key decisions**:

- Wrapper service (not embedded REST in mcp-vector-search)
- Per-session collections in shared ChromaDB
- Job-based async indexing with progress tracking
- Mandatory session_id on all endpoints
- Server-side session enforcement (not prompt-based)

---

## 1. Architecture: Wrapper vs Embedded

### 1.1 Decision: Wrapper Service (Recommended)

```
┌─────────────────────────────────────────────────┐
│      research-mind-service (FastAPI)            │
│  (/Users/mac/workspace/research-mind/          │
│   research-mind-service/app/)                   │
├─────────────────────────────────────────────────┤
│  - FastAPI app                                  │
│  - Session routing & validation                 │
│  - Job queue (Celery/RQ or in-process)        │
│  - Audit logging                               │
└──────────────┬──────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────┐
│  mcp-vector-search (Imported Library)           │
│  (from: pip install mcp-vector-search)         │
├─────────────────────────────────────────────────┤
│  from mcp_vector_search.core import:           │
│    - SemanticIndexer                           │
│    - SemanticSearchEngine                      │
│    - ChromaVectorDatabase                      │
└─────────────────────────────────────────────────┘
```

**Advantages**:

- ✓ No modification to mcp-vector-search core
- ✓ Clean separation of concerns
- ✓ Easier to version/upgrade mcp-vector-search
- ✓ Research-Mind can manage job queuing, logging
- ✓ Middleware available for auth, rate limiting

**Disadvantages**:

- ✗ Additional service to deploy
- ✗ Slight latency overhead (IPC vs library)

### 1.2 Alternative: Embedded REST

Not recommended because:

- Would require modifying mcp-vector-search core
- Session scoping would pollute MCP tool interface
- Harder to test/debug
- Job queue management less flexible

---

## 2. Endpoint Specifications

### 2.1 Session Management

#### POST /api/sessions

Create a new research session with optional content.

**Request**:

```http
POST /api/sessions HTTP/1.1
Content-Type: application/json

{
  "name": "OAuth2 Architecture Review",
  "description": "Review OAuth2 implementation in legacy auth module",
  "content_entities": [
    {
      "type": "repository",
      "path": "/path/to/oauth-repo",
      "filters": ["*.py", "*.md"]
    },
    {
      "type": "file",
      "path": "/path/to/requirements.txt"
    }
  ]
}
```

**Response** (201 Created):

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "OAuth2 Architecture Review",
  "description": "Review OAuth2 implementation in legacy auth module",
  "created_at": "2026-01-30T15:30:00Z",
  "status": "initialized",
  "workspace_path": "/var/lib/research-mind/sessions/550e8400-e29b-41d4-a716-446655440000",
  "index_path": "/var/lib/research-mind/sessions/550e8400-e29b-41d4-a716-446655440000/.mcp-vector-search",
  "content_count": 2
}
```

#### GET /api/sessions/{session_id}

Get session details.

**Response**:

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "OAuth2 Architecture Review",
  "status": "idle",
  "created_at": "2026-01-30T15:30:00Z",
  "last_indexed": "2026-01-30T15:45:00Z",
  "content_count": 2,
  "index_stats": {
    "total_chunks": 1234,
    "total_documents": 45,
    "languages": { "python": 32, "markdown": 13 },
    "storage_size_bytes": 1048576
  }
}
```

#### DELETE /api/sessions/{session_id}

Delete a session and all associated data.

**Response** (204 No Content)

---

### 2.2 Indexing Endpoints

#### POST /api/sessions/{session_id}/index

Start an indexing job. Session must exist.

**Request**:

```http
POST /api/sessions/550e8400-e29b-41d4-a716-446655440000/index HTTP/1.1
Content-Type: application/json

{
  "force": false,
  "exclude_patterns": [
    "**/*.pyc",
    "**/node_modules/**"
  ],
  "priority": "normal"
}
```

**Response** (202 Accepted):

```json
{
  "job_id": "job_abc123",
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "created_at": "2026-01-30T15:46:00Z",
  "estimated_duration_seconds": 45,
  "details": {
    "files_to_index": 567,
    "estimated_chunks": 2340,
    "force_reindex": false
  }
}
```

#### GET /api/sessions/{session_id}/index/jobs/{job_id}

Get indexing job status and progress.

**Response**:

```json
{
  "job_id": "job_abc123",
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "running",
  "progress": 0.35,
  "created_at": "2026-01-30T15:46:00Z",
  "started_at": "2026-01-30T15:46:05Z",
  "updated_at": "2026-01-30T15:46:30Z",
  "metrics": {
    "files_processed": 198,
    "total_files": 567,
    "chunks_created": 823,
    "current_file": "src/auth/oauth2.py",
    "elapsed_seconds": 25,
    "estimated_remaining_seconds": 42
  },
  "errors": []
}
```

**Possible statuses**: `pending`, `running`, `completed`, `failed`, `cancelled`

#### GET /api/sessions/{session_id}/index/jobs

List indexing jobs for a session.

**Query parameters**:

- `limit`: Max results (default 50)
- `status`: Filter by status (pending, running, completed, failed)
- `order_by`: `created_at` (default) or `updated_at`

**Response**:

```json
{
  "jobs": [
    {
      "job_id": "job_abc123",
      "status": "completed",
      "created_at": "2026-01-30T15:46:00Z",
      "completed_at": "2026-01-30T15:47:20Z",
      "metrics": {
        "files_processed": 567,
        "chunks_created": 2340,
        "duration_seconds": 80
      }
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}
```

#### POST /api/sessions/{session_id}/index/entity/{entity_path}

Reindex a specific entity (file or directory) within a session.

**Request**:

```http
POST /api/sessions/.../index/entity/src%2Fauth%2Foauth2.py HTTP/1.1

{
  "force": true
}
```

**Response** (202 Accepted):

```json
{
  "job_id": "job_def456",
  "entity_path": "src/auth/oauth2.py",
  "status": "pending",
  "created_at": "2026-01-30T15:47:00Z"
}
```

---

### 2.3 Search Endpoints

#### POST /api/sessions/{session_id}/search

Semantic search within a session. Session_id is mandatory and enforced server-side.

**Request**:

```http
POST /api/sessions/550e8400-e29b-41d4-a716-446655440000/search HTTP/1.1
Content-Type: application/json

{
  "query": "how does OAuth2 token refresh work",
  "limit": 10,
  "similarity_threshold": 0.75,
  "filters": {
    "language": ["python"],
    "chunk_type": ["function", "method"],
    "file_pattern": "auth/**"
  },
  "include_context": true,
  "context_lines": 5
}
```

**Response** (200 OK):

```json
{
  "query": "how does OAuth2 token refresh work",
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "success",
  "search_time_ms": 87,
  "results": [
    {
      "rank": 1,
      "similarity_score": 0.92,
      "chunk_id": "src_auth_oauth2.py_line_42_line_67",
      "file_path": "src/auth/oauth2.py",
      "language": "python",
      "chunk_type": "function",
      "chunk_name": "refresh_token",
      "start_line": 42,
      "end_line": 67,
      "code_snippet": "def refresh_token(token: str) -> str:\n    \"\"\"Refresh an expired OAuth2 token.\n    ...\n    \"\"\"",
      "context_before": "def refresh_token(token: str) -> str:",
      "context_after": "    return new_token",
      "docstring": "Refresh an expired OAuth2 token using the refresh grant.",
      "parent": "OAuth2Manager",
      "metadata": {
        "complexity": 2,
        "has_tests": true
      }
    },
    {
      "rank": 2,
      "similarity_score": 0.88,
      ...
    }
  ],
  "total_results": 23,
  "result_count": 10,
  "recommendation": "Found 23 results. Top 10 shown. Adjust similarity_threshold to refine."
}
```

**Error responses**:

400 Bad Request (invalid query):

```json
{
  "error": "invalid_request",
  "message": "Query cannot be empty",
  "status_code": 400
}
```

404 Not Found (session doesn't exist):

```json
{
  "error": "session_not_found",
  "message": "Session '550e8400-e29b-41d4-a716-446655440000' not found",
  "status_code": 404
}
```

#### POST /api/sessions/{session_id}/search/similar

Find code similar to a given file/function.

**Request**:

```http
POST /api/sessions/.../search/similar HTTP/1.1

{
  "file_path": "src/auth/oauth2.py",
  "line_start": 42,
  "line_end": 67,
  "limit": 5
}
```

**Response**:

```json
{
  "reference": {
    "file_path": "src/auth/oauth2.py",
    "lines": "42-67",
    "code_snippet": "def refresh_token(...)..."
  },
  "similar_results": [
    {
      "rank": 1,
      "similarity_score": 0.85,
      "file_path": "src/integrations/github_oauth.py",
      "chunk_name": "refresh_github_token",
      ...
    }
  ]
}
```

---

### 2.4 Statistics & Admin Endpoints

#### GET /api/sessions/{session_id}/stats

Get detailed index statistics.

**Response**:

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "index_stats": {
    "total_chunks": 2340,
    "total_documents": 567,
    "storage_size_bytes": 5242880,
    "last_indexed": "2026-01-30T15:47:20Z",
    "embedding_model": "sentence-transformers/all-MiniLM-L6-v2",
    "embedding_dimension": 384
  },
  "language_distribution": {
    "python": {
      "files": 234,
      "chunks": 1200,
      "lines_of_code": 45000
    },
    "typescript": {
      "files": 180,
      "chunks": 890,
      "lines_of_code": 32000
    },
    "markdown": {
      "files": 153,
      "chunks": 250,
      "size_bytes": 1024000
    }
  },
  "chunk_type_distribution": {
    "function": 1450,
    "class": 340,
    "method": 420,
    "module": 130
  },
  "cache_stats": {
    "cache_hits": 1234,
    "cache_misses": 567,
    "hit_rate": 0.685
  }
}
```

#### GET /api/sessions/{session_id}/health

Check if a session is ready for queries.

**Response**:

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "healthy": true,
  "status": "ready",
  "index_ready": true,
  "database_ok": true,
  "last_check": "2026-01-30T15:48:00Z",
  "message": "Session is fully indexed and ready for queries"
}
```

#### GET /api/health

Global service health.

**Response**:

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2026-01-30T15:48:00Z",
  "services": {
    "database": "healthy",
    "queue": "healthy",
    "embedding_model": "loaded"
  },
  "active_sessions": 12,
  "active_jobs": 2
}
```

---

## 3. Request/Response Schemas

### 3.1 Core Models (Pydantic)

```python
# research-mind-service/app/schemas/vector_search.py

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

class SessionCreateRequest(BaseModel):
    """Create a new session."""
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    content_entities: List[Dict[str, Any]] = []

class SearchRequest(BaseModel):
    """Search within a session."""
    query: str = Field(..., min_length=1, max_length=1000)
    limit: int = Field(10, ge=1, le=100)
    similarity_threshold: float = Field(0.75, ge=0.0, le=1.0)
    filters: Optional[Dict[str, Any]] = None
    include_context: bool = True
    context_lines: int = Field(5, ge=0, le=20)

class SearchResult(BaseModel):
    """Single search result."""
    rank: int
    similarity_score: float
    chunk_id: str
    file_path: str
    language: str
    chunk_type: str
    chunk_name: Optional[str]
    start_line: int
    end_line: int
    code_snippet: str
    docstring: Optional[str]
    parent: Optional[str]
    metadata: Dict[str, Any]

class SearchResponse(BaseModel):
    """Search response."""
    query: str
    session_id: str
    status: str
    search_time_ms: int
    results: List[SearchResult]
    total_results: int
    result_count: int

class IndexingJob(BaseModel):
    """Async indexing job."""
    job_id: str
    session_id: str
    status: str  # pending, running, completed, failed
    progress: float  # 0.0-1.0
    created_at: datetime
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    metrics: Dict[str, Any]
    errors: List[str]

class IndexRequest(BaseModel):
    """Request to start indexing."""
    force: bool = False
    exclude_patterns: List[str] = []
    priority: str = "normal"  # low, normal, high
```

### 3.2 Response Status Codes

| Code                      | Meaning           | Use Case                     |
| ------------------------- | ----------------- | ---------------------------- |
| 200 OK                    | Success           | GET requests, search results |
| 201 Created               | Resource created  | POST /sessions               |
| 202 Accepted              | Async job started | POST /index, /search/similar |
| 204 No Content            | Success, no body  | DELETE /sessions/{id}        |
| 400 Bad Request           | Invalid input     | Malformed query, bad filters |
| 404 Not Found             | Resource missing  | Session not found            |
| 409 Conflict              | Invalid state     | Index already running        |
| 422 Unprocessable Entity  | Validation failed | Pydantic validation error    |
| 429 Too Many Requests     | Rate limited      | Too many concurrent jobs     |
| 500 Internal Server Error | Server error      | Indexing failure, DB error   |

---

## 4. Async Job Model

### 4.1 Job Queue Architecture

**Implementation options**:

1. **In-process queue** (simpler, single instance): `asyncio.Queue`
2. **Redis queue** (distributed): `redis-queue` or `rq`
3. **Celery** (advanced): Full async task system

**Recommended for MVP**: In-process queue with persistence to database

### 4.2 Job Lifecycle

```
┌──────────────────────────────────────────────────────┐
│ User submits indexing request (POST /index)         │
└──────────────────┬───────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────┐
│ Job created in "pending" state                       │
│ - JobId generated (UUID)                             │
│ - Stored in research-mind-service DB                 │
│ - Added to job queue                                 │
└──────────────────┬───────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────┐
│ Job picked up by worker thread                       │
│ - Status changed to "running"                        │
│ - start_at timestamp recorded                        │
└──────────────────┬───────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────┐
│ SemanticIndexer processes files                      │
│ - Emits progress updates (every N files)             │
│ - Updates progress in Job record                     │
└──────────────────┬───────────────────────────────────┘
                   │
         ┌─────────┴──────────┐
         │                    │
         ▼                    ▼
    [Success]          [Error]
         │                    │
         ▼                    ▼
┌────────────────┐    ┌────────────────┐
│ "completed"    │    │ "failed"       │
│ completed_at   │    │ error_message  │
│ metrics stored │    │ partial_stats  │
└────────────────┘    └────────────────┘
```

### 4.3 Progress Reporting

**Polling endpoint**: `GET /api/sessions/{session_id}/index/jobs/{job_id}`

```python
# Example: Emit progress every 50 files processed
def index_with_progress(indexer, files, job_id):
    total = len(files)
    for i, file in enumerate(files):
        result = indexer.index_file(file)

        if (i + 1) % 50 == 0:
            # Update progress in database
            job = Job.query.get(job_id)
            job.progress = (i + 1) / total
            job.metrics['files_processed'] = i + 1
            job.metrics['current_file'] = str(file)
            db.session.commit()
```

### 4.4 Job Cancellation

**Endpoint**: `POST /api/sessions/{session_id}/index/jobs/{job_id}/cancel`

```json
{
  "job_id": "job_abc123",
  "status": "cancelled",
  "reason": "user_requested",
  "cancelled_at": "2026-01-30T15:48:30Z",
  "partial_metrics": {
    "files_processed": 234,
    "chunks_created": 890
  }
}
```

---

## 5. Session Scoping & Enforcement

### 5.1 Server-Side Session Validation

**Every request must include session_id** (path parameter).

**Validation logic** (FastAPI middleware):

```python
# research-mind-service/app/middleware/session_validation.py

@app.middleware("http")
async def session_middleware(request: Request, call_next):
    # Extract session_id from path
    path = request.url.path
    match = re.search(r'/sessions/([^/]+)', path)

    if not match:
        return JSONResponse(
            status_code=400,
            content={"error": "missing_session_id"}
        )

    session_id = match.group(1)

    # Validate session exists
    session = Session.query.get(session_id)
    if not session:
        return JSONResponse(
            status_code=404,
            content={"error": "session_not_found"}
        )

    # Validate session not expired
    if session.is_expired():
        return JSONResponse(
            status_code=410,
            content={"error": "session_expired"}
        )

    # Attach to request for use in handlers
    request.state.session_id = session_id
    request.state.session = session

    response = await call_next(request)
    return response
```

### 5.2 Collection Isolation

**For each session**:

- Dedicated ChromaDB collection: `session_{session_id}`
- Separate metadata directory: `{session_root}/.mcp-vector-search/`
- Isolated workspace: `{session_root}/`

**Cross-session contamination prevention**:

```python
class SessionIndexer:
    def __init__(self, session_id: str, session_root: Path):
        self.session_id = session_id
        self.collection_name = f"session_{session_id}"  # Isolated!

        # All paths scoped to session_root
        self.workspace = session_root
        self.index_path = session_root / ".mcp-vector-search"

        # Create indexer with scoped paths
        self.database = ChromaVectorDatabase(
            persist_directory=self.index_path,
            embedding_function=embedding_fn
        )
        self.indexer = SemanticIndexer(
            database=self.database,
            project_root=session_root
        )
```

### 5.3 Access Control (Optional Future)

For multi-user scenarios:

```python
@app.get("/api/sessions/{session_id}")
async def get_session(session_id: str, current_user = Depends(get_current_user)):
    session = Session.query.get(session_id)

    # Verify user owns session
    if session.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Access denied")

    return session
```

---

## 6. Example Requests/Responses

### 6.1 Full Workflow Example

**Step 1: Create session**

```bash
curl -X POST http://localhost:8000/api/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Audit OAuth2 Implementation",
    "content_entities": [
      {"type": "repository", "path": "/home/user/myapp"}
    ]
  }'
```

Response:

```json
{
  "session_id": "abc-123",
  "name": "Audit OAuth2 Implementation",
  "status": "initialized",
  "workspace_path": "/var/lib/research-mind/sessions/abc-123",
  "created_at": "2026-01-30T16:00:00Z"
}
```

**Step 2: Start indexing**

```bash
curl -X POST http://localhost:8000/api/sessions/abc-123/index \
  -H "Content-Type: application/json" \
  -d '{"force": false}'
```

Response:

```json
{
  "job_id": "idx_456",
  "session_id": "abc-123",
  "status": "pending",
  "created_at": "2026-01-30T16:00:05Z"
}
```

**Step 3: Poll for progress**

```bash
curl http://localhost:8000/api/sessions/abc-123/index/jobs/idx_456
```

Response (after 30 seconds):

```json
{
  "job_id": "idx_456",
  "status": "running",
  "progress": 0.45,
  "metrics": {
    "files_processed": 256,
    "total_files": 567,
    "chunks_created": 1045,
    "elapsed_seconds": 30,
    "estimated_remaining_seconds": 37
  }
}
```

**Step 4: Search once indexed**

```bash
curl -X POST http://localhost:8000/api/sessions/abc-123/search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "how does token refresh work",
    "limit": 5,
    "similarity_threshold": 0.75
  }'
```

Response:

```json
{
  "query": "how does token refresh work",
  "session_id": "abc-123",
  "status": "success",
  "search_time_ms": 47,
  "total_results": 12,
  "result_count": 5,
  "results": [
    {
      "rank": 1,
      "similarity_score": 0.94,
      "file_path": "src/auth/oauth2.py",
      "chunk_name": "refresh_token",
      "start_line": 42,
      "end_line": 67,
      "code_snippet": "def refresh_token(token: str) -> str:\n    ...",
      "docstring": "Refresh an expired OAuth2 token..."
    }
  ]
}
```

---

## 7. Security Considerations

### 7.1 Session ID Validation

- **Format**: UUID v4
- **Validation**: Regex check + database existence
- **Replay protection**: Not needed (stateless REST)
- **Spoofing prevention**: Server-side validation only

### 7.2 Query Injection Prevention

- **User queries** → Embedded as vectors only (not interpreted)
- **No SQL injection risk** (ChromaDB handles SQL)
- **File path traversal**: Validate paths are within session workspace

```python
def validate_file_path(session_id: str, file_path: str) -> Path:
    session = Session.query.get(session_id)
    session_root = Path(session.workspace_path)

    requested = (session_root / file_path).resolve()

    # Prevent traversal above session root
    if not str(requested).startswith(str(session_root)):
        raise HTTPException(status_code=403, detail="Path traversal denied")

    return requested
```

### 7.3 Rate Limiting

Recommended:

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter

@app.post("/api/sessions/{session_id}/search")
@limiter.limit("100/minute")  # 100 searches per minute per IP
async def search(session_id: str, req: SearchRequest):
    ...
```

### 7.4 Audit Logging

Required for Research-Mind:

```python
# research-mind-service/app/logging/audit.py

class AuditLog(BaseModel):
    timestamp: datetime
    session_id: str
    user_id: Optional[str]
    action: str  # "search", "index_start", "index_complete"
    query: Optional[str]  # For searches
    result_count: Optional[int]
    duration_ms: Optional[int]
    status: str  # "success", "failed"
    error: Optional[str]

def log_search(session_id: str, query: str, result_count: int, duration_ms: int):
    audit = AuditLog(
        timestamp=datetime.utcnow(),
        session_id=session_id,
        action="search",
        query=query,
        result_count=result_count,
        duration_ms=duration_ms,
        status="success"
    )
    db.session.add(audit)
    db.session.commit()
```

---

## 8. Minimal Security Considerations

- ✓ No API keys/auth (assume network-scoped access for now)
- ✓ Session IDs are UUIDs (not sequential/guessable)
- ✓ File paths validated to session workspace
- ✓ Queries embedded as vectors (no injection risk)
- ✓ Audit logging planned (not MVP)

---

## 9. Implementation Checklist

### Phase 1: MVP (Core REST API)

- [ ] FastAPI service structure created
- [ ] Session CRUD endpoints
- [ ] Indexing endpoints (async job model)
- [ ] Search endpoint with session_id enforcement
- [ ] Per-session collection support in mcp-vector-search
- [ ] Basic error handling
- [ ] Integration tests

### Phase 2: Enhancements

- [ ] Job cancellation
- [ ] Advanced filtering
- [ ] Statistics endpoint
- [ ] Health checks
- [ ] Rate limiting
- [ ] Audit logging

### Phase 3: Production

- [ ] Auth/RBAC
- [ ] WebSocket progress streaming
- [ ] Multi-instance deployment
- [ ] Distributed job queue (Redis/Celery)
- [ ] Comprehensive monitoring

---

## 10. Summary

| Aspect           | Details                                                        |
| ---------------- | -------------------------------------------------------------- |
| **Architecture** | Wrapper service (FastAPI) around mcp-vector-search library     |
| **Scoping**      | Per-session collections in shared ChromaDB                     |
| **Enforcement**  | Server-side session_id validation on all endpoints             |
| **Jobs**         | Async job model with progress tracking and cancellation        |
| **Search**       | Mandatory session_id, optional filters, similarity threshold   |
| **Metadata**     | File path, language, type, parent, line numbers, docstrings    |
| **Isolation**    | Separate collections, metadata dirs, and workspace directories |
| **Auditability** | Logging plan for searches, indexing, administrative actions    |

---

## References

### Files to Create/Modify

**research-mind-service**:

- `app/routes/vector_search.py` - New endpoints
- `app/schemas/vector_search.py` - Pydantic models
- `app/services/session_indexer.py` - Session-scoped wrapper
- `app/services/job_queue.py` - Job management
- `app/middleware/session_validation.py` - Session enforcement

**mcp-vector-search**:

- No changes required (use as library)
- Confirm `collection_name` parameter in `CollectionManager.__init__`

### Deployment

```dockerfile
# research-mind-service/Dockerfile
FROM python:3.11
RUN pip install fastapi uvicorn mcp-vector-search
COPY . /app
WORKDIR /app
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Environment variables**:

```
RESEARCH_MIND_SESSION_DIR=/var/lib/research-mind/sessions
MCP_VECTOR_SEARCH_MODEL=sentence-transformers/all-MiniLM-L6-v2
```
