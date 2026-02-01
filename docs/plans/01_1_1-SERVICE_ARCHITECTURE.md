# Phase 1.1: Service Architecture Setup

**Subphase**: 1.1 of 8 (Phase 1)
**Duration**: 5-6 business days
**Effort**: 40-48 hours
**Team Size**: 2 FTE engineers
**Blocking**: 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8 (all subsequent phases)
**Prerequisite**: Phase 1.0 complete (mcp-vector-search installed)
**Status**: CRITICAL - Unblocks all other Phase 1 work

---

## Subphase Objective

Create FastAPI service scaffold with proper project structure and mcp-vector-search integration. Implement VectorSearchManager singleton that loads embedding model once per startup and caches for all subsequent requests.

**Success Definition**: FastAPI service running on port 15010 with:

- Health check endpoint working (`GET /api/health`)
- VectorSearchManager singleton initialized on startup
- Embedding model loaded (30s first run, cached afterward)
- All environment variables configurable
- Docker image builds successfully
- Service can start and shutdown cleanly

---

## Timeline & Effort

### Day 1-2: Project Structure & FastAPI Setup (16-20 hours)

- Create project skeleton
- Set up FastAPI app
- Configure middleware and error handling
- Implement health check endpoint

### Day 3-4: VectorSearchManager Singleton (12-16 hours)

- Design singleton pattern
- Integrate mcp-vector-search library
- Implement model caching strategy
- Add startup/shutdown hooks
- Test model loading performance

### Day 5-6: Configuration & Deployment (12-16 hours)

- Implement Pydantic Settings for configuration
- Create .env.example
- Build multi-stage Dockerfile
- Test Docker image build
- Documentation and cleanup

**Total Estimated**: 40-48 hours

---

## Deliverables

1. **research-mind-service/app/main.py** (150-200 lines)

   - FastAPI application entry point
   - Middleware configuration
   - Startup/shutdown hooks
   - Health check endpoint

2. **research-mind-service/app/core/vector_search.py** (200-300 lines)

   - VectorSearchManager singleton implementation
   - Lazy model loading
   - Error handling and recovery

3. **research-mind-service/app/core/config.py** (80-120 lines)

   - Pydantic Settings for environment configuration
   - Validation and defaults
   - Documentation of all configuration options

4. **research-mind-service/Dockerfile** (40-60 lines)

   - Multi-stage build
   - PyTorch and transformers included
   - Proper cache management

5. **research-mind-service/pyproject.toml** (updated)

   - mcp-vector-search dependency
   - FastAPI, uvicorn, SQLAlchemy, Pydantic dependencies
   - Development dependencies (pytest, black, mypy)

6. **research-mind-service/.env.example** (new)

   - Template for environment configuration
   - All required and optional variables documented

7. **Project directory structure**:
   ```
   research-mind-service/
   ├── app/
   │   ├── __init__.py
   │   ├── main.py                 # FastAPI entry point (NEW)
   │   ├── core/
   │   │   ├── __init__.py
   │   │   ├── vector_search.py   # VectorSearchManager (NEW)
   │   │   └── config.py          # Configuration (NEW)
   │   ├── routes/
   │   │   └── __init__.py
   │   ├── services/
   │   │   └── __init__.py
   │   ├── schemas/
   │   │   └── __init__.py
   │   ├── models/
   │   │   ├── __init__.py
   │   │   └── session.py         # Stub from Phase 1.0
   │   └── sandbox/
   │       └── __init__.py        # From Phase 1.0
   ├── tests/
   │   └── __init__.py
   ├── Dockerfile                  # Multi-stage build (NEW)
   ├── pyproject.toml             # Updated with deps (NEW)
   ├── .env.example               # Configuration template (NEW)
   └── README.md                  # TBD Phase 1.8
   ```

---

## Detailed Tasks

### Task 1.1.1: Create FastAPI Application Entry Point (6-8 hours)

**Objective**: Build FastAPI app with middleware, error handling, and startup hooks

#### Steps

1. **Create app/main.py**

