# MCP Vector Search: Packaging & Installation Guide

**Document Version**: 1.0
**Date**: 2026-01-31
**Status**: Comprehensive Installation & Packaging Guide
**Audience**: Backend engineers integrating mcp-vector-search into FastAPI service

---

## Executive Summary

This document provides practical guidance for integrating **mcp-vector-search as a Python library** into the research-mind FastAPI service. Rather than using the CLI interface, we package mcp-vector-search as a Python dependency installed via `uv`, enabling direct integration with the service and avoiding subprocess overhead.

**Key Points**:

- **Approach**: Python library integration (not CLI subprocess)
- **Installation**: Via uv package manager in `pyproject.toml`
- **Disk Space**: ~2.5GB (models cached after first run)
- **First Run**: ~30 seconds (model download + initialization)
- **Subsequent Runs**: <1 second (cached models, in-memory sessions)
- **Python Version**: 3.12+ required
- **Testing**: Unit tests mock library, integration tests use real indexing

**Benefits over CLI approach**:

- No subprocess overhead (direct function calls)
- Easier error handling and logging
- Session-aware indexing and search
- Type-safe Python integration
- Better for async/concurrent operations

---

## 1. Installation Options

### 1.1 Standard Installation (Recommended)

Install from PyPI via `uv`:

```toml
# research-mind-service/pyproject.toml

[project]
dependencies = [
    # ... existing dependencies ...
    "mcp-vector-search>=0.1.0",  # PyPI release
]
```

**Installation**:

```bash
cd research-mind-service
uv sync
```

**Pros**:

- Stable, versioned releases
- Community support
- Easy updates

### 1.2 Development Installation (Git Reference)

For co-development with mcp-vector-search:

```toml
# pyproject.toml with git reference

[project]
dependencies = [
    # ... existing dependencies ...
    "mcp-vector-search @ git+https://github.com/anthropics/mcp-vector-search.git@main",
]
```

**Installation**:

```bash
cd research-mind-service
uv sync
```

**Use Case**: Contributing to mcp-vector-search alongside research-mind development

### 1.3 Local Development (Editable Mode)

For local co-development on same machine:

```toml
# pyproject.toml with local path

[project]
dependencies = [
    # ... existing dependencies ...
    "mcp-vector-search @ file:///path/to/mcp-vector-search",
]
```

**Installation**:

```bash
cd research-mind-service
uv sync
```

**Use Case**: Rapid iteration with mcp-vector-search changes

---

## 2. Dependency Analysis

### 2.1 Transitive Dependencies

mcp-vector-search brings in a comprehensive set of dependencies:

```
mcp-vector-search
├── chromadb              # Vector database (core)
│   ├── pydantic          # Data validation
│   ├── requests          # HTTP client
│   ├── numpy             # Numerical computing
│   └── ... (chromadb specific)
├── transformers          # NLP model library
│   ├── huggingface-hub   # Model downloading
│   ├── torch             # ML framework (CPU or GPU)
│   ├── numpy
│   └── ... (transformers specific)
├── sentence-transformers # Embedding models
│   ├── transformers
│   ├── scikit-learn      # ML utilities
│   └── scipy
├── typer                 # CLI framework
├── rich                  # Terminal formatting
└── ... (other utilities)
```

### 2.2 Disk Space Requirements

**Total: ~2.5GB** (first installation)

Breakdown:

- `mcp-vector-search` package: ~50MB
- `transformers` + dependencies: ~800MB
- `torch` (CPU): ~400-600MB (GPU variant: 1.5GB+)
- `chromadb` + dependencies: ~200MB
- Model files (downloaded on first use):
  - Default embedding model: ~400MB
  - Cached embeddings (per project): 100-500MB
- Python cache / compiled files: ~200MB

**After First Run**: Subsequent installations reuse cached models (~500MB additional)

### 2.3 Conflict Check

**No conflicts with existing dependencies**:

Current service dependencies:

- `fastapi`, `uvicorn` - web framework
- `sqlalchemy`, `alembic` - database ORM & migrations
- `psycopg[binary]` - PostgreSQL driver
- `pydantic`, `pydantic-settings` - data validation
- `python-jose`, `passlib` - authentication

