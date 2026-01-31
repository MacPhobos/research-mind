# Development Setup

## Prerequisites
- Python 3.12+ (via asdf or system)
- Node.js 20+ (via asdf or system)
- Docker + Docker Compose
- Make

## Installation

1. Install dependencies:
   ```bash
   make install
   ```

2. Start development stack:
   ```bash
   make dev
   ```

3. Verify:
   - Service: curl http://localhost:15010/health
   - UI: http://localhost:15000

## Troubleshooting

**Port already in use**:
```bash
lsof -i :15010  # Check what's using port
```

**Docker issues**:
```bash
make stop
docker-compose down -v
make dev
```

See CLAUDE.md for more details.
