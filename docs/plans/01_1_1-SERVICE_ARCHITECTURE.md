# Phase 1.1: Service Architecture Setup

**Subphase**: 1.1 of 8 (Phase 1)
**Duration**: 5-6 business days
**Effort**: 40-48 hours
**Team Size**: 2 FTE engineers
**Blocking**: 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8 (all subsequent phases)
**Prerequisite**: Phase 1.0 complete (mcp-vector-search CLI installed)
**Status**: CRITICAL - Unblocks all other Phase 1 work

> **ARCHITECTURE NOTE (v2.0)**: This document reflects the subprocess-based architecture.
> mcp-vector-search runs as a CLI subprocess, NOT as an embedded Python library.
> See `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0) for details.

---

## Subphase Objective

Create FastAPI service scaffold with proper project structure and subprocess-based workspace indexing. Implement WorkspaceIndexer class that spawns `mcp-vector-search` CLI as a subprocess for workspace initialization and indexing operations.

**Success Definition**: FastAPI service running on port 15010 with:

- Health check endpoint working (`GET /api/health`)
- WorkspaceIndexer class operational (spawns subprocess correctly)
- `mcp-vector-search` CLI verified accessible from service environment
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

### Day 3-4: WorkspaceIndexer Subprocess Manager (12-16 hours)

- Design WorkspaceIndexer class using subprocess.run()
- Implement init + index two-step flow
- Add timeout management (30s init, 60s index, 300-600s large projects)
- Add exit code handling and error recovery
- Test subprocess invocation patterns

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

2. **research-mind-service/app/core/workspace_indexer.py** (200-300 lines)

   - WorkspaceIndexer subprocess manager
   - Subprocess invocation with timeout and exit code handling
   - Error handling and recovery patterns

3. **research-mind-service/app/core/config.py** (80-120 lines)

   - Pydantic Settings for environment configuration
   - Validation and defaults
   - Documentation of all configuration options

4. **research-mind-service/Dockerfile** (40-60 lines)

   - Multi-stage build
   - mcp-vector-search CLI installed
   - Proper cache management

5. **research-mind-service/pyproject.toml** (updated)

   - mcp-vector-search dependency (for CLI availability)
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
   │   ├── main.py                    # FastAPI entry point (NEW)
   │   ├── core/
   │   │   ├── __init__.py
   │   │   ├── workspace_indexer.py   # WorkspaceIndexer subprocess manager (NEW)
   │   │   └── config.py             # Configuration (NEW)
   │   ├── routes/
   │   │   └── __init__.py
   │   ├── services/
   │   │   └── __init__.py
   │   ├── schemas/
   │   │   └── __init__.py
   │   ├── models/
   │   │   ├── __init__.py
   │   │   └── session.py            # Stub from Phase 1.0
   │   └── sandbox/
   │       └── __init__.py           # From Phase 1.0
   ├── tests/
   │   └── __init__.py
   ├── Dockerfile                     # Multi-stage build (NEW)
   ├── pyproject.toml                # Updated with deps (NEW)
   ├── .env.example                  # Configuration template (NEW)
   └── README.md                     # TBD Phase 1.8
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
- Workspace indexer CLI verification on startup
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
import subprocess

from app.core.config import settings

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


@app.on_event("startup")
async def startup():
    """Verify mcp-vector-search CLI is available on service startup."""
    logger.info("Verifying mcp-vector-search CLI availability...")

    try:
        result = subprocess.run(
            ["mcp-vector-search", "--version"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            logger.info(f"mcp-vector-search CLI available: {result.stdout.strip()}")
        else:
            logger.warning(
                f"mcp-vector-search CLI returned non-zero: {result.stderr}"
            )
    except FileNotFoundError:
        logger.error(
            "mcp-vector-search CLI not found. "
            "Install with: pip install mcp-vector-search"
        )
        raise RuntimeError("mcp-vector-search CLI not available")
    except subprocess.TimeoutExpired:
        logger.error("mcp-vector-search CLI version check timed out")
        raise RuntimeError("mcp-vector-search CLI not responding")


@app.on_event("shutdown")
async def shutdown():
    """Cleanup on service shutdown."""
    logger.info("Service shutting down")


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
   python3 -c "from app.main import app; print('FastAPI app imports successfully')"
   ```

**Success Criteria**:

- [ ] app/main.py created with 150-200 lines
- [ ] FastAPI app instantiated without errors
- [ ] Health check endpoint accessible (GET /api/health)
- [ ] Error handling middleware working
- [ ] Request logging working
- [ ] Startup verifies mcp-vector-search CLI availability

---

### Task 1.1.2: Implement WorkspaceIndexer Subprocess Manager (12-16 hours)

**Objective**: Create WorkspaceIndexer class that spawns mcp-vector-search subprocess for workspace init and indexing

#### Critical Architecture Pattern

From subprocess integration research, we know:

- mcp-vector-search runs as a **CLI subprocess**, not an embedded library
- Two-step flow: `mcp-vector-search init --force` then `mcp-vector-search index --force`
- Working directory (`cwd`) determines which workspace is indexed
- Exit codes: 0 = success, 1 = failure
- Index artifacts stored in workspace `.mcp-vector-search/` directory

#### Workspace Indexing Subprocess Pattern

```
research-mind-service (FastAPI)
  ├── Workspace Management API
  │   ├── POST /workspaces/{id}/register
  │   └── POST /workspaces/{id}/index
  │
  └── WorkspaceIndexer (subprocess manager)
      └── subprocess.run()
          ├── mcp-vector-search init --force (cwd=workspace_dir, timeout=30s)
          └── mcp-vector-search index --force (cwd=workspace_dir, timeout=60-600s)
              └── Workspace Directory
                  ├── source code files
                  └── .mcp-vector-search/
                      ├── config.json
                      ├── .chromadb/
                      └── embeddings cache
```

#### Steps

1. **Create app/core/workspace_indexer.py**