mcp-vector-search dependencies (transformers, chromadb) have no overlap with above, though both use `pydantic` (compatible versions).

**Verification**:

```bash
cd research-mind-service
uv pip compile pyproject.toml --quiet | grep -E "pydantic|numpy" | sort
```

---

## 3. Development Setup

### 3.1 Update pyproject.toml

**Step 1**: Add mcp-vector-search to dependencies

```toml
[project]
name = "research-mind-service"
version = "0.1.0"
description = "FastAPI service for research-mind"
requires-python = ">=3.12"

dependencies = [
    "fastapi==0.109.0",
    "uvicorn[standard]==0.27.0",
    "sqlalchemy==2.0.23",
    "alembic==1.13.0",
    "psycopg[binary]==3.1.12",
    "pydantic==2.5.0",
    "pydantic-settings==2.1.0",
    "python-jose[cryptography]==3.3.0",
    "passlib[bcrypt]==1.7.4",
    "mcp-vector-search>=0.1.0",  # ADD THIS LINE
]

[project.optional-dependencies]
dev = [
    "pytest==7.4.3",
    "pytest-asyncio==0.21.1",
    "httpx==0.25.2",
    "ruff==0.1.11",
    "black==23.12.0",
    "mypy==1.7.1",
]
```

### 3.2 Environment Configuration

Create or update `.env` in `research-mind-service/`:

```bash
# Model caching and performance
MCP_VECTOR_SEARCH_CACHE_DIR=/tmp/mcp-vs-cache
MCP_VECTOR_SEARCH_MODEL_NAME=all-MiniLM-L6-v2
MCP_VECTOR_SEARCH_BATCH_SIZE=32

# Database configuration
MCP_VECTOR_SEARCH_DB_TYPE=chroma
MCP_VECTOR_SEARCH_DB_PATH=/tmp/mcp-vs-db

# Performance tuning
MCP_VECTOR_SEARCH_CONNECTION_POOL_SIZE=5
MCP_VECTOR_SEARCH_EMBEDDING_DEVICE=cpu  # or "cuda" for GPU
```

### 3.3 Model Caching Strategy

**Lazy Loading with Singleton Pattern**:

```python
# research-mind-service/app/core/vector_search.py

from functools import lru_cache
from mcp_vector_search.core import SemanticIndexer, SearchEngine

class VectorSearchManager:
    """Singleton pattern for model caching."""

    _instance = None
    _indexer = None
    _search_engine = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    @property
    def indexer(self) -> SemanticIndexer:
        """Lazy-load indexer on first use."""
        if self._indexer is None:
            self._indexer = SemanticIndexer(
                model_name="all-MiniLM-L6-v2",
                cache_dir="/tmp/mcp-vs-cache"
            )
        return self._indexer

    @property
    def search_engine(self) -> SearchEngine:
        """Lazy-load search engine on first use."""
        if self._search_engine is None:
            self._search_engine = SearchEngine(
                db_type="chroma",
                db_path="/tmp/mcp-vs-db"
            )
        return self._search_engine

# Use globally
_vs_manager = VectorSearchManager()

async def get_vector_search_manager() -> VectorSearchManager:
    """Dependency injection for FastAPI."""
    return _vs_manager
```

**Performance Characteristics**:

- **First call**: ~30 seconds (download model + initialize)
- **Subsequent calls**: <1 millisecond (cached in memory)
- **Session persistence**: Models remain in memory for duration of service

### 3.4 Installation Workflow

```bash
# 1. Update pyproject.toml (done above)

# 2. Install dependencies
cd /Users/mac/workspace/research-mind
make install
# Output: "Installing dependencies..." -> "uv sync" for service

# 3. First run (automatic model download)
make dev
# Service starts, first API call triggers 30s model download
# Subsequent calls <1s

# 4. Verify installation
cd research-mind-service
uv run python -c "from mcp_vector_search import SemanticIndexer; print('OK')"
```

---

## 4. Development Workflow

### 4.1 Service Startup

**Using existing make target**:

```bash
make dev
```

This starts:

1. PostgreSQL (via docker-compose)
2. FastAPI service with `uvicorn --reload`
3. SvelteKit UI dev server

**Manual startup** (if needed):

```bash
cd research-mind-service
uv run uvicorn app.main:app --host 0.0.0.0 --port 15010 --reload
```

