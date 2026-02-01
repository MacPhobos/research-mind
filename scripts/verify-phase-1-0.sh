#!/bin/bash
# verify-phase-1-0.sh
# Automated verification of Phase 1.0 environment setup
# Usage: ./scripts/verify-phase-1-0.sh

set -e

echo "=== Phase 1.0 Environment Verification ==="
echo ""

# Track pass/fail
PASS=0
FAIL=0

# Helper function for colored output
pass() {
    echo "✓ $1"
    ((PASS++))
}

fail() {
    echo "✗ $1"
    ((FAIL++))
}

# Python check
echo "[1/8] Python 3.12+ verification..."
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d'.' -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d'.' -f2)

if [ "$PYTHON_MAJOR" -gt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -ge 12 ]); then
    pass "Python $PYTHON_VERSION verified"
else
    fail "Python 3.12+ required (found $PYTHON_VERSION)"
fi
echo ""

# mcp-vector-search imports
echo "[2/8] mcp-vector-search imports..."
if python3 -c "from mcp_vector_search.core import GitManager; print('imports ok')" > /dev/null 2>&1; then
    pass "mcp-vector-search imports working"
else
    fail "mcp-vector-search import failed"
fi
echo ""

# Transitive dependencies
echo "[3/8] Transitive dependencies..."
if python3 -c "import torch, transformers, chromadb; from sentence_transformers import SentenceTransformer" > /dev/null 2>&1; then
    TORCH_VERSION=$(python3 -c "import torch; print(torch.__version__)")
    TRANSFORMERS_VERSION=$(python3 -c "import transformers; print(transformers.__version__)")
    CHROMADB_VERSION=$(python3 -c "import chromadb; print(chromadb.__version__)")
    pass "All transitive dependencies present"
    echo "    - PyTorch: $TORCH_VERSION"
    echo "    - Transformers: $TRANSFORMERS_VERSION"
    echo "    - ChromaDB: $CHROMADB_VERSION"
else
    fail "Transitive dependency check failed"
fi
echo ""

# PostgreSQL connection
echo "[4/8] PostgreSQL connection..."
if psql -h localhost -U mac -d research_mind -c "SELECT 1" > /dev/null 2>&1; then
    pass "PostgreSQL connected"
else
    fail "PostgreSQL connection failed"
fi
echo ""

# Database tables
echo "[5/8] Database setup..."
TABLE_COUNT=$(psql -h localhost -U mac -d research_mind -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null || echo "0")
if [ "$TABLE_COUNT" -eq "0" ]; then
    pass "Database empty (expected for Phase 1.0)"
else
    pass "Database has $TABLE_COUNT tables"
fi
echo ""

# Sandbox directory
echo "[6/8] Sandbox directory..."
if [ -d "research-mind-service/app/sandbox" ]; then
    pass "Sandbox directory exists"
    if [ -f "research-mind-service/app/sandbox/__init__.py" ]; then
        pass "Sandbox __init__.py present"
    else
        fail "Sandbox __init__.py missing"
    fi
else
    fail "Sandbox directory missing"
fi
echo ""

# Docker verification
echo "[7/8] Docker verification..."
if command -v docker &> /dev/null; then
    pass "Docker installed: $(docker --version)"
else
    fail "Docker not installed"
fi

if command -v docker-compose &> /dev/null; then
    pass "docker-compose installed: $(docker-compose --version)"
else
    fail "docker-compose not installed"
fi

if docker ps > /dev/null 2>&1; then
    pass "Docker daemon running"
else
    fail "Docker daemon not running (optional - can start with 'open /Applications/Docker.app')"
fi
echo ""

# Session model
echo "[8/8] Session model stub..."
if cd research-mind-service && python3 -c "from app.models.session import Session; print('model ok')" > /dev/null 2>&1; then
    pass "Session model imports successfully"
else
    fail "Session model import failed"
fi
cd - > /dev/null
echo ""

# Summary
echo "=== Phase 1.0 Verification Summary ==="
echo "Passed: $PASS/8"
echo "Failed: $FAIL/8"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "✓ All checks passed - Ready for Phase 1.1"
    exit 0
else
    echo "✗ Some checks failed - Review above for details"
    exit 1
fi
