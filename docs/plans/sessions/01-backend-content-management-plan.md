# Implementation Plan: Backend Session Content Management

> **Status**: Ready for implementation
> **Design Doc**: `docs/designs/sessions/01-backend-session-content-architecture.md`
> **Service**: research-mind-service (FastAPI, Python 3.12, SQLAlchemy 2.0, Alembic, PostgreSQL 18)
> **Date**: 2026-02-01

---

## Prerequisites

Before starting implementation, verify:

- [ ] Design document at `docs/designs/sessions/01-backend-session-content-architecture.md` is approved
- [ ] PostgreSQL database is running and `alembic upgrade head` is current
- [ ] `uv run pytest -v` passes with all existing tests green
- [ ] Working directory: `research-mind-service/`

---

## Phase B-1: Foundation (Configuration + Database)

**Goal**: Add content sandbox configuration, create the `content_items` database table, and ensure the sandbox directory is created at startup.

### B-1.1 Add `content_sandbox_root` to Settings

**Description**: Add the `content_sandbox_root` configuration field to the `Settings` class. This is the root directory where all session content files are stored, separate from `workspace_root` (which is used for indexing only). Also add all content retrieval limit/timeout settings so retrievers can read from `settings` instead of hardcoding constants.

**Design doc reference**: Section 10 (Configuration Additions)

**Files to modify**:
- `app/core/config.py`

**Changes**:

Add the following fields to the `Settings` class, after the `workspace_root` field (line 39):

```python
# --- Content Sandbox ---
# Root directory for session content storage (separate from workspace)
# Development: ./content_sandboxes (relative to service root)
# Production: Override via CONTENT_SANDBOX_ROOT env var
content_sandbox_root: str = "./content_sandboxes"

# --- Content Retrieval Limits ---
max_upload_bytes: int = 50 * 1024 * 1024          # 50 MB
max_text_bytes: int = 10 * 1024 * 1024             # 10 MB
max_url_response_bytes: int = 20 * 1024 * 1024     # 20 MB
max_workspace_bytes: int = 500 * 1024 * 1024       # 500 MB per session
url_fetch_timeout: int = 30                         # seconds
git_clone_timeout: int = 120                        # seconds
git_clone_depth: int = 1                            # shallow clone depth
allowed_upload_extensions: str = ".pdf,.docx,.txt,.md,.csv,.html,.json,.xml"
```

**Dependencies**: None

**Acceptance criteria**:
- `from app.core.config import settings; settings.content_sandbox_root` returns `"./content_sandboxes"`
- All retrieval limit fields are accessible via `settings.<field_name>`
- Existing tests still pass (`uv run pytest -v`)

**Estimated effort**: Small (< 30 min)

---

### B-1.2 Add `CONTENT_SANDBOX_ROOT` to `.env.example`

**Description**: Document the new environment variable in the `.env.example` template so developers know to configure it.

**Design doc reference**: Section 10 (Configuration Additions)

**Files to modify**:
- `.env.example`

**Changes**:

Add after the `WORKSPACE_ROOT` block (after line 22):

```bash
# --- Content Sandbox ---
# Root directory where session content files are stored (separate from workspace)
# Development: ./content_sandboxes (relative to service root)
# Production: /var/lib/research-mind/content_sandboxes (or custom path with permissions)
CONTENT_SANDBOX_ROOT=./content_sandboxes

# --- Content Retrieval Limits ---
MAX_UPLOAD_BYTES=52428800
MAX_TEXT_BYTES=10485760
MAX_URL_RESPONSE_BYTES=20971520
MAX_WORKSPACE_BYTES=524288000
URL_FETCH_TIMEOUT=30
GIT_CLONE_TIMEOUT=120
GIT_CLONE_DEPTH=1
ALLOWED_UPLOAD_EXTENSIONS=.pdf,.docx,.txt,.md,.csv,.html,.json,.xml
```

**Dependencies**: B-1.1

**Acceptance criteria**:
- `.env.example` contains `CONTENT_SANDBOX_ROOT` with a comment explaining its purpose
- All retrieval limit env vars are documented

**Estimated effort**: Small (< 30 min)

---

### B-1.3 Add startup logic to create content sandbox directory

**Description**: Ensure the `content_sandbox_root` directory exists when the application starts. Add this to the existing `lifespan` async context manager in `app/main.py`, alongside the existing workspace/database startup logic.

**Design doc reference**: Section 4 (Sandbox Directory Structure)

**Files to modify**:
- `app/main.py`

**Changes**:

Inside the `lifespan()` function, after the database table creation block (around line 73), add:

```python
# Ensure content sandbox root directory exists
import os
content_sandbox = settings.content_sandbox_root
os.makedirs(content_sandbox, exist_ok=True)
logger.info("Content sandbox root ensured at %s", os.path.abspath(content_sandbox))
```

Note: `os` is already imported at the top of `main.py` (via `subprocess`). Import is not needed if `os` is already available; check and add only if necessary.

**Dependencies**: B-1.1

**Acceptance criteria**:
- Starting the service creates `./content_sandboxes/` if it does not exist
- Starting the service does not fail if `./content_sandboxes/` already exists
- Log message confirms the directory path
- Existing tests still pass

**Estimated effort**: Small (< 30 min)

---

### B-1.4 Create `ContentItem` SQLAlchemy model

**Description**: Create the `ContentItem` ORM model with `ContentType` and `ContentStatus` enums. This model represents a piece of content added to a research session, tracking its type, lifecycle status, storage location, and metadata.

**Design doc reference**: Section 3.1 (SQLAlchemy Model), Section 3.2 (Column Rationale), Section 3.3 (Enum Values Stored as Strings)

**Files to create**:
- `app/models/content_item.py`

**Implementation**: Use the exact code from Design Doc Section 3.1. Key design decisions:
- `content_type` and `status` stored as `String` columns (not PostgreSQL ENUM) to follow existing project pattern (`Session.status`)
- `content_id` is a UUID primary key, also used as subdirectory name in the sandbox
- `session_id` FK references `sessions.session_id` with `ondelete="CASCADE"`
- `metadata_json` uses `JSON` column type for flexible per-content-type metadata
- Three indexes: `idx_content_session_id`, `idx_content_status`, `idx_content_type`

```python
# app/models/content_item.py
# Copy exact code from Design Doc Section 3.1 (lines 79-191 of design doc)
```

**Dependencies**: None