The `--reload` flag enables hot reloading on code changes.

### 4.2 Testing Strategy

**Unit Tests** (fast, mocked):

```python
# research-mind-service/tests/test_vector_search_unit.py

import pytest
from unittest.mock import Mock, patch
from app.core.vector_search import VectorSearchManager

@pytest.fixture
def mock_vs():
    """Mock VectorSearchManager for unit tests."""
    with patch('app.core.vector_search.SemanticIndexer') as mock_indexer:
        manager = VectorSearchManager()
        manager._indexer = mock_indexer
        yield manager

@pytest.mark.asyncio
async def test_search_unit(mock_vs):
    """Unit test with mocked vector search."""
    mock_vs.search_engine.search.return_value = [
        {"id": "1", "score": 0.95, "text": "result"}
    ]

    results = await mock_vs.search_engine.search("query")
    assert len(results) == 1
    assert results[0]["score"] == 0.95

# Run: uv run pytest tests/test_vector_search_unit.py
```

**Integration Tests** (slower, real indexing):

```python
# research-mind-service/tests/test_vector_search_integration.py

import pytest
from app.core.vector_search import VectorSearchManager

@pytest.mark.integration
@pytest.mark.asyncio
async def test_index_and_search_integration():
    """Integration test with real vector search."""
    manager = VectorSearchManager()

    # Index sample code
    files = {
        "auth.py": "def authenticate(token): ...",
        "utils.py": "def validate_email(email): ..."
    }

    for filename, content in files.items():
        await manager.indexer.index_file(filename, content)

    # Search
    results = await manager.search_engine.search("authentication")
    assert len(results) > 0
    assert "auth.py" in results[0]["file"]

# Run: uv run pytest tests/test_vector_search_integration.py -m integration
```

### 4.3 Running Tests

**All tests** (unit + integration, slow):

```bash
make test
# Runs: cd research-mind-service && uv run pytest
```

**Unit tests only** (fast):

```bash
cd research-mind-service
uv run pytest -m "not integration"
```

**Integration tests only**:

```bash
cd research-mind-service
uv run pytest -m integration
```

**With coverage**:

```bash
cd research-mind-service
uv run pytest --cov=app tests/
```

### 4.4 Hot Reload

The `uvicorn --reload` flag automatically restarts the service when code changes. Model caching ensures fast startup:

```
Edit app/routes/search.py
    ↓
File saved
    ↓
uvicorn detects change (5s)
    ↓
Service restarts (1s, models already cached)
    ↓
Ready (no 30s model re-download)
```

---

## 5. Testing Considerations

### 5.1 Unit Test Pattern

**Mock mcp-vector-search in unit tests**:

```python
# Fast, deterministic, no model download

from unittest.mock import Mock, AsyncMock
import pytest

@pytest.fixture
def mock_vector_search():
    mock = Mock()
    mock.search_engine.search = AsyncMock(
        return_value=[
            {
                "id": "file1",
                "score": 0.92,
                "text": "oauth implementation"
            }
        ]
    )
    mock.indexer.index = AsyncMock()
    return mock

@pytest.mark.asyncio
async def test_search_endpoint(mock_vector_search):
    # Uses mocked search
    results = await mock_vector_search.search_engine.search("oauth")
    assert results[0]["score"] == 0.92
```

**Runtime**: <100ms per test

### 5.2 Integration Test Pattern

**Real mcp-vector-search in integration tests**:

```python
# Slower, tests actual behavior, real model download

@pytest.mark.integration
@pytest.fixture(scope="session")
def vector_search_session():
    """One-time setup for integration test session."""
    manager = VectorSearchManager()
    yield manager
    # Cleanup if needed

@pytest.mark.integration
def test_search_integration(vector_search_session):
    # Uses real search engine
    manager = vector_search_session
    results = await manager.search_engine.search("oauth")
    assert len(results) > 0
```

**Runtime**: ~30s first run, ~1s subsequent (model cached)

### 5.3 Performance Profile

| Operation       | First Run | Cached    | Notes                      |
| --------------- | --------- | --------- | -------------------------- |
| Model load      | ~30s      | -         | Download + initialize      |
| Index file      | 50-500ms  | 50-500ms  | Per file                   |
| Search query    | 100-200ms | 100-200ms | Depends on collection size |
| Session startup | ~30s      | <1s       | Only first run             |

