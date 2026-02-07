# Phase 1.8: Documentation & MVP Release

**Subphase**: 1.8 of 8 (Phase 1)
**Duration**: 2 business days
**Effort**: 16 hours
**Team Size**: 1 FTE engineer
**Prerequisite**: Phase 1.7 (all tests passing)
**Status**: FINAL PHASE - MVP release

> **ARCHITECTURE NOTE (v2.0)**: This document reflects the subprocess-based architecture.
> Phase 1 MVP delivers workspace registration and indexing (not search/analysis).
> Search and agent analysis are deferred to a future phase.
> See `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0) for details.

---

## Subphase Objective

Complete documentation and enable local deployment. MVP is production-ready after Phase 1.7 testing, this phase makes it accessible.

**Success Definition**:

- Can boot entire system with `docker compose up`
- All endpoints documented with examples
- Configuration documented
- Error codes documented
- Deployment guide exists

---

## Deliverables

1. **research-mind-service/README.md** - Setup, architecture, examples
2. **docker compose.yml** (at root) - Local dev environment
3. **research-mind-service/Dockerfile** (updated) - Multi-stage build
4. **docs/api-contract.md** - OpenAPI contract
5. **DEPLOYMENT.md** - Production deployment guide
6. **TROUBLESHOOTING.md** - Common issues and solutions

---

## Key Tasks

### Task 1.8.1: README Documentation

Create **research-mind-service/README.md**:

````markdown
# Research-Mind Service

Session-scoped workspace indexing service using mcp-vector-search
subprocess for codebase indexing.

## Quick Start

```bash
# Start service
docker compose up

# Create session
curl -X POST http://localhost:15010/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"name": "My Project"}'

# Trigger indexing (mcp-vector-search subprocess)
curl -X POST http://localhost:15010/api/v1/workspaces/{session_id}/index \
  -H "Content-Type: application/json" \
  -d '{"force": true}'

# Check index status
curl http://localhost:15010/api/v1/workspaces/{session_id}/index/status
```
````

## API Endpoints

### Session Management

- POST /api/sessions - Create session
- GET /api/sessions - List sessions
- GET /api/sessions/{id} - Get session
- DELETE /api/sessions/{id} - Delete session

### Indexing Operations

- POST /api/v1/workspaces/{id}/index - Trigger indexing via subprocess
- GET /api/v1/workspaces/{id}/index/status - Check index status

### System

- GET /api/health - Health check

## Architecture

- FastAPI + Uvicorn
- mcp-vector-search CLI (subprocess-based indexing)
- SQLAlchemy ORM
- Per-workspace isolation via .mcp-vector-search/ directory

### How Indexing Works

```
POST /api/v1/workspaces/{id}/index
  ↓
IndexingService.index_workspace()
  ↓
WorkspaceIndexer (subprocess manager)
  ├── subprocess.run(["mcp-vector-search", "init", "--force"], cwd=workspace_dir)
  └── subprocess.run(["mcp-vector-search", "index", "--force"], cwd=workspace_dir)
  ↓
Exit code 0 = success, 1 = failure
  ↓
Index artifacts in workspace/.mcp-vector-search/
```

## Configuration

See `.env.example` for all configuration options.

Key variables:

- PORT: Service port (default 15010)
- DATABASE_URL: Database connection
- WORKSPACE_ROOT: Root directory for workspaces
- INDEXING_INIT_TIMEOUT: Timeout for init subprocess (default 30s)
- INDEXING_INDEX_TIMEOUT: Timeout for index subprocess (default 60s)
- INDEXING_LARGE_TIMEOUT: Timeout for large projects (default 600s)

## Testing

```bash
pytest tests/ -v --cov=app
```

Expected: >90% coverage, all tests pass

## Security

- Infrastructure-level path validation
- Session/workspace isolation enforced
- Audit logging for all operations

## Future (Planned)

- Search via Claude Code MCP interface
- Agent analysis with citations
- Incremental re-indexing

````

### Task 1.8.2: Docker Compose Setup

Create **docker compose.yml** (at root):

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: research_mind
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  service:
    build:
      context: ./research-mind-service
      dockerfile: Dockerfile
    ports:
      - "15010:15010"
    environment:
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/research_mind  # pragma: allowlist secret
      HOST: 0.0.0.0
      PORT: 15010
      DEBUG: "false"
      WORKSPACE_ROOT: /var/lib/research-mind/workspaces
      INDEXING_INIT_TIMEOUT: 30
      INDEXING_INDEX_TIMEOUT: 60
      INDEXING_LARGE_TIMEOUT: 600
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./research-mind-service:/app
      - workspace_data:/var/lib/research-mind/workspaces
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:15010/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  postgres_data:
  workspace_data:
````

### Task 1.8.3: API Contract

Create **docs/api-contract.md** documenting all endpoints with:

- Request/response schemas
- Status codes
- Error responses
- Examples
- Note that search/analyze endpoints are planned for a future phase

### Task 1.8.4: Deployment Guide

Create **DEPLOYMENT.md** with:

- Single-instance Docker deployment
- Database setup
- mcp-vector-search CLI verification
- Subprocess timeout tuning for production workspaces
- SSL/TLS configuration
- Monitoring setup

### Task 1.8.5: Troubleshooting Guide

Create **TROUBLESHOOTING.md** covering:

- "mcp-vector-search: command not found" - verify installation
- "Indexing timed out" - increase timeout configuration
- "Permission denied on .mcp-vector-search/" - check workspace permissions
- "Index corruption detected" - delete .mcp-vector-search/ and re-index
- "Model download fails" - check disk space and network connectivity

Reference: `docs/research2/MCP_VECTOR_SEARCH_INTEGRATION_GUIDE.md` (v2.0) Troubleshooting section

---

## Release Checklist

- [ ] `docker compose up` works end-to-end
- [ ] Service starts healthily (health check passes)
- [ ] mcp-vector-search CLI available inside container
- [ ] Subprocess invocation works from inside container
- [ ] All session CRUD endpoints documented with examples
- [ ] All indexing endpoints documented with examples
- [ ] Error codes documented (subprocess exit codes, HTTP status codes)
- [ ] Configuration documented (.env.example complete)
- [ ] Deployment guide complete
- [ ] Troubleshooting guide covers 5+ subprocess-specific issues
- [ ] Integration guide reference updated to v2.0 subprocess approach

---

## Acceptance Criteria

- [ ] `docker compose up` works end-to-end
- [ ] Service starts healthily
- [ ] All endpoints documented
- [ ] Examples work as documented
- [ ] Error codes documented
- [ ] Deployment guide complete
- [ ] Troubleshooting guide covers 5+ issues

---

## Summary

**Phase 1.8** completes Phase 1 by:

- Making MVP deployable locally
- Documenting all workspace registration and indexing functionality
- Providing deployment path to production
- Referencing subprocess integration guide (v2.0) for implementation details

**Phase 1 MVP scope**: Workspace registration and indexing service.
Search and agent analysis are planned for a future phase.

---

**Document Version**: 2.0
**Last Updated**: 2026-02-01
**Architecture**: Subprocess-based (replaces v1.0 library embedding approach)
**Parent**: 01-PHASE_1_FOUNDATION.md
