# Getting Started with research-mind

This guide walks you through setting up the research-mind monorepo for local development.

**Time to first run**: ~5 minutes

---

## Prerequisites

### Required Software

| Software       | Minimum Version | Purpose                                  | Check Command            |
| -------------- | --------------- | ---------------------------------------- | ------------------------ |
| Python         | 3.12+           | Backend runtime                          | `python3 --version`      |
| Node.js        | 20.x or 22.x    | Frontend runtime                         | `node --version`         |
| npm            | 10.x+           | Frontend package manager                 | `npm --version`          |
| PostgreSQL     | 15+             | Database                                 | `psql --version`         |
| Docker         | 24+             | Container runtime (optional)             | `docker --version`       |
| Docker Compose | 2.20+           | Multi-container orchestration (optional) | `docker compose version` |

### Installation by Platform

#### macOS (Homebrew)

```bash
# Python 3.12+
brew install python@3.12

# Node.js (via nvm recommended)
brew install nvm
nvm install 22
nvm use 22

# PostgreSQL (if not using Docker)
brew install postgresql@15
brew services start postgresql@15

# Docker Desktop (includes Docker Compose)
brew install --cask docker
```

#### Ubuntu/Debian

```bash
# Python 3.12+
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update
sudo apt install python3.12 python3.12-venv

# Node.js 22.x
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# PostgreSQL 15 (if not using Docker)
sudo apt install postgresql-15

# Docker
sudo apt install docker.io docker-compose-plugin
sudo usermod -aG docker $USER
```

#### Windows

We recommend using **WSL2** (Windows Subsystem for Linux) for the best development experience:

1. Install WSL2: `wsl --install`
2. Install Ubuntu from Microsoft Store
3. Follow Ubuntu instructions above inside WSL2
4. Install Docker Desktop for Windows with WSL2 backend

### Install uv Package Manager

The backend uses `uv` for fast Python dependency management:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

After installation, restart your terminal or run:

```bash
source ~/.bashrc  # or ~/.zshrc
```

Verify installation:

```bash
uv --version
```

### Optional: mcp-vector-search CLI

The project uses `mcp-vector-search` for semantic code search and indexing. Without it installed globally, indexing features will be disabled but the application will still function.

---

## Quick Start

Choose **Option A** (Docker) for the fastest setup, or **Option B** (Local) for full development flexibility.

### Option A: Docker (Recommended for Quick Start)

This runs PostgreSQL, the backend service, and applies migrations in containers.

```bash
# Clone the repository
git clone <repo-url>
cd research-mind

# Start all services
docker compose up -d

# Apply database migrations
docker compose exec service alembic upgrade head

# Verify the backend is running
curl http://localhost:15010/health
# Expected: {"status":"ok","name":"research-mind-service",...}

# Open the UI in your browser
open http://localhost:15000
```

**Note**: The Docker setup currently runs PostgreSQL and the backend service. The frontend runs locally for development.

To start the frontend:

```bash
cd research-mind-ui
npm install
npm run dev
```

### Option B: Local Development (Recommended for Development)

This gives you full control with hot-reload for both frontend and backend.

```bash
# Clone the repository
git clone <repo-url>
cd research-mind

# Install all dependencies (backend + frontend)
make install

# Start PostgreSQL via Docker
docker compose up -d postgres

# Wait for PostgreSQL to be ready
sleep 3

# Copy environment files
cp .env.example .env
cp research-mind-service/.env.example research-mind-service/.env
cp research-mind-ui/.env.example research-mind-ui/.env

# Apply database migrations
cd research-mind-service && uv run alembic upgrade head && cd ..

# Start the development stack
make dev
```

This starts:

- **PostgreSQL**: localhost:5432
- **Backend API**: http://localhost:15010
- **Frontend UI**: http://localhost:15000

---

## Combined Container Deployment

For simpler deployments, use the combined container which runs both backend and frontend in a single image:

### Building the Combined Image

```bash
docker build -f Dockerfile.combined -t research-mind .
```

### Running with External PostgreSQL

The combined container requires an external PostgreSQL database.

**Option 1: Using host machine's PostgreSQL**

```bash
docker run -d \
  --name research-mind \
  -p 15010:15010 \
  -p 15000:15000 \
  -e DATABASE_URL=postgresql+psycopg://postgres:devpass123@host.docker.internal:5432/research_mind \
  -e AUTO_MIGRATE=true \
  -v research-mind-data:/var/lib/research-mind/workspaces \
  research-mind
```

**Option 2: Using Docker network with PostgreSQL container**