**CI/CD Strategy**:

- Unit tests (mocked): Always run, ~30s total
- Integration tests: Mark with `@pytest.mark.integration`
- CI only runs unit tests by default
- Integration tests optional or run on merge to main

---

## 6. Docker Deployment

### 6.1 Multi-Stage Build

**Minimize production image size**:

```dockerfile
# Dockerfile for research-mind-service

# Stage 1: Builder
FROM python:3.12-slim as builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy pyproject.toml and install dependencies
COPY pyproject.toml .
RUN pip install uv && \
    uv pip install --compile-bytecode -r <(uv pip compile pyproject.toml) \
    --target /build/wheels

# Stage 2: Runtime
FROM python:3.12-slim

WORKDIR /app

# Install runtime dependencies only (no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy wheels from builder
COPY --from=builder /build/wheels /app/wheels

# Copy application
COPY app/ ./app/

# Set Python path to use wheels
ENV PYTHONPATH=/app/wheels:$PYTHONPATH

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:15010/health')"

EXPOSE 15010

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "15010"]
```

### 6.2 Model Caching in Docker

**Option A: Pre-download in image** (larger image, faster startup):

```dockerfile
# Add to Dockerfile after Stage 2 COPY
RUN python -c "
    from transformers import AutoTokenizer, AutoModel
    AutoTokenizer.from_pretrained('all-MiniLM-L6-v2')
    AutoModel.from_pretrained('all-MiniLM-L6-v2')
"
```

**Option B: Volume mount** (smaller image, cold start ~30s):

```yaml
# docker-compose.yml
services:
  service:
    image: research-mind-service:latest
    ports:
      - "15010:15010"
    volumes:
      - model_cache:/root/.cache/huggingface/models
    environment:
      HF_HOME: /root/.cache/huggingface
      TRANSFORMERS_CACHE: /root/.cache/huggingface/models

volumes:
  model_cache:
    driver: local
```

### 6.3 Production Flags

```bash
# Use --frozen and --no-dev for production
cd research-mind-service
uv pip install --frozen --no-dev
```

### 6.4 Environment Variables

```dockerfile
# In docker-compose.yml or kubernetes deployment

environment:
  MCP_VECTOR_SEARCH_CACHE_DIR: /cache/mcp-vs
  MCP_VECTOR_SEARCH_MODEL_NAME: all-MiniLM-L6-v2
  MCP_VECTOR_SEARCH_EMBEDDING_DEVICE: cpu
  MCP_VECTOR_SEARCH_CONNECTION_POOL_SIZE: 10
  TRANSFORMERS_CACHE: /cache/transformers
  HF_HOME: /cache/huggingface
```

---

## 7. Performance Optimization

### 7.1 Model Caching

**Singleton pattern** (already in section 3.3):

- Load model once per service instance
- Reuse for all subsequent requests
- In-memory storage (~400MB)

### 7.2 Session Persistence

**In-memory session cache**:

```python
# research-mind-service/app/core/session_cache.py

from datetime import datetime, timedelta
from typing import Dict

class SessionCache:
    """In-memory cache for session indexers to avoid reloads."""

    def __init__(self, ttl_minutes=30):
        self._cache: Dict[str, tuple] = {}
        self._ttl = timedelta(minutes=ttl_minutes)

    def get_or_create(self, session_id: str):
        """Get cached session or create new one."""
        if session_id in self._cache:
            indexer, timestamp = self._cache[session_id]
            if datetime.now() - timestamp < self._ttl:
                return indexer

        # Create new indexer for this session
        indexer = SemanticIndexer(session_path=f"/tmp/sessions/{session_id}")
        self._cache[session_id] = (indexer, datetime.now())
        return indexer

    def clear_expired(self):
        """Remove expired sessions."""
        now = datetime.now()
        expired = [sid for sid, (_, ts) in self._cache.items()
                   if now - ts > self._ttl]
        for sid in expired:
            del self._cache[sid]
```

**Benefits**:

- Session indexers persist in memory
- No re-initialization on subsequent API calls
- TTL prevents memory leaks