**Acceptance criteria**:
- File `app/models/content_item.py` exists with `ContentItem`, `ContentType`, `ContentStatus`
- `ContentType` enum has values: `file_upload`, `text`, `url`, `git_repo`, `mcp_source`
- `ContentStatus` enum has values: `pending`, `processing`, `ready`, `error`
- Foreign key on `session_id` references `sessions.session_id` with CASCADE delete
- Three indexes defined in `__table_args__`

**Estimated effort**: Small (< 30 min)

---

### B-1.5 Register model in `app/models/__init__.py`

**Description**: Import `ContentItem` in the models package `__init__.py` so that Alembic's autogenerate can discover it when creating migrations.

**Design doc reference**: Section 11 (File Structure, Modified files)

**Files to modify**:
- `app/models/__init__.py`

**Changes**:

Add to existing imports:

```python
from app.models.content_item import ContentItem  # noqa: F401
```

The current file contains:
```python
"""ORM models package."""

from app.models.audit_log import AuditLog  # noqa: F401
from app.models.session import Session  # noqa: F401
```

After modification:
```python
"""ORM models package."""

from app.models.audit_log import AuditLog  # noqa: F401
from app.models.content_item import ContentItem  # noqa: F401
from app.models.session import Session  # noqa: F401
```

**Dependencies**: B-1.4

**Acceptance criteria**:
- `from app.models import ContentItem` works without error
- `Base.metadata.tables` includes `"content_items"` when models are imported

**Estimated effort**: Small (< 30 min)

---

### B-1.6 Generate Alembic migration

**Description**: Auto-generate an Alembic migration for the new `content_items` table.

**Design doc reference**: Section 14 (Migration Strategy)

**Commands**:
```bash
cd research-mind-service
uv run alembic revision --autogenerate -m "Add content_items table"
```

**Files created**:
- `migrations/versions/xxx_add_content_items_table.py` (auto-generated)

**Post-generation review checklist**:
- [ ] Table name is `content_items`
- [ ] All columns match the model definition (content_id, session_id, content_type, title, source_ref, storage_path, status, error_message, size_bytes, mime_type, metadata_json, created_at, updated_at)
- [ ] Foreign key references `sessions.session_id` with `ondelete="CASCADE"`
- [ ] Three indexes created: `idx_content_session_id`, `idx_content_status`, `idx_content_type`
- [ ] `downgrade()` drops indexes before dropping table
- [ ] No unexpected additional operations (e.g., modifying existing tables)

**Dependencies**: B-1.4, B-1.5

**Acceptance criteria**:
- Migration file exists in `migrations/versions/`
- Migration content matches expected schema from Design Doc Section 14

**Estimated effort**: Small (< 30 min)

---

### B-1.7 Verify migration applies cleanly

**Description**: Apply the migration and verify the database schema is correct.

**Commands**:
```bash
cd research-mind-service
uv run alembic upgrade head
uv run alembic current
```

**Rollback strategy**: If migration fails or produces incorrect schema:
```bash
uv run alembic downgrade -1
```
Then fix the migration file and re-apply.

**Dependencies**: B-1.6

**Acceptance criteria**:
- `alembic upgrade head` completes without errors
- `alembic current` shows the new migration as current head
- Database contains `content_items` table with all expected columns and indexes
- `alembic downgrade -1` successfully removes the table (test rollback, then re-apply)

**Estimated effort**: Small (< 30 min)

---

### Phase B-1 Verification

```bash
cd research-mind-service
uv run pytest -v                          # All existing tests pass
uv run alembic current                    # Shows latest migration
uv run python -c "from app.models import ContentItem; print(ContentItem.__tablename__)"
# Should print: content_items
uv run python -c "from app.core.config import settings; print(settings.content_sandbox_root)"
# Should print: ./content_sandboxes
```

---

## Phase B-2: Retriever Framework

**Goal**: Build the pluggable content retriever system -- base protocol, factory, and all five retriever implementations.

### B-2.1 Create retrievers package `__init__.py`

**Description**: Create the `app/services/retrievers/` package with an empty `__init__.py`.

**Design doc reference**: Section 11 (File Structure)

**Files to create**:
- `app/services/retrievers/__init__.py`

**Content**: Empty file or minimal docstring:
```python
"""Pluggable content retriever implementations."""
```

**Dependencies**: None

**Acceptance criteria**:
- `app/services/retrievers/` directory exists with `__init__.py`

**Estimated effort**: Small (< 30 min)

---

### B-2.2 Create `base.py` with `RetrievalResult` and `ContentRetriever` Protocol

**Description**: Define the `RetrievalResult` frozen dataclass and `ContentRetriever` typing Protocol. These form the contract that all retrievers implement.

**Design doc reference**: Section 5.1 (Base Protocol)

**Files to create**:
- `app/services/retrievers/base.py`

**Implementation**: Use the exact code from Design Doc Section 5.1. Key points:
- `RetrievalResult` is a `@dataclass(frozen=True)` with fields: `success`, `storage_path`, `size_bytes`, `mime_type`, `title`, `metadata`, `error_message`
- `ContentRetriever` is a `Protocol` with a single `retrieve()` method
- The `retrieve()` method accepts keyword-only arguments: `source`, `target_dir`, `title`, `metadata`

**Dependencies**: None

**Acceptance criteria**:
- `from app.services.retrievers.base import RetrievalResult, ContentRetriever` works
- `RetrievalResult` is frozen (immutable after creation)
- `ContentRetriever` is a Protocol (can be used for structural subtyping)

**Estimated effort**: Small (< 30 min)

---

### B-2.3 Create `factory.py` with `get_retriever()` factory function

**Description**: Implement the retriever factory that maps `ContentType` values to retriever classes and instantiates them.

**Design doc reference**: Section 5.3 (Retriever Factory)

**Files to create**:
- `app/services/retrievers/factory.py`

**Implementation**: Use the exact code from Design Doc Section 5.3. The `_REGISTRY` dict maps content type string values to retriever classes. `get_retriever()` raises `ValueError` for unknown content types.

Note: This file imports all retriever classes, so it should be created after the retrievers themselves, or simultaneously. For implementation ordering, create the factory file last among the retriever files, or stub imports that will be filled in subsequent tasks.

**Dependencies**: B-2.2, B-2.4, B-2.5, B-2.6, B-2.7, B-2.8 (imports all retrievers)

**Acceptance criteria**:
- `get_retriever("text")` returns a `TextRetriever` instance
- `get_retriever("file_upload")` returns a `FileUploadRetriever` instance
- `get_retriever("url")` returns a `UrlRetriever` instance
- `get_retriever("git_repo")` returns a `GitRepoRetriever` instance
- `get_retriever("mcp_source")` returns a `McpSourceRetriever` instance
- `get_retriever("unknown")` raises `ValueError`

