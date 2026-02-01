# Phase 1.7: Integration Tests

**Subphase**: 1.7 of 8 (Phase 1)
**Duration**: 5-7 business days
**Effort**: 40-56 hours
**Team Size**: 1-2 FTE engineers
**Prerequisite**: Phase 1.1-1.5 complete (Phase 1.6 Agent Integration deferred to a future phase)
**Blocking**: 1.8
**Status**: CRITICAL - MVP validation

---

## Subphase Objective

Comprehensive integration testing validating end-to-end research loop, cross-session isolation, and security controls. Provides confidence that MVP is production-ready.

**Success Definition**:

- End-to-end flow works: session → register workspace → index (via subprocess) → verify artifacts
- Multi-workspace isolation verified (100% separation)
- Path traversal blocked (100% detection)
- Concurrent subprocess access safe (5+ simultaneous workspaces)
- Subprocess error handling verified (timeout, exit code != 0)
- > 90% test coverage

---

## Test Categories

### 1. End-to-End Tests (Subprocess-Based)

- Create session and register workspace
- Trigger indexing (subprocess invocation)
- Verify subprocess exits with code 0
- Verify `.mcp-vector-search/` directory exists after indexing
- Verify index artifacts created (config.json, .chromadb/, cache/)
- Search functionality deferred to a future phase

### 2. Subprocess Invocation Tests

- Test subprocess invocation succeeds (exit code 0)
- Test subprocess timeout handling (configurable timeout, TimeoutExpired caught)
- Test subprocess error handling (exit code 1, stderr captured)
- Test subprocess output capture (stdout/stderr)
- Test path validation before subprocess invocation (invalid paths rejected BEFORE spawn)

### 3. Multi-Workspace Isolation Tests

- Create two workspaces with different content
- Index both workspaces in parallel (concurrent subprocesses)
- Verify each workspace has independent `.mcp-vector-search/` directory
- Verify no cross-contamination between workspace indexes
- Verify workspace A indexing doesn't affect workspace B

### 4. Security Tests (Fuzzing)

- Path traversal attempts (20+ patterns)
- Hidden file access attempts
- Symlink escape attempts
- Session validation bypass attempts
- Workspace path injection (invalid paths passed to subprocess `cwd`)

### 5. Concurrent Access Tests

- 5+ workspaces indexing simultaneously via subprocess
- Workspace deletion while subprocess is running
- Race condition testing on subprocess management
- Verify no duplicate subprocess spawns for same workspace

### 6. Error Handling Tests

- Missing session -> 404
- Invalid workspace path -> 400 (rejected before subprocess spawn)
- Subprocess timeout -> error returned with details
- Subprocess exit code 1 -> error returned with stderr
- Malformed requests

---

## Deliverables

1. **tests/test_integration_e2e.py** - End-to-end flow tests (subprocess-based)
2. **tests/test_subprocess_invocation.py** - Subprocess invocation, timeout, and error handling tests
3. **tests/test_workspace_isolation.py** - Multi-workspace isolation tests
4. **tests/test_security.py** - Security and fuzzing tests
5. **tests/test_concurrent_access.py** - Concurrency safety tests (parallel subprocesses)
6. **tests/test_error_handling.py** - Error case tests
7. **Coverage report** >90% code coverage

---

## Test Implementation Strategy

### Test Infrastructure

```python
# conftest.py - Pytest fixtures

import tempfile
from pathlib import Path

@pytest.fixture
def test_client():
    """FastAPI test client with in-memory DB."""
    # Create test database
    # Setup test client
    # Return client

@pytest.fixture
def test_session():
    """Create test session."""
    # POST /api/sessions with test data
    # Return session

@pytest.fixture
def test_workspace():
    """Create temporary workspace directory with sample files."""
    with tempfile.TemporaryDirectory() as tmp:
        workspace = Path(tmp)
        # Create sample Python files
        (workspace / "main.py").write_text("def main(): pass\n")
        (workspace / "utils.py").write_text("def helper(): pass\n")
        (workspace / "auth.py").write_text("def authenticate(user): pass\n")
        yield workspace

@pytest.fixture
def test_workspace_pair():
    """Create two isolated workspace directories for isolation testing."""
    with tempfile.TemporaryDirectory() as tmp1, tempfile.TemporaryDirectory() as tmp2:
        ws1 = Path(tmp1)
        ws2 = Path(tmp2)
        (ws1 / "auth.py").write_text("def authenticate(user): pass\n")
        (ws2 / "database.py").write_text("def connect_db(): pass\n")
        yield ws1, ws2
```

### End-to-End Test Example (Subprocess-Based)

```python
@pytest.mark.asyncio
async def test_full_indexing_flow(test_client, test_workspace):
    """Test complete workspace registration and indexing flow."""

    # 1. Create session
    session_response = test_client.post(
        "/api/sessions",
        json={"name": "Test Session"}
    )
    assert session_response.status_code == 201
    session_id = session_response.json()["session_id"]

    # 2. Register and index workspace (triggers subprocess)
    index_response = test_client.post(
        f"/api/sessions/{session_id}/index",
        json={"directory_path": str(test_workspace)}
    )
    assert index_response.status_code == 202

    # 3. Wait for indexing subprocess to complete
    # (poll status endpoint or wait for completion)
    import time
    for _ in range(60):
        status = test_client.get(
            f"/api/sessions/{session_id}/index/status"
        ).json()
        if status["status"] in ["completed", "failed"]:
            break
        time.sleep(1)

    assert status["status"] == "completed"

    # 4. Verify index artifacts created by subprocess
    index_dir = test_workspace / ".mcp-vector-search"
    assert index_dir.exists(), ".mcp-vector-search/ directory should exist after indexing"
    assert (index_dir / "config.json").exists(), "config.json should exist"

    # 5. Search functionality deferred to a future phase
```