```python
"""
FastAPI application entry point for research-mind service.

Manages:
- VectorSearchManager singleton initialization
- Middleware configuration
- Error handling
- Health checks
- Resource cleanup on shutdown
"""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import logging
import time

from app.core.config import settings
from app.core.vector_search import VectorSearchManager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="Research-Mind Service",
    description="Session-scoped agentic research system",
    version="1.0.0",
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global state
_vector_search_manager: VectorSearchManager = None


@app.on_event("startup")
async def startup():
    """Initialize VectorSearchManager singleton on service startup."""
    global _vector_search_manager

    logger.info("Initializing VectorSearchManager singleton...")
    start_time = time.time()

    try:
        _vector_search_manager = VectorSearchManager()
        duration = time.time() - start_time
        logger.info(f"✓ VectorSearchManager initialized in {duration:.1f}s")
    except Exception as e:
        logger.error(f"✗ Failed to initialize VectorSearchManager: {e}")
        raise


@app.on_event("shutdown")
async def shutdown():
    """Cleanup VectorSearchManager on service shutdown."""
    global _vector_search_manager

    if _vector_search_manager:
        logger.info("Shutting down VectorSearchManager...")
        try:
            # Clean up resources (close connections, etc.)
            _vector_search_manager.shutdown()
            logger.info("✓ VectorSearchManager shutdown complete")
        except Exception as e:
            logger.error(f"✗ Error during shutdown: {e}")


def get_vector_search_manager() -> VectorSearchManager:
    """Get VectorSearchManager singleton instance."""
    global _vector_search_manager
    if _vector_search_manager is None:
        raise RuntimeError("VectorSearchManager not initialized. Ensure startup completed.")
    return _vector_search_manager


# Health check endpoint
@app.get("/api/health")
async def health_check():
    """Health check endpoint for load balancers."""
    return {
        "status": "healthy",
        "service": "research-mind",
        "version": "1.0.0",
    }


# Error handlers
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler for unhandled errors."""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "detail": str(exc) if settings.debug else "An error occurred",
        },
    )


# Request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log all incoming requests."""
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    logger.info(
        f"{request.method} {request.url.path} - {response.status_code} ({duration:.3f}s)"
    )
    return response


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
    )
```

2. **Test FastAPI startup**
   ```bash
   cd research-mind-service
   python3 -c "from app.main import app; print('✓ FastAPI app imports successfully')"
   ```

**Success Criteria**:

- [ ] app/main.py created with 150-200 lines
- [ ] FastAPI app instantiated without errors
- [ ] Health check endpoint accessible (GET /api/health)
- [ ] Error handling middleware working
- [ ] Request logging working
- [ ] Startup/shutdown hooks defined

---

### Task 1.1.2: Implement VectorSearchManager Singleton (12-16 hours)

**Objective**: Create singleton that loads embedding model once and caches for all requests

#### Critical Architecture Pattern

From Phase 1.0 verification, we know:

- First model load: 2-3 minutes (includes ~400MB download to cache)
- Cached load: <1ms (in-memory reference)
- Must load exactly ONCE per service startup
- Must be thread-safe for concurrent requests

#### Steps

1. **Create app/core/vector_search.py**