**Estimated effort**: Small (< 30 min)

---

### B-2.4 Create `text_retriever.py` -- `TextRetriever`

**Description**: Implement the retriever for raw text content. Accepts a text string, writes `content.txt` and `metadata.json` to the target directory.

**Design doc reference**: Section 5.2 (TextRetriever)

**Files to create**:
- `app/services/retrievers/text_retriever.py`

**Implementation**: Use the exact code from Design Doc Section 5.2. Key behavior:
- Validates text size against `MAX_TEXT_BYTES` (10 MB). Note: In a follow-up, this constant should be replaced with `settings.max_text_bytes` for configurability.
- Writes `content.txt` with UTF-8 encoding
- Writes `metadata.json` with title and any extra metadata
- Returns `RetrievalResult` with `mime_type="text/plain"`

**Dependencies**: B-2.2

**Acceptance criteria**:
- `TextRetriever().retrieve(source="hello", target_dir=tmp_path)` creates `content.txt` and `metadata.json`
- `content.txt` contains the exact source text
- Returns `success=True` with correct `size_bytes`
- Rejects text exceeding 10 MB with `success=False`

**Estimated effort**: Small (< 30 min)

---

### B-2.5 Create `file_upload.py` -- `FileUploadRetriever`

**Description**: Implement the retriever for multipart file uploads. Accepts raw bytes and an original filename, writes the file to the target directory.

**Design doc reference**: Section 5.2 (FileUploadRetriever)

**Files to create**:
- `app/services/retrievers/file_upload.py`

**Implementation**: Use the exact code from Design Doc Section 5.2. Key behavior:
- Validates file size against `MAX_UPLOAD_BYTES` (50 MB)
- Detects MIME type from filename using `mimetypes.guess_type()`
- Writes the file with the original filename to `target_dir`
- Returns metadata with `original_filename`

**Dependencies**: B-2.2

**Acceptance criteria**:
- `FileUploadRetriever().retrieve(source=b"data", target_dir=tmp_path, metadata={"original_filename": "test.pdf"})` creates `test.pdf`
- Returns `success=True` with correct `size_bytes` and `mime_type`
- Rejects files exceeding 50 MB with `success=False`
- Uses "upload" as default filename when `original_filename` not provided

**Estimated effort**: Small (< 30 min)

---

### B-2.6 Create `url_retriever.py` -- `UrlRetriever`

**Description**: Implement the retriever for URL content. Uses `httpx` to fetch URL content and stores it as `content.md` with `metadata.json`.

**Design doc reference**: Section 5.2 (UrlRetriever)

**External dependency**: Requires `httpx` package. Verify it is in `pyproject.toml`; if not, add it:
```bash
uv add httpx
```

**Files to create**:
- `app/services/retrievers/url_retriever.py`

**Implementation**: Use the exact code from Design Doc Section 5.2. Key behavior:
- Uses `httpx.Client` with configurable timeout and `follow_redirects=True`
- Sets `User-Agent: research-mind/0.1`
- Validates response size against `MAX_RESPONSE_BYTES` (20 MB)
- Handles `HTTPStatusError` and `RequestError` gracefully
- Writes `content.md` (raw response bytes) and `metadata.json`
- Extracts MIME type from `content-type` header

**Dependencies**: B-2.2

**Acceptance criteria**:
- Successfully fetches a URL and writes content/metadata files
- Returns appropriate error for HTTP errors (4xx, 5xx)
- Returns appropriate error for connection failures
- Returns appropriate error for responses exceeding size limit
- Respects timeout configuration

**Estimated effort**: Medium (30-60 min)

---

### B-2.7 Create `git_repo.py` -- `GitRepoRetriever`

**Description**: Implement the retriever for git repository cloning. Uses `subprocess.run()` to perform a shallow clone.

**Design doc reference**: Section 5.2 (GitRepoRetriever)

**Files to create**:
- `app/services/retrievers/git_repo.py`

**Implementation**: Use the exact code from Design Doc Section 5.2. Key behavior:
- Runs `git clone --depth 1 --single-branch <url> <repo_dir>`
- Clones into `target_dir/repo/` subdirectory
- Configurable timeout (default 120s) and depth (default 1)
- Handles `TimeoutExpired`, `FileNotFoundError` (git not on PATH), and non-zero exit codes
- Calculates total bytes by walking the cloned directory
- Writes `metadata.json` with clone URL, depth, and total bytes
- Derives title from clone URL if not provided

**Dependencies**: B-2.2

**Acceptance criteria**:
- Successfully clones a public git repo (integration test with real repo or mocked subprocess)
- Returns appropriate error for timeout
- Returns appropriate error when `git` CLI is not found
- Returns appropriate error for non-zero exit code (e.g., invalid URL)
- Calculates correct `size_bytes` from cloned files

**Estimated effort**: Medium (30-60 min)

---

### B-2.8 Create `mcp_source.py` -- `McpSourceRetriever` (stub)

**Description**: Create a placeholder retriever for MCP-based content sources. Always returns `success=False` with "not yet implemented" message.

**Design doc reference**: Section 5.2 (McpSourceRetriever)

**Files to create**:
- `app/services/retrievers/mcp_source.py`

**Implementation**: Use the exact code from Design Doc Section 5.2. This is a stub that will be implemented when MCP protocol integration is defined.

**Dependencies**: B-2.2

**Acceptance criteria**:
- `McpSourceRetriever().retrieve(source="mcp://...", target_dir=tmp_path)` returns `success=False`
- Error message indicates MCP retrieval is not yet implemented

**Estimated effort**: Small (< 30 min)

---

### B-2.9 Unit tests for all retrievers

**Description**: Write comprehensive unit tests for each retriever, testing both success and error paths.

**Design doc reference**: Section 15 (Testing Strategy, Unit Tests: Retrievers)

**Files to create**:
- `tests/test_retrievers.py`

**Test cases**:

