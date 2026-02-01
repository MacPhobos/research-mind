# Phase 1.8: Documentation & MVP Release

**Subphase**: 1.8 of 8 (Phase 1)
**Duration**: 2 business days
**Effort**: 16 hours
**Team Size**: 1 FTE engineer
**Prerequisite**: Phase 1.7 (all tests passing)
**Status**: FINAL PHASE - MVP release

---

## Subphase Objective

Complete documentation and enable local deployment. MVP is production-ready after Phase 1.7 testing, this phase makes it accessible.

**Success Definition**:

- Can boot entire system with `docker-compose up`
- All endpoints documented with examples
- Configuration documented
- Error codes documented
- Deployment guide exists

---

## Deliverables

1. **research-mind-service/README.md** - Setup, architecture, examples
2. **docker-compose.yml** (at root) - Local dev environment
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

Session-scoped agentic research system combining semantic code search
with Claude agent analysis.

## Quick Start

```bash
# Start service
docker-compose up

# Create session
curl -X POST http://localhost:15010/api/sessions \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Session"}'

# Index content
curl -X POST http://localhost:15010/api/sessions/{session_id}/index \
  -H "Content-Type: application/json" \
  -d '{"directory_path": "/path/to/code"}'

# Search
curl -X POST http://localhost:15010/api/sessions/{session_id}/search \
  -H "Content-Type: application/json" \
  -d '{"query": "how does auth work", "limit": 10}'

# Analyze
curl -X POST http://localhost:15010/api/sessions/{session_id}/analyze \
  -H "Content-Type: application/json" \
  -d '{"question": "explain authentication flow"}'
```
````

## API Endpoints

- POST /api/sessions - Create session
- GET /api/sessions - List sessions
- GET /api/sessions/{id} - Get session
- DELETE /api/sessions/{id} - Delete session
- POST /api/sessions/{id}/index - Start indexing
- GET /api/sessions/{id}/index/jobs/{job_id} - Get job status
- POST /api/sessions/{id}/search - Search indexed content
- POST /api/sessions/{id}/analyze - Invoke agent
- GET /api/health - Health check

## Configuration

See `.env.example` for all configuration options.

Key variables:

- PORT: Service port (default 15010)
- DATABASE_URL: Database connection
- EMBEDDINGS_MODEL: Model for embeddings (default: all-MiniLM-L6-v2)

## Architecture

- FastAPI + Uvicorn
- mcp-vector-search for indexing/search
- Claude-ppm for agent analysis
- SQLAlchemy ORM
- Per-session isolation

## Testing

```bash
pytest tests/ -v --cov=app
```

Expected: >90% coverage, all tests pass

## Security

- Infrastructure-level path validation
- Session isolation enforced
- Network disabled in agent subprocess
- Audit logging for all operations

````

### Task 1.8.2: Docker Compose Setup

Create **docker-compose.yml** (at root):

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15
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
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./research-mind-service:/app
      - session_data:/var/lib/research-mind/sessions
      - chromadb_data:/var/lib/research-mind/chromadb
      - hf_cache:${HF_CACHE_DIR:-/root/.cache/huggingface}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:15010/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  postgres_data:
  session_data:
  chromadb_data:
  hf_cache:
````

### Task 1.8.3: API Contract

Create **docs/api-contract.md** documenting all endpoints with:

- Request/response schemas
- Status codes
- Error responses
- Examples

### Task 1.8.4: Deployment Guide

Create **DEPLOYMENT.md** with:

- Kubernetes deployment manifests (Phase 4)
- Single-instance Docker deployment
- Database setup
- SSL/TLS configuration
- Monitoring setup

---

## Acceptance Criteria

- [ ] `docker-compose up` works end-to-end
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
- Documenting all functionality
- Providing deployment path to production

MVP is now complete and ready for user testing.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Parent**: 01-PHASE_1_FOUNDATION.md
