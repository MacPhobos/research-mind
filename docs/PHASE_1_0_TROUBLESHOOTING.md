# Phase 1.0 Troubleshooting Guide

Common issues encountered during Phase 1.0 environment setup and their solutions.

---

## Issue 1: PyTorch Installation Fails

### Symptoms

```
error: Microsoft Visual C++ 14.0 is required
```

or

```
fatal error: Python.h: No such file or directory
```

### Root Cause

Missing system compiler or development headers required to build PyTorch from source.

### Solutions

**macOS**:

```bash
xcode-select --install
```

**Linux (Ubuntu/Debian)**:

```bash
sudo apt install build-essential python3.12-dev
```

### Prevention

Install build tools BEFORE running `pip install mcp-vector-search`.

---

## Issue 2: HuggingFace Model Download Times Out

### Symptoms

```
TimeoutError: Download of model-file failed
```

or

```
HfHubHTTPError: 429 Client Error: Too Many Requests
```

### Root Cause

Network timeout, insufficient disk space, or HuggingFace rate limiting.

### Solutions

1. **Check disk space**:

   ```bash
   df -h
   # Should have 2.5GB+ available
   ```

2. **Set cache directory**:

   ```bash
   export HF_HOME=~/.cache/huggingface
   export TRANSFORMERS_CACHE=~/.cache/huggingface/transformers
   export HF_HUB_CACHE=~/.cache/huggingface/hub
   ```

3. **Retry with backoff**:

   ```bash
   # Try again in a few minutes
   python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"
   ```

4. **Use alternative cache**:
   ```bash
   mkdir -p /tmp/hf_cache
   export HF_HOME=/tmp/hf_cache
   python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"
   ```

### Prevention

- Pre-download model in isolation before Phase 1.1 starts
- Ensure 500MB+ free disk space before downloading
- Use HF_TOKEN if available for higher rate limits

---

## Issue 3: PostgreSQL Connection Refused

### Symptoms

```
psql: error: connection to server at "localhost" (127.0.0.1), port 5432 failed
FATAL: the database system is initializing recovery
```

### Root Cause

PostgreSQL service not running, incorrect credentials, or database not created.

### Solutions

1. **Check if running** (macOS):

   ```bash
   brew services list | grep postgres
   # Should show "started"
   ```

2. **Start PostgreSQL** (macOS):

   ```bash
   brew services start postgresql@18
   ```

3. **Check credentials**:

   ```bash
   psql -U mac -h localhost -c "SELECT version();"
   # Use correct username (mac, postgres, etc.)
   ```

4. **Create database**:
   ```bash
   psql -U mac -h localhost -d postgres -c "CREATE DATABASE research_mind;"
   ```

### Prevention

- Verify PostgreSQL running BEFORE Phase 1.0 begins: `psql --version`
- Test connection BEFORE running migrations: `psql -h localhost -c "SELECT 1;"`

---

## Issue 4: mcp-vector-search Imports Fail

### Symptoms

```
ModuleNotFoundError: No module named 'mcp_vector_search'
```

### Root Cause

mcp-vector-search not installed, installed to wrong Python version, or pip cache issue.

### Solutions

1. **Verify installation**:

   ```bash
   python3 -m pip show mcp-vector-search
   ```

2. **Reinstall**:

   ```bash
   pip install --upgrade --force-reinstall mcp-vector-search
   ```

3. **Check Python version**:

   ```bash
   python3 --version
   # Must be 3.12+
   ```

4. **Clear pip cache**:
   ```bash
   pip cache purge
   pip install mcp-vector-search
   ```

### Prevention

- Verify Python 3.12+ BEFORE installing: `python3 --version`
- Use consistent Python version: `which python3`

---

## Issue 5: Docker Daemon Not Running

### Symptoms

```
error during connect: This error may indicate the docker daemon is not running.
```

### Root Cause

Docker application not started.

### Solutions

**macOS**:

```bash
# Start Docker.app
open /Applications/Docker.app

# Wait 30 seconds, then verify
docker ps
```

**Linux**:

```bash
sudo systemctl start docker
```

### Prevention

- Start Docker before running docker commands
- For Phase 1.0, Docker is optional - defer to Phase 1.8 if not needed

---

## Issue 6: Out of Memory During Installation

### Symptoms

```
MemoryError: Unable to allocate X.XX GiB for an array
```

### Root Cause

Insufficient RAM to compile PyTorch or other large packages.

### Solutions