```python
# TextRetriever tests
def test_text_retriever_writes_content(tmp_path):
    """Design Doc Section 15: test_text_retriever_writes_content"""

def test_text_retriever_rejects_oversized(tmp_path):
    """Text exceeding MAX_TEXT_BYTES returns success=False."""

def test_text_retriever_writes_metadata(tmp_path):
    """metadata.json contains title and extra metadata."""

def test_text_retriever_default_title(tmp_path):
    """Title defaults to 'Untitled text' when not provided."""

# FileUploadRetriever tests
def test_file_upload_writes_file(tmp_path):
    """Uploaded bytes are written with original filename."""

def test_file_upload_rejects_oversized(tmp_path):
    """Design Doc Section 15: test_file_upload_retriever_rejects_oversized"""

def test_file_upload_detects_mime_type(tmp_path):
    """MIME type is guessed from filename extension."""

def test_file_upload_default_filename(tmp_path):
    """Uses 'upload' when original_filename not in metadata."""

# UrlRetriever tests
def test_url_retriever_success(tmp_path, monkeypatch_or_respx):
    """Mocked HTTP GET returns content, written to content.md."""

def test_url_retriever_http_error(tmp_path):
    """HTTP 404 returns success=False with status code in error."""

def test_url_retriever_connection_error(tmp_path):
    """Connection failure returns success=False."""

def test_url_retriever_oversized_response(tmp_path):
    """Response exceeding MAX_RESPONSE_BYTES returns success=False."""

# GitRepoRetriever tests
def test_git_repo_handles_missing_git(tmp_path, monkeypatch):
    """Design Doc Section 15: monkeypatch subprocess.run to raise FileNotFoundError"""

def test_git_repo_handles_clone_failure(tmp_path, monkeypatch):
    """Non-zero exit code returns success=False with stderr."""

def test_git_repo_handles_timeout(tmp_path, monkeypatch):
    """TimeoutExpired returns success=False."""

def test_git_repo_derives_title_from_url(tmp_path, monkeypatch):
    """Title derived from clone URL when not provided."""

# McpSourceRetriever tests
def test_mcp_source_returns_not_implemented(tmp_path):
    """Always returns success=False with not-implemented message."""

# Factory tests
def test_factory_returns_correct_retriever():
    """get_retriever() returns correct class for each content type."""

def test_factory_raises_for_unknown_type():
    """get_retriever('unknown') raises ValueError."""
```

**Dependencies**: B-2.2 through B-2.8

**Acceptance criteria**:
- All retriever tests pass: `uv run pytest tests/test_retrievers.py -v`
- Each retriever has at least 2 tests (success + error case)
- Factory tests cover all content types plus unknown type error
- No external network calls (use mocks/monkeypatch for URL and git retrievers)

**Estimated effort**: Large (1-2 hrs)

---

### Phase B-2 Verification

```bash
cd research-mind-service
uv run pytest tests/test_retrievers.py -v  # All retriever tests pass
uv run pytest -v                            # All existing tests still pass
uv run python -c "from app.services.retrievers.factory import get_retriever; print(get_retriever('text'))"
# Should print: <app.services.retrievers.text_retriever.TextRetriever object at ...>
```

---

## Phase B-3: Service Layer

**Goal**: Build the content service business logic, Pydantic schemas, and integrate with existing audit and session services.

### B-3.1 Create Pydantic schemas in `app/schemas/content.py`

**Description**: Define `AddContentRequest`, `ContentItemResponse`, and `ContentListResponse` Pydantic models for request validation and response serialization.

**Design doc reference**: Section 7 (Pydantic Schemas)

**Files to create**:
- `app/schemas/content.py`

**Implementation**: Use the exact code from Design Doc Section 7. Key points:
- `AddContentRequest`: fields `content_type` (required), `title` (optional, max 512), `source` (optional, max 2048), `metadata` (optional dict)
- `ContentItemResponse`: mirrors all `ContentItem` model fields, uses `ConfigDict(from_attributes=True)`
- `ContentListResponse`: `items` list + `count` integer

**Dependencies**: None

**Acceptance criteria**:
- `AddContentRequest(content_type="text", source="hello")` validates successfully
- `AddContentRequest(content_type="text", title="x" * 513)` raises validation error
- `ContentItemResponse` can be constructed from a dict with all required fields
- `ContentListResponse` accepts a list of `ContentItemResponse` and a count

**Estimated effort**: Small (< 30 min)

---

### B-3.2 Create `app/services/content_service.py`

**Description**: Implement the content service with `add_content()`, `list_content()`, `get_content()`, and `delete_content()` functions. This is the core business logic layer that orchestrates retriever execution, database operations, and file management.

**Design doc reference**: Section 6.1 (ContentService)

**Files to create**:
- `app/services/content_service.py`

**Implementation**: Use the code from Design Doc Section 6.1. Key behavior:

1. **`add_content()`**:
   - Validates session exists via `_get_session_or_raise()`
   - Creates `ContentItem` record with `status=pending`
   - Creates content subdirectory at `{content_sandbox_root}/{session_id}/{content_id}/`
   - Updates status to `processing`, runs retriever
   - Updates record with result (`ready` or `error`)
   - Logs via `AuditService.log_content_add()`
   - Returns 201 even on retriever failure (error captured in status)

2. **`list_content()`**: Paginated query filtered by session_id, ordered by `created_at desc`

3. **`get_content()`**: Single item lookup by session_id + content_id

4. **`delete_content()`**:
   - Removes files from `{content_sandbox_root}/{session_id}/{content_id}/` via `shutil.rmtree()`
   - Deletes DB record
   - Logs via `AuditService.log_content_delete()`

**Dependencies**: B-1.4, B-2.3, B-3.1, B-3.3

**Acceptance criteria**:
- `add_content()` creates a DB record and sandbox directory
- `add_content()` returns `ContentItemResponse` with `status=ready` for successful retrieval
- `add_content()` returns `ContentItemResponse` with `status=error` for failed retrieval (NOT an HTTP error)
- `list_content()` returns paginated results
- `get_content()` returns None for non-existent content
- `delete_content()` removes both DB record and filesystem directory

**Estimated effort**: Large (1-2 hrs)

---

### B-3.3 Add audit methods to `app/services/audit_service.py`

**Description**: Add `log_content_add()` and `log_content_delete()` static methods to the existing `AuditService` class.

**Design doc reference**: Section 6.2 (Integration with Existing Services, AuditService additions)

**Files to modify**:
- `app/services/audit_service.py`

**Changes**: Add two new methods after the existing `log_failed_request()` method (around line 189):

```python
@staticmethod
def log_content_add(
    db: Session, session_id: str, content_id: str,
    content_type: str, status: str,
) -> None:
    AuditService._create_entry(
        db, session_id, "content_add",
        metadata_json={
            "content_id": content_id,
            "content_type": content_type,
            "status": status,
        },
    )

@staticmethod
def log_content_delete(
    db: Session, session_id: str, content_id: str,
) -> None:
    AuditService._create_entry(
        db, session_id, "content_delete",
        metadata_json={"content_id": content_id},
    )
```

**Dependencies**: None

