# Phase 1.0: Environment Setup (Pre-Phase)

**Phase Duration**: 2-3 calendar days (10-18 hours of engineering effort)
**Status**: CRITICAL - Must complete before Phase 1.1 begins
**Team Size**: 1 FTE engineer
**Effort Estimate**: 10-18 hours total

---

## Phase Objective

Verify mcp-vector-search is properly installed, configured, and tested. Establish baseline environment documentation. This pre-phase de-risks Phase 1.1-1.8 by validating dependencies and architectural patterns upfront before full development begins.

**Success Definition**: By end of Phase 1.0, engineering team has confidence to proceed with Phase 1.1 knowing all critical dependencies are installed, verified, and documented.

---

## Timeline & Effort

### Day 1 (4-6 hours)

- Task 1.0.1: Environment Prerequisites (30 min)
- Task 1.0.2: Install mcp-vector-search (2-4 hours)
- Task 1.0.3: Verify PostgreSQL (1-2 hours)

### Day 2 (4-6 hours)

- Task 1.0.4: Create Sandbox Directory (1 hour)
- Task 1.0.5: Test Model Caching (1-2 hours)
- Task 1.0.6: Session Model Stub (1-2 hours)
- Task 1.0.7: Verify Docker (1 hour)

### Day 3 (2-4 hours)

- Task 1.0.8: Document Baseline (2-4 hours)

**Total Estimated Time**: 10-18 calendar hours across 2-3 business days
**Critical Path**: Task 1.0.2 (mcp-vector-search installation) is longest single task

---

## Deliverables

1. **Updated pyproject.toml** with mcp-vector-search dependency (pinned version)
2. **.env.example template** with all required environment variables
3. **docs/PHASE_1_0_BASELINE.md** documenting:
   - System environment (Python version, OS, disk space, memory)
   - Package versions installed (mcp-vector-search, PyTorch, transformers, ChromaDB, etc.)
   - Performance baselines (model load time, embedding speed, search latency)
   - Known issues discovered and mitigations applied
   - Risk assessment and architectural decisions validated
4. **scripts/verify-phase-1-0.sh** - Automated verification script for future engineers
5. **Troubleshooting guide** addressing 5+ common installation issues
6. **app/sandbox/ directory** structure created for Phase 1.4 path validator
7. **app/models/session.py stub** (incomplete, finalized in Phase 1.2)

---

## Detailed Tasks

### 1.0.1: Environment Prerequisites (30 minutes)

**Objective**: Verify system meets minimum requirements for mcp-vector-search

#### Checklist

- [ ] Python 3.12+ installed
  - Command: `python3 --version` (must be 3.12 or higher)
  - If missing: install via `brew install python@3.12` (macOS) or `apt install python3.12` (Linux)
- [ ] Virtual environment created and activated
  - Command: `python3.12 -m venv venv && source venv/bin/activate`
- [ ] 3+ GB free disk space available
  - Command: `df -h` (check available space)
  - mcp-vector-search + dependencies = ~2.5GB
  - Embedding model (all-MiniLM-L6-v2) = ~400MB
  - Margin for builds/caches = 100MB
- [ ] 4+ GB RAM available (verify with `free -h` or `vm_stat` on macOS)

**Success Criteria**:

- Python 3.12+ confirmed
- Virtual environment active
- 3GB+ disk space confirmed
- No system blockers identified

---

### 1.0.2: Install mcp-vector-search (2-4 hours) - CRITICAL BLOCKER

**Objective**: Install mcp-vector-search library and verify all transitive dependencies

**Note**: This is the longest single task in Phase 1.0 due to large dependency tree (~2.5GB). Model download (first run only) takes 2-3 minutes.

#### Installation Steps

1. **Add mcp-vector-search to pyproject.toml**

   ```toml
   [project]
   dependencies = [
       "mcp-vector-search>=0.1.0",  # Pin to stable release
       "fastapi>=0.104.0",
       "uvicorn>=0.24.0",
       "sqlalchemy>=2.0.0",
       "pydantic>=2.0.0",
       "pydantic-settings>=2.0.0",
   ]
   ```

2. **Install via uv (fast, parallel dependency resolution)**

   ```bash
   uv sync
   ```

   Expected: 5-10 minutes depending on network speed and cache state

3. **Verify Core Imports**

   ```python
   python3 -c "
   from mcp_vector_search import Client
   from mcp_vector_search.indexing import SemanticIndexer
   from mcp_vector_search.search import SearchEngine
   print('✓ mcp-vector-search imports working')
   "
   ```