```python
"""
VectorSearchManager singleton for mcp-vector-search integration.

Responsible for:
- Loading embedding model exactly once per service startup
- Managing ChromaDB instance (shared across sessions)
- Providing session-scoped indexer wrappers
- Resource cleanup on shutdown

Thread-safe singleton pattern ensures model loads exactly once.
"""

import logging
from typing import Optional
from pathlib import Path
import threading

from mcp_vector_search import Client
from mcp_vector_search.indexing import SemanticIndexer
from mcp_vector_search.search import SearchEngine

logger = logging.getLogger(__name__)


class VectorSearchManager:
    """
    Singleton manager for mpc-vector-search library.

    Loads embedding model on first access (lazy loading), then caches
    for all subsequent requests. Thread-safe for concurrent access.

    Performance Characteristics:
    - First initialization: ~30 seconds (downloads model if not cached)
    - Subsequent initializations: <1ms (loads from cache)
    - Memory usage: ~400MB (model) + ~100MB (ChromaDB)

    Attributes:
        client: mcp-vector-search Client instance
        indexer: SemanticIndexer instance
        search_engine: SearchEngine instance
    """

    _instance: Optional['VectorSearchManager'] = None
    _lock: threading.Lock = threading.Lock()

    def __new__(cls):
        """Ensure only one instance exists (thread-safe singleton)."""
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        """Initialize VectorSearchManager (lazy loading on first access)."""
        if self._initialized:
            return  # Already initialized, skip

        logger.info("Initializing VectorSearchManager...")

        try:
            # Initialize mcp-vector-search client
            # Model will be downloaded on first use (if not cached)
            self.client = Client()

            # Get indexer and search engine
            self.indexer = SemanticIndexer(client=self.client)
            self.search_engine = SearchEngine(client=self.client)

            logger.info("✓ VectorSearchManager initialized successfully")
            self._initialized = True

        except Exception as e:
            logger.error(f"✗ Failed to initialize VectorSearchManager: {e}")
            raise

    def shutdown(self):
        """Cleanup resources on service shutdown."""
        logger.info("Shutting down VectorSearchManager...")

        try:
            # Close any open connections
            if hasattr(self.client, 'close'):
                self.client.close()

            logger.info("✓ VectorSearchManager shutdown complete")
        except Exception as e:
            logger.error(f"✗ Error during shutdown: {e}")

    def get_session_indexer(self, session_id: str):
        """
        Get a SessionIndexer for a specific session.

        Creates a wrapper around SemanticIndexer that enforces
        session scoping via collection naming: session_{session_id}

        Args:
            session_id: UUID of the session

        Returns:
            SessionIndexer: Scoped indexer for the session
        """
        # Will be implemented in Phase 1.3
        # Returns wrapper with session-scoped collection
        from app.core.session_indexer import SessionIndexer
        return SessionIndexer(session_id=session_id, manager=self)

    def get_session_search(self, session_id: str):
        """
        Get a search engine scoped to a session.

        Args:
            session_id: UUID of the session

        Returns:
            Callable: Search function scoped to session collection
        """
        # Will be implemented in Phase 1.3
        # Returns search wrapper with session-scoped collection
        collection_name = f"session_{session_id}"

        async def search(query: str, top_k: int = 10):
            """Search within session collection."""
            return await self.search_engine.search(
                query=query,
                collection_name=collection_name,
                top_k=top_k,
            )

        return search
```

2. **Test Singleton Pattern**

   ```bash
   python3 << 'EOF'
   import time
   from app.core.vector_search import VectorSearchManager

   # First instantiation (loads model)
   print("First instantiation...")
   start = time.time()
   manager1 = VectorSearchManager()
   duration1 = time.time() - start
   print(f"Duration: {duration1:.1f}s")

   # Second instantiation (should be immediate)
   print("Second instantiation...")
   start = time.time()
   manager2 = VectorSearchManager()
   duration2 = time.time() - start
   print(f"Duration: {duration2:.3f}s")

   # Verify singleton
   assert manager1 is manager2, "Singleton pattern failed!"
   print("✓ Singleton pattern verified")

   # Cleanup
   manager1.shutdown()
   EOF
   ```

**Success Criteria**:

- [ ] VectorSearchManager singleton pattern implemented
- [ ] Thread-safe initialization (double-checked locking)
- [ ] Model loads on first instantiation (30s expected)
- [ ] Model cached on second instantiation (<1s)
- [ ] Same instance returned (singleton verified)
- [ ] Shutdown method cleans up resources

---

### Task 1.1.3: Implement Configuration System (6-8 hours)

**Objective**: Create Pydantic Settings for environment configuration

#### Steps

1. **Create app/core/config.py**