**Acceptance criteria**:
- `AuditService.log_content_add(db, "sid", "cid", "text", "ready")` creates an audit log entry with action `"content_add"`
- `AuditService.log_content_delete(db, "sid", "cid")` creates an audit log entry with action `"content_delete"`
- Exceptions are swallowed (existing `_create_entry` behavior)

**Estimated effort**: Small (< 30 min)

---

### B-3.4 Add `update_session()` to `app/services/session_service.py`

**Description**: Implement the `update_session()` function that allows updating a session's name, description, or status. The `UpdateSessionRequest` schema already exists in `app/schemas/session.py`.

**Design doc reference**: Section 8.2 (Session Update Endpoint)

**Files to modify**:
- `app/services/session_service.py`

**Changes**: Add a new function after `list_sessions()` and before `delete_session()`:

```python
def update_session(
    db: DbSession, session_id: str, request: UpdateSessionRequest
) -> SessionResponse | None:
    """Update mutable fields on a session."""
    session = db.query(Session).filter(Session.session_id == session_id).first()
    if session is None:
        return None

    if request.name is not None:
        session.name = request.name
    if request.description is not None:
        session.description = request.description
    if request.status is not None:
        session.status = request.status

    session.mark_accessed()
    db.commit()
    db.refresh(session)

    return _build_response(session)
```

Also add the import for `UpdateSessionRequest`:

```python
from app.schemas.session import CreateSessionRequest, SessionResponse, UpdateSessionRequest
```

**Dependencies**: None (schema already exists)

**Acceptance criteria**:
- `update_session(db, session_id, UpdateSessionRequest(name="New Name"))` updates only the name
- Returns `None` for non-existent session
- `last_accessed` is updated on every call
- Only non-None fields are updated (partial update)

**Estimated effort**: Small (< 30 min)

---

### B-3.5 Update `delete_session()` to clean up content sandbox

**Description**: Modify the existing `delete_session()` function in `session_service.py` to also remove the session's content sandbox directory (`{content_sandbox_root}/{session_id}/`). The database CASCADE will handle deleting `ContentItem` records, but the files on disk need explicit cleanup.

**Design doc reference**: Section 6.2 (Integration with Existing Services, SessionService changes)

**Files to modify**:
- `app/services/session_service.py`

**Changes**: In the `delete_session()` function, after the workspace cleanup block (around line 104), add:

```python
# Clean up content sandbox directory
from pathlib import Path
content_sandbox_dir = Path(settings.content_sandbox_root) / session_id
if content_sandbox_dir.is_dir():
    shutil.rmtree(content_sandbox_dir, ignore_errors=True)
    logger.info("Removed content sandbox directory %s", content_sandbox_dir)
```

Note: `shutil` is already imported. `settings` is already imported. `Path` import can go at the top of the file.

**Dependencies**: B-1.1

**Acceptance criteria**:
- Deleting a session removes `{content_sandbox_root}/{session_id}/` if it exists
- Deleting a session that has no content sandbox directory does not error
- Existing workspace cleanup still works
- Both workspace and content sandbox are cleaned up

**Estimated effort**: Small (< 30 min)

---

### Phase B-3 Verification

```bash
cd research-mind-service
uv run pytest -v                            # All tests pass
uv run python -c "from app.schemas.content import AddContentRequest; print(AddContentRequest(content_type='text', source='hi'))"
uv run python -c "from app.services.content_service import add_content; print('content_service imported OK')"
```

---

## Phase B-4: API Routes

**Goal**: Create the content CRUD endpoints, add the session PATCH endpoint, register routes, and update response schemas.

### B-4.1 Create `app/routes/content.py` -- Content CRUD endpoints

**Description**: Implement the four content management endpoints: POST (add), GET list, GET single, DELETE.

**Design doc reference**: Section 8.1 (Content Routes), Section 9 (API Request/Response Examples)

**Files to create**:
- `app/routes/content.py`

**Implementation**: Use the code from Design Doc Section 8.1. Key design decisions:

- All endpoints are nested under `/api/v1/sessions/{session_id}/content`
- POST uses `Form(...)` parameters (not JSON body) to support multipart file uploads alongside metadata
- File upload is optional (`UploadFile | None = File(None)`)
- POST returns 201 with `ContentItemResponse`
- GET list returns `ContentListResponse` with pagination
- GET single returns `ContentItemResponse` or 404
- DELETE returns 204 No Content or 404

**Important**: The POST endpoint receives `content_type`, `title`, and `source` as form fields (not JSON), because multipart forms cannot mix JSON body with file upload. The route constructs an `AddContentRequest` from the form fields.

**Dependencies**: B-3.1, B-3.2

**Acceptance criteria**:
- `POST /api/v1/sessions/{id}/content/` with form data creates content
- `POST /api/v1/sessions/{id}/content/` with file upload creates file content
- `GET /api/v1/sessions/{id}/content/` returns paginated list
- `GET /api/v1/sessions/{id}/content/{content_id}` returns single item or 404
- `DELETE /api/v1/sessions/{id}/content/{content_id}` returns 204 or 404
- All error responses use the standard `{"detail": {"error": {"code": ..., "message": ...}}}` format

**Estimated effort**: Medium (30-60 min)

---

### B-4.2 Add PATCH endpoint to `app/routes/sessions.py`

**Description**: Add the `PATCH /api/v1/sessions/{session_id}` endpoint using the existing `UpdateSessionRequest` schema and the new `update_session()` service function.

**Design doc reference**: Section 8.2 (Session Update Endpoint)

**Files to modify**:
- `app/routes/sessions.py`

**Changes**:

Add import for `UpdateSessionRequest`:
```python
from app.schemas.session import (
    CreateSessionRequest,
    SessionListResponse,
    SessionResponse,
    UpdateSessionRequest,
)
```

Add the PATCH route after the GET single endpoint (after line 56):

```python
@router.patch("/{session_id}", response_model=SessionResponse)
def update_session(
    session_id: str,
    request: UpdateSessionRequest,
    db: Session = Depends(get_db),
) -> SessionResponse:
    """Update a session's name, description, or status."""
    result = session_service.update_session(db, session_id, request)
    if result is None:
        raise HTTPException(
            status_code=404,
            detail={
                "error": {
                    "code": "SESSION_NOT_FOUND",
                    "message": f"Session '{session_id}' not found",
                }
            },
        )
    return result
```

**Dependencies**: B-3.4

**Acceptance criteria**:
- `PATCH /api/v1/sessions/{id}` with `{"name": "New"}` updates the session name
- Returns 404 for non-existent session
- Partial updates work (only provided fields are changed)

**Estimated effort**: Small (< 30 min)

