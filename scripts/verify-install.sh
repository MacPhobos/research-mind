#!/usr/bin/env bash
# verify-install.sh -- Research Mind installation doctor
# Usage: ./scripts/verify-install.sh [--pre-install] [--quick]

PASS_COUNT=0; FAIL_COUNT=0; WARN_COUNT=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PRE_INSTALL=false; QUICK=false

for arg in "$@"; do
    case "$arg" in
        --pre-install) PRE_INSTALL=true ;;
        --quick)       QUICK=true ;;
    esac
done

pass()  { echo -e "  ${GREEN}✓${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail()  { echo -e "  ${RED}✗${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
info()  { echo -e "  ${BLUE}i${NC} $1"; }

# Detect OS
OS="unknown"
case "$(uname -s)" in
    Darwin*) OS="macos" ;;
    Linux*)  OS="linux" ;;
esac

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$PROJECT_ROOT/Makefile" ] || [ ! -f "$PROJECT_ROOT/.tool-versions" ]; then
    echo "Error: Must run from the research-mind project root."
    echo "Usage: ./scripts/verify-install.sh"
    exit 2
fi
cd "$PROJECT_ROOT"

# Read expected versions from .tool-versions
EXPECTED_PYTHON=$(grep '^python' .tool-versions | awk '{print $2}')
EXPECTED_NODE=$(grep '^nodejs' .tool-versions | awk '{print $2}')

echo ""
echo "Research Mind -- Installation Doctor"
echo "===================================="
echo ""

# =============================================================================
# Phase 1: Runtime Tools
# =============================================================================
echo "Phase 1: Runtime Tools"

# ASDF
if command -v asdf &>/dev/null; then
    ASDF_VER=$(asdf version 2>&1 | head -1 | sed 's/[^0-9.]//g')
    ASDF_MAJOR=$(echo "$ASDF_VER" | cut -d. -f1)
    ASDF_MINOR=$(echo "$ASDF_VER" | cut -d. -f2)
    if [ "${ASDF_MAJOR:-0}" -ge 1 ] || { [ "${ASDF_MAJOR:-0}" -eq 0 ] && [ "${ASDF_MINOR:-0}" -ge 18 ]; }; then
        pass "ASDF $ASDF_VER (Go)"
    else
        fail "ASDF $ASDF_VER (>= 0.18.0 required)"
        info "  Fix: https://asdf-vm.com/guide/getting-started.html"
    fi
else
    fail "ASDF not installed"
    info "  Fix: https://asdf-vm.com/guide/getting-started.html"
fi

# Python
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1 | awk '{print $2}')
    PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
    if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 12 ]; then
        pass "Python $PY_VER (expected $EXPECTED_PYTHON)"
    else
        fail "Python $PY_VER (expected $EXPECTED_PYTHON)"
        info "  Fix: asdf install python $EXPECTED_PYTHON"
    fi
else
    fail "Python 3 not found"
    info "  Fix: asdf plugin add python && asdf install"
fi

# Node.js
if command -v node &>/dev/null; then
    NODE_VER=$(node --version | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
    if [ "$NODE_MAJOR" -ge 22 ]; then
        pass "Node.js $NODE_VER (expected $EXPECTED_NODE)"
    else
        fail "Node.js $NODE_VER (expected $EXPECTED_NODE)"
        info "  Fix: asdf install nodejs $EXPECTED_NODE"
    fi
else
    fail "Node.js not found"
    info "  Fix: asdf plugin add nodejs && asdf install"
fi

# uv
if command -v uv &>/dev/null; then
    UV_VER=$(uv --version 2>&1 | awk '{print $2}')
    pass "uv $UV_VER"
else
    fail "uv not installed"
    info "  Fix: asdf plugin add uv && asdf install"
fi

# pipx
if command -v pipx &>/dev/null; then
    PIPX_VER=$(pipx --version 2>&1)
    pass "pipx $PIPX_VER"
else
    fail "pipx not installed"
    info "  Fix: asdf plugin add pipx && asdf install"
fi

# npm
if command -v npm &>/dev/null; then
    NPM_VER=$(npm --version 2>&1)
    pass "npm $NPM_VER"
else
    fail "npm not found (should come with Node.js)"
fi

echo ""

# =============================================================================
# Phase 2: System Dependencies
# =============================================================================
echo "Phase 2: System Dependencies"

# Docker
if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>&1 | sed 's/Docker version //' | cut -d, -f1)
    pass "Docker $DOCKER_VER"
else
    fail "Docker not installed"
    info "  Fix: Install Docker Desktop from https://docker.com"