```bash
# Create network
docker network create research-mind-net

# Start PostgreSQL
docker run -d \
  --name research-mind-db \
  --network research-mind-net \
  -e POSTGRES_PASSWORD=devpass123 \
  -e POSTGRES_DB=research_mind \
  -v research-mind-pgdata:/var/lib/postgresql/data \
  postgres:15-alpine

# Start Research Mind
docker run -d \
  --name research-mind \
  --network research-mind-net \
  -p 15010:15010 \
  -p 15000:15000 \
  -e DATABASE_URL=postgresql+psycopg://postgres:devpass123@research-mind-db:5432/research_mind \
  -e AUTO_MIGRATE=true \
  -v research-mind-data:/var/lib/research-mind/workspaces \
  research-mind
```

### Environment Variables

| Variable        | Required | Default                             | Description                       |
| --------------- | -------- | ----------------------------------- | --------------------------------- |
| `DATABASE_URL`  | Yes      | -                                   | PostgreSQL connection string      |
| `AUTO_MIGRATE`  | No       | `false`                             | Run Alembic migrations on startup |
| `WORKSPACE_DIR` | No       | `/var/lib/research-mind/workspaces` | Directory for workspace data      |

### Verifying the Combined Container

```bash
# Check container is running
docker ps | grep research-mind

# Check health
curl http://localhost:15010/health
curl http://localhost:15000

# View logs
docker logs research-mind
```

---

## Verifying Your Installation

### Automated Verification

Run the verification script to check all components:

```bash
./scripts/verify-install.sh
```

**Note**: If this script doesn't exist yet, use the manual checks below.

### Manual Verification

#### 1. Check Backend Health

```bash
curl http://localhost:15010/health
```

Expected response:

```json
{
  "status": "ok",
  "name": "research-mind-service",
  "version": "0.1.0",
  "git_sha": "..."
}
```

#### 2. Check API Version

```bash
curl http://localhost:15010/api/v1/version
```

Expected response:

```json
{
  "name": "research-mind-service",
  "version": "0.1.0",
  "git_sha": "..."
}
```

#### 3. Check Frontend

```bash
curl -s http://localhost:15000 | head -c 100
```

You should see HTML content starting with `<!DOCTYPE html>` or similar.

#### 4. Check Database Connection

```bash
docker compose exec postgres psql -U postgres -d research_mind -c "SELECT 1"
```

Expected: Returns `1` without errors.

---

## Common Setup Options

### Using an Existing PostgreSQL Instance

If you already have PostgreSQL running locally:

1. **Create the database**:

   ```bash
   createdb research_mind
   ```

2. **Update the connection string** in `research-mind-service/.env`:

   ```bash
   DATABASE_URL=postgresql+psycopg://postgres:yourpassword@localhost:5432/research_mind
   ```

3. **Run migrations**:

   ```bash
   cd research-mind-service
   uv run alembic upgrade head
   ```

4. **Skip Docker postgres** when starting:
   ```bash
   # Start only the backend and frontend
   cd research-mind-service && uv run uvicorn app.main:app --host 0.0.0.0 --port 15010 --reload &
   cd research-mind-ui && npm run dev &
   ```

### Changing Ports

#### Backend Port (default: 15010)

Update these files:

- `research-mind-service/.env`: `PORT=15010`
- `research-mind-ui/.env`: `VITE_API_BASE_URL=http://localhost:15010`
- `docker-compose.yml`: Change `"15010:15010"` port mapping

#### Frontend Port (default: 15000)

Update these files:

- `research-mind-ui/vite.config.ts`: Change `server.port`
- `research-mind-service/.env`: Update `CORS_ORIGINS` to include new port

#### PostgreSQL Port (default: 5432)

Update these files:

- `docker-compose.yml`: Change `"5432:5432"` port mapping
- `research-mind-service/.env`: Update `DATABASE_URL` with new port
- `.env`: Update `DATABASE_URL` with new port

### Environment Variables Reference

| Variable            | Default                                                                 | Description                                     |
| ------------------- | ----------------------------------------------------------------------- | ----------------------------------------------- |
| `DATABASE_URL`      | `postgresql+psycopg://postgres:devpass123@localhost:5432/research_mind` | Database connection string                      |
| `SERVICE_PORT`      | `15010`                                                                 | Backend API port                                |
| `VITE_API_BASE_URL` | `http://localhost:15010`                                                | Frontend's API endpoint                         |
| `CORS_ORIGINS`      | `["http://localhost:15000"]`                                            | Allowed CORS origins                            |
| `LOG_LEVEL`         | `INFO`                                                                  | Logging verbosity (DEBUG, INFO, WARNING, ERROR) |

---

## Next Steps

Once your environment is running:

### Development Guides

- **Backend Development**: See [`research-mind-service/CLAUDE.md`](../research-mind-service/CLAUDE.md)
  - FastAPI patterns, database migrations, testing
- **Frontend Development**: See [`research-mind-ui/CLAUDE.md`](../research-mind-ui/CLAUDE.md)
  - SvelteKit patterns, TanStack Query, component development

