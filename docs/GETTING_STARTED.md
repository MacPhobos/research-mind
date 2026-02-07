# Getting Started with research-mind

This guide walks you through setting up the research-mind monorepo for local development.

**Supported platforms**: macOS and Ubuntu only (Windows is not supported)

**Time to first run**: 10-15 minutes

- ASDF setup: 2-3 minutes (first time only)
- Dependency install: 5-7 minutes
- Docker pull: 1-2 minutes
- Database migration: 1 minute

---

## Quick Start (Experienced Developers)

Already have Python 3.12, Node.js 22, uv, and Docker installed?

```bash
git clone git@github.com:MacPhobos/research-mind.git
cd research-mind
# Clone sub-projects (not git submodules)
git clone git@github.com:MacPhobos/research-mind-service.git research-mind-service
git clone git@github.com:MacPhobos/research-mind-ui.git research-mind-ui
make setup             # Create .env files from examples
# >>> Review and customize .env files if needed <<<
make install           # Install all dependencies
docker compose up -d postgres  # Start PostgreSQL
# Run database migrations (separate step -- not included in make dev)
cd research-mind-service && uv run alembic upgrade head && cd ..
make dev               # Start service (15010) + UI (15000)
```

> **Note**: `make setup` and `make install` are intentionally separate commands. `make setup` creates `.env` files from examples, giving you the opportunity to review and customize environment variables (such as `DATABASE_URL` and ports) before `make install` installs dependencies.

Verify: http://localhost:15000

Need detailed instructions? Continue reading below.

---

## Prerequisites

### Required Software

| Software       | Minimum Version | Purpose                                  | Check Command            |
| -------------- |---------------| ---------------------------------------- | ------------------------ |
| Python         | 3.12+         | Backend runtime                          | `python3 --version`      |
| Node.js        | 22.x          | Frontend runtime                         | `node --version`         |
| npm            | 10.x+         | Frontend package manager                 | `npm --version`          |
| PostgreSQL     | 15+ (16 recommended) | Database                          | `psql --version`         |
| pipx           | 1.8+          | Global tool installer (mcp-vector-search, claude-mpm) | `pipx --version`         |
| Docker         | 29+           | Container runtime (optional)             | `docker --version`       |
| Docker Compose | 5+            | Multi-container orchestration (optional) | `docker compose version` |

### Installation by Platform

#### macOS (Homebrew)

```bash
# Python 3.12+
brew install python@3.12

# Node.js (via nvm recommended)
brew install nvm
nvm install 22
nvm use 22

# PostgreSQL 15+ (16 recommended) - if not using Docker
brew install postgresql@16
brew services start postgresql@16

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

# PostgreSQL 15+ (16 recommended) - if not using Docker
sudo apt install postgresql-16

# Docker
sudo apt install docker.io docker-compose-plugin
sudo usermod -aG docker $USER
```

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

### Install pipx

`pipx` is required for installing `mcp-vector-search` and `claude-mpm` as globally available CLI tools:

```bash
# macOS
brew install pipx
pipx ensurepath

# Ubuntu/Debian
sudo apt install pipx
pipx ensurepath
```

After installation, restart your terminal or run:

```bash
source ~/.bashrc  # or ~/.zshrc
```

Verify installation:

```bash
pipx --version
```

### Optional: mcp-vector-search CLI

The project uses `mcp-vector-search` for semantic code search and indexing. Without it installed globally, indexing features will be disabled but the application will still function.

---

## ASDF Version Manager (Recommended)