---

### B-4.3 Register content router in `app/main.py`

**Description**: Import and register the content router in the FastAPI application.

**Design doc reference**: Section 8.3 (Route Registration)

**Files to modify**:
- `app/main.py`

**Changes**:

Add import (around line 24, with other router imports):
```python
from app.routes.content import router as content_router
```

Add router registration (around line 170, after the audit router):
```python
# Content management routes (prefixed with /api/v1/sessions/{session_id}/content)
app.include_router(content_router)
```

**Dependencies**: B-4.1

**Acceptance criteria**:
- Content endpoints appear in OpenAPI docs at `http://localhost:15010/docs`
- All content routes are accessible and return expected responses

**Estimated effort**: Small (< 30 min)

---

### B-4.4 Update `SessionResponse` schema to include `content_count`

**Description**: Add a `content_count` field to `SessionResponse` so the UI can display how many content items a session has without a separate API call.

**Design doc reference**: Section 8.4 (Endpoint Summary) -- implied by the session management design

**Files to modify**:
- `app/schemas/session.py` -- add `content_count: int = 0` field
- `app/services/session_service.py` -- populate `content_count` in `_build_response()`

**Changes to `app/schemas/session.py`**:

Add to `SessionResponse`:
```python
content_count: int = 0
```

**Changes to `app/services/session_service.py`**:

Update `_build_response()` to query content count:
```python
from app.models.content_item import ContentItem

def _build_response(session: Session, db: DbSession | None = None) -> SessionResponse:
    """Convert an ORM Session into a SessionResponse with is_indexed."""
    content_count = 0
    if db is not None:
        content_count = (
            db.query(ContentItem)
            .filter(ContentItem.session_id == session.session_id)
            .count()
        )
    return SessionResponse(
        session_id=session.session_id,
        name=session.name,
        description=session.description,
        workspace_path=session.workspace_path,
        created_at=session.created_at,
        last_accessed=session.last_accessed,
        status=session.status,
        archived=session.archived,
        ttl_seconds=session.ttl_seconds,
        is_indexed=session.is_indexed(),
        content_count=content_count,
    )
```

Note: This requires passing `db` to `_build_response()` in all callers (`create_session`, `get_session`, `list_sessions`, `update_session`). Update all call sites to pass `db`.

**Dependencies**: B-1.4, B-3.4

**Acceptance criteria**:
- `GET /api/v1/sessions/{id}` response includes `content_count` field
- `content_count` reflects the actual number of content items for the session
- Sessions with no content show `content_count: 0`
- Existing session tests still pass (default value 0)

**Estimated effort**: Medium (30-60 min)

---

### Phase B-4 Verification

```bash
cd research-mind-service
uv run pytest -v                            # All tests pass
# Start the server and verify endpoints in OpenAPI docs:
# uv run uvicorn app.main:app --port 15010 --reload
# Open http://localhost:15010/docs and verify content endpoints appear
```

---

## Phase B-5: Integration Tests

**Goal**: Write comprehensive integration tests that exercise the full request lifecycle through the API endpoints.

### B-5.1 Create `tests/test_content.py` -- endpoint integration tests

**Description**: Write integration tests for all content endpoints: add text, add file upload, list, get single, delete. Uses the same `TestClient` + SQLite pattern as existing tests.

**Design doc reference**: Section 15 (Testing Strategy, Integration Tests: Content Endpoints)

**Files to create**:
- `tests/test_content.py`

**Test fixture setup**: The test file needs its own `client` fixture (following the pattern in existing test files like `test_sessions.py`), or use the `shared_client` and `create_session` fixtures from `conftest.py`. The content sandbox root must be overridden to a temp directory.

**Test cases**:

```python
# --- Setup ---
# Override settings.content_sandbox_root to tmp_path
# Create a session via the API before each content test

# --- Add content tests ---
def test_add_text_content(client, session_id):
    """POST text content returns 201 with status=ready."""

def test_add_file_upload(client, session_id):
    """POST with file returns 201 with original filename in metadata."""

def test_add_url_content_mocked(client, session_id, monkeypatch):
    """POST URL content with mocked httpx returns 201."""

def test_add_content_invalid_session(client):
    """POST to non-existent session returns 404."""

def test_add_content_invalid_type(client, session_id):
    """POST with unknown content_type returns error status."""

# --- List content tests ---
def test_list_content_empty(client, session_id):
    """GET list for session with no content returns empty list."""

def test_list_content_with_items(client, session_id):
    """GET list returns all added items with correct count."""

def test_list_content_pagination(client, session_id):
    """GET list respects limit and offset parameters."""

# --- Get content tests ---
def test_get_content(client, session_id, content_id):
    """GET single content item returns full details."""

def test_get_content_not_found(client, session_id):
    """GET non-existent content returns 404."""

# --- Delete content tests ---
def test_delete_content(client, session_id, content_id):
    """DELETE returns 204 and removes from list."""

def test_delete_content_not_found(client, session_id):
    """DELETE non-existent content returns 404."""
```

**Dependencies**: B-4.1, B-4.3

**Acceptance criteria**:
- All tests pass: `uv run pytest tests/test_content.py -v`
- Tests cover happy path and error cases for all four endpoints
- Content sandbox override prevents tests from writing to real directories

**Estimated effort**: Large (1-2 hrs)

---

### B-5.2 Test session deletion cascades content items

**Description**: Verify that deleting a session via `DELETE /api/v1/sessions/{id}` also removes all associated content items from the database (via CASCADE) and from the filesystem.

**Design doc reference**: Section 6.2 (SessionService changes)

**Files to modify**:
- `tests/test_content.py` (add test case)

**Test case**:

```python
def test_session_delete_cascades_content(client, create_session):
    """Deleting a session removes all its content items."""
    # 1. Create session
    session = create_session(client, "Cascade Test")
    session_id = session["session_id"]

    # 2. Add content
    client.post(f"/api/v1/sessions/{session_id}/content/",
                data={"content_type": "text", "source": "test data", "title": "Note"})

    # 3. Verify content exists
    resp = client.get(f"/api/v1/sessions/{session_id}/content/")
    assert resp.json()["count"] == 1

    # 4. Delete session
    resp = client.delete(f"/api/v1/sessions/{session_id}")
    assert resp.status_code == 204

    # 5. Verify session gone
    resp = client.get(f"/api/v1/sessions/{session_id}")
    assert resp.status_code == 404
```

**Dependencies**: B-5.1

**Acceptance criteria**:
- Test passes
- Content items are removed from DB when session is deleted

**Estimated effort**: Small (< 30 min)