```python
"""
Configuration management using Pydantic Settings.

All configuration from environment variables, with sensible defaults.
Validates all settings on startup.
"""

from pydantic_settings import BaseSettings
from typing import List
import os


class Settings(BaseSettings):
    """Application settings from environment variables."""

    # Service Configuration
    host: str = "0.0.0.0"
    port: int = 15010
    debug: bool = False

    # Logging
    log_level: str = "INFO"

    # Database Configuration
    database_url: str = "sqlite:///./research_mind.db"
    database_echo: bool = False

    # mcp-vector-search Configuration
    # Model will be cached at these locations
    hf_cache_dir: str = os.path.expanduser("~/.cache/huggingface/")
    embeddings_model: str = "all-MiniLM-L6-v2"
    embeddings_device: str = "cpu"  # "cpu" or "cuda"

    # Session Configuration
    session_workspace_root: str = "/var/lib/research-mind/sessions/"
    session_max_duration_minutes: int = 60
    session_idle_timeout_minutes: int = 30

    # Vector Search Configuration
    chromadb_persist_dir: str = "/var/lib/research-mind/chromadb/"
    search_result_limit: int = 10
    search_timeout_seconds: int = 30

    # CORS Configuration
    cors_origins: List[str] = ["http://localhost:15000", "http://localhost:3000"]

    # Security Configuration
    path_validator_enabled: bool = True
    audit_logging_enabled: bool = True

    # Feature Flags
    enable_agent_integration: bool = True
    enable_caching: bool = False  # Phase 2
    enable_warm_pools: bool = False  # Phase 2

    class Config:
        """Pydantic Settings config."""
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


# Global settings instance
settings = Settings()


def validate_settings():
    """Validate settings on startup."""
    import logging
    logger = logging.getLogger(__name__)

    logger.info(f"Service Configuration:")
    logger.info(f"  Host: {settings.host}:{settings.port}")
    logger.info(f"  Database: {settings.database_url}")
    logger.info(f"  Debug: {settings.debug}")
    logger.info(f"  Workspace Root: {settings.session_workspace_root}")
    logger.info(f"  Model: {settings.embeddings_model}")

    # Create required directories
    from pathlib import Path

    for directory in [
        settings.session_workspace_root,
        settings.chromadb_persist_dir,
    ]:
        Path(directory).mkdir(parents=True, exist_ok=True)
        logger.info(f"  Created/verified directory: {directory}")
```

2. **Create .env.example**

```bash
# Service Configuration
HOST=0.0.0.0
PORT=15010
DEBUG=False
LOG_LEVEL=INFO

# Database Configuration
DATABASE_URL=postgresql://postgres:password@localhost:5432/research_mind  # pragma: allowlist secret
# Or use SQLite for development:
# DATABASE_URL=sqlite:///./research_mind.db
DATABASE_ECHO=False

# mcp-vector-search Configuration
HF_CACHE_DIR=~/.cache/huggingface/
EMBEDDINGS_MODEL=all-MiniLM-L6-v2
EMBEDDINGS_DEVICE=cpu  # "cpu" or "cuda"

# Session Configuration
SESSION_WORKSPACE_ROOT=/var/lib/research-mind/sessions/
SESSION_MAX_DURATION_MINUTES=60
SESSION_IDLE_TIMEOUT_MINUTES=30

# Vector Search Configuration
CHROMADB_PERSIST_DIR=/var/lib/research-mind/chromadb/
SEARCH_RESULT_LIMIT=10
SEARCH_TIMEOUT_SECONDS=30

# CORS Configuration
CORS_ORIGINS=http://localhost:15000,http://localhost:3000

# Security
PATH_VALIDATOR_ENABLED=True
AUDIT_LOGGING_ENABLED=True

# Feature Flags
ENABLE_AGENT_INTEGRATION=True
ENABLE_CACHING=False
ENABLE_WARM_POOLS=False
```

3. **Test Configuration**
   ```bash
   python3 -c "from app.core.config import settings, validate_settings; validate_settings(); print('✓ Configuration loaded')"
   ```

**Success Criteria**:

- [ ] Pydantic Settings class created
- [ ] All required variables documented
- [ ] Defaults sensible and documented
- [ ] .env.example template complete
- [ ] Configuration validates on startup
- [ ] Environment variables override defaults

---

### Task 1.1.4: Create Dockerfile (4-6 hours)