fi

# Docker Compose v2
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    COMPOSE_VER=$(docker compose version --short 2>&1)
    pass "Docker Compose $COMPOSE_VER"
else
    fail "Docker Compose v2 not available"
    info "  Fix: Install Docker Desktop (includes Compose v2)"
fi

# WeasyPrint system deps
check_weasyprint_dep() {
    local name="$1"
    local brew_pkg="$2"
    local apt_pkg="$3"

    if [ "$OS" = "macos" ]; then
        if brew list "$brew_pkg" &>/dev/null 2>&1; then
            pass "$name (WeasyPrint)"
            return
        fi
    elif [ "$OS" = "linux" ]; then
        if dpkg -l "$apt_pkg" 2>/dev/null | grep -q "^ii"; then
            pass "$name (WeasyPrint)"
            return
        fi
    fi
    # Cross-platform fallback
    if pkg-config --exists "$name" 2>/dev/null; then
        pass "$name (WeasyPrint)"
    else
        fail "$name not found (WeasyPrint dependency)"
        if [ "$OS" = "macos" ]; then
            info "  Fix: brew install $brew_pkg"
        elif [ "$OS" = "linux" ]; then
            info "  Fix: sudo apt install $apt_pkg"
        fi
    fi
}

check_weasyprint_dep "cairo"      "cairo"      "libcairo2-dev"
check_weasyprint_dep "pango"      "pango"      "libpango1.0-dev"
check_weasyprint_dep "gdk-pixbuf" "gdk-pixbuf" "libgdk-pixbuf2.0-dev"

echo ""