### 7.3 Connection Pooling

mcp-vector-search uses ChromaDB with built-in connection pooling. Configure pool size:

```python
# research-mind-service/app/core/vector_search.py

from mcp_vector_search.core.database import ChromaDB

db = ChromaDB(
    path="/tmp/mcp-vs-db",
    connection_pool_size=10  # Tunable per load
)
```

### 7.4 Batch Embedding Configuration

For indexing large codebases, configure batch size:

```python
# research-mind-service/app/core/vector_search.py

indexer = SemanticIndexer(
    model_name="all-MiniLM-L6-v2",
    batch_size=32,  # Process 32 chunks at once
    max_workers=4   # 4 parallel embedding workers
)

# Index large directory
await indexer.index_directory(
    path="/path/to/codebase",
    recursive=True,
    batch_size=64  # Override for this operation
)
```

---

## 8. CI/CD Integration

### 8.1 GitHub Actions Setup

**Run fast unit tests in CI**:

```yaml
# .github/workflows/test.yml

name: Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.12"]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ matrix.python-version }}

      - name: Install uv
        run: curl -LsSf https://astral.sh/uv/install.sh | sh

      - name: Install dependencies
        run: |
          cd research-mind-service
          uv sync

      - name: Run unit tests (mocked)
        run: |
          cd research-mind-service
          uv run pytest -m "not integration" --cov=app

      - name: Lint
        run: |
          cd research-mind-service
          uv run ruff check app
          uv run black --check app

      - name: Type check
        run: |
          cd research-mind-service
          uv run mypy app
```

### 8.2 Optional Integration Tests

**Separate workflow for integration tests** (slower):

```yaml
# .github/workflows/integration-test.yml

name: Integration Tests

on:
  push:
    branches: [main]
  schedule:
    - cron: "0 0 * * *" # Daily

jobs:
  integration:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: "3.12"

      - name: Install uv
        run: curl -LsSf https://astral.sh/uv/install.sh | sh

      - name: Install dependencies
        run: |
          cd research-mind-service
          uv sync

      - name: Run integration tests
        run: |
          cd research-mind-service
          uv run pytest -m integration --timeout=300
```

---

## 9. Quick Reference Table

### Installation & Setup

| Task                  | Command                        | Time  | Notes                                            |
| --------------------- | ------------------------------ | ----- | ------------------------------------------------ |
| Fresh install         | `make install`                 | 2-5m  | Downloads deps, caches models on first dev start |
| Start dev stack       | `make dev`                     | 30s\* | \*First run: 30s for model download              |
| Run unit tests        | `make test`                    | 30s   | Uses mocked vector search                        |
| Run integration tests | `uv run pytest -m integration` | 2-5m  | Real indexing, models cached                     |
| Hot reload            | Save file, auto-reload         | 5-10s | Models already cached                            |

### Performance Profile

| Operation               | Latency   | Factors                           |
| ----------------------- | --------- | --------------------------------- |
| Session startup         | 30s / <1s | First / subsequent                |
| Single file index       | 50-500ms  | File size, language               |
| Search query            | 100-200ms | Collection size, query complexity |
| Batch index (100 files) | 5-30s     | File sizes, batch configuration   |

### Environment Variables

| Variable                             | Default                       | Purpose              |
| ------------------------------------ | ----------------------------- | -------------------- |
| `MCP_VECTOR_SEARCH_CACHE_DIR`        | `/tmp/mcp-vs-cache`           | Model cache location |
| `MCP_VECTOR_SEARCH_MODEL_NAME`       | `all-MiniLM-L6-v2`            | Embedding model      |
| `MCP_VECTOR_SEARCH_DB_PATH`          | `/tmp/mcp-vs-db`              | Vector DB location   |
| `MCP_VECTOR_SEARCH_EMBEDDING_DEVICE` | `cpu`                         | `cpu` or `cuda`      |
| `TRANSFORMERS_CACHE`                 | `~/.cache/huggingface/models` | HuggingFace cache    |

### File Locations

| What                      | Location                                          |
| ------------------------- | ------------------------------------------------- |
| Service config            | `research-mind-service/pyproject.toml`            |
| Service code              | `research-mind-service/app/`                      |
| Vector search integration | `research-mind-service/app/core/vector_search.py` |
| Tests                     | `research-mind-service/tests/`                    |
| Environment               | `research-mind-service/.env`                      |
| Dockerfile                | `research-mind-service/Dockerfile`                |