**Objective**: Multi-stage Docker build including mpc-vector-search dependencies

#### Steps

1. **Create Dockerfile**

```dockerfile
# Multi-stage Dockerfile for research-mind-service
# Stage 1: Builder (install dependencies)
FROM python:3.12-slim as builder

WORKDIR /build

# Install system dependencies for building
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy pyproject.toml and install Python dependencies
COPY pyproject.toml .
RUN pip install --upgrade pip && \
    pip install --user --no-cache-dir -e .

# Stage 2: Runtime (minimal image with only runtime deps)
FROM python:3.12-slim as runtime

WORKDIR /app

# Install runtime-only dependencies
RUN apt-get update && apt-get install -y \
    libgomp1 \  # For PyTorch multithreading
    && rm -rf /var/lib/apt/lists/*

# Copy Python dependencies from builder
COPY --from=builder /root/.local /root/.local

# Set PATH to use local Python packages
ENV PATH=/root/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TRANSFORMERS_CACHE=/cache/huggingface/transformers \
    HF_HOME=/cache/huggingface \
    HF_HUB_CACHE=/cache/huggingface/hub

# Copy application code
COPY . .

# Create required directories
RUN mkdir -p /var/lib/research-mind/sessions \
    && mkdir -p /var/lib/research-mind/chromadb \
    && mkdir -p /cache/huggingface

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:15010/api/health || exit 1

# Run service
CMD ["python3", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "15010"]
```

2. **Create .dockerignore**

```
.git
.gitignore
__pycache__
*.pyc
*.pyo
*.pyd
.Python
.venv
venv
.env
.env.local
*.db
*.sqlite
.pytest_cache
.coverage
htmlcov
dist
build
*.egg-info
node_modules
.DS_Store
```

3. **Test Docker build**
   ```bash
   cd research-mind-service
   docker build -t research-mind-service:test .
   docker run --rm research-mind-service:test python3 -c "from app.main import app; print('✓ Docker build successful')"
   ```

**Success Criteria**:

- [ ] Dockerfile created with multi-stage build
- [ ] All dependencies included
- [ ] Health check configured
- [ ] Docker image builds without errors
- [ ] Image size reasonable (<2GB)
- [ ] .dockerignore prevents unnecessary files

---

### Task 1.1.5: Update pyproject.toml (2-3 hours)

**Objective**: Add all required dependencies for Phase 1.1

#### Steps

1. **Update/create pyproject.toml**

```toml
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "research-mind-service"
version = "1.0.0"
description = "Session-scoped agentic research system"
authors = [{name = "Research Mind Team"}]
requires-python = ">=3.12"

dependencies = [
    # Core dependencies
    "fastapi>=0.104.0",
    "uvicorn[standard]>=0.24.0",
    "pydantic>=2.0.0",
    "pydantic-settings>=2.0.0",

    # Database
    "sqlalchemy>=2.0.0",
    "alembic>=1.12.0",
    "psycopg2-binary>=2.9.0",  # PostgreSQL driver

    # mcp-vector-search (CRITICAL for Phase 1.1)
    "mcp-vector-search>=0.1.0",

    # Additional utilities
    "python-dotenv>=1.0.0",
    "httpx>=0.25.0",
    "python-multipart>=0.0.6",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "pytest-asyncio>=0.21.0",
    "pytest-cov>=4.1.0",
    "black>=23.0.0",
    "isort>=5.12.0",
    "mypy>=1.5.0",
    "ruff>=0.1.0",
    "httpx>=0.25.0",
]

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
addopts = "--cov=app --cov-report=html --cov-report=term-missing"

[tool.black]
line-length = 100
target-version = ["py312"]

[tool.mypy]
python_version = "3.12"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = false
```

2. **Install dependencies**
   ```bash
   cd research-mind-service
   uv sync  # or: pip install -e .[dev]
   ```

**Success Criteria**:

- [ ] pyproject.toml created/updated
- [ ] mcp-vector-search dependency added
- [ ] All required dependencies specified
- [ ] Dev dependencies included (pytest, mypy, black)
- [ ] uv sync or pip install completes successfully

