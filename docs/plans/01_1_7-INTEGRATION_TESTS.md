# Phase 1.7: Integration Tests

**Subphase**: 1.7 of 8 (Phase 1)
**Duration**: 5-7 business days
**Effort**: 40-56 hours
**Team Size**: 1-2 FTE engineers
**Prerequisite**: All Phase 1.1-1.6 complete
**Blocking**: 1.8
**Status**: CRITICAL - MVP validation

---

## Subphase Objective

Comprehensive integration testing validating end-to-end research loop, cross-session isolation, and security controls. Provides confidence that MVP is production-ready.

**Success Definition**:

- End-to-end flow works: session → index → search → analyze
- Cross-session isolation verified (100% separation)
- Path traversal blocked (100% detection)
- Concurrent access safe (5+ simultaneous sessions)
- > 90% test coverage

---

## Test Categories

### 1. End-to-End Tests

- Create session
- Index content (poll until complete)
- Search for results
- Invoke agent
- Verify answer returned with citations

### 2. Isolation Tests

- Create two sessions with different content
- Verify session 1 search doesn't return session 2 results
- Verify agent in session 1 can't access session 2 files

### 3. Security Tests (Fuzzing)

- Path traversal attempts (20+ patterns)
- Hidden file access attempts
- Symlink escape attempts
- Session validation bypass attempts

### 4. Concurrent Access Tests

- 5+ sessions indexing simultaneously
- Multiple concurrent searches
- Session deletion while indexing
- Race condition testing

### 5. Error Handling Tests

- Missing session → 404
- Invalid query → 400
- Timeout handling
- Malformed requests

---

## Deliverables

1. **tests/test_integration_e2e.py** - End-to-end flow tests
2. **tests/test_isolation.py** - Cross-session isolation tests
3. **tests/test_security.py** - Security and fuzzing tests
4. **tests/test_concurrent_access.py** - Concurrency safety tests
5. **tests/test_error_handling.py** - Error case tests
6. **Coverage report** >90% code coverage

---

## Test Implementation Strategy

### Test Infrastructure

```python
# conftest.py - Pytest fixtures

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
    """Create test workspace with content."""
    # Create directory with sample Python files
    # Return path
```

### End-to-End Test Example

```python
@pytest.mark.asyncio
async def test_full_research_loop(test_client, test_workspace):
    """Test complete research flow."""

    # 1. Create session
    session_response = test_client.post(
        "/api/sessions",
        json={"name": "Test Session"}
    )
    assert session_response.status_code == 201
    session_id = session_response.json()["session_id"]

    # 2. Start indexing
    index_response = test_client.post(
        f"/api/sessions/{session_id}/index",
        json={"directory_path": str(test_workspace)}
    )
    assert index_response.status_code == 202
    job_id = index_response.json()["job_id"]

    # 3. Wait for indexing to complete
    for _ in range(60):  # 60 second timeout
        job = test_client.get(
            f"/api/sessions/{session_id}/index/jobs/{job_id}"
        ).json()
        if job["status"] == "completed":
            break
        await asyncio.sleep(1)

    assert job["status"] == "completed"

    # 4. Search
    search_response = test_client.post(
        f"/api/sessions/{session_id}/search",
        json={"query": "authentication", "limit": 10}
    )
    assert search_response.status_code == 200
    results = search_response.json()
    assert results["count"] > 0

    # 5. Analyze
    analyze_response = test_client.post(
        f"/api/sessions/{session_id}/analyze",
        json={"question": "How does auth work?"}
    )
    assert analyze_response.status_code == 200
    analysis = analyze_response.json()
    assert "answer" in analysis
    assert len(analysis["citations"]) > 0
```

### Isolation Test Example

```python
def test_session_isolation(test_client, test_workspace_1, test_workspace_2):
    """Verify sessions don't contaminate each other."""

    # Create and index two sessions
    session1 = test_client.post(
        "/api/sessions", json={"name": "S1"}
    ).json()
    session2 = test_client.post(
        "/api/sessions", json={"name": "S2"}
    ).json()

    # Index different content
    # (session1 has auth code, session2 has database code)

    # Search in session1 for "authentication"
    # Should NOT return database results from session2
    results1 = test_client.post(
        f"/api/sessions/{session1['session_id']}/search",
        json={"query": "authentication"}
    ).json()

    # Verify no results from session2
    for result in results1["results"]:
        assert result["file_path"].startswith(session1["workspace_path"])
```

### Security Test Example

```python
def test_path_traversal_blocked(test_client, test_session):
    """Test that path traversal is blocked."""

    blocked_paths = [
        "../../../etc/passwd",
        "../../.env",
        "/root/.ssh",
        "./.env.local",
    ]

    for path in blocked_paths:
        # Attempt to access blocked path
        response = test_client.get(
            f"/api/sessions/{test_session}/files/{path}"
        )
        # Should be blocked (404 or 403)
        assert response.status_code in [403, 404]
```

---

## Acceptance Criteria

### Test Coverage

- [ ] > 90% code coverage (all routes tested)
- [ ] End-to-end flow tested
- [ ] Session isolation tested
- [ ] Security tested (20+ attack patterns)
- [ ] Concurrency tested
- [ ] Error cases tested

### Test Execution

- [ ] All tests pass locally
- [ ] All tests pass in CI/CD
- [ ] Test suite completes in <5 minutes
- [ ] No flaky tests (consistent results)

### Security Validation

- [ ] Path traversal 100% blocked
- [ ] Session validation on every request
- [ ] No cross-session data leakage
- [ ] Network disabled in agent subprocess
- [ ] Audit logging capturing all attempts

---

## Summary

**Phase 1.7** delivers:

- Comprehensive integration test suite
- End-to-end validation of MVP
- Security testing and fuzzing
- Concurrency safety verification
- > 90% code coverage

Gates Phase 1 completion and enables Phase 2 optimization work.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Parent**: 01-PHASE_1_FOUNDATION.md