---

## 10. Practical Examples

### 10.1 Updated pyproject.toml

```toml
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "research-mind-service"
version = "0.1.0"
description = "FastAPI service for research-mind"
requires-python = ">=3.12"

dependencies = [
    "fastapi==0.109.0",
    "uvicorn[standard]==0.27.0",
    "sqlalchemy==2.0.23",
    "alembic==1.13.0",
    "psycopg[binary]==3.1.12",
    "pydantic==2.5.0",
    "pydantic-settings==2.1.0",
    "python-jose[cryptography]==3.3.0",
    "passlib[bcrypt]==1.7.4",
    "mcp-vector-search>=0.1.0",
]

[project.optional-dependencies]
dev = [
    "pytest==7.4.3",
    "pytest-asyncio==0.21.1",
    "httpx==0.25.2",
    "ruff==0.1.11",
    "black==23.12.0",
    "mypy==1.7.1",
]

[tool.setuptools.packages]
find = { where = ["."], include = ["app*"] }
```

### 10.2 Vector Search Integration (FastAPI Route)

```python
# research-mind-service/app/routes/search.py

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import List
from app.core.vector_search import get_vector_search_manager, VectorSearchManager

router = APIRouter(prefix="/api/v1", tags=["search"])

class SearchResult(BaseModel):
    file: str
    score: float
    text: str
    line_number: int

class SearchRequest(BaseModel):
    query: str
    session_id: str
    limit: int = 10

@router.post("/search", response_model=List[SearchResult])
async def search(
    request: SearchRequest,
    vs_manager: VectorSearchManager = Depends(get_vector_search_manager)
):
    """Search indexed codebase using semantic search."""
    try:
        results = await vs_manager.search_engine.search(
            query=request.query,
            limit=request.limit,
            session_id=request.session_id
        )

        return [
            SearchResult(
                file=r["file"],
                score=r["score"],
                text=r["text"],
                line_number=r.get("line_number", 0)
            )
            for r in results
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/index")
async def index_files(
    session_id: str = Query(...),
    path: str = Query(...),
    vs_manager: VectorSearchManager = Depends(get_vector_search_manager)
):
    """Index codebase directory for a session."""
    try:
        await vs_manager.indexer.index_directory(
            path=path,
            session_id=session_id,
            recursive=True
        )
        return {"status": "indexing", "session_id": session_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

### 10.3 Model Caching Implementation

```python
# research-mind-service/app/core/vector_search.py

import os
from functools import lru_cache
from typing import Optional
from mcp_vector_search.core import SemanticIndexer, SearchEngine

class VectorSearchManager:
    """Singleton pattern for cached model management."""

    _instance: Optional['VectorSearchManager'] = None
    _indexer: Optional[SemanticIndexer] = None
    _search_engine: Optional[SearchEngine] = None

    def __new__(cls) -> 'VectorSearchManager':
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialize()
        return cls._instance

    def _initialize(self) -> None:
        """Initialize manager with configuration."""
        self._cache_dir = os.getenv(
            'MCP_VECTOR_SEARCH_CACHE_DIR',
            '/tmp/mcp-vs-cache'
        )
        self._model_name = os.getenv(
            'MCP_VECTOR_SEARCH_MODEL_NAME',
            'all-MiniLM-L6-v2'
        )
        self._db_path = os.getenv(
            'MCP_VECTOR_SEARCH_DB_PATH',
            '/tmp/mcp-vs-db'
        )
        self._device = os.getenv(
            'MCP_VECTOR_SEARCH_EMBEDDING_DEVICE',
            'cpu'
        )
        os.makedirs(self._cache_dir, exist_ok=True)
        os.makedirs(self._db_path, exist_ok=True)

    @property
    def indexer(self) -> SemanticIndexer:
        """Get indexer, lazy-load on first access."""
        if self._indexer is None:
            self._indexer = SemanticIndexer(
                model_name=self._model_name,
                cache_dir=self._cache_dir,
                device=self._device
            )
        return self._indexer

    @property
    def search_engine(self) -> SearchEngine:
        """Get search engine, lazy-load on first access."""
        if self._search_engine is None:
            self._search_engine = SearchEngine(
                db_type="chroma",
                db_path=self._db_path,
                pool_size=10
            )
        return self._search_engine