[ASDF](https://asdf-vm.com/) is the recommended tool version manager for this project. It reads the `.tool-versions` file in the repository root and ensures you have exactly the right versions of Python, Node.js, uv, and pipx.

**ASDF 0.18+ required.** This project requires ASDF 0.18.0 or later (the Go rewrite). The legacy bash version of ASDF is not supported. On macOS, `brew install asdf` installs the Go version by default. On Linux, ensure you install from the correct release (see below).

Users who prefer not to use ASDF must install all tooling dependencies manually at the versions specified in `.tool-versions`. This is the user's responsibility.

### Current Tool Versions (.tool-versions)

| Tool   | Version  |
| ------ | -------- |
| Python | 3.12.11  |
| Node.js| 22.21.1  |
| pipx   | 1.8.0    |
| uv     | 0.9.26   |

### Installing ASDF

**CRITICAL**: ASDF 0.18.0 or later (the Go rewrite) is required. Do not install the legacy bash version. Older versions have incompatible plugin behavior and will not work correctly with this project.

#### macOS (Homebrew)

```bash
# Installs the Go version by default (0.18+)
brew install asdf

# Add to your shell profile (~/.zshrc or ~/.bashrc)
echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc
source ~/.zshrc
```

#### Ubuntu/Linux

```bash
# Download the Go binary release (not the legacy bash version)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.18.0
echo -e '\n. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
echo -e '\n. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
source ~/.bashrc
```

### Verify ASDF Version

```bash
asdf --version
# Must be 0.18.0 or later
```

### Install ASDF Plugins

```bash
asdf plugin add python
asdf plugin add nodejs
asdf plugin add uv
asdf plugin add pipx
```

### Install Tool Versions

From the repository root (where `.tool-versions` lives):

```bash
asdf install
```

This reads `.tool-versions` and installs all specified versions automatically.

### Verify Installed Versions

```bash
asdf current
```

Expected output:

```
python   3.12.11   /Users/you/workspace/research-mind/.tool-versions
nodejs   22.21.1   /Users/you/workspace/research-mind/.tool-versions
pipx     1.8.0     /Users/you/workspace/research-mind/.tool-versions
```

---

## Docker Setup Decision Matrix

| Scenario | Approach | Command |
|----------|----------|---------|
| Local development (recommended) | Docker for PostgreSQL only | `docker compose up -d postgres` + `make dev` |
| Full containerized dev | All services in Docker | `docker compose up` |

For most development work, use **Docker for PostgreSQL only**. This gives you hot-reload for both the backend and frontend while keeping the database in a container.

Use **full containerized dev** when you want to verify Docker builds or test in a production-like environment.

---

## Pre-Flight: Port Conflict Detection

Before starting services, verify that the default ports are available:

```bash
# Check for conflicts on the service port (15010)
lsof -i :15010
# Check for conflicts on the UI port (15000)
lsof -i :15000
# Check for conflicts on the PostgreSQL port (5432)
lsof -i :5432
```

If any of these commands return output, another process is using that port. Either stop the conflicting process or configure alternative ports (see the [Changing Ports](#changing-ports) section below).

---

## Installation

Choose **Option A** (Docker for everything) for the quickest start, or **Option B** (Local development) for full development flexibility with hot-reload.

### Option A: Docker (All Services)

This runs PostgreSQL and the backend service in containers.

```bash
# Clone the repository
git clone git@github.com:MacPhobos/research-mind.git
cd research-mind

# Clone sub-projects
git clone git@github.com:MacPhobos/research-mind-service.git research-mind-service
git clone git@github.com:MacPhobos/research-mind-ui.git research-mind-ui

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
git clone git@github.com:MacPhobos/research-mind.git
cd research-mind

# Clone sub-projects
git clone git@github.com:MacPhobos/research-mind-service.git research-mind-service
git clone git@github.com:MacPhobos/research-mind-ui.git research-mind-ui

# Copy environment files (do this FIRST so you can review/customize)
make setup
# >>> Review .env files and adjust DATABASE_URL, ports, etc. if needed <<<

# Install all dependencies (backend + frontend)
make install

# Start PostgreSQL via Docker
docker compose up -d postgres

# Wait for PostgreSQL to be ready
sleep 3

# Apply database migrations (explicit separate step)
cd research-mind-service && uv run alembic upgrade head && cd ..

# Start the development stack (does NOT run migrations)
make dev
```

> **Important**: `make dev` does NOT auto-run database migrations. Always run `alembic upgrade head` explicitly after database setup and whenever new migrations are added.

This starts:

- **PostgreSQL**: localhost:5432
- **Backend API**: http://localhost:15010
- **Frontend UI**: http://localhost:15000

---

## Verifying Your Installation

### Automated Verification

Run the verification script to check all components:

```bash
./scripts/verify-install.sh
```

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

If you already have PostgreSQL 15+ (16 recommended) running locally:

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

> **DATABASE_URL format**: The canonical format uses the `postgresql+psycopg://` prefix (with psycopg3 async driver). The format in `.env.example` is the source of truth. Do not use `postgresql://` or `postgres://` -- always use `postgresql+psycopg://`.

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

**Diagnosis**:

```bash
# Check what is using each port
lsof -i :15010  # Backend service port
lsof -i :15000  # Frontend UI port
lsof -i :5432   # PostgreSQL port
```

**Solution**:

```bash
# Option 1: Kill the conflicting process
lsof -ti:15010 | xargs kill -9

# Option 2: Use alternative ports (see "Changing Ports" section above)
```

If port 5432 is in use by a local PostgreSQL installation, either stop it or update `DATABASE_URL` and `docker-compose.yml` to use a different port.

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

### ASDF Troubleshooting

#### `python --version` Shows Wrong Version

**Symptom**: After running `asdf install`, `python --version` or `python3 --version` still shows an older version.

**Solutions**:

1. **Reshim** to regenerate ASDF shims:

   ```bash
   asdf reshim python
   ```

2. **Verify your shell is using ASDF shims** (not system Python):

   ```bash
   which python3
   # Should show something like: ~/.asdf/shims/python3
   # If it shows /usr/bin/python3, ASDF shims are not first in your PATH
   ```

3. **Reload your shell** to pick up PATH changes:

   ```bash
   source ~/.zshrc  # or ~/.bashrc
   ```

4. **Verify the correct version is active**:

   ```bash
   asdf current python
   # Expected: python 3.12.11  /path/to/research-mind/.tool-versions
   ```

#### `asdf: command not found`

**Symptom**: Running `asdf` gives "command not found".

**Solution**: ASDF is not loaded in your shell. Add it to your shell profile:

**For Zsh (~/.zshrc)**:

```bash
# If installed via Homebrew (macOS)
. $(brew --prefix asdf)/libexec/asdf.sh

# If installed via git clone
. "$HOME/.asdf/asdf.sh"
```

**For Bash (~/.bashrc)**:

```bash
. "$HOME/.asdf/asdf.sh"
. "$HOME/.asdf/completions/asdf.bash"
```

After editing your profile, reload:

```bash
source ~/.zshrc  # or ~/.bashrc
```

#### Version Conflicts Between Directories

**Symptom**: Different tool versions activate in different directories, or ASDF uses an unexpected version.

**Explanation**: ASDF resolves versions using `.tool-versions` files with the following hierarchy (highest priority first):

1. `.tool-versions` in the current directory
2. `.tool-versions` in parent directories (walking up to `/`)
3. `~/.tool-versions` (global fallback)

If a sub-project has its own `.tool-versions`, it will override the monorepo root's versions when you `cd` into that directory.

**Solutions**:

1. **Check which `.tool-versions` is active**:

   ```bash
   asdf current
   # Shows version and which .tool-versions file it came from
   ```

2. **Ensure you are in the correct directory** when running commands:

   ```bash
   cd /path/to/research-mind
   asdf current  # Should reference ./tool-versions in this directory
   ```

3. **Set a global fallback** (optional, for tools used outside any project):

   ```bash
   asdf global python 3.12.11
   asdf global nodejs 22.21.1
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
    | HTTP
SvelteKit Frontend
    | REST API
FastAPI Backend (localhost:15010)
    | SQL
PostgreSQL (localhost:5432)
```

---

## Getting Help

- **Project README**: [`README.md`](../README.md)
- **Backend Guide**: [`research-mind-service/CLAUDE.md`](../research-mind-service/CLAUDE.md)
- **Frontend Guide**: [`research-mind-ui/CLAUDE.md`](../research-mind-ui/CLAUDE.md)
- **API Contract**: [`research-mind-service/docs/api-contract.md`](../research-mind-service/docs/api-contract.md)