---

### B-5.3 Test content sandbox directory cleanup on session delete

**Description**: Verify that the content sandbox directory (`{content_sandbox_root}/{session_id}/`) is removed when a session is deleted.

**Files to modify**:
- `tests/test_content.py` (add test case)

**Test case**:

```python
def test_session_delete_cleans_content_sandbox(client, create_session, tmp_content_sandbox):
    """Deleting a session removes its content sandbox directory."""
    session = create_session(client, "Sandbox Cleanup Test")
    session_id = session["session_id"]

    # Add content (creates sandbox directory)
    client.post(f"/api/v1/sessions/{session_id}/content/",
                data={"content_type": "text", "source": "test", "title": "Note"})

    # Verify sandbox exists
    sandbox_dir = Path(tmp_content_sandbox) / session_id
    assert sandbox_dir.is_dir()

    # Delete session
    client.delete(f"/api/v1/sessions/{session_id}")

    # Verify sandbox removed
    assert not sandbox_dir.exists()
```

**Dependencies**: B-5.1, B-3.5

**Acceptance criteria**:
- Test passes
- Content sandbox directory is removed from filesystem

**Estimated effort**: Small (< 30 min)

---

### B-5.4 Test error cases

**Description**: Test edge cases: invalid session ID, invalid content type, file too large.

**Files to modify**:
- `tests/test_content.py` (add test cases)

**Test cases**:

```python
def test_add_content_to_nonexistent_session(client):
    """POST to non-existent session returns 404 SESSION_NOT_FOUND."""
    resp = client.post(
        "/api/v1/sessions/00000000-0000-4000-8000-000000000000/content/",
        data={"content_type": "text", "source": "test"},
    )
    assert resp.status_code == 404
    assert resp.json()["detail"]["error"]["code"] == "SESSION_NOT_FOUND"

def test_add_oversized_file(client, session_id):
    """Uploading a file exceeding MAX_UPLOAD_BYTES returns error status."""
    # Create a file just over the limit
    # Note: with default 50MB limit, this test may be slow; consider lowering
    # the limit in test settings or testing the retriever directly

def test_add_content_mcp_returns_error(client, session_id):
    """MCP source content type returns status=error (stub)."""
    resp = client.post(
        f"/api/v1/sessions/{session_id}/content/",
        data={"content_type": "mcp_source", "source": "mcp://test"},
    )
    assert resp.status_code == 201
    assert resp.json()["status"] == "error"
    assert "not yet implemented" in resp.json()["error_message"]
```

**Dependencies**: B-5.1

**Acceptance criteria**:
- All error case tests pass
- Error responses follow the standard error format

**Estimated effort**: Medium (30-60 min)

---

### B-5.5 Test content sandbox isolation between sessions

**Description**: Verify that content from one session does not appear in another session's content list or sandbox directory.

**Files to modify**:
- `tests/test_content.py` (add test case)

**Test case**:

```python
def test_content_isolation_between_sessions(client, create_session):
    """Content items are isolated per session."""
    # Create two sessions
    s1 = create_session(client, "Session 1")
    s2 = create_session(client, "Session 2")

    # Add content to session 1
    client.post(f"/api/v1/sessions/{s1['session_id']}/content/",
                data={"content_type": "text", "source": "s1 data", "title": "S1 Note"})

    # Session 2 should have no content
    resp = client.get(f"/api/v1/sessions/{s2['session_id']}/content/")
    assert resp.json()["count"] == 0

    # Session 1 should have 1 item
    resp = client.get(f"/api/v1/sessions/{s1['session_id']}/content/")
    assert resp.json()["count"] == 1
```

**Dependencies**: B-5.1

**Acceptance criteria**:
- Test passes
- Content items are correctly scoped to their session

**Estimated effort**: Small (< 30 min)

---

### Phase B-5 Verification

```bash
cd research-mind-service
uv run pytest tests/test_content.py -v      # All content tests pass
uv run pytest tests/test_retrievers.py -v   # All retriever tests pass
uv run pytest -v                            # ALL tests pass (including existing)
```

---

## Phase B-6: Contract + Documentation

**Goal**: Update the API contract to include all new endpoints and schemas, sync with the frontend, and verify everything passes.

### B-6.1 Update `docs/api-contract.md` to v1.2.0

**Description**: Add all new content management endpoints and schemas to the API contract. Bump version from 1.1.0 to 1.2.0 (minor version bump for new endpoints, no breaking changes).

**Design doc reference**: Section 8.4 (Endpoint Summary), Section 9 (API Request/Response Examples), Section 12 (Error Handling Strategy)

**Files to modify**:
- `research-mind-service/docs/api-contract.md`

**Changes**:

1. Update version header: `1.1.0` -> `1.2.0`
2. Add "Content Management" section to Table of Contents
3. Add `ContentItem` schema definition (TypeScript interface)
4. Add `ContentListResponse` schema
5. Add `AddContentRequest` schema (note: form fields, not JSON body)
6. Document all five endpoints:
   - `POST /api/v1/sessions/{session_id}/content` (201)
   - `GET /api/v1/sessions/{session_id}/content` (200)
   - `GET /api/v1/sessions/{session_id}/content/{content_id}` (200)
   - `DELETE /api/v1/sessions/{session_id}/content/{content_id}` (204)
   - `PATCH /api/v1/sessions/{session_id}` (200)
7. Add new error codes: `CONTENT_NOT_FOUND`, `INVALID_CONTENT_TYPE`, `FILE_TOO_LARGE`, `UNSUPPORTED_FILE_TYPE`, `RETRIEVAL_FAILED`, `RETRIEVAL_TIMEOUT`, `WORKSPACE_FULL`
8. Add `content_count` field to Session schema
9. Add new status codes: 201 (content created), 413 (file too large), 415 (unsupported file type)
10. Add changelog entry for v1.2.0

**Dependencies**: B-4.1, B-4.2, B-4.4

**Acceptance criteria**:
- Contract version is `1.2.0`
- All new endpoints are documented with request/response examples
- All new error codes are listed
- Session schema includes `content_count`
- Changelog has v1.2.0 entry

**Estimated effort**: Large (1-2 hrs)

---

### B-6.2 Copy updated contract to frontend

**Description**: Synchronize the API contract with the frontend project.

**Commands**:
```bash
cp research-mind-service/docs/api-contract.md research-mind-ui/docs/api-contract.md
```

**Dependencies**: B-6.1

**Acceptance criteria**:
- Both `api-contract.md` files are byte-identical
- Verify with: `diff research-mind-service/docs/api-contract.md research-mind-ui/docs/api-contract.md`