4. **Verify Transitive Dependencies** (these must all be present for model to load)
   ```python
   python3 -c "
   import torch
   import transformers
   from sentence_transformers import SentenceTransformer
   import chromadb
   print('✓ All transitive dependencies present')
   print(f'  PyTorch version: {torch.__version__}')
   print(f'  Transformers version: {transformers.__version__}')
   print(f'  ChromaDB version: {chromadb.__version__}')
   "
   ```

#### Expected Dependency Tree

```
mcp-vector-search (0.1.0+)
├── torch (~2.0 or higher) - ~600MB
├── transformers (~4.30+) - ~500MB
├── sentence-transformers (~2.2+) - ~200MB
├── chromadb (~0.4+) - ~150MB
├── numpy
├── scikit-learn
├── pandas
└── [other dependencies]

Total: ~2.5GB of disk space
```

#### Troubleshooting

**Problem**: PyTorch installation fails due to missing compiler
**Solution**: Ensure Xcode Command Line Tools installed (macOS) or build-essential (Linux)

```bash
# macOS
xcode-select --install

# Linux (Ubuntu/Debian)
sudo apt install build-essential python3.12-dev
```

**Problem**: Out of memory during `uv sync`
**Solution**: Install in stages with specific versions

```bash
pip install torch transformers sentence-transformers chromadb
uv sync
```

**Problem**: HuggingFace model download fails
**Solution**: Set cache directory and retry

```bash
export HF_HOME=/tmp/hf_cache
python3 -c "from sentence_transformers import SentenceTransformer; m = SentenceTransformer('all-MiniLM-L6-v2')"
```

**Success Criteria**:

- [ ] `uv sync` completes without errors
- [ ] Core imports succeed (Client, SemanticIndexer, SearchEngine)
- [ ] All transitive dependencies verified
- [ ] pip freeze shows mcp-vector-search installed

---

### 1.0.3: Verify PostgreSQL (1-2 hours)

**Objective**: Ensure database is running and migrations are applied

#### Steps

1. **Start PostgreSQL Service** (if not already running)

   ```bash
   # macOS (via Homebrew)
   brew services start postgresql@15

   # Linux (Ubuntu/Debian)
   sudo systemctl start postgresql

   # Docker
   docker-compose up -d postgres
   ```

2. **Verify Connection**

   ```bash
   psql -h localhost -U postgres -c "SELECT version();"
   ```

   Expected: PostgreSQL version 13+ confirmed

3. **Run Alembic Migrations**

   ```bash
   cd research-mind-service
   alembic upgrade head
   ```

   Expected output:

   ```
   INFO  [alembic.runtime.migration] Context impl PostgresqlImpl()
   INFO  [alembic.runtime.migration] Will assume transactional DDL is supported by the backend
   INFO  [alembic.migration] Running upgrade  -> 001_initial_schema, done
   ```

4. **Verify Tables Created**
   ```bash
   psql -h localhost -U postgres -d research_mind -c "
   SELECT table_name FROM information_schema.tables
   WHERE table_schema = 'public' ORDER BY table_name;
   "
   ```
   Expected tables:
   - `sessions` (created by 001_initial_schema)
   - `audit_logs` (created by migration if Phase 1.5 schema applied)
   - `alembic_version` (migration tracking)

#### Database Configuration

Create/verify `.env` file with:

```bash
DATABASE_URL=postgresql://postgres:password@localhost:5432/research_mind  # pragma: allowlist secret
SQLALCHEMY_ECHO=false  # Set to true for SQL debugging
```

**Success Criteria**:

- [ ] PostgreSQL service running
- [ ] Connection verified
- [ ] Alembic migrations applied successfully
- [ ] All expected tables present
- [ ] .env configured with DATABASE_URL

---

### 1.0.4: Create Sandbox Directory (1 hour)

**Objective**: Establish directory structure for Phase 1.4 path validator

#### Steps

1. **Create Directory Structure**

   ```bash
   mkdir -p research-mind-service/app/sandbox
   touch research-mind-service/app/sandbox/__init__.py
   ```

2. **Verify Structure**

   ```bash
   tree research-mind-service/app/sandbox/
   ```

   Expected:

   ```
   research-mind-service/app/sandbox/
   └── __init__.py
   ```