### Subprocess Invocation Test Example

```python
import subprocess

def test_subprocess_invocation_succeeds(test_workspace):
    """Test that mcp-vector-search subprocess exits with code 0."""
    result = subprocess.run(
        ["mcp-vector-search", "init", "--force"],
        cwd=str(test_workspace),
        timeout=30,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Init failed: {result.stderr}"

def test_subprocess_timeout_handling(test_workspace):
    """Test that subprocess timeout is properly caught."""
    # Use a very short timeout to trigger TimeoutExpired
    try:
        subprocess.run(
            ["mcp-vector-search", "index", "--force"],
            cwd=str(test_workspace),
            timeout=0.001,  # Intentionally too short
            capture_output=True,
            text=True
        )
        assert False, "Should have raised TimeoutExpired"
    except subprocess.TimeoutExpired:
        pass  # Expected behavior

def test_subprocess_error_handling(tmp_path):
    """Test handling of subprocess exit code 1."""
    # Use empty directory without init to trigger error
    result = subprocess.run(
        ["mcp-vector-search", "index", "--force"],
        cwd=str(tmp_path),
        timeout=30,
        capture_output=True,
        text=True
    )
    # Should fail because workspace not initialized
    assert result.returncode != 0

def test_index_artifacts_created(test_workspace):
    """Test that .mcp-vector-search/ directory exists after indexing."""
    subprocess.run(
        ["mcp-vector-search", "init", "--force"],
        cwd=str(test_workspace), timeout=30, check=True
    )
    assert (test_workspace / ".mcp-vector-search").exists()
    assert (test_workspace / ".mcp-vector-search" / "config.json").exists()

def test_path_validation_before_subprocess(test_client, test_session):
    """Test that invalid paths are rejected BEFORE subprocess is spawned."""
    response = test_client.post(
        f"/api/sessions/{test_session}/index",
        json={"directory_path": "../../../etc"}
    )
    assert response.status_code in [400, 403]
```

### Multi-Workspace Isolation Test Example

```python
def test_multi_workspace_isolation(test_workspace_pair):
    """Verify two workspaces can index in parallel without interference."""
    ws1, ws2 = test_workspace_pair

    import concurrent.futures

    def index_workspace(workspace):
        subprocess.run(
            ["mcp-vector-search", "init", "--force"],
            cwd=str(workspace), timeout=30, check=True
        )
        result = subprocess.run(
            ["mcp-vector-search", "index", "--force"],
            cwd=str(workspace), timeout=60,
            capture_output=True, text=True
        )
        return result.returncode

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(index_workspace, ws1)
        f2 = executor.submit(index_workspace, ws2)
        assert f1.result() == 0, "Workspace 1 indexing failed"
        assert f2.result() == 0, "Workspace 2 indexing failed"

    # Verify independent indexes
    assert (ws1 / ".mcp-vector-search").exists()
    assert (ws2 / ".mcp-vector-search").exists()
```

### Security Test Example

```python
def test_path_traversal_blocked(test_client, test_session):
    """Test that path traversal is blocked before subprocess invocation."""

    blocked_paths = [
        "../../../etc/passwd",
        "../../.env",
        "/root/.ssh",
        "./.env.local",
    ]

    for path in blocked_paths:
        # Attempt to index with blocked path
        response = test_client.post(
            f"/api/sessions/{test_session}/index",
            json={"directory_path": path}
        )
        # Should be blocked (400 or 403) BEFORE subprocess is spawned
        assert response.status_code in [400, 403]
```

---

## Acceptance Criteria

### Test Coverage

- [ ] > 90% code coverage (all routes tested)
- [ ] End-to-end flow tested (session -> register -> index subprocess -> verify artifacts)
- [ ] Subprocess invocation tested (exit code 0, timeout, error)
- [ ] Multi-workspace isolation tested (parallel indexing, independent artifacts)
- [ ] Security tested (20+ attack patterns, path validation before subprocess)
- [ ] Concurrency tested (5+ parallel subprocesses)
- [ ] Error cases tested (timeout, exit code 1, invalid path)

### Test Execution

- [ ] All tests pass locally
- [ ] All tests pass in CI/CD
- [ ] Test suite completes in <5 minutes
- [ ] No flaky tests (consistent results)
- [ ] Temporary workspace fixtures clean up properly

### Security Validation

- [ ] Path traversal 100% blocked (before subprocess invocation)
- [ ] Session validation on every request
- [ ] No cross-workspace data leakage
- [ ] Workspace paths validated before passing to subprocess `cwd`
- [ ] Audit logging capturing all subprocess events and blocked attempts

---

## Summary

**Phase 1.7** delivers:

- Comprehensive integration test suite for subprocess-based architecture
- End-to-end validation of workspace registration and indexing flow
- Subprocess invocation testing (success, timeout, error handling)
- Multi-workspace isolation verification
- Security testing and fuzzing (path validation before subprocess spawn)
- Concurrency safety verification (parallel subprocess execution)
- > 90% code coverage

Gates Phase 1 completion and enables future search and optimization work.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Parent**: 01-PHASE_1_FOUNDATION.md
