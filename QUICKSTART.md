# Research Mind -- Quickstart

> For detailed instructions, see [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)

**Prerequisites:** ASDF 0.18+ (Go rewrite), Docker Desktop, Make

## 1. Clone

These are separate repositories, not submodules.

```bash
git clone git@github.com:MacPhobos/research-mind.git research-mind
git clone git@github.com:MacPhobos/research-mind-service.git research-mind/research-mind-service
git clone git@github.com:MacPhobos/research-mind-ui.git research-mind/research-mind-ui
```

## 2. Install ASDF Plugins and Tools

```bash
asdf plugin add python
asdf plugin add nodejs
asdf plugin add uv
asdf plugin add pipx
cd research-mind
asdf install
```

## 3. System Dependencies

Required by WeasyPrint (PDF generation).

**macOS:**

```bash
brew install cairo pango gdk-pixbuf libffi
```

**Ubuntu:**

```bash
sudo apt install libcairo2-dev libpango1.0-dev libgdk-pixbuf2.0-dev libffi-dev
```

## 4. Setup and Install

```bash
make setup    # Creates .env files from .env.example templates
make install  # Installs Python (uv sync) and Node.js (npm install) dependencies
```

## 5. Database

```bash
docker compose up -d postgres             # Start PostgreSQL 16
cd research-mind-service
uv run alembic upgrade head               # Apply migrations
cd ..
```

## 6. Post-Install

```bash
cd research-mind-service
uv run playwright install chromium         # Browser for content retrieval
cd ..
```

Optional global CLI tools:

```bash
pipx install mcp-vector-search
pipx install claude-mpm
```

## 7. Run

```bash
make dev
```

Verify:

- Service: http://localhost:15010/health
- UI: http://localhost:15000
- API docs: http://localhost:15010/docs

## 8. Verify Installation

```bash
./scripts/verify-install.sh
```

Pre-install check (prerequisites only):

```bash
./scripts/verify-install.sh --pre-install
```

## Stop

```bash
make stop
```

## Reset

```bash
make db-reset   # Drop and recreate database with migrations
make clean      # Remove node_modules, .venv, and database volumes
```

## Troubleshooting

See [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) for detailed instructions and troubleshooting.