3. **Document Purpose** - Create `research-mind-service/app/sandbox/README.md`:

   ```markdown
   # Sandbox Directory

   This directory contains security-critical isolation components for Phase 1.4.

   ## Files

   - `path_validator.py` - Path traversal prevention (Phase 1.4)
   - `session_validator.py` - Session isolation enforcement (Phase 1.4)

   ## Security Critical

   Do not remove or modify these files without security review.
   ```

**Success Criteria**:

- [ ] `app/sandbox/` directory exists
- [ ] `__init__.py` present (makes it Python module)
- [ ] Directory structure verified
- [ ] Purpose documented in README.md

---

### 1.0.5: Test Model Caching (1-2 hours) - Proof of Concept

**Objective**: Verify embedding model can be downloaded and cached successfully

**Rationale**: Model download happens first time mcp-vector-search is used. This is a one-time cost (~2-3 min) that must succeed reliably. We verify this works before Phase 1.1 starts.

#### Steps

1. **Set HuggingFace Cache Environment Variables** (enables persistent caching)

   ```bash
   export TRANSFORMERS_CACHE=~/.cache/huggingface/transformers
   export HF_HOME=~/.cache/huggingface
   export HF_HUB_CACHE=~/.cache/huggingface/hub
   ```

2. **First Run: Download Embedding Model** (2-3 minutes on first run)

   ```python
   python3 << 'EOF'
   import time
   from sentence_transformers import SentenceTransformer

   # First run: downloads model from HuggingFace
   start = time.time()
   model = SentenceTransformer('all-MiniLM-L6-v2')
   duration = time.time() - start

   print(f"✓ Model loaded in {duration:.1f} seconds")
   print(f"  First run is slower (downloads ~400MB)")

   # Test embedding
   sentences = ["This is a test", "Second test sentence"]
   embeddings = model.encode(sentences)
   print(f"✓ Embeddings generated: shape {embeddings.shape}")
   EOF
   ```

   Expected: ~2-3 minutes on first run, files cached in `~/.cache/huggingface/`

3. **Second Run: Verify Cache Hit** (should be <1 second)

   ```python
   python3 << 'EOF'
   import time
   from sentence_transformers import SentenceTransformer

   # Second run: loads from cache (fast)
   start = time.time()
   model = SentenceTransformer('all-MiniLM-L6-v2')
   duration = time.time() - start

   print(f"✓ Model loaded in {duration:.3f} seconds")
   print(f"  Cache hit! (model loaded from ~/.cache/huggingface/)")
   EOF
   ```

   Expected: <1 second (loading from disk cache)

4. **Document Cache Performance Baseline** in PHASE_1_0_BASELINE.md:
   - First run: 2-3 minutes + ~400MB download
   - Subsequent runs: <100ms (in-memory cache)
   - Cache location: `~/.cache/huggingface/`
   - Critical for Phase 1.1 startup latency expectations

#### Caching Architecture Pattern

```python
# This pattern will be used in Phase 1.1's VectorSearchManager singleton

class VectorSearchManager:
    _instance = None
    _model = None  # Cached model, loaded once per process

    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        # Load model ONCE on first access (~30s on first run, cached after)
        # Then reuse for all subsequent requests
        self.model = SentenceTransformer('all-MiniLM-L6-v2')

    def embed(self, text: str) -> np.ndarray:
        # Subsequent calls use cached model (<1ms)
        return self.model.encode(text)
```

**Success Criteria**:

- [ ] First run completes successfully (2-3 minutes)
- [ ] Model downloads to cache directory
- [ ] Second run <1 second (cache hit verified)
- [ ] HuggingFace cache directory exists with model files
- [ ] Embeddings can be generated and have correct shape
- [ ] Performance baseline documented

---

### 1.0.6: Session Model Stub (1-2 hours)

**Objective**: Create incomplete session model that will be completed in Phase 1.2

#### Steps