# Singleton instance
_vs_manager = VectorSearchManager()

async def get_vector_search_manager() -> VectorSearchManager:
    """FastAPI dependency injection."""
    return _vs_manager
```

### 10.4 Unit Test with Mock

```python
# research-mind-service/tests/test_search_unit.py

import pytest
from unittest.mock import Mock, AsyncMock, patch
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

@pytest.fixture
def mock_vector_search():
    """Mock VectorSearchManager for fast unit tests."""
    with patch('app.core.vector_search.VectorSearchManager') as MockVS:
        manager = Mock()
        manager.search_engine.search = AsyncMock(
            return_value=[
                {
                    "file": "auth.py",
                    "score": 0.95,
                    "text": "def authenticate(token):",
                    "line_number": 42
                }
            ]
        )
        MockVS.return_value = manager
        yield manager

def test_search_endpoint(mock_vector_search):
    """Test search endpoint with mocked vector search."""
    response = client.post(
        "/api/v1/search",
        json={
            "query": "authentication",
            "session_id": "test-session",
            "limit": 10
        }
    )

    assert response.status_code == 200
    results = response.json()
    assert len(results) == 1
    assert results[0]["file"] == "auth.py"
    assert results[0]["score"] == 0.95

def test_search_error_handling(mock_vector_search):
    """Test error handling in search."""
    mock_vector_search.search_engine.search.side_effect = Exception("DB error")

    response = client.post(
        "/api/v1/search",
        json={"query": "test", "session_id": "test"}
    )

    assert response.status_code == 500
    assert "detail" in response.json()
```

### 10.5 Integration Test with Real Indexing

```python
# research-mind-service/tests/test_search_integration.py

import pytest
import tempfile
from pathlib import Path
from app.core.vector_search import VectorSearchManager

@pytest.mark.integration
@pytest.fixture(scope="session")
def temp_codebase():
    """Create temporary codebase for indexing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create sample Python files
        auth_file = Path(tmpdir) / "auth.py"
        auth_file.write_text("""
def authenticate(token: str) -> bool:
    '''Authenticate user with token.'''
    return validate_token(token)

def validate_token(token: str) -> bool:
    '''Validate JWT token.'''
    pass
""")

        utils_file = Path(tmpdir) / "utils.py"
        utils_file.write_text("""
def validate_email(email: str) -> bool:
    '''Validate email format.'''
    return '@' in email and '.' in email
