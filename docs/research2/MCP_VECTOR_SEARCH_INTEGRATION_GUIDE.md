# mcp-vector-search Subprocess Integration Guide

**Document Version**: 2.0 (Subprocess-Based)
**Date**: 2026-02-01
**Status**: Production-Ready Integration Guide
**Audience**: Backend engineers integrating mcp-vector-search subprocess in research-mind-service
**Source**: `mcp-vector-search-subprocess-integration-research.md` (verified through testing)

---

## Executive Summary

This guide provides the definitive approach for integrating **mcp-vector-search as a subprocess** within research-mind-service. The tool runs as a standalone CLI process, not as an embedded Python library.

### Key Points

- ✅ **Subprocess-based architecture**: research-mind-service spawns mcp-vector-search CLI process
- ✅ **Per-workspace isolation**: Each workspace maintains independent index in `.mcp-vector-search/` directory
- ✅ **Two-step initialization**: `mcp-vector-search init` (one-time) then `mcp-vector-search index` (on demand)
- ✅ **Exit code reliability**: Simple success/failure detection via exit codes (0 = success, 1 = failure)
- ✅ **Parallel-safe**: Multiple workspaces can index simultaneously without interference

### Quick Start

```python
import subprocess
from pathlib import Path

workspace_dir = Path("/path/to/workspace")

# Step 1: Initialize workspace (one-time)
subprocess.run(
    ["mcp-vector-search", "init", "--force"],
    cwd=str(workspace_dir),
    timeout=30,
    check=True  # Raise CalledProcessError if exit code != 0
)

# Step 2: Index workspace
subprocess.run(
    ["mcp-vector-search", "index", "--force"],
    cwd=str(workspace_dir),
    timeout=60,
    check=True
)
```

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [CLI Command Reference](#cli-command-reference)
3. [Subprocess Invocation Pattern](#subprocess-invocation-pattern)
4. [Index Storage & Artifacts](#index-storage--artifacts)
5. [Python Integration Examples](#python-integration-examples)
6. [Error Handling & Recovery](#error-handling--recovery)
7. [Performance & Optimization](#performance--optimization)
8. [Multi-Workspace Isolation](#multi-workspace-isolation)
9. [Troubleshooting](#troubleshooting)
10. [Implementation Checklist](#implementation-checklist)

---

## Architecture Overview

### Design Pattern: Subprocess-Based Indexing

```
research-mind-service (FastAPI)
  ├── Workspace Management API
  │   ├── POST /workspaces/{id}/register
  │   └── POST /workspaces/{id}/index
  │
  └── Indexing Operations
      └── spawn subprocess: mcp-vector-search init/index
          └── Workspace Directory
              ├── source code files
              └── .mcp-vector-search/
                  ├── config.json
                  ├── .chromadb/
                  └── embeddings cache
```

### Why Subprocess?

- **Isolation**: Each workspace has independent index in its own directory
- **Simplicity**: Clean CLI interface, no Python library embedding
- **Safety**: No shared state between workspaces, no threading concerns
- **Testability**: Easy to test via subprocess invocation
- **Scalability**: Can spawn multiple processes for parallel indexing

### When to Index

**On Workspace Registration**:

```
User registers workspace
  ↓
research-mind-service validates sandbox path
  ↓
Spawn: mcp-vector-search init && mcp-vector-search index
  ↓
Index artifacts stored in workspace/.mcp-vector-search/
  ↓
Workspace ready for search (Phase 2)
```

**On Workspace Update** (Future - Phase 2):

```
User notifies of file changes
  ↓
Spawn: mcp-vector-search index reindex [file_path]
  ↓
Index updated incrementally
```

---

## CLI Command Reference

### mcp-vector-search init

**Purpose**: Initialize a workspace for mcp-vector-search

**Usage**:

```bash
mcp-vector-search init [OPTIONS]
```

**Key Options**:
| Option | Type | Purpose |
|--------|------|---------|
| `--force` | flag | Force re-initialization even if already initialized |

**What It Does**:

1. Creates `.mcp-vector-search/` directory
2. Creates `config.json` with embedding model settings
3. Adds `.mcp-vector-search/` to `.gitignore`
4. Runs initial indexing on all detected files
5. Downloads embedding model (~250-500 MB on first run)

**Exit Codes**:

- `0`: Success
- `1`: Failure (permission error, invalid directory, etc.)

**Example**:

```bash
cd /path/to/workspace
mcp-vector-search init --force
```

### mcp-vector-search index

**Purpose**: Index or update codebase

**Usage**:

```bash
mcp-vector-search index [OPTIONS]
```

**Key Options**:
| Option | Short | Type | Default | Purpose |
|--------|-------|------|---------|---------|
| `--force` | `-f` | flag | false | Force full reindex (ignore change detection) |
| `--extensions` | `-e` | string | auto-detect | Override file types (e.g., `.py,.js,.ts`) |
| `--batch-size` | `-b` | integer | 32 | Batch size for embeddings (1-128) |
| `--background` | `-bg` | flag | false | Run indexing in background |
| `--watch` | `-w` | flag | false | Watch files and auto-update index |

**Exit Codes**:

- `0`: Success
- `1`: Failure

**Example - Full Reindex**:

```bash
cd /path/to/workspace
mcp-vector-search index --force
```

### mcp-vector-search index reindex [FILE_PATH]

**Purpose**: Reindex specific file or entire project

**Usage**:

```bash
mcp-vector-search index reindex [FILE_PATH]
```

**Example**:

```bash
# Reindex entire project
mcp-vector-search index reindex --all --force

# Reindex specific file
mcp-vector-search index reindex src/main.py
```

### Other Useful Commands

**Check Index Health**:

```bash
mcp-vector-search index health
```

**Show Indexing Status**:

```bash
mcp-vector-search index status
```

**Clean Index** (remove all data):

```bash
mcp-vector-search index clean
```

---

## Subprocess Invocation Pattern

### Basic Pattern

```python
import subprocess
from pathlib import Path

def index_workspace(workspace_dir: Path, timeout: int = 60) -> bool:
    """Index a workspace using mcp-vector-search subprocess."""
    try:
        # Initialize workspace (one-time)
        subprocess.run(
            ["mcp-vector-search", "init", "--force"],
            cwd=str(workspace_dir),
            timeout=30,
            check=True
        )

        # Index workspace
        subprocess.run(
            ["mcp-vector-search", "index", "--force"],
            cwd=str(workspace_dir),
            timeout=timeout,
            check=True
        )

        return True
    except subprocess.TimeoutExpired:
        print(f"Indexing timed out after {timeout}s")
        return False
    except subprocess.CalledProcessError as e:
        print(f"Indexing failed with exit code {e.returncode}")
        return False
```

### With Output Capture

```python
import subprocess
from pathlib import Path

def index_workspace_with_output(workspace_dir: Path) -> tuple[bool, str, str]:
    """Index workspace and capture stdout/stderr."""
    try:
        # Initialize
        subprocess.run(
            ["mcp-vector-search", "init", "--force"],
            cwd=str(workspace_dir),
            timeout=30,
            check=True,
            capture_output=True
        )

        # Index with output capture
        result = subprocess.run(
            ["mcp-vector-search", "index", "--force"],
            cwd=str(workspace_dir),
            timeout=60,
            check=False,  # Don't raise on non-zero exit
            capture_output=True,
            text=True
        )

        if result.returncode == 0:
            return True, result.stdout, ""
        else:
            return False, result.stdout, result.stderr

    except subprocess.TimeoutExpired:
        return False, "", "Timeout"
    except Exception as e:
        return False, "", str(e)
```

### With File Extension Override

```python
def index_workspace_custom_extensions(
    workspace_dir: Path,
    extensions: list[str]
) -> bool:
    """Index specific file types only."""
    try:
        ext_str = ",".join(extensions)  # e.g., ".py,.js,.ts"

        subprocess.run(
            ["mcp-vector-search", "init", "--force"],
            cwd=str(workspace_dir),
            timeout=30,
            check=True
        )

        subprocess.run(
            ["mcp-vector-search", "index", "--force", "--extensions", ext_str],
            cwd=str(workspace_dir),
            timeout=60,
            check=True
        )

        return True
    except subprocess.CalledProcessError:
        return False
```

---

## Index Storage & Artifacts

### Directory Structure

After indexing, a workspace contains:

```
workspace/
├── source code files
├── .mcp-vector-search/          ← Index artifacts (auto-created)
│   ├── config.json              ← mcp-vector-search configuration
│   ├── .chromadb/               ← Vector database (ChromaDB)
│   │   ├── index.db
│   │   └── uuids.parquet
│   ├── cache/                   ← Embeddings cache
│   │   └── embeddings.pkl
│   └── .gitignore               ← Already contains .mcp-vector-search/
```

### Artifact Characteristics

| File          | Size           | Purpose                    | Shareable               |
| ------------- | -------------- | -------------------------- | ----------------------- |
| `config.json` | <1 KB          | mcp-vector-search settings | No (workspace-specific) |
| `.chromadb/`  | 200-400 KB     | Vector embeddings index    | No                      |
| `cache/`      | 200-150 KB     | Cached embeddings          | No                      |
| **Total**     | **432-552 KB** | Complete index             | No                      |

### Git Configuration

The `.mcp-vector-search/` directory is automatically added to `.gitignore`. Verify:

```bash
cd workspace
cat .gitignore | grep mcp-vector-search
# Output: .mcp-vector-search/
```

**Do NOT commit index artifacts** - they're workspace-specific and can be regenerated.

---

## Python Integration Examples

### Example 1: WorkspaceIndexer Class

```python
import subprocess
from pathlib import Path
from dataclasses import dataclass
from typing import Optional

@dataclass
class IndexingResult:
    success: bool
    elapsed_seconds: float
    stdout: str
    stderr: str

    def __str__(self) -> str:
        status = "✓" if self.success else "✗"
        return f"{status} Indexing {'succeeded' if self.success else 'failed'} ({self.elapsed_seconds:.1f}s)"

class WorkspaceIndexer:
    """Manages mcp-vector-search subprocess for workspace indexing."""

    def __init__(self, workspace_dir: Path):
        self.workspace_dir = Path(workspace_dir).resolve()

    def initialize(self, timeout: int = 30) -> IndexingResult:
        """Initialize workspace (one-time)."""
        return self._run_command(
            ["mcp-vector-search", "init", "--force"],
            timeout=timeout
        )

    def index(self, timeout: int = 60, force: bool = True) -> IndexingResult:
        """Index workspace."""
        cmd = ["mcp-vector-search", "index"]
        if force:
            cmd.append("--force")

        return self._run_command(cmd, timeout=timeout)

    def reindex_file(self, file_path: str, timeout: int = 30) -> IndexingResult:
        """Reindex specific file."""
        return self._run_command(
            ["mcp-vector-search", "index", "reindex", file_path],
            timeout=timeout
        )

    def check_health(self, timeout: int = 10) -> IndexingResult:
        """Check index health."""
        return self._run_command(
            ["mcp-vector-search", "index", "health"],
            timeout=timeout
        )

    def _run_command(self, cmd: list[str], timeout: int) -> IndexingResult:
        """Run mcp-vector-search subprocess."""
        import time

        start_time = time.time()
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self.workspace_dir),
                timeout=timeout,
                capture_output=True,
                text=True,
                check=False
            )
            elapsed = time.time() - start_time

            return IndexingResult(
                success=result.returncode == 0,
                elapsed_seconds=elapsed,
                stdout=result.stdout,
                stderr=result.stderr
            )
        except subprocess.TimeoutExpired:
            elapsed = time.time() - start_time
            return IndexingResult(
                success=False,
                elapsed_seconds=elapsed,
                stdout="",
                stderr=f"Timeout after {timeout}s"
            )
```

### Example 2: FastAPI Integration

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from pathlib import Path

app = FastAPI()

class WorkspaceIndexRequest(BaseModel):
    workspace_id: str
    workspace_path: str

@app.post("/api/v1/workspaces/{workspace_id}/index")
async def index_workspace(workspace_id: str, request: WorkspaceIndexRequest):
    """Index a workspace."""
    workspace_dir = Path(request.workspace_path).resolve()

    # Validate path is within sandbox
    sandbox_root = Path("/path/to/sandbox")
    if not str(workspace_dir).startswith(str(sandbox_root)):
        raise HTTPException(status_code=400, detail="Path outside sandbox")

    # Perform indexing
    indexer = WorkspaceIndexer(workspace_dir)

    # Initialize
    init_result = indexer.initialize()
    if not init_result.success:
        raise HTTPException(
            status_code=500,
            detail=f"Initialization failed: {init_result.stderr}"
        )

    # Index
    index_result = indexer.index()
    if not index_result.success:
        raise HTTPException(
            status_code=500,
            detail=f"Indexing failed: {index_result.stderr}"
        )

    return {
        "workspace_id": workspace_id,
        "status": "indexed",
        "elapsed_seconds": index_result.elapsed_seconds
    }
```

---

## Error Handling & Recovery

### Exit Code Interpretation

| Exit Code | Meaning | Action                   |
| --------- | ------- | ------------------------ |
| `0`       | Success | Proceed normally         |
| `1`       | Failure | Check stderr for details |

### Common Error Conditions

**Workspace Not Initialized**:

```
Error: Project not initialized. Run 'mcp-vector-search init' first.
```

**Recovery**: Call `init` command before `index`

**Permission Denied**:

```
Error: Permission denied: /path/to/workspace/.mcp-vector-search
```

**Recovery**: Check directory permissions, ensure service has write access

**Corrupted Index**:

```
Error: Index corruption detected
```

**Recovery**: Delete `.mcp-vector-search/` directory and re-run `init`

**Timeout**:

```
subprocess.TimeoutExpired: Command timed out after 60 seconds
```

**Recovery**: Increase timeout for large workspaces (300-600s for 1000+ files)

### Robust Error Handling Pattern

```python
def index_workspace_robust(workspace_dir: Path) -> dict:
    """Index with comprehensive error handling."""
    errors = []

    # Step 1: Initialize
    try:
        subprocess.run(
            ["mcp-vector-search", "init", "--force"],
            cwd=str(workspace_dir),
            timeout=30,
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "initialization_timeout"}
    except subprocess.CalledProcessError as e:
        if "already initialized" in e.stderr:
            pass  # OK to proceed
        else:
            return {"success": False, "error": e.stderr}

    # Step 2: Index
    try:
        result = subprocess.run(
            ["mcp-vector-search", "index", "--force"],
            cwd=str(workspace_dir),
            timeout=60,
            check=False,
            capture_output=True,
            text=True
        )

        if result.returncode == 0:
            return {"success": True}
        else:
            return {"success": False, "error": result.stderr}

    except subprocess.TimeoutExpired:
        return {"success": False, "error": "indexing_timeout"}
    except Exception as e:
        return {"success": False, "error": str(e)}
```

---

## Performance & Optimization

### Timing Baselines

From research testing (2-file test project):

- **Init**: ~2-5 seconds (includes model download on first run)
- **First Index**: ~3.89 seconds
- **Reindex**: ~3.78 seconds
- **Model Cache**: ~250-500 MB (one-time download)

### For Larger Projects

**Estimated Scaling** (not tested):

- 100 files, 10K LOC: ~10-15 seconds
- 500 files, 50K LOC: ~30-60 seconds
- 1000+ files, 100K+ LOC: ~120-300 seconds

**Recommendation**: Use **300-600 second timeout** for production workspaces.

### Optimization Options

**Batch Size Tuning**:

```bash
# Default (32) is reasonable, but can increase for throughput
mcp-vector-search index --batch-size 64
```

**Background Indexing**:

```python
# Don't wait for completion
subprocess.Popen(  # Use Popen instead of run for background
    ["mcp-vector-search", "index", "--force", "--background"],
    cwd=str(workspace_dir)
)
```

---

## Multi-Workspace Isolation

### Verified Isolation Characteristics

✅ **Isolated indexes**: Each workspace's `.mcp-vector-search/` is independent
✅ **Parallel-safe**: Multiple workspaces can index simultaneously
✅ **No cross-contamination**: Indexing workspace A doesn't affect workspace B
✅ **ChromaDB locking**: Single-writer safety via ChromaDB's internal locks

### Safe Patterns

```python
import concurrent.futures

def index_multiple_workspaces(workspace_paths: list[Path]) -> list[bool]:
    """Index multiple workspaces in parallel."""

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = [
            executor.submit(index_workspace, path)
            for path in workspace_paths
        ]
        return [f.result() for f in futures]
```

### Unsafe Patterns ❌

```python
# DON'T: Index same workspace from multiple processes simultaneously
# This can corrupt ChromaDB index
subprocess.Popen(["mcp-vector-search", "index"], cwd=workspace_dir)
subprocess.Popen(["mcp-vector-search", "index"], cwd=workspace_dir)  # BAD!
```

---

## Troubleshooting

### "mcp-vector-search: command not found"

**Cause**: mcp-vector-search not installed in Python environment

**Solution**:

```bash
pip install mcp-vector-search
# Verify
which mcp-vector-search
mcp-vector-search --version
```

### "Project not initialized"

**Cause**: Skipped `init` command

**Solution**: Always call `init` before `index`

```python
subprocess.run(["mcp-vector-search", "init", "--force"], cwd=workspace_dir, check=True)
subprocess.run(["mcp-vector-search", "index", "--force"], cwd=workspace_dir, check=True)
```

### "Permission denied" on `.mcp-vector-search/`

**Cause**: Service doesn't have write access

**Solution**: Ensure workspace directory is writable

```bash
ls -la workspace/
# Should show rwx for group/owner
chmod 755 workspace/
```

### Model Download Fails

**Cause**: Network timeout or disk space

**Solution**:

```bash
# Check disk space
df -h /path/to/workspace
# Should have 1GB+ free

# Retry init
mcp-vector-search init --force
```

---

## Implementation Checklist

### Phase 1.0 Pre-Phase

- [ ] mcp-vector-search CLI installed and verified
- [ ] Workspace directory structure created
- [ ] Path validation sandbox configured

### Phase 1.1 Service Architecture

- [ ] `WorkspaceIndexer` class implemented (from Example 1)
- [ ] FastAPI endpoint for workspace indexing (from Example 2)
- [ ] Error handling patterns implemented
- [ ] Logging integrated (index start, completion, errors)
- [ ] Tests for subprocess invocation and error cases

### Phase 1.2 Session Management

- [ ] Session model tracks workspace registration
- [ ] Index status verified via `.mcp-vector-search/` existence
- [ ] Index cleanup on workspace deletion

### Testing

- [ ] Unit tests for `WorkspaceIndexer` class
- [ ] Integration tests with real workspace directories
- [ ] Error handling tests (timeout, permission, corruption)
- [ ] Multi-workspace isolation tests
- [ ] Performance baseline measurements

---

## Related Documents

- **mcp-vector-search-subprocess-integration-research.md**: Complete research findings and test results
- **RESEARCH_SUMMARY.md**: Quick reference of key findings
- **Phase 1.1 Plan**: Service architecture implementation

---

## Version History

| Version | Date       | Changes                                                |
| ------- | ---------- | ------------------------------------------------------ |
| 2.0     | 2026-02-01 | Subprocess-based approach (replaces library embedding) |
| 1.0     | 2026-01-31 | Original library embedding approach (deprecated)       |