---

### Task 1.1.6: Testing & Integration (4-6 hours)

**Objective**: Verify all components work together

#### Steps

1. **Create tests/test_service.py**

```python
"""
Unit tests for Phase 1.1 service architecture.
"""

import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.core.config import settings
from app.core.vector_search import VectorSearchManager


@pytest.fixture
def client():
    """FastAPI test client."""
    return TestClient(app)


def test_health_check(client):
    """Test health check endpoint."""
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "research-mind"


def test_vector_search_manager_singleton():
    """Test VectorSearchManager singleton pattern."""
    manager1 = VectorSearchManager()
    manager2 = VectorSearchManager()
    assert manager1 is manager2, "Singleton pattern failed"


def test_configuration_loaded():
    """Test that configuration is properly loaded."""
    assert settings.host == "0.0.0.0"
    assert settings.port == 15010
    assert settings.database_url is not None
    assert settings.embeddings_model == "all-MiniLM-L6-v2"


def test_vector_search_manager_has_required_attributes():
    """Test VectorSearchManager has required attributes."""
    manager = VectorSearchManager()
    assert hasattr(manager, 'client')
    assert hasattr(manager, 'indexer')
    assert hasattr(manager, 'search_engine')
    assert callable(getattr(manager, 'shutdown'))
```

2. **Run tests**

   ```bash
   cd research-mind-service
   pytest tests/ -v --cov=app
   ```

3. **Manual integration test**

   ```bash
   # Terminal 1: Start service
   cd research-mind-service
   python3 -m uvicorn app.main:app --host 0.0.0.0 --port 15010 --reload

   # Terminal 2: Test health endpoint
   curl http://localhost:15010/api/health
   # Expected: {"status":"healthy","service":"research-mind","version":"1.0.0"}
   ```

**Success Criteria**:

- [ ] Health check endpoint returns 200
- [ ] Singleton pattern verified
- [ ] Configuration loads without errors
- [ ] Service starts on port 15010
- [ ] VectorSearchManager initializes
- [ ] All tests pass
- [ ] No import errors
- [ ] Docker image builds and runs

---

## Research References

### Primary References

**docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md** (Sections 4, 5, 10)

- **Section 4: Architecture Design: SessionIndexer Wrapper**

  - VectorSearchManager singleton pattern (exact template used here)
  - Model caching strategy proven in Phase 1.0
  - Code example for lazy-loading singleton
  - Integration with FastAPI startup/shutdown hooks

- **Section 5: Environment Setup & Configuration**

  - HuggingFace cache directory configuration
  - Model caching via environment variables
  - Performance baseline expectations

- **Section 10: Reference Implementation Patterns**
  - Complete code templates for VectorSearchManager
  - Proper resource cleanup on shutdown

**docs/research/mcp-vector-search-rest-api-proposal.md** (Section 1)

- Service architecture overview
- REST API framework requirements
- Session scoping architecture

**docs/research/combined-architecture-recommendations.md** (Section 4)

- Phase 1 implementation strategy
- Singleton pattern recommendation

### Secondary References

- **IMPLEMENTATION_PLAN.md** - Phase 1.1 section (lines 167-214)
- **docs/research/mcp-vector-search-capabilities.md** - Library internals context

---

## Acceptance Criteria

All criteria must be met before Phase 1.2 can start:

### Functionality (MUST COMPLETE)

- [ ] FastAPI service running on port 15010
- [ ] GET /api/health returns 200 with correct JSON response
- [ ] VectorSearchManager singleton initializes on startup
- [ ] Embedding model loads successfully
- [ ] Service starts and shuts down cleanly
- [ ] No import errors or dependency issues

### Architecture (MUST COMPLETE)

- [ ] Singleton pattern implemented correctly
- [ ] Lazy loading of embedding model
- [ ] Thread-safe initialization
- [ ] Proper resource cleanup on shutdown
- [ ] Configuration system working

### Testing (MUST COMPLETE)