### API Documentation

- **API Contract**: [`research-mind-service/docs/api-contract.md`](../research-mind-service/docs/api-contract.md)
- **Interactive API Docs**: http://localhost:15010/docs (Swagger UI)
- **OpenAPI Spec**: http://localhost:15010/openapi.json

### Common Tasks

```bash
# Run all tests
make test

# Format code
make fmt

# Lint code
make lint

# Type check
make typecheck

# Regenerate TypeScript types from OpenAPI
make gen-client

# Reset database (drops all data)
make db-reset

# Stop all services
make stop
```

---

## Troubleshooting

### Port Already in Use

**Symptom**: Error like "address already in use" when starting services.

**Solution**:

```bash
# Find what's using the port
lsof -ti:15010  # For backend
lsof -ti:15000  # For frontend

# Kill the process
lsof -ti:15010 | xargs kill -9
```

### Database Connection Refused

**Symptom**: `connection refused` or `could not connect to server`

**Solutions**:

1. **Check if PostgreSQL is running**:

   ```bash
   docker compose ps
   # Or for local PostgreSQL:
   pg_isready -h localhost -p 5432
   ```

2. **Start PostgreSQL**:

   ```bash
   docker compose up -d postgres
   # Wait a few seconds for it to start
   sleep 5
   ```

3. **Check connection string** in `research-mind-service/.env`:
   ```bash
   # Should match your PostgreSQL setup
   DATABASE_URL=postgresql+psycopg://postgres:devpass123@localhost:5432/research_mind
   ```

### Node.js Version Mismatch

**Symptom**: Errors about unsupported Node.js features or npm version conflicts.

**Solution**: Use nvm to manage Node versions:

```bash
# Install nvm if not already installed
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Restart terminal, then:
nvm install 22
nvm use 22

# Verify
node --version  # Should be v22.x.x
```

### uv Not Found

**Symptom**: `command not found: uv`

**Solution**:

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Restart your terminal or source your profile
source ~/.bashrc  # or ~/.zshrc

# Verify
uv --version
```

### Migrations Fail

**Symptom**: `alembic upgrade head` fails with errors.

**Solutions**:

1. **Ensure database exists**:

   ```bash
   docker compose exec postgres psql -U postgres -c "CREATE DATABASE research_mind" 2>/dev/null || echo "Database already exists"
   ```

2. **Check migration state**:

   ```bash
   cd research-mind-service
   uv run alembic current
   ```

3. **Reset database** (deletes all data):
   ```bash
   make db-reset
   ```

### Frontend Can't Connect to Backend

**Symptom**: "Connection failed" or CORS errors in browser console.

**Solutions**:

1. **Check backend is running**:

   ```bash
   curl http://localhost:15010/health
   ```

2. **Check CORS configuration** in `research-mind-service/.env`:

   ```bash
   CORS_ORIGINS=["http://localhost:15000","http://localhost:3000"]
   ```

3. **Check frontend API URL** in `research-mind-ui/.env`:
   ```bash
   VITE_API_BASE_URL=http://localhost:15010
   ```

### Docker Issues

**Symptom**: Docker commands fail or containers won't start.

**Solutions**:

1. **Ensure Docker daemon is running**:

   ```bash
   docker ps
   # If error, start Docker Desktop or:
   # macOS: open /Applications/Docker.app
   # Linux: sudo systemctl start docker
   ```

2. **Clean up and restart**:

   ```bash
   docker compose down -v
   docker compose up -d
   ```

3. **Check logs**:
   ```bash
   docker compose logs postgres
   docker compose logs service
   ```

---

## Architecture Overview

```
research-mind/
├── research-mind-service/    # Python FastAPI backend (port 15010)
│   ├── app/                  # Application code
│   ├── migrations/           # Alembic database migrations
│   └── tests/                # Backend tests
├── research-mind-ui/         # SvelteKit frontend (port 15000)
│   ├── src/                  # Application code
│   └── tests/                # Frontend tests
├── docs/                     # Shared documentation
├── docker-compose.yml        # Container orchestration
└── Makefile                  # Common development tasks
```

**Data Flow**:

```
Browser (localhost:15000)
    ↓ HTTP
SvelteKit Frontend
    ↓ REST API
FastAPI Backend (localhost:15010)
    ↓ SQL
PostgreSQL (localhost:5432)
```

---

## Getting Help

- **Project README**: [`README.md`](../README.md)
- **Backend Guide**: [`research-mind-service/CLAUDE.md`](../research-mind-service/CLAUDE.md)
- **Frontend Guide**: [`research-mind-ui/CLAUDE.md`](../research-mind-ui/CLAUDE.md)
- **API Contract**: [`research-mind-service/docs/api-contract.md`](../research-mind-service/docs/api-contract.md)
