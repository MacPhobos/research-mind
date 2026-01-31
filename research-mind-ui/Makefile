.PHONY: help install dev build preview test test-watch test-ui lint fmt typecheck check clean

help:
	@echo "Research Mind UI - Available targets:"
	@echo ""
	@echo "  make install     Install dependencies"
	@echo "  make dev         Start development server on port 5173"
	@echo "  make build       Build for production"
	@echo "  make preview     Preview production build locally"
	@echo "  make test        Run all tests once"
	@echo "  make test-watch  Run tests in watch mode"
	@echo "  make test-ui     Run tests with UI"
	@echo "  make lint        Run linter"
	@echo "  make fmt         Format code"
	@echo "  make typecheck   Type check TypeScript/Svelte"
	@echo "  make check       Run lint, typecheck, and tests"
	@echo "  make clean       Remove build artifacts and dependencies"
	@echo ""

install:
	@echo "Installing dependencies..."
	npm install
	@echo "Dependencies installed"

dev:
	@echo "Starting development server..."
	npm run dev

build:
	@echo "Building for production..."
	npm run build

preview:
	@echo "Previewing production build..."
	npm run preview

test:
	@echo "Running tests..."
	npm run test -- --run

test-watch:
	@echo "Running tests in watch mode..."
	npm run test

test-ui:
	@echo "Running tests with UI..."
	npm run test:ui

lint:
	@echo "Linting code..."
	npm run lint

fmt:
	@echo "Formatting code..."
	npm run format

typecheck:
	@echo "Type checking..."
	npm run typecheck

check: lint typecheck test
	@echo "All checks passed"

clean:
	@echo "Cleaning up..."
	rm -rf node_modules dist .svelte-kit .turbo coverage
	@echo "Cleaned"

.DEFAULT_GOAL := help
