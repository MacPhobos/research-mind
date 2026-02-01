# MCP Vector Search Integration Guide: Phase 1.0 Pre-Phase Setup

**Document Version**: 1.0
**Date**: 2026-01-31
**Status**: Critical Integration Guide for Phase 1.0 MVP
**Audience**: Backend engineers integrating mcp-vector-search for research-mind FastAPI service
**Related Documents**:
- mcp-vector-search-packaging-installation.md (1,388 lines)
- mcp-vector-search-capabilities.md
- mcp-vector-search-rest-api-proposal.md
- PLAN_VS_RESEARCH_ANALYSIS.md

---

## Executive Summary

**Problem**: The implementation plan requires mcp-vector-search as the foundation for Phase 1.0, but the library integration is **NOT** currently in place. The PLAN_VS_RESEARCH_ANALYSIS.md identifies this as a **CRITICAL BLOCKER** for Phase 1.

**Impact**:
- Phase 1.1 (Service Architecture) cannot proceed without mcp-vector-search dependency
- Current pyproject.toml is missing the critical library
- ~2.5GB disk space needed for dependencies and models
- Model caching singleton pattern must be designed and validated
- Per-session collection management requires tested implementation

**Solution**: This guide provides a **comprehensive pre-Phase-1 setup checklist** to de-risk Phase 1.0 implementation by:
1. Installing and verifying mcp-vector-search dependency
2. Understanding critical integration patterns (singleton, model caching, session scoping)
3. Creating proven architecture for SessionIndexer wrapper
4. Establishing Phase 1.0 environment baseline (2-3 day pre-phase task)
5. Identifying and mitigating installation/configuration risks

**Estimated Time**: 2-3 days for complete Phase 1.0 pre-phase setup (before Phase 1.1 formal kickoff)

---

## Table of Contents

