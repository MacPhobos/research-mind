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

## The Golden Rule: API Contract First

**Contract Location**: `docs/api-contract.md` (source of truth)

All changes to the API must:
1. Update `research-mind-service/docs/api-contract.md`
2. Update service models
3. Run service tests
4. Copy contract to `research-mind-ui/docs/api-contract.md`
5. Run `make gen-client` in UI
6. Update UI code using new types
7. Run UI tests

**NEVER**:
- Manually edit generated types
- Deploy without regenerating client
- Change API without updating contract in BOTH places

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

## Non-Goals

- User authentication (stubs exist, production auth TBD)
- Multi-environment setup (local dev only for now)
- Load testing or scale optimization
