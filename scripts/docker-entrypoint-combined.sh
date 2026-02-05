#!/bin/bash
set -e

echo "==========================================="
echo "  Research Mind (Combined Mode)"
echo "==========================================="
echo ""

# Check required environment variable
if [ -z "$DATABASE_URL" ]; then
    echo "ERROR: DATABASE_URL environment variable is required"
    echo "Example: postgresql+psycopg://postgres:devpass123@host.docker.internal:5432/research_mind"
    exit 1
fi

echo "Database URL: ${DATABASE_URL%@*}@[hidden]"
echo ""

# Run database migrations if AUTO_MIGRATE is set
if [ "${AUTO_MIGRATE:-false}" = "true" ]; then
    echo "Running database migrations..."
    cd /app && alembic upgrade head
    echo "Migrations complete."
    echo ""
fi

# Start backend in background
echo "Starting backend on port 15010..."
cd /app
uvicorn app.main:app --host 0.0.0.0 --port 15010 &
BACKEND_PID=$!

# Wait for backend to be ready
echo "Waiting for backend to be ready..."
for i in {1..30}; do
    if curl -sf http://localhost:15010/health > /dev/null 2>&1; then
        echo "Backend is ready."
        break
    fi
    sleep 1
done

# Start frontend in background
echo "Starting frontend on port 15000..."
cd /app/ui
PORT=15000 HOST=0.0.0.0 node build &
FRONTEND_PID=$!

echo ""
echo "==========================================="
echo "  Services Started"
echo "==========================================="
echo "  Backend:  http://localhost:15010"
echo "  Frontend: http://localhost:15000"
echo "  API Docs: http://localhost:15010/docs"
echo "==========================================="
echo ""

# Trap signals for graceful shutdown
trap "echo 'Shutting down...'; kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; exit 0" SIGTERM SIGINT

# Wait for both processes
wait $BACKEND_PID $FRONTEND_PID