# Stop here for --pre-install
if [ "$PRE_INSTALL" = true ]; then
    echo "===================================="
    echo -e "Results: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}, ${YELLOW}${WARN_COUNT} warnings${NC}"
    echo "(--pre-install: phases 3-8 skipped)"
    echo ""
    [ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
fi

# =============================================================================
# Phase 3: Repository Structure
# =============================================================================
echo "Phase 3: Repository Structure"

if [ -d "research-mind-service" ]; then
    pass "research-mind-service/ exists"
else
    fail "research-mind-service/ not found"
    info "  Fix: git clone git@github.com:MacPhobos/research-mind-service.git research-mind-service"
fi

if [ -d "research-mind-ui" ]; then
    pass "research-mind-ui/ exists"
else
    fail "research-mind-ui/ not found"
    info "  Fix: git clone git@github.com:MacPhobos/research-mind-ui.git research-mind-ui"
fi

# .env files
ENV_OK=true
for envpath in ".env" "research-mind-service/.env" "research-mind-ui/.env"; do
    if [ ! -f "$envpath" ]; then
        ENV_OK=false
    fi
done
if [ "$ENV_OK" = true ]; then
    pass ".env files configured (root, service, ui)"
else
    fail ".env files missing"
    info "  Fix: make setup"
fi

echo ""

# =============================================================================
# Phase 4: Dependencies Installed
# =============================================================================
echo "Phase 4: Dependencies"

# Python venv
if [ -d "research-mind-service/.venv" ]; then
    pass "Python venv (.venv)"
else
    fail "Python venv not found"
    info "  Fix: cd research-mind-service && uv sync"
fi

# Node modules
if [ -d "research-mind-ui/node_modules" ]; then
    pass "Node modules (node_modules)"
else
    fail "Node modules not found"
    info "  Fix: cd research-mind-ui && npm install"
fi

# Playwright chromium
PW_FOUND=false
for chromium_dir in research-mind-service/.venv/lib/python*/site-packages/playwright/driver/package/.local-browsers/chromium-*; do
    if [ -d "$chromium_dir" ] 2>/dev/null; then
        PW_FOUND=true
        break
    fi
done
if [ "$PW_FOUND" = true ]; then
    pass "Playwright chromium"
else
    fail "Playwright chromium not installed"
    info "  Fix: cd research-mind-service && uv run playwright install chromium"
fi

echo ""

# =============================================================================
# Phase 5: Database
# =============================================================================
echo "Phase 5: Database"

# Postgres container
PG_RUNNING=false
if docker ps 2>/dev/null | grep -q "postgres"; then
    pass "PostgreSQL container running"
    PG_RUNNING=true
else
    fail "PostgreSQL container not running"
    info "  Fix: docker compose up -d postgres"
fi

# Port 5432 accessible (only if container is running)
if [ "$PG_RUNNING" = true ]; then
    if nc -z localhost 5432 2>/dev/null || (echo >/dev/tcp/localhost/5432) 2>/dev/null; then
        pass "Port 5432 accessible"
    else
        fail "Port 5432 not accessible"
        info "  Fix: Check docker compose logs postgres"
    fi
fi

# DATABASE_URL format
if [ -f "research-mind-service/.env" ]; then
    DB_URL=$(grep '^DATABASE_URL=' research-mind-service/.env 2>/dev/null | cut -d= -f2-)
    if echo "$DB_URL" | grep -q '+psycopg'; then
        pass "DATABASE_URL format valid (+psycopg)"
    elif [ -n "$DB_URL" ]; then
        fail "DATABASE_URL missing +psycopg driver"
        info "  Fix: Edit research-mind-service/.env, use postgresql+psycopg://..."
    else
        warn "DATABASE_URL not set in research-mind-service/.env"
    fi
fi

# Migration status (skip if --quick or postgres not running)
if [ "$QUICK" = false ] && [ "$PG_RUNNING" = true ] && [ -d "research-mind-service" ]; then
    CURRENT=$(cd research-mind-service && uv run alembic current 2>/dev/null | grep -oE '[a-f0-9]{12}' | head -1)
    HEAD=$(cd research-mind-service && uv run alembic heads 2>/dev/null | grep -oE '[a-f0-9]{12}' | head -1)
    if [ -n "$CURRENT" ] && [ -n "$HEAD" ] && [ "$CURRENT" = "$HEAD" ]; then
        pass "Migrations current ($CURRENT)"
    elif [ -n "$HEAD" ]; then
        fail "Migrations not current (at: ${CURRENT:-none}, head: $HEAD)"
        info "  Fix: cd research-mind-service && uv run alembic upgrade head"
    else
        warn "Could not determine migration status"
    fi
elif [ "$QUICK" = true ]; then
    info "Migrations check skipped (--quick)"
fi

echo ""

# =============================================================================
# Phase 6: Services (if running)
# =============================================================================
echo "Phase 6: Services"

BACKEND_RUNNING=false
FRONTEND_RUNNING=false

if [ "$QUICK" = false ]; then
    if curl -sf http://localhost:15010/health &>/dev/null; then
        pass "Backend (http://localhost:15010/health)"
        BACKEND_RUNNING=true
    else
        warn "Backend not running"
        info "  Start: make dev"
    fi

    if curl -sf http://localhost:15000 &>/dev/null; then
        pass "Frontend (http://localhost:15000)"
        FRONTEND_RUNNING=true
    else
        warn "Frontend not running"
        info "  Start: make dev"
    fi
else
    info "Service checks skipped (--quick)"
fi

echo ""

# =============================================================================
# Phase 7: Port Availability
# =============================================================================
echo "Phase 7: Port Availability"

check_port() {
    local port=$1
    local label=$2
    if nc -z localhost "$port" 2>/dev/null || (echo >/dev/tcp/localhost/"$port") 2>/dev/null; then
        info "$label (port $port in use -- service running)"
    else
        pass "$label (port $port available)"
    fi
}

# Only meaningful if services are not all running
if [ "$BACKEND_RUNNING" = true ] && [ "$FRONTEND_RUNNING" = true ] && [ "$PG_RUNNING" = true ]; then
    info "Skipped (all services running)"
else
    check_port 5432  "PostgreSQL"
    check_port 15010 "Backend"
    check_port 15000 "Frontend"
fi

echo ""

# =============================================================================
# Phase 8: Optional Tools
# =============================================================================
echo "Phase 8: Optional Tools"

check_optional() {
    local cmd="$1"
    local install="$2"
    if command -v "$cmd" &>/dev/null; then
        local ver
        ver=$("$cmd" --version 2>&1 | head -1)
        pass "$cmd ($ver)"
    else
        warn "$cmd not installed (optional)"
        info "  Install: $install"
    fi
}

check_optional "mcp-vector-search" "pipx install mcp-vector-search"
check_optional "claude-mpm"        "pipx install claude-mpm"

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "===================================="
TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
echo -e "Results: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}, ${YELLOW}${WARN_COUNT} warnings${NC}"
echo ""

if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
    echo "All checks passed. Environment is ready."
    echo "  Start: make dev"
    echo "  UI:    http://localhost:15000"
    echo "  API:   http://localhost:15010/docs"
elif [ "$FAIL_COUNT" -eq 0 ]; then
    echo "Core requirements passed. Review warnings above."
else
    echo "Some checks failed. Fix the issues above and re-run:"
    echo "  ./scripts/verify-install.sh"
fi

[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