**Estimated effort**: Small (< 30 min)

---

### B-6.3 Run full test suite

**Description**: Execute all tests and verify nothing is broken.

**Commands**:
```bash
cd research-mind-service
uv run pytest -v
```

**Dependencies**: B-6.2

**Acceptance criteria**:
- All tests pass with zero failures
- No warnings related to new code

**Estimated effort**: Small (< 30 min)

---

### B-6.4 Run linting and type checking

**Description**: Verify code quality across all new and modified files.

**Commands**:
```bash
cd research-mind-service
uv run ruff check app tests
uv run mypy app
```

**Dependencies**: B-6.3

**Acceptance criteria**:
- `ruff check` reports no errors
- `mypy` reports no type errors in new files
- No formatting issues (`uv run black --check app tests`)

**Estimated effort**: Small (< 30 min)

---

### Phase B-6 Verification

```bash
cd research-mind-service
uv run pytest -v                            # All tests pass
uv run ruff check app tests                 # No lint errors
uv run mypy app                             # No type errors
diff docs/api-contract.md ../research-mind-ui/docs/api-contract.md  # Identical
```

---

## Summary: Task Dependency Graph

```
B-1.1 (config) ─────────────┐
B-1.2 (.env) ← B-1.1        │
B-1.3 (startup) ← B-1.1     │
B-1.4 (model) ───────────── ─┤
B-1.5 (init) ← B-1.4        │
B-1.6 (migration) ← B-1.5   │
B-1.7 (verify) ← B-1.6      │
                              │
B-2.1 (pkg init) ────────────┤
B-2.2 (base) ────────────── ─┤
B-2.4 (text) ← B-2.2        │
B-2.5 (file) ← B-2.2        │
B-2.6 (url) ← B-2.2         │
B-2.7 (git) ← B-2.2         │
B-2.8 (mcp) ← B-2.2         │
B-2.3 (factory) ← B-2.4..8  │
B-2.9 (tests) ← B-2.3       │
                              │
B-3.1 (schemas) ─────────── ─┤
B-3.3 (audit) ───────────── ─┤
B-3.4 (update svc) ──────── ─┤
B-3.5 (delete cleanup) ← B-1.1
B-3.2 (content svc) ← B-1.4, B-2.3, B-3.1, B-3.3
                              │
B-4.1 (content routes) ← B-3.1, B-3.2
B-4.2 (PATCH route) ← B-3.4  │
B-4.3 (register) ← B-4.1    │
B-4.4 (content_count) ← B-1.4, B-3.4
                              │
B-5.1..5 (tests) ← B-4.1, B-4.3
                              │
B-6.1 (contract) ← B-4.*    │
B-6.2 (copy) ← B-6.1        │
B-6.3 (test suite) ← B-6.2  │
B-6.4 (lint) ← B-6.3        │
```

---

## External Package Dependencies

| Package | Version | Phase | Purpose |
|---------|---------|-------|---------|
| `httpx` | latest | B-2.6 | HTTP client for URL retrieval |

**Check if already in `pyproject.toml`**:
```bash
grep httpx pyproject.toml
```

If not present:
```bash
uv add httpx
```

---

## Rollback Strategy

### Database Migration Rollback

If the `content_items` migration causes issues:

```bash
cd research-mind-service
uv run alembic downgrade -1     # Remove content_items table
uv run alembic current          # Verify previous migration is current
```

### Code Rollback

All new files can be deleted and modified files reverted via git:

```bash
# New files to remove:
git checkout -- app/models/content_item.py
git checkout -- app/schemas/content.py
git checkout -- app/services/content_service.py
git checkout -- app/services/retrievers/
git checkout -- app/routes/content.py
git checkout -- tests/test_content.py
git checkout -- tests/test_retrievers.py

# Modified files to revert:
git checkout -- app/models/__init__.py
git checkout -- app/services/audit_service.py
git checkout -- app/services/session_service.py
git checkout -- app/routes/sessions.py
git checkout -- app/core/config.py
git checkout -- app/main.py
git checkout -- .env.example
git checkout -- docs/api-contract.md
```

---

## Total Estimated Effort

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| B-1: Foundation | 7 tasks | ~2-3 hours |
| B-2: Retrievers | 9 tasks | ~4-5 hours |
| B-3: Service Layer | 5 tasks | ~3-4 hours |
| B-4: API Routes | 4 tasks | ~2-3 hours |
| B-5: Integration Tests | 5 tasks | ~3-4 hours |
| B-6: Contract + Docs | 4 tasks | ~2-3 hours |
| **Total** | **34 tasks** | **~16-22 hours** |

---

## Files Created (New)

| File | Phase |
|------|-------|
| `app/models/content_item.py` | B-1.4 |
| `app/schemas/content.py` | B-3.1 |
| `app/services/content_service.py` | B-3.2 |
| `app/services/retrievers/__init__.py` | B-2.1 |
| `app/services/retrievers/base.py` | B-2.2 |
| `app/services/retrievers/factory.py` | B-2.3 |
| `app/services/retrievers/text_retriever.py` | B-2.4 |
| `app/services/retrievers/file_upload.py` | B-2.5 |
| `app/services/retrievers/url_retriever.py` | B-2.6 |
| `app/services/retrievers/git_repo.py` | B-2.7 |
| `app/services/retrievers/mcp_source.py` | B-2.8 |
| `app/routes/content.py` | B-4.1 |
| `tests/test_retrievers.py` | B-2.9 |
| `tests/test_content.py` | B-5.1 |
| `migrations/versions/xxx_add_content_items_table.py` | B-1.6 |

## Files Modified (Existing)

| File | Phase | Changes |
|------|-------|---------|
| `app/core/config.py` | B-1.1 | Add `content_sandbox_root` + retrieval limit settings |
| `.env.example` | B-1.2 | Add `CONTENT_SANDBOX_ROOT` + limit env vars |
| `app/main.py` | B-1.3, B-4.3 | Startup sandbox creation, register content router |
| `app/models/__init__.py` | B-1.5 | Add `ContentItem` import |
| `app/services/audit_service.py` | B-3.3 | Add `log_content_add()`, `log_content_delete()` |
| `app/services/session_service.py` | B-3.4, B-3.5, B-4.4 | Add `update_session()`, content sandbox cleanup, `content_count` |
| `app/routes/sessions.py` | B-4.2 | Add PATCH endpoint |
| `app/schemas/session.py` | B-4.4 | Add `content_count` field |
| `docs/api-contract.md` | B-6.1 | Bump to v1.2.0, add content endpoints |