1. [Phase 1.0 Pre-Phase Overview](#phase-10-pre-phase-overview)
2. [Dependency Installation & Verification](#dependency-installation--verification)
3. [Critical Integration Patterns](#critical-integration-patterns)
4. [Architecture Design: SessionIndexer Wrapper](#architecture-design-sessionindexer-wrapper)
5. [Environment Setup & Configuration](#environment-setup--configuration)
6. [Pre-Phase Verification Checklist](#pre-phase-verification-checklist)
7. [Risk Mitigation & Troubleshooting](#risk-mitigation--troubleshooting)
8. [Phase 1.0 Environment Baseline](#phase-10-environment-baseline)
9. [Timeline Impact & Critical Path](#timeline-impact--critical-path)
10. [Reference Implementation Patterns](#reference-implementation-patterns)

---

## Phase 1.0 Pre-Phase Overview

### What is Phase 1.0?

Phase 1.0 is a **2-3 day preparation phase** (BEFORE formal Phase 1 kickoff) to ensure mcp-vector-search is properly integrated and tested. The PLAN_VS_RESEARCH_ANALYSIS.md recommended this phase be added to de-risk Phase 1.1-1.8.

**Goal**: By end of Phase 1.0, the backend engineering team can confidently proceed with Phase 1.1 knowing:
- ✓ mcp-vector-search is installed and working
- ✓ Dependency conflicts resolved
- ✓ Model caching strategy proven
- ✓ Session isolation approach validated
- ✓ Baseline environment documented

### Phase 1.0 Tasks (2-3 Days)

| Task | Duration | Blocking | Description |
|------|----------|----------|-------------|
| **1.0.1** | 30min | Phase 1.1 | Verify Python 3.12+ and virtual environment |
| **1.0.2** | 2-4h | Phase 1.1 | Install mcp-vector-search + dependencies |
| **1.0.3** | 1-2h | Phase 1.1 | Verify PostgreSQL connection + Alembic migrations |
| **1.0.4** | 1h | Phase 1.4 | Create app/sandbox/ directory structure |
| **1.0.5** | 1-2h | Phase 1.1 | Test singleton ChromaDB manager (proof of concept) |
| **1.0.6** | 1-2h | Phase 1.2 | Create app/models/session.py stub |
| **1.0.7** | 1h | Phase 1.1 | Verify Docker/docker-compose |
| **1.0.8** | 2-4h | Phase 1.3 | Document baseline environment + risks discovered |

**Total Estimated Time**: 10-18 hours (2-3 calendar days)

---

## Dependency Installation & Verification

### Step 1.0.1: Environment Prerequisites

**Objective**: Verify system meets minimum requirements for mcp-vector-search

#### Check Python Version

```bash
python3 --version
# Output should be: Python 3.12.x or higher

# If not 3.12+, consider:
# - macOS: brew install python@3.12
# - Ubuntu: sudo apt install python3.12 python3.12-venv
# - Windows: Download from python.org
```

**Why**: mcp-vector-search requires Python 3.12+. FastAPI and other dependencies have similar requirements.

#### Create/Verify Virtual Environment

```bash
cd /Users/mac/workspace/research-mind

# Check if venv exists
ls -la .venv/ 2>/dev/null && echo "venv exists" || echo "venv missing"

# Create if missing
python3.12 -m venv .venv

# Activate
source .venv/bin/activate
# On Windows: .venv\Scripts\activate

# Verify activation
which python  # Should show /path/to/.venv/bin/python
python --version  # Should be 3.12+
```

**Expected Output**:
```
/Users/mac/workspace/research-mind/.venv/bin/python
Python 3.12.x
```

#### Upgrade pip, setuptools, wheel

```bash
python -m pip install --upgrade pip setuptools wheel
# Expected: Successfully installed pip-X.X.X, setuptools-X.X.X, wheel-X.X.X
```

**Disk Space Check**

```bash
# Check available disk space (need ~3GB for mcp-vector-search)
df -h / | grep -v Filesystem

# Example output:
# /dev/disk1s5s1  233Gi  120Gi  108Gi  53% /
# If available < 3GB, will need to cleanup or use external storage
```

**Risk**: If <3GB available, mcp-vector-search installation will fail.

---

### Step 1.0.2: Install mcp-vector-search (CRITICAL)

**Objective**: Install mcp-vector-search library and verify all transitive dependencies

#### Update pyproject.toml

```bash
cd /Users/mac/workspace/research-mind/research-mind-service
```

Edit `pyproject.toml` and add mcp-vector-search to dependencies:

**Before**:
```toml
[project]
name = "research-mind-service"
version = "0.1.0"
requires-python = ">=3.12"

dependencies = [
    "fastapi==0.109.0",
    "uvicorn[standard]==0.27.0",
    "sqlalchemy==2.0.23",
    # ... other dependencies
]
```

**After** (ADD THIS LINE):
```toml
[project]
name = "research-mind-service"
version = "0.1.0"
requires-python = ">=3.12"

dependencies = [
    "fastapi==0.109.0",
    "uvicorn[standard]==0.27.0",
    "sqlalchemy==2.0.23",
    # ... other dependencies
    "mcp-vector-search>=0.1.0",  # ADD THIS
]
```

#### Install via uv sync

```bash
cd /Users/mac/workspace/research-mind/research-mind-service

# Install all dependencies
uv sync

# This command:
# - Reads pyproject.toml
# - Downloads mcp-vector-search and transitive deps (~2.5GB total)
# - Compiles packages to .venv/
# - Creates lock file for reproducibility
```

**Expected Output**:
```
Resolved 47 packages in Xs
Installed 47 packages in Xs
```

**Duration**: 2-4 minutes (depends on network, disk speed)

#### Verify Installation

```bash
# Test 1: Import mcp-vector-search
python -c "from mcp_vector_search import Client; print('OK')"
# Expected: OK (no errors)

# Test 2: Check installed version
python -c "import mcp_vector_search; print(mcp_vector_search.__version__)"
# Expected: 0.1.0 or similar

# Test 3: Verify transitive dependencies
python -c "import transformers, torch, chromadb, sentence_transformers; print('All deps OK')"
# Expected: All deps OK

# Test 4: Check disk usage
du -sh ~/.cache/huggingface/ 2>/dev/null || echo "No HF cache yet"
du -sh .venv/ | head -1

# Expected output (after installation):
# .venv/ should be ~1.5-2GB
# ~/.cache/huggingface/ will grow as models download
```

**Common Issues**:

| Issue | Cause | Fix |
|-------|-------|-----|
| `pip: command not found` | Virtual env not activated | `source .venv/bin/activate` |
| `No space left on device` | Insufficient disk space | Free up 3GB or use external storage |
| `ModuleNotFoundError: transformers` | Installation incomplete | Re-run `uv sync` |
| `torch installation slow` | Large package (600MB) | Normal; be patient |
| `Permission denied` on cache dir | File permissions issue | `sudo chown -R $USER ~/.cache/` |

---

### Step 1.0.3: Verify PostgreSQL Connection

**Objective**: Ensure database is ready for session storage

#### Check PostgreSQL Status

```bash
# macOS (if using Homebrew)
brew services list | grep postgres

# Linux
systemctl status postgresql

# Docker (if containerized)
docker-compose ps | grep postgres

# If not running, start it:
# macOS: brew services start postgresql
# Linux: sudo systemctl start postgresql
# Docker: docker-compose up -d postgres
```

**Expected Output**:
```
postgresql ... started
```

#### Test Connection

```bash
# Using psql if available
psql -U postgres -h localhost -d postgres -c "SELECT version();"

# Or use Python
python -c "
import sqlalchemy as sa
engine = sa.create_engine('postgresql://postgres:postgres@localhost:5432/research_mind')
with engine.connect() as conn:
    result = conn.execute(sa.text('SELECT 1'))
    print('Connected!')
"
```

**Expected Output**:
```
Connected!
```

#### Run Alembic Migrations

```bash
cd /Users/mac/workspace/research-mind/research-mind-service

# Check migration status
alembic current
# Output: (head)

# If not at head, upgrade
alembic upgrade head
# Output: Running upgrade ... (if needed)
```

**Database Schema**: After migrations, tables should include:
- `sessions` (for session management in Phase 1.2)
- `audit_logs` (for audit logging in Phase 1.5)

---

### Step 1.0.4: Create Sandbox Directory Structure

**Objective**: Prepare app/sandbox/ for Phase 1.4 path validator

```bash
mkdir -p /Users/mac/workspace/research-mind/research-mind-service/app/sandbox

# Create __init__.py
touch /Users/mac/workspace/research-mind/research-mind-service/app/sandbox/__init__.py

# Verify
ls -la /Users/mac/workspace/research-mind/research-mind-service/app/sandbox/
# Expected: __init__.py, (empty for now)
```

This directory will hold the PathValidator implementation in Phase 1.4.

---

### Step 1.0.5: Verify Docker/Docker-Compose (Optional but Recommended)

**Objective**: Ensure Docker tooling works for Phase 1.8 deployment

```bash
# Check Docker installation
docker --version
# Expected: Docker version X.X.X

# Check docker-compose
docker-compose --version
# Expected: Docker Compose version X.X.X

# Test docker-compose.yml
cd /Users/mac/workspace/research-mind
docker-compose config > /dev/null && echo "docker-compose.yml is valid"
```

---

## Critical Integration Patterns

### Pattern 1: Singleton ChromaDB Manager (CRITICAL)

**Problem**: mcp-vector-search requires model initialization (~30s on first run), embedding model loading (400MB), and ChromaDB connection setup. Repeating this for each request is wasteful.

**Solution**: Implement singleton pattern for model caching.

#### Design Principle

```python
# Pseudo-code showing the pattern

class VectorSearchManager:
    """
    Singleton pattern for mcp-vector-search.

    - Load model once per service instance
    - Reuse in-memory for all requests
    - TTL-based session cleanup
    """

    _instance = None  # Class-level singleton instance
    _indexer = None   # Lazy-loaded indexer

    def __new__(cls):
        """Ensure only one instance exists."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialize()
        return cls._instance

    def _initialize(self):
        """One-time initialization."""
        # Load configuration from environment
        # Set up caching directories
        # Create ChromaDB connection pool

    @property
    def indexer(self) -> SemanticIndexer:
        """Lazy-load indexer on first access."""
        if self._indexer is None:
            # This loads the 400MB model, takes ~30s
            # But only happens ONCE
            self._indexer = SemanticIndexer(...)
        return self._indexer
```

#### Performance Characteristics

| Operation | First Call | Subsequent Calls |
|-----------|-----------|-----------------|
| Model load | 30s (model download + init) | - |
| Indexer access | - | <1ms (cached) |
| Search query | 100-200ms | 100-200ms |
| Index file | 50-500ms | 50-500ms |

**Key Point**: The 30-second model load happens **once per service startup**, not per request. With hot reloading disabled in production, this is negligible.

### Pattern 2: Session-Scoped Collections

**Problem**: mcp-vector-search's ChromaDB stores data in `.mcp-vector-search/chroma.sqlite3`. Without scoping, all sessions share the same collection, causing data contamination.

**Solution**: Create per-session collections using parameterized collection_name.

#### Design Principle

```python
class SessionIndexer:
    """
    Per-session wrapper around mcp-vector-search.

    - Each session gets isolated collection
    - Each session gets isolated workspace directory
    - Shared embedding model (singleton, loaded once)
    """

    def __init__(self, session_id: str, session_root: Path):
        self.session_id = session_id

        # Create session-scoped paths
        self.workspace = session_root
        self.index_path = session_root / ".mcp-vector-search"

        # CRITICAL: Unique collection name per session
        self.collection_name = f"session_{session_id}"

        # Create indexer with scoped collection
        self.indexer = SemanticIndexer(
            project_root=self.workspace,
            collection_name=self.collection_name
        )
```

#### Storage Layout

```
.mcp-vector-search/chroma.sqlite3
├── Collection: "session_abc123"
│   └── [chunks indexed for session abc123]
├── Collection: "session_def456"
│   └── [chunks indexed for session def456]
└── Collection: "session_ghi789"
    └── [chunks indexed for session ghi789]

# Each session also has config:
sessions/
├── abc123/.mcp-vector-search/config.json
├── def456/.mcp-vector-search/config.json
└── ghi789/.mcp-vector-search/config.json
```

**Isolation Guarantee**: Each collection is logically isolated. Search in session_abc123 never returns results from session_def456.

### Pattern 3: Model Caching via Environment Variables

**Problem**: mcp-vector-search downloads embedding model from HuggingFace (~400MB). On first run, this takes time and bandwidth. Subsequent runs should reuse cached model.

**Solution**: Configure HuggingFace cache directory via environment variables.

#### Configuration

```bash
# Set before running service
export TRANSFORMERS_CACHE=/tmp/mcp-vs-cache/transformers
export HF_HOME=/tmp/mcp-vs-cache/huggingface
export HF_HUB_CACHE=/tmp/mcp-vs-cache/hub

# Or in .env file
TRANSFORMERS_CACHE=/tmp/mcp-vs-cache/transformers
HF_HOME=/tmp/mcp-vs-cache/huggingface
HF_HUB_CACHE=/tmp/mcp-vs-cache/hub

# Verify caching
python -c "from transformers import AutoModel; m = AutoModel.from_pretrained('all-MiniLM-L6-v2')"
# First run: Downloads 400MB, takes ~2min
# Second run: Uses cache, takes <1s

# Check cache
du -sh ~/.cache/huggingface/
# Expected: ~400MB after download
```

**Performance Impact**:
- First run: 2-3 minutes (initial model download)
- Subsequent runs: <1 second (cache hit)

---

## Architecture Design: SessionIndexer Wrapper

### Overview

The SessionIndexer is a thin wrapper around mcp-vector-search that:
1. Manages per-session collections
2. Enforces session-scoped workspace directories
3. Provides FastAPI-friendly interfaces
4. Handles error propagation

### Implementation Template

```python
# research-mind-service/app/core/vector_search.py

import os
from pathlib import Path
from typing import Optional, List
from datetime import datetime, timedelta
from mcp_vector_search.core import SemanticIndexer, SemanticSearchEngine
from mcp_vector_search.core.database import ChromaVectorDatabase

class VectorSearchManager:
    """
    Singleton manager for mcp-vector-search.

    Responsibilities:
    - Load model once per service
    - Provide global embedding model
    - Manage ChromaDB connection pool
    - Support per-session collections
    """

    _instance: Optional['VectorSearchManager'] = None
    _indexer: Optional[SemanticIndexer] = None
    _search_engine: Optional[SemanticSearchEngine] = None

    def __new__(cls) -> 'VectorSearchManager':
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialize()
        return cls._instance

    def _initialize(self) -> None:
        """One-time initialization."""
        self._cache_dir = Path(
            os.getenv('MCP_VECTOR_SEARCH_CACHE_DIR', '/tmp/mcp-vs-cache')
        )
        self._model_name = os.getenv(
            'MCP_VECTOR_SEARCH_MODEL_NAME',
            'all-MiniLM-L6-v2'
        )
        self._db_path = Path(
            os.getenv('MCP_VECTOR_SEARCH_DB_PATH', '/tmp/mcp-vs-db')
        )
        self._device = os.getenv(
            'MCP_VECTOR_SEARCH_EMBEDDING_DEVICE',
            'cpu'
        )

        # Create directories
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._db_path.mkdir(parents=True, exist_ok=True)

    @property
    def indexer(self) -> SemanticIndexer:
        """Get indexer, lazy-load on first access."""
        if self._indexer is None:
            self._indexer = SemanticIndexer(
                model_name=self._model_name,
                cache_dir=str(self._cache_dir),
                device=self._device
            )
        return self._indexer

    @property
    def search_engine(self) -> SemanticSearchEngine:
        """Get search engine, lazy-load on first access."""
        if self._search_engine is None:
            self._search_engine = SemanticSearchEngine(
                db_type="chroma",
                db_path=str(self._db_path),
                pool_size=10
            )
        return self._search_engine


# Global singleton instance
_vs_manager = VectorSearchManager()


async def get_vector_search_manager() -> VectorSearchManager:
    """FastAPI dependency injection."""
    return _vs_manager


class SessionIndexer:
    """
    Per-session wrapper around mcp-vector-search.

    Ensures:
    - Session-scoped collections
    - Session-scoped workspace directories
    - Proper error handling
    """

    def __init__(self, session_id: str, session_root: Path):
        self.session_id = session_id
        self.workspace = session_root
        self.index_path = session_root / ".mcp-vector-search"
        self.collection_name = f"session_{session_id}"

        # Use global manager's indexer + search engine
        # But with session-scoped collection name
        self._vs_manager = _vs_manager

    async def index_directory(
        self,
        path: Path,
        recursive: bool = True,
        force: bool = False
    ) -> dict:
        """Index a directory for this session."""
        try:
            result = await self._vs_manager.indexer.index_directory(
                path=path,
                session_id=self.session_id,
                collection_name=self.collection_name,
                recursive=recursive,
                force=force
            )
            return {
                "status": "success",
                "job_id": result.get("job_id"),
                "files_indexed": result.get("file_count"),
                "chunks_created": result.get("chunk_count")
            }
        except Exception as e:
            return {
                "status": "error",
                "error": str(e)
            }

    async def search(
        self,
        query: str,
        limit: int = 10,
        similarity_threshold: float = 0.75
    ) -> dict:
        """Search indexed content for this session."""
        try:
            results = await self._vs_manager.search_engine.search(
                query=query,
                collection_name=self.collection_name,
                top_k=limit,
                similarity_threshold=similarity_threshold
            )
            return {
                "status": "success",
                "query": query,
                "results": results,
                "count": len(results)
            }
        except Exception as e:
            return {
                "status": "error",
                "error": str(e)
            }
```

### Usage in FastAPI Routes

```python
# research-mind-service/app/routes/vector_search.py

from fastapi import APIRouter, Depends, HTTPException
from app.core.vector_search import SessionIndexer, get_vector_search_manager

router = APIRouter(prefix="/api/v1", tags=["search"])

@router.post("/sessions/{session_id}/search")
async def search(
    session_id: str,
    query: str,
    limit: int = 10
):
    """Search within a session."""
    # Get session from database (Phase 1.2)
    session = Session.query.get(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # Create session-scoped indexer
    indexer = SessionIndexer(
        session_id=session_id,
        session_root=Path(session.workspace_path)
    )

    # Perform search
    result = await indexer.search(query, limit=limit)

    return result
```

---

## Environment Setup & Configuration

### Environment Variables

Create `.env` file in `research-mind-service/`:

```bash
# research-mind-service/.env

# Service Configuration
SERVICE_PORT=15010
SERVICE_HOST=0.0.0.0
DEBUG=False

# Database Configuration
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/research_mind
SQLALCHEMY_ECHO=False

# mcp-vector-search Configuration
MCP_VECTOR_SEARCH_CACHE_DIR=/tmp/mcp-vs-cache
MCP_VECTOR_SEARCH_MODEL_NAME=all-MiniLM-L6-v2
MCP_VECTOR_SEARCH_DB_PATH=/tmp/mcp-vs-db
MCP_VECTOR_SEARCH_EMBEDDING_DEVICE=cpu  # or "cuda" if GPU available

# HuggingFace Model Caching
TRANSFORMERS_CACHE=/tmp/mcp-vs-cache/transformers
HF_HOME=/tmp/mcp-vs-cache/huggingface
HF_HUB_CACHE=/tmp/mcp-vs-cache/hub

# Session Configuration
SESSION_ROOT_DIR=/var/lib/research-mind/sessions
SESSION_TTL_HOURS=24

# Logging
LOG_LEVEL=INFO
AUDIT_LOG_PATH=/var/log/research-mind/audit.log

# CORS (for frontend)
CORS_ORIGINS=["http://localhost:15000", "http://localhost:3000"]
```

### Configuration Loading

```python
# research-mind-service/app/core/config.py

from pydantic_settings import BaseSettings
from pathlib import Path

class Settings(BaseSettings):
    service_port: int = 15010
    service_host: str = "0.0.0.0"
    debug: bool = False

    database_url: str
    sqlalchemy_echo: bool = False

    # mcp-vector-search
    mcp_vector_search_cache_dir: Path = Path("/tmp/mcp-vs-cache")
    mcp_vector_search_model_name: str = "all-MiniLM-L6-v2"
    mcp_vector_search_db_path: Path = Path("/tmp/mcp-vs-db")
    mcp_vector_search_embedding_device: str = "cpu"

    # HuggingFace
    transformers_cache: Path = Path("/tmp/mcp-vs-cache/transformers")
    hf_home: Path = Path("/tmp/mcp-vs-cache/huggingface")
    hf_hub_cache: Path = Path("/tmp/mcp-vs-cache/hub")

    # Sessions
    session_root_dir: Path = Path("/var/lib/research-mind/sessions")
    session_ttl_hours: int = 24

    # Logging
    log_level: str = "INFO"
    audit_log_path: Path = Path("/var/log/research-mind/audit.log")

    # CORS
    cors_origins: list = ["http://localhost:15000"]

    class Config:
        env_file = ".env"
        case_sensitive = False

settings = Settings()
```

### Load Configuration in Main App

```python
# research-mind-service/app/main.py

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.core.vector_search import _vs_manager

app = FastAPI(title="Research-Mind Service")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup_event():
    """Initialize on startup."""
    # Pre-load vector search manager
    # This triggers model download on first startup
    _ = _vs_manager.indexer
    print("Vector search manager initialized")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown."""
    print("Shutting down")
```

---

## Pre-Phase Verification Checklist

### Checklist Items (Complete These Before Phase 1 Kickoff)

#### ✓ Environment Setup (1.0.1-1.0.3)

- [ ] Python 3.12+ installed and verified
- [ ] Virtual environment created and activated
- [ ] pip/setuptools/wheel upgraded
- [ ] Disk space: 3GB+ available

**Verification Command**:
```bash
python --version && df -h / && ls -la .venv/
```

#### ✓ Dependencies Installed (1.0.2)

- [ ] mcp-vector-search added to pyproject.toml
- [ ] `uv sync` completed successfully
- [ ] All imports verified (transformers, torch, chromadb, etc.)
- [ ] Disk usage acceptable (~1.5-2GB for .venv/)

**Verification Command**:
```bash
python -c "from mcp_vector_search import Client; print('OK')" && du -sh .venv/
```

#### ✓ Database Ready (1.0.3)

- [ ] PostgreSQL running
- [ ] Alembic migrations applied (`alembic upgrade head`)
- [ ] Session database connection works
- [ ] Tables created (sessions, audit_logs)

**Verification Command**:
```bash
alembic current && python -c "import sqlalchemy; print('DB OK')"
```

#### ✓ Directory Structure (1.0.4)

- [ ] app/sandbox/ directory created
- [ ] app/sandbox/__init__.py exists
- [ ] (Later) app/models/session.py stub created

**Verification Command**:
```bash
ls -la app/sandbox/ && test -f app/sandbox/__init__.py && echo "OK"
```

#### ✓ Model Caching (1.0.5 - Proof of Concept)

- [ ] ChromaDB connection test passed
- [ ] Environment variables set correctly
- [ ] Model download succeeds (may take 2-3 minutes on first run)
- [ ] Subsequent calls use cache (<1s)

**Verification Command**:
```bash
time python -c "from mcp_vector_search import Client; c = Client(); c.index(path='.')" # First run: ~2-3min
time python -c "from mcp_vector_search import Client; c = Client()" # Second run: <1s
```

#### ✓ Docker Ready (1.0.7 - Optional)

- [ ] Docker installed and running
- [ ] docker-compose.yml valid (`docker-compose config` succeeds)
- [ ] Can build service image (optional, for Phase 1.8)

**Verification Command**:
```bash
docker --version && docker-compose config > /dev/null && echo "Docker OK"
```

#### ✓ Baseline Documentation (1.0.8)

- [ ] Environment variables documented in `.env.example`
- [ ] Phase 1.0 setup steps recorded
- [ ] Risks discovered during setup documented
- [ ] Troubleshooting notes for common issues captured

**Example .env.example**:
```bash
# Copy from .env, remove sensitive values
DATABASE_URL=postgresql://postgres:PASSWORD@localhost:5432/research_mind
MCP_VECTOR_SEARCH_CACHE_DIR=/tmp/mcp-vs-cache
# ... etc
```

### Verification Script (Automated)

```bash
#!/bin/bash
# research-mind-service/scripts/verify-phase-1-0.sh

set -e

echo "=== Phase 1.0 Verification Script ==="

echo "1. Python version..."
python3 --version | grep -q "3.12" && echo "✓ Python 3.12+" || echo "✗ Python <3.12"

echo "2. Virtual environment..."
test -d .venv && echo "✓ .venv exists" || echo "✗ .venv missing"

echo "3. mcp-vector-search installed..."
python -c "from mcp_vector_search import Client; print('✓ mcp-vector-search OK')" || echo "✗ Installation failed"

echo "4. Disk space..."
available=$(df / | awk 'NR==2 {print int($4/1024)}')
test $available -gt 3000 && echo "✓ >3GB available" || echo "⚠ <3GB available"

echo "5. Database..."
python -c "import sqlalchemy; print('✓ Database OK')" || echo "✗ Database failed"

echo "6. Sandbox directory..."
test -d app/sandbox && echo "✓ app/sandbox exists" || echo "✗ app/sandbox missing"

echo "7. Docker..."
docker --version > /dev/null 2>&1 && echo "✓ Docker OK" || echo "⚠ Docker not available"

echo ""
echo "=== Phase 1.0 Verification Complete ==="
```

**Run verification**:
```bash
chmod +x scripts/verify-phase-1-0.sh
./scripts/verify-phase-1-0.sh
```

---

## Risk Mitigation & Troubleshooting

### Common Installation Issues

#### Issue 1: "No space left on device"

**Cause**: Insufficient disk space for ~2.5GB mcp-vector-search dependencies

**Solution**:
```bash
# Check available space
df -h / | tail -1

# If <3GB, free up space:
# Option A: Clean pip cache
pip cache purge

# Option B: Use external disk
export TRANSFORMERS_CACHE=/Volumes/ExternalDisk/cache/transformers

# Option C: Increase disk allocation (if VM)
# Increase VM disk in hypervisor settings
```

**Prevention**: Check space before Phase 1.0 (Step 1.0.1)

---

#### Issue 2: "ModuleNotFoundError: No module named 'mcp_vector_search'"

**Cause**: Package not installed or venv not activated

**Solution**:
```bash
# Verify venv activated
which python | grep .venv
# Should show: /path/to/.venv/bin/python

# If not activated
source .venv/bin/activate

# Reinstall
cd research-mind-service
uv sync

# Verify
python -c "from mcp_vector_search import Client; print('OK')"
```

**Prevention**: Always verify venv activation before running commands

---

#### Issue 3: "torch installation hangs or fails"

**Cause**: Large package (600MB+), network issues, or permission problems

**Solution**:
```bash
# Upgrade pip first
python -m pip install --upgrade pip

# Install with verbose output
python -m pip install torch -v

# If still fails, check network
curl -I https://pypi.org/simple/torch/

# Alternative: Use conda (if available)
conda install pytorch -c pytorch
```

**Prevention**: Run installation on stable network connection, allow 10+ minutes

---

#### Issue 4: "PostgreSQL connection refused"

**Cause**: Database not running or connection string incorrect

**Solution**:
```bash
# Check if running
# macOS
brew services list | grep postgres

# Linux
systemctl status postgresql

# If not running, start it
# macOS
brew services start postgresql

# Linux
sudo systemctl start postgresql

# Verify connection
psql -U postgres -c "SELECT 1;"

# Check DATABASE_URL in .env
# Expected: postgresql://username:password@localhost:5432/research_mind
```

**Prevention**: Start PostgreSQL before Phase 1.0

---

#### Issue 5: "HuggingFace model download timeout"

**Cause**: Network issues or HuggingFace API overload

**Solution**:
```bash
# Set timeout
export HF_HUB_TIMEOUT=60  # seconds

# Pre-download model manually
python -c "
from transformers import AutoModel
AutoModel.from_pretrained('all-MiniLM-L6-v2')
"

# If fails, check HuggingFace status
curl https://huggingface.co/api/status

# Alternative: Use local model path if available
export TRANSFORMERS_OFFLINE=1
```

**Prevention**: Download model during Phase 1.0 setup (not during Phase 1.1)

---

### Concurrent Access Safety

**Question**: Is per-session collection approach safe with concurrent indexing?

**Research Finding** (from combined-architecture-recommendations.md): "ChromaDB concurrent write safety: How safe is concurrent write to same collection from multiple indexing jobs?" - Open question.

**Mitigation Strategy**:

1. **Test concurrent writes in Phase 1.0**:
```python
# research-mind-service/tests/test_concurrent_access.py

import asyncio
from pathlib import Path
from app.core.vector_search import SessionIndexer

async def test_concurrent_indexing():
    """Test concurrent writes to shared ChromaDB."""
    session1 = SessionIndexer("session_1", Path("/tmp/session_1"))
    session2 = SessionIndexer("session_2", Path("/tmp/session_2"))

    # Index simultaneously
    task1 = session1.index_directory(Path("test_data1"))
    task2 = session2.index_directory(Path("test_data2"))

    results = await asyncio.gather(task1, task2)

    # Verify no cross-contamination
    s1_results = await session1.search("test")
    s2_results = await session2.search("test")

    # Results should be separate
    assert s1_results["count"] > 0
    assert s2_results["count"] > 0
    # BUT verify no overlap (hard to test without specifics)
```

2. **Plan Fallback** (if issues found):
   - Separate ChromaDB instance per session
   - Adds complexity but guarantees isolation

3. **Document Findings**:
   - Record in Phase 1.0 baseline
   - Inform Phase 1.1 implementation decisions

---

## Phase 1.0 Environment Baseline

### Baseline Document Template

Create `docs/PHASE_1_0_BASELINE.md` documenting:

```markdown
# Phase 1.0 Environment Baseline

**Date**: [Date Phase 1.0 Completed]
**Engineer**: [Name]
**Status**: [Ready for Phase 1.1 / Needs Work]

## System Environment

- **Python Version**: [e.g., 3.12.1]
- **Virtual Environment**: [e.g., /Users/mac/workspace/research-mind/.venv]
- **OS**: [macOS/Linux/Windows]
- **Architecture**: [x86_64/ARM64]
- **Disk Space Available**: [e.g., 150GB /]

## Installed Versions

- mcp-vector-search: [version]
- transformers: [version]
- torch: [version]
- chromadb: [version]
- FastAPI: [version]
- SQLAlchemy: [version]

## Performance Baseline

| Operation | Duration | Notes |
|-----------|----------|-------|
| Model load (first run) | 30-60s | One-time on service startup |
| Model access (cached) | <1ms | Subsequent calls |
| Index single file | 100-500ms | Depends on file size |
| Search query | 50-150ms | Typical 10 results |

## Verified Functionality

- ✓ mcp-vector-search imports successfully
- ✓ ChromaDB connection works
- ✓ Model caching via environment variables
- ✓ Session-scoped collections (collection_name parameter)
- ✓ Concurrent access to shared ChromaDB (test results: [PASS/NEEDS_WORK])
- ✓ PostgreSQL connectivity
- ✓ Alembic migrations applied

## Known Issues & Mitigations

### Issue: Model Download Takes 2-3 Minutes
- **Mitigation**: Pre-download in Phase 1.0, use cache in Phase 1+
- **Impact**: One-time cost on first service startup

### Issue: [Any other issues discovered]
- **Cause**: [Root cause]
- **Mitigation**: [How to handle]
- **Impact**: [What's affected]

## Risk Assessment

### Critical Risks Mitigated

- [Risk]: ChromaDB concurrent writes
  - **Status**: ✓ Tested with [test name], results: [pass/inconclusive]
  - **Decision**: Proceed with per-session collections

### Remaining Risks

- [Risk]: [Description]
  - **Probability**: [Low/Medium/High]
  - **Mitigation**: [How to handle in Phase 1.1+]

## Recommendations for Phase 1.1

1. [Specific recommendation based on Phase 1.0 findings]
2. [Monitoring/logging needed]
3. [Performance optimization opportunities]

## Approval Checklist

- [ ] All verification tests pass
- [ ] Baseline document complete
- [ ] Known issues documented
- [ ] Risk mitigation strategies in place
- [ ] Engineering team briefed on findings

**Approved for Phase 1.1 kickoff**: [Yes/No]
**Approved by**: [Name]
**Date**: [Date]
```

---

## Timeline Impact & Critical Path

### Phase 1.0 Duration: 2-3 Days

| Day | Tasks | Duration | Cumulative |
|-----|-------|----------|-----------|
| **Day 1** | 1.0.1-1.0.3: Env setup, install, verify | 4-6h | 4-6h |
| **Day 1-2** | 1.0.2 (continued): Model caching test | 2-4h | 6-10h |
| **Day 2** | 1.0.4-1.0.7: Directories, Docker, config | 4-6h | 10-16h |
| **Day 3** | 1.0.8: Documentation, baseline, approval | 2-4h | 12-20h |

**Total**: 12-20 hours (2-3 calendar days)

### Critical Path Impact

**Original Plan** (without Phase 1.0):
```
Start → Phase 1.1 (5-6 days) → Phase 1.2,1.3,1.4 (parallel) → ...
Risk: mcp-vector-search issues discovered during Phase 1.1
```

**With Phase 1.0**:
```
Phase 1.0 (2-3 days) → Phase 1.1 (5-6 days) → Phase 1.2,1.3,1.4 (parallel) → ...
Benefit: Issues discovered early, Phase 1.1 can start with confidence
```

**Net Impact**:
- **Added**: 2-3 days (Phase 1.0)
- **Saved**: 3-5 days (avoiding Phase 1.1 troubleshooting)
- **Net**: +0-2 days, but with much higher confidence and lower risk

### Revised Phase 1 Timeline

| Phase | Original | Adjusted | Notes |
|-------|----------|----------|-------|
| **1.0** | - | 2-3 days | NEW: Pre-phase setup |
| **1.1** | 3-4 days | 5-6 days | Slightly extended for mcp-vector-search integration |
| **1.2** | 3-4 days | 3-4 days | Session CRUD |
| **1.3** | 4-5 days | 5-6 days | Vector search REST API |
| **1.4** | 2-3 days | 2-3 days | Path validator (parallel with 1.1) |
| **1.5** | 2-3 days | 2-3 days | Audit logging |
| **1.6** | 4-5 days | 5-7 days | Agent integration |
| **1.7** | 4 days | 5-7 days | Integration tests (includes security) |
| **1.8** | 2 days | 2 days | Documentation |
| **TOTAL** | 10-12 days | 15-21 days | More realistic, lower risk |

**Revised Expectation**: **Phase 1 MVP in 15-21 calendar days** (not 10-12)

---

## Reference Implementation Patterns

### Pattern: Creating Session Model (Phase 1.2 Preview)

```python
# research-mind-service/app/models/session.py

from sqlalchemy import Column, String, DateTime, Integer, JSON, Boolean
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
from pathlib import Path
import uuid

Base = declarative_base()

class Session(Base):
    """Database model for research sessions."""

    __tablename__ = "sessions"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(200), nullable=False)
    description = Column(String(1000), nullable=True)

    # Workspace and indexing
    workspace_path = Column(String(500), unique=True, nullable=False)
    index_path = Column(String(500), nullable=False)

    # Status and metadata
    status = Column(String(50), default="initialized")  # initialized, indexing, ready, error
    created_at = Column(DateTime, default=datetime.utcnow)
    last_accessed = Column(DateTime, default=datetime.utcnow)
    last_indexed = Column(DateTime, nullable=True)

    # Statistics
    content_count = Column(Integer, default=0)
    total_chunks = Column(Integer, default=0)
    total_documents = Column(Integer, default=0)
    storage_size_bytes = Column(Integer, default=0)

    # Configuration
    config = Column(JSON, nullable=True)  # Store mcp-vector-search config

    # TTL support
    ttl_hours = Column(Integer, default=24)
    expires_at = Column(DateTime, nullable=True)

    def __repr__(self):
        return f"<Session {self.id} {self.name}>"
```

### Pattern: Creating Index Status Tracking (Phase 1.3 Preview)

```python
# research-mind-service/app/models/indexing_job.py

from sqlalchemy import Column, String, DateTime, Float, Integer, JSON, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
import uuid

Base = declarative_base()

class IndexingJob(Base):
    """Track async indexing jobs."""

    __tablename__ = "indexing_jobs"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)

    status = Column(String(50), default="pending")  # pending, running, completed, failed
    progress = Column(Float, default=0.0)  # 0.0-1.0

    created_at = Column(DateTime, default=datetime.utcnow)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)

    # Metrics
    files_to_process = Column(Integer, default=0)
    files_processed = Column(Integer, default=0)
    chunks_created = Column(Integer, default=0)
    current_file = Column(String(500), nullable=True)

    # Error handling
    error_message = Column(String(1000), nullable=True)
    error_traceback = Column(String(5000), nullable=True)

    # Configuration
    config = Column(JSON, nullable=True)  # indexing options

    def __repr__(self):
        return f"<IndexingJob {self.id} {self.status}>"
```

### Pattern: FastAPI Startup/Shutdown (Phase 1.1 Integration)

```python
# research-mind-service/app/main.py

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from app.core.config import settings
from app.core.vector_search import _vs_manager
from app.routes import sessions, vector_search, health

logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Handle startup and shutdown."""

    # Startup
    logger.info("Starting research-mind service...")
    try:
        # Pre-load vector search manager
        # This triggers model download on first startup
        _ = _vs_manager.indexer
        logger.info("Vector search manager initialized")
    except Exception as e:
        logger.error(f"Failed to initialize vector search: {e}")
        raise

    yield

    # Shutdown
    logger.info("Shutting down research-mind service...")
    # Add cleanup if needed

app = FastAPI(
    title="Research-Mind Service",
    description="Semantic code search with agentic analysis",
    version="1.0.0",
    lifespan=lifespan
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(health.router)
app.include_router(sessions.router)
app.include_router(vector_search.router)

@app.get("/api/v1/health")
async def health_check():
    """Service health check."""
    return {
        "status": "healthy",
        "version": "1.0.0"
    }
```

---

## Summary & Next Steps

### Phase 1.0 Completion Checklist

- [ ] Environment prerequisites verified (1.0.1)
- [ ] mcp-vector-search installed and tested (1.0.2)
- [ ] PostgreSQL connected and migrations applied (1.0.3)
- [ ] Sandbox directory structure created (1.0.4)
- [ ] Model caching tested (1.0.5)
- [ ] Docker verified (1.0.7)
- [ ] Baseline documentation complete (1.0.8)
- [ ] All verification tests pass
- [ ] Known issues documented and mitigated
- [ ] Team briefed on Phase 1.0 findings

### Approval Gate

**Before proceeding to Phase 1.1:**

1. ✓ Phase 1.0 baseline document signed off
2. ✓ All critical risks mitigated (concurrent access, model caching, etc.)
3. ✓ pyproject.toml updated with mcp-vector-search
4. ✓ Verification script passes
5. ✓ Team consensus on timeline adjustment (10-12 → 15-21 days)

### Handoff to Phase 1.1

Upon Phase 1.0 completion:

1. **Engineering team** receives Phase 1.0 baseline document
2. **Phase 1.1 planning** accounts for:
   - Extended mcp-vector-search setup complexity
   - Environment configuration requirements
   - Model caching singleton pattern
   - Session-scoped collection management
3. **Phase 1.1 kickoff** with confidence that dependencies are verified

### Key Artifacts Produced by Phase 1.0

1. **Phase 1.0 Baseline Document** (`docs/PHASE_1_0_BASELINE.md`)
2. **Updated pyproject.toml** with mcp-vector-search dependency
3. **Verification script** (`scripts/verify-phase-1-0.sh`)
4. **.env.example** template
5. **Troubleshooting guide** (within this document)
6. **Risk assessment** for Phase 1.1+

---

## Appendix: Quick Reference

### Commands Cheat Sheet

```bash
# Phase 1.0.1: Environment Setup
python3 --version
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel

# Phase 1.0.2: Install mcp-vector-search
cd research-mind-service
uv sync
python -c "from mcp_vector_search import Client; print('OK')"

# Phase 1.0.3: Database
alembic current
alembic upgrade head

# Phase 1.0.4: Directories
mkdir -p app/sandbox
touch app/sandbox/__init__.py

# Phase 1.0.5: Model caching test
export TRANSFORMERS_CACHE=/tmp/mcp-vs-cache/transformers
time python -c "from transformers import AutoModel; AutoModel.from_pretrained('all-MiniLM-L6-v2')"

# Phase 1.0.7: Docker
docker --version
docker-compose config > /dev/null && echo "OK"

# Phase 1.0: Full verification
./scripts/verify-phase-1-0.sh
```

### Key Directories & Files

| Path | Purpose | Status |
|------|---------|--------|
| `research-mind-service/pyproject.toml` | Dependencies (ADD mcp-vector-search) | TO DO |
| `research-mind-service/.env` | Environment configuration | TO DO |
| `research-mind-service/.env.example` | Template for .env | TO DO |
| `research-mind-service/app/sandbox/` | Sandbox layer (Phase 1.4) | TO DO |
| `research-mind-service/app/core/vector_search.py` | VectorSearchManager singleton | TO DO |
| `research-mind-service/app/models/session.py` | Session database model | TO DO |
| `research-mind-service/scripts/verify-phase-1-0.sh` | Verification script | TO DO |
| `docs/PHASE_1_0_BASELINE.md` | Environment baseline document | TO DO |

---

## References

### Research Documentation

1. **mcp-vector-search-packaging-installation.md** (1,388 lines)
   - Comprehensive installation guide
   - Model caching strategies
   - Docker deployment patterns
   - CI/CD integration

2. **mcp-vector-search-capabilities.md**
   - Architecture overview
   - Indexing and search flow
   - ChromaDB integration
   - Extension points for REST API

3. **mcp-vector-search-rest-api-proposal.md**
   - REST API endpoint specifications
   - Session management design
   - Job model and async patterns
   - Security considerations

4. **PLAN_VS_RESEARCH_ANALYSIS.md**
   - Gap analysis identifying critical blockers
   - Scaffolding readiness assessment
   - Risk assessment for Phase 1+
   - Timeline adjustments (10-12 → 15-21 days)

5. **combined-architecture-recommendations.md**
   - Final architectural recommendations
   - Risk register and mitigations
   - Implementation strategy
   - Cost/latency targets

### External Resources

- **mcp-vector-search Repository**: https://github.com/anthropics/mcp-vector-search
- **ChromaDB Documentation**: https://docs.trychroma.com/
- **HuggingFace Transformers**: https://huggingface.co/docs/transformers/
- **FastAPI Documentation**: https://fastapi.tiangolo.com/
- **Pydantic Settings**: https://docs.pydantic.dev/latest/concepts/pydantic_settings/

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-31 | Research Agent | Initial comprehensive guide |

**Status**: Ready for Phase 1.0 execution

---

**End of MCP Vector Search Integration Guide**