- [ ] Unit tests created and passing
- [ ] Health check test passing
- [ ] Singleton test passing
- [ ] Configuration test passing
- [ ] Docker image builds successfully
- [ ] Service starts in Docker

### Documentation (MUST COMPLETE)

- [ ] pyproject.toml complete with all deps
- [ ] .env.example template created
- [ ] Inline code documentation present
- [ ] README section for Phase 1.1 drafted

### Code Quality (MUST COMPLETE)

- [ ] Code follows PEP 8 style guide
- [ ] Type hints added where applicable
- [ ] Error handling proper (no bare except)
- [ ] Logging implemented for startup/shutdown
- [ ] No security issues identified

---

## Go/No-Go Criteria

**GO to Phase 1.2** if:

- [ ] Health check test passes
- [ ] VectorSearchManager singleton works correctly
- [ ] Docker image builds without errors
- [ ] Service starts and responds to requests
- [ ] Configuration system validated
- [ ] Tech lead approves architecture

**NO-GO if**:

- [ ] Import errors or dependency conflicts
- [ ] VectorSearchManager fails to initialize
- [ ] Health check not working
- [ ] Docker build fails
- [ ] Singleton pattern not thread-safe

**Resolution for NO-GO**:

1. Debug dependency issues (likely mpc-vector-search compatibility)
2. Fix VectorSearchManager implementation
3. Resolve Docker build issues
4. Re-run acceptance criteria

---

## Risks

### Risk 1: mcp-vector-search Integration Issues

**Description**: VectorSearchManager fails to integrate with mcp-vector-search library

**Probability**: Low-Medium (library was validated in Phase 1.0)

**Impact**: HIGH - Blocks all downstream phases

**Mitigation**:

- Phase 1.0 pre-validated library integration
- Use exact code templates from MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md
- Reference implementation patterns from research docs

**Detection**: Task 1.1.2 test failures

**Fallback**: Revert to CLI-based integration (less ideal but possible)

---

### Risk 2: Model Loading Timeout

**Description**: Embedding model download/loading takes longer than expected

**Probability**: Low (verified in Phase 1.0)

**Impact**: MEDIUM - Startup latency issue

**Mitigation**:

- Baseline established in Phase 1.0 (2-3 min expected)
- Document startup expectations clearly
- Consider longer startup timeout in CI/CD

**Detection**: Service startup takes >5 minutes

**Fallback**: Use smaller model, or pre-cache model in Docker image

---

### Risk 3: Memory Issues with Large Model

**Description**: 400MB+ model consumes too much memory

**Probability**: Low (standard model for embedding)

**Impact**: MEDIUM - Can't run on resource-constrained systems

**Mitigation**:

- Use standard all-MiniLM-L6-v2 model (well-tested)
- Monitor memory usage
- Support CPU-only mode (default)

**Detection**: Memory usage >1GB after initialization

**Fallback**: Use even smaller model (DistilBERT)

---

## Success Metrics

| Metric                 | Target                     | Measurement                            |
| ---------------------- | -------------------------- | -------------------------------------- |
| **Service Start Time** | <2 min                     | Time from docker-compose up to healthy |
| **Health Check**       | 100ms                      | Response time for /api/health          |
| **Singleton Pattern**  | Thread-safe                | Concurrent access test                 |
| **Model Load**         | 30s (first), <1ms (cached) | Timing measurements                    |
| **Test Coverage**      | >90%                       | pytest --cov report                    |
| **Error Handling**     | 0 crashes                  | Service resilience                     |

---

## Summary

**Phase 1.1** establishes the foundation for all subsequent Phase 1 work by:

1. Creating FastAPI service scaffold with proper structure
2. Implementing VectorSearchManager singleton for efficient model management
3. Setting up configuration system (environment variables)
4. Integrating with mpc-vector-search library
5. Verifying everything works in Docker

**Upon completion**, all subsequent phases (1.2-1.8) can begin in parallel knowing the service foundation is solid.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Next Phase**: Phase 1.2 (Session Management), 1.3 (Vector Search API), 1.4 (Path Validator)
**Parent**: 01-PHASE_1_FOUNDATION.md