1. **Create File**: `research-mind-service/app/models/session.py`

   ```python
   """
   Session model for research-mind.

   Persists session metadata, workspace configuration, and indexing state.
   Completed during Phase 1.2, stub created in Phase 1.0.
   """

   from datetime import datetime
   from uuid import uuid4
   from sqlalchemy import Column, String, DateTime, Integer, JSON
   from sqlalchemy.ext.declarative import declarative_base

   Base = declarative_base()

   class Session(Base):
       """
       Session record persisting research context.

       Fields:
       - session_id: UUID v4 identifier (immutable)
       - name: Human-readable session name
       - description: Optional session description
       - workspace_path: Root directory for session content (/var/lib/research-mind/sessions/{id})
       - created_at: Session creation timestamp (UTC)
       - last_accessed: Last activity timestamp (UTC)
       - status: Session lifecycle status (active, archived, deleted)
       - index_stats: JSON blob tracking index metadata
         - file_count: Number of indexed files
         - chunk_count: Number of indexed chunks
         - total_size_bytes: Total indexed content size
         - last_indexed_at: Timestamp of last indexing job
       """
       __tablename__ = "sessions"

       # Primary key
       session_id = Column(String(36), primary_key=True, default=lambda: str(uuid4()))

       # Metadata
       name = Column(String(255), nullable=False)
       description = Column(String(1024), nullable=True)
       workspace_path = Column(String(512), nullable=False, unique=True)

       # Timestamps
       created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
       last_accessed = Column(DateTime, nullable=False, default=datetime.utcnow)

       # Status and configuration
       status = Column(String(50), nullable=False, default="active")

       # Index metadata (JSON)
       index_stats = Column(JSON, nullable=True, default={
           "file_count": 0,
           "chunk_count": 0,
           "total_size_bytes": 0,
           "last_indexed_at": None,
       })

       def __repr__(self):
           return f"<Session {self.session_id}: {self.name}>"
   ```

2. **Verify Import Works**
   ```bash
   cd research-mind-service
   python3 -c "from app.models.session import Session; print('✓ Session model imports successfully')"
   ```

**Success Criteria**:

- [ ] File created at correct path
- [ ] Imports without errors
- [ ] All required fields present (session_id, name, workspace_path, timestamps, etc.)
- [ ] Schema matches Phase 1.2 requirements
- [ ] Comment block documents Phase 1.2 completion plan

---

### 1.0.7: Verify Docker (1 hour)

**Objective**: Ensure Docker and docker-compose are installed and working

#### Steps

1. **Check Docker Installation**

   ```bash
   docker --version
   # Expected: Docker version 20.10+ or higher
   ```

2. **Check docker-compose Installation**

   ```bash
   docker-compose --version
   # Expected: Docker Compose version 2.0+ or higher
   ```

3. **Verify Docker Daemon Running**

   ```bash
   docker ps
   # Expected: Empty list of containers (no error)
   ```

4. **Validate docker-compose.yml** (root of monorepo)

   ```bash
   docker-compose config > /dev/null && echo "✓ docker-compose.yml is valid"
   ```