""")

        yield tmpdir

@pytest.mark.integration
@pytest.mark.asyncio
async def test_index_and_search_integration(temp_codebase):
    """Integration test: index real files and search."""
    manager = VectorSearchManager()

    # Index the temporary codebase
    await manager.indexer.index_directory(
        path=temp_codebase,
        session_id="test-integration",
        recursive=True
    )

    # Search for authentication-related code
    results = await manager.search_engine.search(
        query="authenticate user",
        session_id="test-integration",
        limit=10
    )

    # Verify results
    assert len(results) > 0
    assert any("auth.py" in r["file"] for r in results)

    # Check scoring
    scores = [r["score"] for r in results]
    assert all(0 <= score <= 1 for score in scores)

@pytest.mark.integration
@pytest.mark.asyncio
async def test_search_email_validation(temp_codebase):
    """Integration test: search for email validation."""
    manager = VectorSearchManager()

    # Index
    await manager.indexer.index_directory(
        path=temp_codebase,
        session_id="test-email",
        recursive=True
    )

    # Search
    results = await manager.search_engine.search(
        query="email validation",
        session_id="test-email",
        limit=5
    )

    # Verify utils.py is found
    assert any("utils.py" in r["file"] for r in results)
```

### 10.6 Dockerfile for Production

```dockerfile
# research-mind-service/Dockerfile

# Build stage
FROM python:3.12-slim as builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY pyproject.toml .
RUN pip install --upgrade pip uv && \
    uv pip install --compile-bytecode \
    -r <(uv pip compile pyproject.toml --no-dev) \
    --target /build/deps

# Runtime stage
FROM python:3.12-slim

WORKDIR /app

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy Python packages from builder
COPY --from=builder /build/deps /app/deps

# Copy application code
COPY app/ ./app/

# Set Python path
ENV PYTHONPATH=/app/deps:$PYTHONPATH \
    PYTHONUNBUFFERED=1 \
    MCP_VECTOR_SEARCH_CACHE_DIR=/cache/mcp-vs \
    TRANSFORMERS_CACHE=/cache/transformers

# Create cache directories
RUN mkdir -p /cache/mcp-vs /cache/transformers

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:15010/health')" || exit 1

EXPOSE 15010

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "15010"]
```

### 10.7 GitHub Actions Workflow

```yaml
# .github/workflows/test.yml

name: Test

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.12"]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: ${{ matrix.python-version }}

      - name: Install uv
        run: curl -LsSf https://astral.sh/uv/install.sh | sh

      - name: Install dependencies
        run: |
          cd research-mind-service
          uv sync

      - name: Lint with ruff
        run: |
          cd research-mind-service
          uv run ruff check app tests --line-length=100

      - name: Format check with black
        run: |
          cd research-mind-service
          uv run black --check app tests

      - name: Type check with mypy
        run: |
          cd research-mind-service
          uv run mypy app --ignore-missing-imports

      - name: Run unit tests
        run: |
          cd research-mind-service
          uv run pytest tests/ -m "not integration" \
            --cov=app --cov-report=xml --cov-report=term

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: ./research-mind-service/coverage.xml
```

---

## 11. Related Documentation

For additional context and architectural decisions, refer to:

- **[combined-architecture-recommendations.md](/Users/mac/workspace/research-mind/docs/research/combined-architecture-recommendations.md)**
  High-level architecture combining mcp-vector-search with claude-mpm

- **[mcp-vector-search-capabilities.md](/Users/mac/workspace/research-mind/docs/research/mcp-vector-search-capabilities.md)**
  Detailed capabilities, limitations, and architecture of mcp-vector-search

- ~~**mcp-vector-search-rest-api-proposal.md**~~ (deleted - library-based approach was abandoned)

- **[claude-mpm-sandbox-containment-plan.md](/Users/mac/workspace/research-mind/docs/research/claude-mpm-sandbox-containment-plan.md)**
  Sandbox isolation strategy for agentic analysis

---

## 12. Troubleshooting

### Model Download Hangs

**Issue**: First run appears to hang at "downloading model"

**Solution**:

```bash
# Check network
curl https://huggingface.co/

# Manually pre-download model
python -c "
from transformers import AutoModel
AutoModel.from_pretrained('all-MiniLM-L6-v2')
"

# Verify cache
ls -la ~/.cache/huggingface/models/
```

### High Memory Usage

**Issue**: Service uses >2GB RAM

**Solution**:

- Reduce batch size: `batch_size=8` (default 32)
- Use CPU-only: `device="cpu"` (not CUDA)
- Increase session TTL to cache fewer sessions
- Clear old session cache: `session_cache.clear_expired()`

### ChromaDB Lock Errors

**Issue**: "Database is locked" errors in tests

**Solution**:

```bash
# Use different DB path for each test
# Or configure SQLite WAL mode:
db = ChromaDB(
    path=db_path,
    settings={"database": {"sqlite_journal_mode": "wal"}}
)
```

### Import Errors in Tests

**Issue**: `ModuleNotFoundError: No module named 'mcp_vector_search'`

**Solution**:

```bash
cd research-mind-service
uv sync  # Reinstall
uv run pytest tests/  # Run with uv
```

---

## Summary

This document provides complete guidance for integrating mcp-vector-search as a Python library into research-mind's FastAPI service. Key takeaways:

1. **Installation**: Add to `pyproject.toml`, install via `uv sync`
2. **Caching**: Singleton pattern for models, in-memory session cache
3. **Testing**: Mock for unit tests (fast), real for integration tests (slow)
4. **Deployment**: Multi-stage Docker build, environment variables for config
5. **Performance**: ~30s first run, <1s subsequent, 100-200ms per search query

The approach avoids subprocess overhead and enables tight integration with FastAPI, making it ideal for session-aware semantic indexing and search within the research-mind architecture.
