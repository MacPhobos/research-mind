#!/bin/bash
# verify-install.sh
# Verifies that the research-mind development environment is correctly set up.
# Usage: ./scripts/verify-install.sh

set -e

echo "=============================================="
echo "  research-mind Installation Verification"
echo "=============================================="
echo ""

# Track pass/fail
PASS=0
FAIL=0
WARN=0

# Helper functions
pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo "[WARN] $1"
    WARN=$((WARN + 1))
}

info() {
    echo "[INFO] $1"
}

# Determine script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "Project root: $PROJECT_ROOT"
echo ""

# =============================================================================
# 1. Python Check
# =============================================================================
echo "--- Checking Python ---"

if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d'.' -f2)

    if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 12 ]; then
        pass "Python $PYTHON_VERSION (>= 3.12 required)"
    else
        fail "Python $PYTHON_VERSION found, but >= 3.12 required"
    fi
else
    fail "Python 3 not found"
fi
echo ""

# =============================================================================
# 2. Node.js Check
# =============================================================================
echo "--- Checking Node.js ---"

if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d'.' -f1)

    if [ "$NODE_MAJOR" -ge 20 ]; then
        pass "Node.js v$NODE_VERSION (>= 20.x required)"
    else
        fail "Node.js v$NODE_VERSION found, but >= 20.x required"
    fi
else
    fail "Node.js not found"
fi

if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm --version)
    pass "npm $NPM_VERSION"
else
    fail "npm not found"
fi
echo ""

# =============================================================================
# 3. uv Package Manager Check
# =============================================================================
echo "--- Checking uv Package Manager ---"

if command -v uv &> /dev/null; then
    UV_VERSION=$(uv --version 2>&1 | head -1)
    pass "$UV_VERSION"
else
    fail "uv not found - install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi
echo ""

# =============================================================================
# 4. Docker Check (Optional)
# =============================================================================
echo "--- Checking Docker (Optional) ---"

if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version 2>&1)
    pass "$DOCKER_VERSION"

    if docker ps &> /dev/null; then
        pass "Docker daemon is running"
    else
        warn "Docker daemon is not running (start Docker Desktop or run 'sudo systemctl start docker')"
    fi
else
    warn "Docker not installed (optional, but recommended for PostgreSQL)"
fi

if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version 2>&1 | head -1)
    pass "$COMPOSE_VERSION"
else
    warn "Docker Compose not available"
fi
echo ""

# =============================================================================
# 5. PostgreSQL Check
# =============================================================================
echo "--- Checking PostgreSQL ---"

# Check if postgres container is running
if docker ps 2>/dev/null | grep -q "postgres"; then
    pass "PostgreSQL container is running"

    # Try to connect
    if docker compose exec -T postgres psql -U postgres -d research_mind -c "SELECT 1" &> /dev/null; then
        pass "Database 'research_mind' is accessible"
    else
        fail "Cannot connect to 'research_mind' database"
    fi
elif command -v psql &> /dev/null; then
    PSQL_VERSION=$(psql --version 2>&1 | head -1)
    pass "$PSQL_VERSION (local installation)"

    if pg_isready -h localhost -p 5432 &> /dev/null; then
        pass "PostgreSQL is accepting connections on localhost:5432"
    else
        warn "PostgreSQL is not running on localhost:5432"
    fi
else
    warn "PostgreSQL not detected (run 'docker compose up -d postgres' to start)"
fi
echo ""

# =============================================================================
# 6. Backend Dependencies Check
# =============================================================================
echo "--- Checking Backend Dependencies ---"

if [ -d "research-mind-service" ]; then
    if [ -f "research-mind-service/.venv/bin/python" ] || [ -d "research-mind-service/.venv" ]; then
        pass "Backend virtual environment exists"
    else
        warn "Backend virtual environment not found (run 'cd research-mind-service && uv sync')"
    fi

    if [ -f "research-mind-service/.env" ]; then
        pass "Backend .env file exists"
    else
        warn "Backend .env file missing (copy from .env.example)"
    fi
else
    fail "research-mind-service directory not found"
fi
echo ""

# =============================================================================
# 7. Frontend Dependencies Check
# =============================================================================
echo "--- Checking Frontend Dependencies ---"

if [ -d "research-mind-ui" ]; then
    if [ -d "research-mind-ui/node_modules" ]; then
        pass "Frontend node_modules exists"
    else
        warn "Frontend node_modules not found (run 'cd research-mind-ui && npm install')"
    fi

    if [ -f "research-mind-ui/.env" ]; then
        pass "Frontend .env file exists"
    else
        warn "Frontend .env file missing (copy from .env.example)"
    fi
else
    fail "research-mind-ui directory not found"
fi
echo ""

# =============================================================================
# 8. Service Health Checks
# =============================================================================
echo "--- Checking Running Services ---"

# Backend health check
if curl -s http://localhost:15010/health &> /dev/null; then
    HEALTH_RESPONSE=$(curl -s http://localhost:15010/health)
    pass "Backend is running on http://localhost:15010"
    info "  Response: $HEALTH_RESPONSE"
else
    warn "Backend is not running on http://localhost:15010 (start with 'make dev')"
fi

# Frontend check
if curl -s http://localhost:15000 &> /dev/null; then
    pass "Frontend is running on http://localhost:15000"
else
    warn "Frontend is not running on http://localhost:15000 (start with 'make dev')"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=============================================="
echo "  Verification Summary"
echo "=============================================="
echo ""
echo "  Passed:   $PASS"
echo "  Failed:   $FAIL"
echo "  Warnings: $WARN"
echo ""

if [ "$FAIL" -eq 0 ]; then
    if [ "$WARN" -eq 0 ]; then
        echo "All checks passed! Your environment is ready."
        echo ""
        echo "Next steps:"
        echo "  1. Start development: make dev"
        echo "  2. Open UI: http://localhost:15000"
        echo "  3. API docs: http://localhost:15010/docs"
    else
        echo "Core requirements passed, but there are some warnings."
        echo "Review the warnings above and address if needed."
    fi
    exit 0
else
    echo "Some checks failed. Please review the issues above."
    echo ""
    echo "Quick fixes:"
    echo "  - Install dependencies: make install"
    echo "  - Start PostgreSQL: docker compose up -d postgres"
    echo "  - Start services: make dev"
    exit 1
fi