5. **Test Docker Build** (Dockerfile should exist, may not be fully complete yet)
   ```bash
   cd research-mind-service
   docker build -t research-mind-service:test . 2>&1 | head -20
   ```
   Expected: Build starts (may fail due to incomplete Dockerfile, that's OK)

**Troubleshooting**:

**Problem**: Docker daemon not running
**Solution**:

```bash
# macOS
open /Applications/Docker.app

# Linux
sudo systemctl start docker
```

**Problem**: docker-compose not found
**Solution**:

```bash
# macOS
brew install docker-compose

# Linux
sudo apt install docker-compose
```

**Success Criteria**:

- [ ] `docker --version` returns 20.10+
- [ ] `docker-compose --version` returns 2.0+
- [ ] `docker ps` runs without error
- [ ] `docker-compose config` validates
- [ ] Docker daemon running and accessible

---

### 1.0.8: Document Baseline (2-4 hours)

**Objective**: Create comprehensive baseline documentation for Phase 1 team reference

#### Deliverable 1: docs/PHASE_1_0_BASELINE.md

This document captures the exact state of the development environment after Phase 1.0 completes, including versions, performance baselines, known issues, and risk assessment.

**Template Content**:

```markdown
# Phase 1.0 Environment Baseline

**Date Completed**: [YYYY-MM-DD]
**Engineer**: [Name]
**Duration**: [X hours]
**Status**: [Complete / Partial / With Issues]

## System Information

### Hardware

- OS: [macOS / Linux / other]
- Architecture: [arm64 / x86_64]
- RAM: [X GB]
- Disk Space (Available): [X GB]
- CPU: [Description]

### Python Environment

- Python Version: [3.12.x]
- Virtual Environment: [Path]
- Package Manager: uv / pip / other

## Installed Packages

### Core Dependencies (from Phase 1.0)

- mcp-vector-search: [version]
- torch: [version]
- transformers: [version]
- sentence-transformers: [version]
- chromadb: [version]
- fastapi: [version]
- uvicorn: [version]
- sqlalchemy: [version]
- pydantic: [version]

### Database

- PostgreSQL Version: [version]
- Database Name: research_mind
- Migrations Applied: [number]
- Tables Created: [list]

### Docker

- Docker Version: [version]
- docker-compose Version: [version]
- Docker Daemon: [running/stopped]

## Performance Baselines

### Model Loading

- First Load: [X.X minutes] (includes ~400MB download)
- Cached Load: [X ms] (from ~/.cache/huggingface/)
- Cache Size: [X MB]

### Embedding Generation

- Sample Text: "This is a test"
- Embedding Time: [X ms]
- Vector Dimension: 384 (for all-MiniLM-L6-v2)

### Database

- PostgreSQL Connection Time: [X ms]
- Query Time (simple SELECT): [X ms]

## Known Issues & Mitigations

### Issue 1: [Description]

**Severity**: [Critical / High / Medium / Low]
**Workaround**: [How to work around]
**Resolution Plan**: [Plan to fix, or defer]

### Issue 2: [Description]

...

## Risk Assessment

### Dependency Risks

- [ ] mcp-vector-search compatibility with Python 3.12
- [ ] PyTorch installation issues
- [ ] HuggingFace model download reliability
- [ ] PostgreSQL connectivity
- [ ] Docker setup

### Architecture Risks (for Phase 1.1+)

- [ ] Singleton ChromaDB manager thread safety
- [ ] Per-session collection isolation
- [ ] Model caching invalidation
- [ ] Memory usage under load

**Mitigation Strategy**: [Describe how risks will be mitigated in Phase 1.1-1.8]

## Verification Checklist

- [x] Python 3.12+ installed
- [x] mcp-vector-search installed and imports working
- [x] All transitive dependencies present
- [x] PostgreSQL running and migrations applied
- [x] Model caching verified (2-3 min first run, <1s cached)
- [x] Docker/docker-compose working
- [x] app/sandbox/ directory structure created
- [x] app/models/session.py stub created and imports
- [x] .env.example template created
- [x] No blocking issues for Phase 1.1

## Handoff to Phase 1.1

**Engineering Team**: Ready to proceed with Phase 1.1 (Service Architecture) ✓

**Critical Artifacts**:

- pyproject.toml (with mcp-vector-search dependency)
- .env.example (environment configuration template)
- verify-phase-1-0.sh (automated verification script)
- This baseline document (for reference)

**Assumptions for Phase 1.1**:

- Python 3.12+, mcp-vector-search installed, PostgreSQL running
- Model caching working (first run takes 2-3 min, cached runs <1s)
- Docker available for containerization
- Session model stub ready for completion

**Key Learnings**:
[Engineer captures lessons learned, gotchas, optimizations discovered]

## Sign-Off

**Completed By**: [Name and Date]
**Reviewed By**: [TBD - tech lead review before Phase 1.1 kickoff]
```

#### Deliverable 2: scripts/verify-phase-1-0.sh

Automated verification script for future engineers:

```bash
#!/bin/bash
# verify-phase-1-0.sh
# Automated verification of Phase 1.0 environment setup
# Usage: ./scripts/verify-phase-1-0.sh

set -e

echo "=== Phase 1.0 Environment Verification ==="
echo ""

# Python
echo "[1/8] Python 3.12+ check..."
python3 --version
python3_major=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)
if [ "$python3_major" \< "3.12" ]; then
    echo "✗ Python 3.12+ required (found $python3_major)"
    exit 1
fi
echo "✓ Python 3.12+ verified"
echo ""

# mcp-vector-search
echo "[2/8] mcp-vector-search imports..."
python3 -c "from mcp_vector_search import Client; from mcp_vector_search.indexing import SemanticIndexer; from mcp_vector_search.search import SearchEngine" && echo "✓ mcp-vector-search imports working" || exit 1
echo ""

# Transitive dependencies
echo "[3/8] Transitive dependencies..."
python3 -c "import torch, transformers, chromadb; from sentence_transformers import SentenceTransformer" && echo "✓ All transitive dependencies present" || exit 1
echo ""

# PostgreSQL
echo "[4/8] PostgreSQL connection..."
psql -h localhost -U postgres -c "SELECT 1" > /dev/null && echo "✓ PostgreSQL connected" || exit 1
echo ""

# Alembic migrations
echo "[5/8] Database migrations..."
cd research-mind-service
alembic current > /dev/null && echo "✓ Alembic migrations applied" || exit 1
cd ..
echo ""

# Sandbox directory
echo "[6/8] Sandbox directory..."
[ -d "research-mind-service/app/sandbox" ] && echo "✓ Sandbox directory exists" || exit 1
[ -f "research-mind-service/app/sandbox/__init__.py" ] && echo "✓ Sandbox __init__.py present" || exit 1
echo ""

# Docker
echo "[7/8] Docker verification..."
docker --version > /dev/null && echo "✓ Docker installed" || exit 1
docker-compose --version > /dev/null && echo "✓ docker-compose installed" || exit 1
docker ps > /dev/null 2>&1 && echo "✓ Docker daemon running" || exit 1
echo ""

# Session model
echo "[8/8] Session model stub..."
cd research-mind-service
python3 -c "from app.models.session import Session; print('✓ Session model imports')"
cd ..
echo ""

echo "=== Phase 1.0 Verification Complete ==="
echo "✓ All checks passed - Ready for Phase 1.1"
```

#### Deliverable 3: Troubleshooting Guide (docs/PHASE_1_0_TROUBLESHOOTING.md)

Document addressing 5+ common issues:

1. **PyTorch Installation Fails** - compiler not found
2. **HuggingFace Model Download Times Out** - network or disk space
3. **PostgreSQL Connection Refused** - not running
4. **mcp-vector-search Imports Fail** - missing transitive dependency
5. **Docker Daemon Not Running** - startup issue
6. **Out of Memory During pip install** - insufficient RAM

**Success Criteria**:

- [ ] PHASE_1_0_BASELINE.md created and complete
- [ ] verify-phase-1-0.sh script created and tested
- [ ] Troubleshooting guide covers 5+ common issues
- [ ] All deliverables reviewed by tech lead
- [ ] Known issues and mitigations documented
- [ ] Risk assessment completed
- [ ] Ready to hand off to Phase 1.1

---

## Research References

### Primary References

- **docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md** (Sections 1-5)

  - Section 1: Phase 1.0 Pre-Phase Overview (exactly parallels this document)
  - Section 3: Critical Integration Patterns (singleton, caching, session scoping)
  - Section 4: Architecture Design with code templates
  - Section 5: Environment Setup and Configuration
  - Section 6: Pre-Phase Verification Checklist (maps to acceptance criteria)

- **docs/research2/IMPLEMENTATION_PLAN_ANALYSIS.md** (Section 2)

  - Gap Analysis identifying mcp-vector-search as CRITICAL BLOCKER
  - Justification for Phase 1.0 existence (was not in original plan)
  - Risk register for Phase 1.0 setup

- **docs/research/mcp-vector-search-packaging-installation.md**
  - Practical installation guide (1,388 lines)
  - Docker containerization strategy
  - Testing approach for integration

### Secondary References

- **docs/research/mcp-vector-search-capabilities.md** - Library architecture context
- **IMPLEMENTATION_PLAN.md** - Original plan (Sections: Phase 1.0, Timeline & Effort)

### Context Links

- Original IMPLEMENTATION_PLAN.md Phase 1.0 section (lines 56-164)
- Original IMPLEMENTATION_PLAN.md Timeline section (lines 862-877)
- Original IMPLEMENTATION_PLAN.md Dependencies section (lines 886-919)

---

## Acceptance Criteria

All criteria must be met before Phase 1.1 can begin:

### Critical Path Items (MUST COMPLETE)

- [ ] Python 3.12+ installed and verified
- [ ] mcp-vector-search installed via `uv sync` (no import errors)
- [ ] Model download works (first run 2-3 min, cached runs <1s)
- [ ] PostgreSQL running and migrations applied
- [ ] All expected database tables created
- [ ] Docker and docker-compose installed and verified
- [ ] app/sandbox/ directory structure created
- [ ] app/models/session.py stub created and imports correctly

### Documentation Items (MUST COMPLETE)

- [ ] PHASE_1_0_BASELINE.md written and complete
- [ ] .env.example template created with all variables
- [ ] verify-phase-1-0.sh script created, tested, and documented
- [ ] Troubleshooting guide created (5+ issues covered)
- [ ] Performance baselines measured and documented
- [ ] Risk assessment completed

### Sign-Off Items (MUST COMPLETE)

- [ ] All verification tests pass (automated and manual)
- [ ] No blocking issues identified (or mitigations documented)
- [ ] Tech lead reviews all deliverables
- [ ] Engineering team consensus to proceed to Phase 1.1
- [ ] All artifacts committed to git

---

## Go/No-Go Gates

### Gate 1: Dependency Installation (End of Task 1.0.2)

**Prerequisites for Gate 1**:

- [ ] `uv sync` completes without errors
- [ ] Core imports work (Client, SemanticIndexer, SearchEngine)
- [ ] All transitive dependencies installed

**Go/No-Go Decision**:

- **GO**: All imports successful, no dependency conflicts
- **NO-GO**: Missing dependencies, import failures, or major version conflicts
  - **Resolution**: Debug dependency issues, document workarounds, re-run until GO

**Owner**: Backend engineer
**Approver**: Tech lead (if blocker)

### Gate 2: Environment Setup Complete (End of Task 1.0.8)

**Prerequisites for Gate 2**:

- [ ] All 8 tasks complete (1.0.1 through 1.0.8)
- [ ] verify-phase-1-0.sh passes all checks
- [ ] PHASE_1_0_BASELINE.md written and reviewed
- [ ] All risk assessment and known issues documented
- [ ] No critical blockers for Phase 1.1

**Go/No-Go Decision**:

- **GO**: Phase 1.0 complete, environment ready, team consensus to proceed
- **NO-GO**: Unresolved issues or team concerns about readiness
  - **Resolution**: Address concerns, document decisions, escalate if needed

**Owner**: Backend engineer
**Approver**: Tech lead + engineering team lead
**Documentation**: Sign-off in PHASE_1_0_BASELINE.md

---

## Risks & Mitigations

### Risk 1: mcp-vector-search Installation Failure (CRITICAL)

**Description**: Dependency installation fails due to conflicting packages or missing system dependencies (compiler, system libraries)

**Probability**: Medium (2.5GB dependency tree with PyTorch, transformers, large downloads)

**Impact**: Phase 1.0 cannot complete, Phase 1.1-1.8 blocked indefinitely

**Detection**:

- `uv sync` fails with dependency conflict error
- Import errors when testing core imports
- Build failures in PyTorch/transformers compilation

**Mitigation Strategies**:

1. Use `uv` (faster parallel resolution) instead of pip
2. Pre-verify system has compiler (Xcode tools on macOS, build-essential on Linux)
3. Install core dependencies in stages if monolithic `uv sync` fails
4. Document any custom version pins needed for compatibility
5. Have fallback approach (install to isolated directory, freeze versions)

**Escalation**: If unresolved after 4 hours, escalate to infrastructure team for environment setup

**Fallback**: Use pre-built Docker image with mcp-vector-search already installed (available in Phase 1.0 research guide)

---

### Risk 2: Model Download Failure (CRITICAL)

**Description**: HuggingFace model (all-MiniLM-L6-v2, ~400MB) fails to download on first run

**Probability**: Low-Medium (network timeout, disk space issue, HuggingFace rate limiting)

**Impact**: Model caching cannot be verified, blocking Phase 1.1's VectorSearchManager design

**Detection**:

- Task 1.0.5 fails when attempting first model load
- Network timeout or disk full error during `SentenceTransformer()` initialization
- HuggingFace 429 (rate limit) or 503 (service unavailable) errors

**Mitigation Strategies**:

1. Pre-download model in isolation (separate Python process)
2. Set `HF_HOME` to persistent cache directory
3. Verify 500MB+ disk space before download attempt
4. Use --offline flag or pre-cached model if available
5. Retry with exponential backoff (3 attempts max)

**Fallback**: Use smaller model (DistilBERT instead of all-MiniLM-L6-v2) as proof of concept

---

### Risk 3: PostgreSQL Connection Issues (HIGH)

**Description**: PostgreSQL not running, incorrect connection string, or database not created

**Probability**: Medium (requires manual startup or Docker setup)

**Impact**: Task 1.0.3 fails, database cannot be verified, Phase 1.2 (Session Management) blocked

**Detection**:

- `psql` command fails to connect
- "connection refused" error
- Migration fails to connect to database

**Mitigation Strategies**:

1. Document PostgreSQL startup procedure in .env.example
2. Provide docker-compose.yml with PostgreSQL service (volume-backed)
3. Include diagnostic script to verify connection
4. Pre-create database if not exists (migration handles this)
5. Allow SQLite as fallback for Phase 1.0 verification (switch to Postgres in Phase 1.1)

**Fallback**: Use SQLite for Phase 1.0 verification only, migrate to PostgreSQL before Phase 1.1

---

### Risk 4: Insufficient Disk Space (MEDIUM)

**Description**: mcp-vector-search dependencies + model cache exceed available disk space

**Probability**: Low (2.5GB required, most systems have more), but possible on constrained envs

**Impact**: Installation fails, Phase 1.0 cannot complete

**Detection**:

- `df -h` shows <2.5GB available
- `uv sync` fails with "disk full" error
- Model download fails due to disk space

**Mitigation Strategies**:

1. Task 1.0.1 verifies 3GB+ available before proceeding
2. Clean up unnecessary files (caches, old dependencies)
3. Use fast storage (SSD preferred, not spinning disk)
4. Monitor disk usage during installation with `du -sh ~/.cache`

**Fallback**: Free up space and retry, or use different disk partition

---

### Risk 5: Docker Not Running (LOW)

**Description**: Docker daemon not running or not installed

**Probability**: Low (most dev machines have Docker, but may not be running)

**Impact**: Task 1.0.7 fails, but does not block Phase 1.0 completion (Docker required for Phase 1.8)

**Detection**:

- `docker ps` returns error
- `docker --version` command not found

**Mitigation Strategies**:

1. Provide instructions for starting Docker daemon
2. Include Docker installation check in verify-phase-1-0.sh
3. Document that Docker is required for Phase 1.8 (not critical for Phase 1.0 core)
4. Allow Phase 1.1-1.7 to proceed without Docker (use local Python execution)
5. Phase 1.8 revisits Docker requirement with full setup

**Fallback**: Defer Docker setup to Phase 1.8, proceed with local Python execution for Phase 1.1-1.7

---

## Dependencies

### External Dependencies (Must be installed before Phase 1.0)

- Python 3.12+
- PostgreSQL 13+
- Docker (optional for Phase 1.0, required by Phase 1.8)
- uv package manager

### Internal Dependencies (Phase 1.0 creates/enables)

- mcp-vector-search library (enables Phase 1.1)
- Database migrations (enables Phase 1.2)
- app/sandbox/ directory (enables Phase 1.4)
- Session model stub (enables Phase 1.2)

### Blocking Relationships

```
Phase 1.0 (MUST COMPLETE)
    ↓ (CRITICAL BLOCKER)
Phase 1.1: Service Architecture
    ↓
Phase 1.2-1.8: All remaining Phase 1 subphases
```

---

## Success Metrics

### Quantitative Metrics

| Metric                      | Target    | Measurement                                                |
| --------------------------- | --------- | ---------------------------------------------------------- |
| Installation Time           | 2-3 hours | Wall-clock time from start to `uv sync` completion         |
| mcp-vector-search Imports   | 100%      | All 3 core imports succeed without errors                  |
| Model Load Time (First Run) | 2-3 min   | Time from first `SentenceTransformer()` call to completion |
| Model Load Time (Cached)    | <100ms    | Time from import to initialization with cached model       |
| Disk Space Required         | 2.5GB     | Total of dependencies + model + caches                     |
| Verification Tests          | 100% pass | All 8 verification steps in verify-phase-1-0.sh pass       |

### Qualitative Metrics

| Metric                | Success Criteria                                       |
| --------------------- | ------------------------------------------------------ |
| Documentation Quality | PHASE_1_0_BASELINE.md comprehensive, clear, actionable |
| Risk Assessment       | All known issues documented with mitigations           |
| Troubleshooting       | 5+ common issues covered with solutions                |
| Team Readiness        | Engineering team consensus to proceed to Phase 1.1     |
| Artifact Quality      | All deliverables reviewed by tech lead before sign-off |

---

## Summary

**Phase 1.0** is a critical 2-3 day pre-phase that de-risks Phase 1.1-1.8 by:

1. **Installing mcp-vector-search** (~2.5GB) and verifying all dependencies work
2. **Establishing integration patterns** (singleton ChromaDB, model caching, session scoping)
3. **Validating architecture decisions** through proof-of-concept implementations
4. **Documenting baseline environment** for team reference and troubleshooting
5. **Creating verification automation** for future engineers

Upon Phase 1.0 completion, the engineering team has high confidence in proceeding with Phase 1.1 Service Architecture, knowing all critical dependencies are installed, tested, and documented.

**Phase 1.0 enables Phase 1.1-1.8 to move faster by eliminating setup surprises and establishing proven architectural patterns early.**

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Next Review**: After Phase 1.0 completion (go/no-go gate 2)
