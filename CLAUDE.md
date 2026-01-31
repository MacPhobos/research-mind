# research-mind Monorepo Development Guide

## Quick Start

```bash
make install
make dev
```

Service: http://localhost:15010
UI: http://localhost:15000

## Project Structure

- **research-mind-service/**: Python FastAPI backend
- **research-mind-ui/**: SvelteKit TypeScript frontend
- **docs/**: Shared documentation + API contract

## The Golden Rule: API Contract is FROZEN

**Contract Location**:

- Backend source of truth: `research-mind-service/docs/api-contract.md`
- Frontend copy: `research-mind-ui/docs/api-contract.md` (must be identical)

The API contract is the **single source of truth** for all communication between service and UI. All changes must flow through the contract first.

### Contract Synchronization Workflow (ONE WAY ONLY)

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

**NEVER**:

- Manually edit `src/lib/api/generated.ts` (auto-generated)
- Update service without updating contract first
- Deploy frontend without regenerating types after backend changes
- Let the two `api-contract.md` files diverge
- Change API without version bump if breaking

### Contract Change Checklist

When modifying the API:

- [ ] Updated `research-mind-service/docs/api-contract.md`
- [ ] Version bumped (major/minor/patch as appropriate)
- [ ] Changelog entry added
- [ ] Backend schemas/models updated
- [ ] Backend tests pass (`make test`)
- [ ] Contract copied to `research-mind-ui/docs/api-contract.md`
- [ ] Frontend types regenerated (`make gen-client`)
- [ ] Frontend code updated to use new types
- [ ] Frontend tests pass (`make test`)
- [ ] Both `api-contract.md` files are identical

## Configuration

### Service Port: 15010

- Change in root `.env` and `docker-compose.yml`
- Update UI's `VITE_API_BASE_URL`

### UI Port: 15000

- Change in research-mind-ui/.env
- CORS may need adjustment in service

### Database

- Default: Postgres (port 5432, user: postgres)
- Reset with: `make db-reset`

## Common Tasks

```bash
make dev              # Start everything
make stop             # Stop everything
make test             # Run all tests
make lint             # Check code quality
make gen-client       # Regenerate TS client from OpenAPI
make db-reset         # Drop and recreate database
```

## Type Generation (OpenAPI → TypeScript)

The frontend generates TypeScript types from the backend's OpenAPI schema:

### How It Works

1. **Backend** (FastAPI):

   - OpenAPI spec auto-generated at `http://localhost:15010/openapi.json`
   - Based on Pydantic models in `app/schemas/`

2. **Type Generation**:

   - Script: `npm run gen:api` (in `research-mind-ui/`)
   - Command: `openapi-typescript http://localhost:15010/openapi.json -o src/lib/api/generated.ts`
   - Output: `src/lib/api/generated.ts` (auto-generated, DO NOT EDIT)

3. **Frontend Usage**:

   ```typescript
   import type { Session, IndexingJob, SearchResult } from "$lib/api/generated";

   // These types are guaranteed to match the backend
   const session: Session = await fetch("/api/v1/sessions/123").then((r) =>
     r.json(),
   );
   ```

### Workflow

```
Service schema change
    ↓
Backend test passes
    ↓
npm run gen:api
    ↓
Types updated automatically
    ↓
UI code updated
    ↓
Frontend test passes
```

**Important**: Generated types are always in sync with backend because they're derived from OpenAPI schema.

## Adding a New Endpoint

1. **Service**:

   - Add route in `research-mind-service/app/routes/`
   - Add Pydantic models in `research-mind-service/app/schemas/`
   - Write test in `research-mind-service/tests/`
   - Update `docs/api-contract.md`

2. **UI**:
   - Copy contract to `research-mind-ui/docs/api-contract.md`
   - Run `make gen-client`
   - Use generated types in UI components

## Guard Rails

- **No `.env` in git**: Use `.env.example` only
- **Migrations required**: All schema changes via Alembic
- **Type safety**: Generated TypeScript types (no hand-rolled fetch)
- **Tests required**: >1 test per component
- **Ports must differ**: Service ≠ UI port
- **Contract frozen**: Never deviate from `api-contract.md`
- **Version bump required**: Any API change requires contract version bump
- **Both repos sync**: Contract must be identical in both service and UI

## API Versioning

The API uses `/api/v1` prefix. Future versions will use `/api/v2`, `/api/v3`, etc.

### When to Bump Version

- **Major** (1.0.0 → 2.0.0): Breaking changes (removed endpoints, incompatible schema changes)
- **Minor** (1.0.0 → 1.1.0): New endpoints or new optional fields
- **Patch** (1.0.0 → 1.0.1): Bug fixes, documentation updates

### Deployment Safety

Always deploy in this order:

1. **Backend first** with new/updated endpoints
2. **Frontend** regenerated types, code updated
3. Never deploy frontend without updated types
4. Use feature flags for gradual rollout of breaking changes

## Non-Goals

- User authentication (stubs exist, production auth TBD)
- Multi-environment setup (local dev only for now)
- Load testing or scale optimization
