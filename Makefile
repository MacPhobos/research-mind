.PHONY: help setup init install dev stop test lint fmt typecheck gen-client db-up db-reset clean

help:
	@echo "Available targets:"
	@grep "^[a-z-]*:" Makefile | cut -d: -f1 | sed 's/^/  make /'

setup:
	@echo "Setting up environment files..."
	@if [ -f .env ]; then \
		echo "  SKIP: .env already exists"; \
	else \
		cp .env.example .env; \
		echo "  CREATED: .env"; \
	fi
	@if [ -f research-mind-service/.env ]; then \
		echo "  SKIP: research-mind-service/.env already exists"; \
	else \
		cp research-mind-service/.env.example research-mind-service/.env; \
		echo "  CREATED: research-mind-service/.env"; \
	fi
	@if [ -f research-mind-ui/.env ]; then \
		echo "  SKIP: research-mind-ui/.env already exists"; \
	else \
		cp research-mind-ui/.env.example research-mind-ui/.env; \
		echo "  CREATED: research-mind-ui/.env"; \
	fi
	@echo ""
	@echo "Setup complete. You can customize the .env files as needed."

init: setup

install:
	@echo "Installing dependencies..."
	cd research-mind-ui && npm install
	cd research-mind-service && uv sync
	@echo "✓ Dependencies installed"

dev:
	@echo "Starting dev stack (Service + UI + Postgres)..."
	docker compose up -d postgres
	@sleep 2
	@cd research-mind-service && uv run uvicorn app.main:app --host 0.0.0.0 --port 15010 --reload &
	@cd research-mind-ui && npm run dev &
	@echo "✓ Dev stack running"
	@echo "  Service: http://localhost:15010"
	@echo "  UI: http://localhost:15000"
	@echo "  Health: curl http://localhost:15010/health"

stop:
	pkill -f "uvicorn" || true
	pkill -f "vite" || true
	docker compose down

test:
	@echo "Running tests..."
	cd research-mind-service && uv run pytest
	cd research-mind-ui && npm run test

lint:
	@echo "Linting..."
	cd research-mind-service && uv run ruff check app tests
	cd research-mind-ui && npm run lint

fmt:
	@echo "Formatting..."
	cd research-mind-service && uv run black app tests && uv run ruff check --fix app tests
	cd research-mind-ui && npm run format

typecheck:
	@echo "Type checking..."
	cd research-mind-service && uv run mypy app
	cd research-mind-ui && npm run typecheck

gen-client:
	@echo "Generating TypeScript client from OpenAPI..."
	cd research-mind-ui && npx openapi-typescript http://localhost:15010/openapi.json -o src/lib/api/generated.ts
	@echo "✓ Client generated at research-mind-ui/src/lib/api/generated.ts"

db-up:
	docker compose up -d postgres
	@sleep 2
	@echo "✓ Postgres running on localhost:5432"

db-reset:
	docker compose down -v
	docker compose up -d postgres
	@sleep 2
	@cd research-mind-service && uv run alembic upgrade head
	@echo "✓ Database reset and migrated"

clean:
	rm -rf research-mind-ui/node_modules research-mind-service/.venv
	docker compose down -v
	@echo "✓ Cleaned"