1. **Close unnecessary applications** to free RAM

2. **Install in stages**:

   ```bash
   pip install torch transformers sentence-transformers
   pip install mcp-vector-search
   ```

3. **Reduce system load**:
   ```bash
   # Kill other processes consuming memory
   ```

### Prevention

- Verify 4GB+ RAM available: `vm_stat` (macOS) or `free -h` (Linux)
- Close IDE, browser, other apps before installing

---

## Issue 7: Session Model Imports Fail

### Symptoms

```
ModuleNotFoundError: No module named 'sqlalchemy'
```

### Root Cause

SQLAlchemy not installed or different Python version used.

### Solutions

1. **Install SQLAlchemy**:

   ```bash
   pip install sqlalchemy
   ```

2. **Verify in correct directory**:
   ```bash
   cd research-mind-service
   python3 -c "from app.models.session import Session; print('✓')"
   ```

### Prevention

- Install all dependencies from `pyproject.toml` before Phase 1.0 starts

---

## Issue 8: Alembic Configuration Error

### Symptoms

```
sqlalchemy.exc.NoSuchModuleError: Can't load plugin: sqlalchemy.dialects:driver
```

### Root Cause

Database URL has incorrect format or driver not installed.

### Solutions

1. **Verify DATABASE_URL format**:

   ```bash
   # Should be: postgresql://user@host:port/dbname
   echo $DATABASE_URL
   ```

2. **Install psycopg**:

   ```bash
   pip install psycopg[binary]
   ```

3. **Test connection manually**:
   ```bash
   psql -h localhost -U mac -d research_mind -c "SELECT 1;"
   ```

### Prevention

- Use `.env.example` template for DATABASE_URL
- Install psycopg before running migrations

---

## Issue 9: Network Timeout During pip Install

### Symptoms

```
ERROR: Could not find a version that satisfies the requirement
```

### Root Cause

Network connectivity issue or PyPI mirror unavailable.

### Solutions

1. **Check internet**:

   ```bash
   ping google.com
   ```

2. **Use alternative mirror**:

   ```bash
   pip install -i https://mirror.baidu.com/pypi/simple mcp-vector-search
   ```

3. **Retry with patience**:
   ```bash
   pip install --retries 5 mcp-vector-search
   ```

### Prevention

- Install during stable network connectivity
- Have backup network option (mobile hotspot)

---

## Issue 10: Python Version Conflicts

### Symptoms

```
python3: command not found
```

or

```
Python 3.11.0 (too old, need 3.12+)
```

### Root Cause

Multiple Python versions installed, PATH issues, or older version default.

### Solutions

1. **Check which Python**:

   ```bash
   which python3
   python3 --version
   ```

2. **Use explicit path**:

   ```bash
   /usr/local/bin/python3.12 --version
   ```

3. **Install 3.12** (macOS):
   ```bash
   brew install python@3.12
   brew link python@3.12
   ```

### Prevention

- Verify `python3 --version` returns 3.12+ at session start
- Add correct Python to PATH if needed

---

## Verification Checklist

After resolving any issues, verify Phase 1.0 completion:

```bash
# 1. Python
python3 --version  # Should be 3.12+

# 2. mcp-vector-search
python3 -c "from mcp_vector_search.core import GitManager; print('✓')"

# 3. Dependencies
python3 -c "import torch, transformers, chromadb; from sentence_transformers import SentenceTransformer; print('✓')"

# 4. Database
psql -U mac -d research_mind -c "SELECT 1;"

# 5. Model cache
python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2'); print('✓')"

# 6. Sandbox directory
[ -d research-mind-service/app/sandbox ] && echo "✓"

# 7. Session model
cd research-mind-service && python3 -c "from app.models.session import Session; print('✓')"

# 8. Docker (optional)
docker --version && docker ps > /dev/null && echo "✓"
```

If all checks pass, Phase 1.0 is complete and ready for Phase 1.1.

---

## Getting Help

If you encounter issues not listed here:

1. **Check the Phase 1.0 baseline**: `/Users/mac/workspace/research-mind/docs/PHASE_1_0_BASELINE.md`
2. **Review requirements**: `research-mind-service/pyproject.toml`
3. **Check logs**: Look for error messages in full output
4. **Search online**: Search error message + "python 3.12 mcp-vector-search"

---

## Document Metadata

**Version**: 1.0
**Created**: 2026-01-31
**Issues Covered**: 10+ common problems
**Next Update**: After Phase 1.1 begins