```python
"""
WorkspaceIndexer subprocess manager for mcp-vector-search.

Responsible for:
- Spawning mcp-vector-search CLI as subprocess
- Two-step init + index flow per workspace
- Exit code handling and error recovery
- Timeout management for different project sizes
- Index status checking via .mcp-vector-search/ directory existence

This class does NOT embed mcp-vector-search as a library.
It invokes the CLI via subprocess.run() with cwd set to workspace directory.
"""

import subprocess
import logging
import time
from pathlib import Path
from typing import Optional
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class IndexingResult:
    """Result of a subprocess indexing operation."""
    success: bool
    elapsed_seconds: float
    stdout: str
    stderr: str
    command: str

    def __str__(self) -> str:
        status = "SUCCESS" if self.success else "FAILED"
        return f"{status}: {self.command} ({self.elapsed_seconds:.1f}s)"


class WorkspaceIndexer:
    """
    Manages mcp-vector-search subprocess for workspace indexing.

    Each workspace maintains its own independent index in
    .mcp-vector-search/ directory. This class spawns CLI
    subprocesses to initialize and index workspaces.

    Performance Characteristics:
    - Init: ~2-5 seconds (includes model download on first run: ~250-500 MB)
    - Index (small project): ~3-5 seconds
    - Index (100 files): ~10-15 seconds
    - Index (500 files): ~30-60 seconds
    - Index (1000+ files): ~120-300 seconds

    Attributes:
        workspace_dir: Path to workspace directory
    """

    # Default timeouts (seconds)
    INIT_TIMEOUT = 30
    INDEX_TIMEOUT_SMALL = 60      # <100 files
    INDEX_TIMEOUT_MEDIUM = 300    # 100-500 files
    INDEX_TIMEOUT_LARGE = 600     # 500+ files

    def __init__(self, workspace_dir: Path):
        """
        Initialize WorkspaceIndexer for a specific workspace.

        Args:
            workspace_dir: Path to workspace directory (must exist)

        Raises:
            ValueError: If workspace directory does not exist
        """
        self.workspace_dir = Path(workspace_dir).resolve()
        if not self.workspace_dir.is_dir():
            raise ValueError(f"Workspace directory not found: {self.workspace_dir}")

    def initialize(self, timeout: int = INIT_TIMEOUT) -> IndexingResult:
        """
        Initialize workspace for mcp-vector-search (one-time).

        Creates .mcp-vector-search/ directory with config and index artifacts.

        Args:
            timeout: Max seconds to wait (default 30s)

        Returns:
            IndexingResult with success/failure and output
        """
        return self._run_command(
            ["mcp-vector-search", "init", "--force"],
            timeout=timeout,
        )

    def index(self, timeout: int = INDEX_TIMEOUT_SMALL, force: bool = True) -> IndexingResult:
        """
        Index workspace source code.

        Args:
            timeout: Max seconds to wait (default 60s, increase for large projects)
            force: Force full reindex (default True)

        Returns:
            IndexingResult with success/failure and output
        """
        cmd = ["mcp-vector-search", "index"]
        if force:
            cmd.append("--force")
        return self._run_command(cmd, timeout=timeout)

    def initialize_and_index(self, index_timeout: int = INDEX_TIMEOUT_SMALL) -> IndexingResult:
        """
        Full init + index flow for a workspace.

        Args:
            index_timeout: Timeout for the index step

        Returns:
            IndexingResult from the index step (or init step if it failed)
        """
        init_result = self.initialize()
        if not init_result.success:
            logger.error(f"Init failed for {self.workspace_dir}: {init_result.stderr}")
            return init_result

        return self.index(timeout=index_timeout)

    def check_health(self, timeout: int = 10) -> IndexingResult:
        """Check index health status."""
        return self._run_command(
            ["mcp-vector-search", "index", "health"],
            timeout=timeout,
        )

    def is_indexed(self) -> bool:
        """
        Check if workspace has been indexed.

        Checks for existence of .mcp-vector-search/ directory
        in the workspace, which is created by the init command.

        Returns:
            True if .mcp-vector-search/ directory exists
        """
        index_dir = self.workspace_dir / ".mcp-vector-search"
        return index_dir.is_dir()

    def _run_command(self, cmd: list[str], timeout: int) -> IndexingResult:
        """
        Run mcp-vector-search CLI subprocess.

        Args:
            cmd: Command and arguments
            timeout: Max seconds to wait

        Returns:
            IndexingResult with success/failure and captured output
        """
        cmd_str = " ".join(cmd)
        logger.info(f"Running: {cmd_str} (cwd={self.workspace_dir}, timeout={timeout}s)")

        start_time = time.time()
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.workspace_dir),
                timeout=timeout,
                capture_output=True,
                text=True,
                check=False,  # Don't raise on non-zero exit
            )
            elapsed = time.time() - start_time

            indexing_result = IndexingResult(
                success=result.returncode == 0,
                elapsed_seconds=elapsed,
                stdout=result.stdout,
                stderr=result.stderr,
                command=cmd_str,
            )

            if indexing_result.success:
                logger.info(f"Completed: {cmd_str} ({elapsed:.1f}s)")
            else:
                logger.error(
                    f"Failed: {cmd_str} (exit code {result.returncode}): {result.stderr}"
                )

            return indexing_result

        except subprocess.TimeoutExpired:
            elapsed = time.time() - start_time
            logger.error(f"Timeout: {cmd_str} after {timeout}s")
            return IndexingResult(
                success=False,
                elapsed_seconds=elapsed,
                stdout="",
                stderr=f"Timeout after {timeout}s",
                command=cmd_str,
            )

        except FileNotFoundError:
            elapsed = time.time() - start_time
            logger.error("mcp-vector-search CLI not found in PATH")
            return IndexingResult(
                success=False,
                elapsed_seconds=elapsed,
                stdout="",
                stderr="mcp-vector-search CLI not found. Install with: pip install mcp-vector-search",
                command=cmd_str,
            )
```

2. **Test WorkspaceIndexer**

   ```bash
   python3 << 'EOF'
   import tempfile
   from pathlib import Path
   from app.core.workspace_indexer import WorkspaceIndexer

   # Create a temp workspace
   with tempfile.TemporaryDirectory() as tmpdir:
       workspace = Path(tmpdir)
       # Create a test file
       (workspace / "test.py").write_text("def hello(): return 'world'")

       indexer = WorkspaceIndexer(workspace)

       # Test init
       result = indexer.initialize()
       print(f"Init: {result}")

       # Test index
       result = indexer.index()
       print(f"Index: {result}")

       # Test is_indexed
       print(f"Is indexed: {indexer.is_indexed()}")
   EOF
   ```

**Success Criteria**:

- [ ] WorkspaceIndexer class implemented with subprocess.run()
- [ ] Two-step init + index flow working
- [ ] Exit code handling (0 = success, 1 = failure)
- [ ] Timeout management configurable (30s init, 60-600s index)
- [ ] is_indexed() checks .mcp-vector-search/ directory existence
- [ ] Proper error handling for timeout, missing CLI, and failures

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

    # Workspace Configuration
    workspace_root: str = "/var/lib/research-mind/workspaces/"

    # Subprocess Timeout Configuration (seconds)
    indexing_init_timeout: int = 30        # mcp-vector-search init
    indexing_index_timeout: int = 60       # mcp-vector-search index (small projects)
    indexing_large_timeout: int = 600      # mcp-vector-search index (large projects)

    # Session Configuration
    session_max_duration_minutes: int = 60
    session_idle_timeout_minutes: int = 30

    # CORS Configuration
    cors_origins: List[str] = ["http://localhost:15000", "http://localhost:3000"]

    # Security Configuration
    path_validator_enabled: bool = True
    audit_logging_enabled: bool = True

    # Feature Flags
    enable_agent_integration: bool = False  # Deferred to Phase 2
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
    logger.info(f"  Workspace Root: {settings.workspace_root}")
    logger.info(f"  Init Timeout: {settings.indexing_init_timeout}s")
    logger.info(f"  Index Timeout: {settings.indexing_index_timeout}s")

    # Create required directories
    from pathlib import Path

    for directory in [
        settings.workspace_root,
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

# Workspace Configuration
WORKSPACE_ROOT=/var/lib/research-mind/workspaces/

# Subprocess Timeout Configuration (seconds)
INDEXING_INIT_TIMEOUT=30
INDEXING_INDEX_TIMEOUT=60
INDEXING_LARGE_TIMEOUT=600

# Session Configuration
SESSION_MAX_DURATION_MINUTES=60
SESSION_IDLE_TIMEOUT_MINUTES=30

# CORS Configuration
CORS_ORIGINS=http://localhost:15000,http://localhost:3000

# Security
PATH_VALIDATOR_ENABLED=True
AUDIT_LOGGING_ENABLED=True

# Feature Flags
ENABLE_AGENT_INTEGRATION=False
ENABLE_CACHING=False
ENABLE_WARM_POOLS=False
```

3. **Test Configuration**
   ```bash
   python3 -c "from app.core.config import settings, validate_settings; validate_settings(); print('Configuration loaded')"
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

**Objective**: Multi-stage Docker build including mcp-vector-search CLI

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

# Copy Python dependencies from builder
COPY --from=builder /root/.local /root/.local

# Set PATH to use local Python packages (includes mcp-vector-search CLI)
ENV PATH=/root/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Copy application code
COPY . .

# Create required directories
RUN mkdir -p /var/lib/research-mind/workspaces

# Verify mcp-vector-search CLI is available
RUN mcp-vector-search --version || echo "WARNING: mcp-vector-search CLI not found"

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
   docker run --rm research-mind-service:test mcp-vector-search --version
   ```

**Success Criteria**:

- [ ] Dockerfile created with multi-stage build
- [ ] mcp-vector-search CLI available inside container
- [ ] Health check configured
- [ ] Docker image builds without errors
- [ ] Image size reasonable (<1GB)
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

    # mcp-vector-search (provides CLI command)
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
- [ ] mcp-vector-search dependency added (provides CLI)
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
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from app.main import app
from app.core.config import settings
from app.core.workspace_indexer import WorkspaceIndexer, IndexingResult


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


def test_workspace_indexer_init():
    """Test WorkspaceIndexer initialization."""
    with tempfile.TemporaryDirectory() as tmpdir:
        indexer = WorkspaceIndexer(Path(tmpdir))
        assert indexer.workspace_dir == Path(tmpdir).resolve()


def test_workspace_indexer_invalid_dir():
    """Test WorkspaceIndexer rejects invalid directory."""
    with pytest.raises(ValueError, match="not found"):
        WorkspaceIndexer(Path("/nonexistent/path"))


def test_workspace_indexer_is_indexed():
    """Test is_indexed checks .mcp-vector-search/ directory."""
    with tempfile.TemporaryDirectory() as tmpdir:
        workspace = Path(tmpdir)
        indexer = WorkspaceIndexer(workspace)

        # Not indexed initially
        assert indexer.is_indexed() is False

        # Create .mcp-vector-search/ directory
        (workspace / ".mcp-vector-search").mkdir()
        assert indexer.is_indexed() is True


@patch("subprocess.run")
def test_workspace_indexer_subprocess_invocation(mock_run):
    """Test subprocess is called correctly."""
    mock_run.return_value = MagicMock(returncode=0, stdout="OK", stderr="")

    with tempfile.TemporaryDirectory() as tmpdir:
        indexer = WorkspaceIndexer(Path(tmpdir))
        result = indexer.initialize()

        assert result.success is True
        mock_run.assert_called_once()
        call_args = mock_run.call_args
        assert call_args[0][0] == ["mcp-vector-search", "init", "--force"]
        assert call_args[1]["cwd"] == str(Path(tmpdir).resolve())


@patch("subprocess.run")
def test_workspace_indexer_timeout_handling(mock_run):
    """Test timeout is handled gracefully."""
    import subprocess
    mock_run.side_effect = subprocess.TimeoutExpired(cmd="test", timeout=30)

    with tempfile.TemporaryDirectory() as tmpdir:
        indexer = WorkspaceIndexer(Path(tmpdir))
        result = indexer.initialize()

        assert result.success is False
        assert "Timeout" in result.stderr


@patch("subprocess.run")
def test_workspace_indexer_exit_code_handling(mock_run):
    """Test non-zero exit code is handled."""
    mock_run.return_value = MagicMock(
        returncode=1, stdout="", stderr="Permission denied"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        indexer = WorkspaceIndexer(Path(tmpdir))
        result = indexer.initialize()

        assert result.success is False
        assert "Permission denied" in result.stderr


def test_configuration_loaded():
    """Test that configuration is properly loaded."""
    assert settings.host == "0.0.0.0"
    assert settings.port == 15010
    assert settings.database_url is not None
    assert settings.indexing_init_timeout == 30
    assert settings.indexing_index_timeout == 60
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
- [ ] WorkspaceIndexer subprocess invocation verified
- [ ] Exit code handling tested (success + failure)
- [ ] Timeout handling tested
- [ ] Configuration loads without errors
- [ ] Service starts on port 15010
- [ ] All tests pass
- [ ] No import errors
- [ ] Docker image builds and runs

---

## Research References

### Primary References

**docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md** (v2.0 - Subprocess-Based)

- **Architecture Overview**: Subprocess-based design pattern
- **CLI Command Reference**: init, index, reindex commands
- **Subprocess Invocation Pattern**: subprocess.run() with cwd
- **Python Integration Examples**: WorkspaceIndexer class template
- **Error Handling & Recovery**: Exit codes, timeouts, common errors
- **Performance & Optimization**: Timing baselines and scaling estimates

**docs/research2/RESEARCH_SUMMARY.md**

- Quick reference of verified subprocess behavior
- Test results for subprocess invocation, isolation, exit codes

### Secondary References

- **IMPLEMENTATION_PLAN.md** - Phase 1.1 section
- **docs/research2/mcp-vector-search-subprocess-integration-research.md** - Complete research findings

---

## Acceptance Criteria

All criteria must be met before Phase 1.2 can start:

### Functionality (MUST COMPLETE)

- [ ] FastAPI service running on port 15010
- [ ] GET /api/health returns 200 with correct JSON response
- [ ] mcp-vector-search CLI verified available on startup
- [ ] WorkspaceIndexer spawns subprocess correctly
- [ ] Service starts and shuts down cleanly
- [ ] No import errors or dependency issues

### Architecture (MUST COMPLETE)

- [ ] Subprocess-based indexing pattern implemented
- [ ] Two-step init + index flow working
- [ ] Exit code handling (0=success, 1=failure)
- [ ] Timeout management (configurable per operation)
- [ ] Index status checking via .mcp-vector-search/ directory
- [ ] Configuration system working

### Testing (MUST COMPLETE)

- [ ] Unit tests created and passing
- [ ] Health check test passing
- [ ] WorkspaceIndexer subprocess tests passing (mocked)
- [ ] Configuration test passing
- [ ] Docker image builds successfully
- [ ] Service starts in Docker with mcp-vector-search CLI available

### Documentation (MUST COMPLETE)

- [ ] pyproject.toml complete with all deps
- [ ] .env.example template created
- [ ] Inline code documentation present
- [ ] README section for Phase 1.1 drafted

### Code Quality (MUST COMPLETE)

- [ ] Code follows PEP 8 style guide
- [ ] Type hints added where applicable
- [ ] Error handling proper (no bare except)
- [ ] Logging implemented for subprocess operations
- [ ] No security issues identified

---

## Go/No-Go Criteria

**GO to Phase 1.2** if:

- [ ] Health check test passes
- [ ] WorkspaceIndexer subprocess invocation works correctly
- [ ] Docker image builds without errors
- [ ] Service starts and responds to requests
- [ ] Configuration system validated
- [ ] Tech lead approves architecture

**NO-GO if**:

- [ ] mcp-vector-search CLI not found or not working
- [ ] Subprocess invocation fails
- [ ] Health check not working
- [ ] Docker build fails
- [ ] Exit code handling not reliable

**Resolution for NO-GO**:

1. Verify mcp-vector-search installation (pip install mcp-vector-search)
2. Debug subprocess invocation (check PATH, permissions)
3. Resolve Docker build issues
4. Re-run acceptance criteria

---

## Risks

### Risk 1: mcp-vector-search CLI Not Available

**Description**: mcp-vector-search CLI command not found in service environment

**Probability**: Low-Medium (CLI was validated in Phase 1.0)

**Impact**: HIGH - Blocks all indexing operations

**Mitigation**:

- Phase 1.0 pre-validated CLI installation
- Startup check verifies CLI availability
- Dockerfile includes explicit verification step

**Detection**: Service startup failure, CLI version check fails

**Fallback**: Reinstall mcp-vector-search, verify PATH configuration

---

### Risk 2: Subprocess Timeout on Large Workspaces

**Description**: Indexing large codebases exceeds default timeout

**Probability**: Medium (large projects may have 1000+ files)

**Impact**: MEDIUM - Indexing fails for large projects

**Mitigation**:

- Configurable timeouts (60s, 300s, 600s tiers)
- Research baseline: 3.89s for 2-file project, estimated 120-300s for 1000+ files
- Large project timeout set to 600s by default
- Background indexing option for very large projects

**Detection**: TimeoutExpired exceptions in logs

**Fallback**: Increase timeout, use --batch-size for throughput, break into smaller indexing jobs

---

### Risk 3: Concurrent Subprocess Safety

**Description**: Multiple index operations on same workspace simultaneously

**Probability**: Low (API should serialize per workspace)

**Impact**: MEDIUM - ChromaDB corruption possible

**Mitigation**:

- Single-writer safety: never index same workspace from multiple processes
- API-level serialization per workspace
- ChromaDB has internal locking for single-writer safety
- Different workspaces can index in parallel safely

**Detection**: ChromaDB corruption errors, index health check failures

**Fallback**: Delete .mcp-vector-search/ directory and re-initialize

---

## Success Metrics

| Metric                 | Target               | Measurement                            |
| ---------------------- | -------------------- | -------------------------------------- |
| **Service Start Time** | <30s                 | Time from docker-compose up to healthy |
| **Health Check**       | <100ms               | Response time for /api/health          |
| **CLI Verification**   | <10s on startup      | mcp-vector-search --version check      |
| **Subprocess Init**    | <30s                 | mcp-vector-search init runtime         |
| **Subprocess Index**   | <60s (small project) | mcp-vector-search index runtime        |
| **Test Coverage**      | >90%                 | pytest --cov report                    |
| **Error Handling**     | 0 crashes            | Service resilience                     |

---

## Summary

**Phase 1.1** establishes the foundation for all subsequent Phase 1 work by:

1. Creating FastAPI service scaffold with proper structure
2. Implementing WorkspaceIndexer subprocess manager for mcp-vector-search CLI
3. Setting up configuration system (environment variables, timeouts)
4. Verifying mcp-vector-search CLI availability on startup
5. Verifying everything works in Docker

**Upon completion**, all subsequent phases (1.2-1.8) can begin in parallel knowing the service foundation is solid.

---

**Document Version**: 2.0
**Last Updated**: 2026-02-01
**Architecture**: Subprocess-based (replaces v1.0 library embedding approach)
**Next Phase**: Phase 1.2 (Session Management), 1.3 (Indexing Operations), 1.4 (Path Validator)
**Parent**: 01-PHASE_1_FOUNDATION.md
