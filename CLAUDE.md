# research-mind Monorepo

## Overview

This monorepo contains:

- **research-mind-service/**: Python FastAPI backend
- **research-mind-ui/**: SvelteKit TypeScript frontend
- **docs/**: Shared documentation

**For project-specific development**:

- Backend patterns: See `research-mind-service/CLAUDE.md`
- Frontend patterns: See `research-mind-ui/CLAUDE.md`

## Quick Start

```bash
make install    # Install dependencies for both projects
make dev        # Start backend and frontend
```

**URLs**:

- Service: http://localhost:15010
- UI: http://localhost:15000

## The Golden Rule: API Contract is FROZEN

**Contract Location**:

- Backend source of truth: `research-mind-service/docs/api-contract.md`
- Frontend copy: `research-mind-ui/docs/api-contract.md` (must be identical)

The API contract is the **single source of truth** for all communication between service and UI. All changes must flow through the contract first.

### Contract Synchronization Workflow

**Backend → Frontend (strict ordering)**

1. **Update contract**: Edit `research-mind-service/docs/api-contract.md`
   - Add new endpoints, change schemas, update error codes
   - Version bump if breaking change
2. **Update backend models**: Add Pydantic schemas in `research-mind-service/app/schemas/`
3. **Implement backend**: Add routes in `research-mind-service/app/routes/`
4. **Run backend tests**: `make test` (all tests pass)
5. **Copy contract to frontend**: `cp research-mind-service/docs/api-contract.md research-mind-ui/docs/api-contract.md`
6. **Regenerate frontend types**: `make gen-client` (generates `src/lib/api/generated.ts`)
7. **Update frontend code**: Use new generated types in components
8. **Run frontend tests**: `make test` (all tests pass)

**Critical Rules**:

- Both `api-contract.md` files must be identical
- Never manually edit `src/lib/api/generated.ts` (auto-generated)
- Update service contract BEFORE implementing changes
- Deploy frontend only after regenerating types
- Version bump required for breaking changes

For detailed implementation workflows:

- Service side: See `research-mind-service/CLAUDE.md`
- UI side: See `research-mind-ui/CLAUDE.md`

### Contract Change Checklist

When modifying the API:

- [ ] Updated `research-mind-service/docs/api-contract.md`
- [ ] Version bumped (major/minor/patch)
- [ ] Changelog entry added
- [ ] Backend schemas/models updated
- [ ] Backend tests pass
- [ ] Contract copied to `research-mind-ui/docs/api-contract.md`
- [ ] Frontend types regenerated
- [ ] Frontend code updated
- [ ] Frontend tests pass
- [ ] Both `api-contract.md` files are identical

## Cross-Project Configuration

### Port Configuration

- **Service**: 15010 (change in root `.env`, `docker-compose.yml`, and UI's `VITE_API_BASE_URL`)
- **UI**: 15000 (change in `research-mind-ui/.env` and service CORS config)

### Type Generation Workflow

The frontend generates TypeScript types from the backend's OpenAPI schema:

```
Backend schema change
    ↓
Backend tests pass
    ↓
make gen-client
    ↓
Types updated automatically
    ↓
Frontend code updated
    ↓
Frontend tests pass
```

Generated types (`src/lib/api/generated.ts`) are always in sync with backend because they're derived from OpenAPI spec at `http://localhost:15010/openapi.json`.

## Common Monorepo Tasks

```bash
make dev              # Start both backend and frontend
make stop             # Stop all services
make test             # Run tests for both projects
make lint             # Check code quality (both projects)
make gen-client       # Regenerate TypeScript types from OpenAPI
make db-reset         # Drop and recreate database
```

For project-specific commands, see sub-project CLAUDE.md files.

## API Versioning

The API uses `/api/v1` prefix. Future versions will use `/api/v2`, `/api/v3`, etc.

### When to Bump Version

- **Major** (1.0.0 → 2.0.0): Breaking changes (removed endpoints, incompatible schema changes)
- **Minor** (1.0.0 → 1.1.0): New endpoints or new optional fields
- **Patch** (1.0.0 → 1.0.1): Bug fixes, documentation updates

## Deployment Order

Always deploy in this order:

1. **Backend first** with new/updated endpoints
2. **Frontend second** with regenerated types and updated code
3. Never deploy frontend without updated types
4. Use feature flags for gradual rollout of breaking changes

## Guard Rails (Cross-Project)

- **No `.env` in git**: Use `.env.example` only
- **Contract frozen**: Both `api-contract.md` files must be identical
- **Version bump required**: Any API change requires contract version bump
- **Backend first**: Always deploy backend before frontend
- **Tests required**: All tests must pass before deployment
- **Type safety**: Use generated TypeScript types (never hand-rolled fetch)

## Non-Goals

- User authentication (stubs exist, production auth TBD)
- Multi-environment setup (local dev only for now)
- Load testing or scale optimization
