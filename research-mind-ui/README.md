# Research Mind UI

A SvelteKit frontend application for the research-mind service.

## Overview

This is a modern, type-safe SvelteKit application that provides a user interface for the research-mind service. It uses TanStack Query for data fetching, Zod for validation, and Vitest for testing.

## Configuration

- **Port**: 15000 (localhost)
- **Service API**: http://localhost:15010
- **Framework**: SvelteKit 4.2+
- **Language**: TypeScript 5.6+
- **Package Manager**: npm

## Getting Started

### Prerequisites

- Node.js 20.x or 22.x
- npm 10.x or later

### Installation

```bash
npm install
```

### Development

```bash
npm run dev
```

The application will be available at `http://localhost:15000`

### Build

```bash
npm run build
```

### Preview Production Build

```bash
npm run preview
```

## Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run preview` - Preview production build
- `npm run test` - Run tests with Vitest
- `npm run test:ui` - Run tests with UI
- `npm run typecheck` - Run TypeScript type checking
- `npm run lint` - Run ESLint
- `npm run format` - Format code with Prettier

## Environment Variables

Create a `.env.local` file for local development:

```
VITE_API_BASE_URL=http://localhost:15010
```

See `.env.example` for all available variables.

## Project Structure

```
src/
├── routes/            # SvelteKit page routes
│   ├── +page.svelte   # Home page
│   └── +layout.svelte # Root layout
├── lib/
│   ├── api/           # API client and hooks
│   │   ├── client.ts  # API client with Zod schemas
│   │   └── hooks.ts   # SvelteKit/TanStack Query hooks
│   ├── components/    # Reusable Svelte components
│   ├── stores/        # Svelte stores for state
│   └── utils/         # Utility functions
└── app.css            # Global styles

tests/                 # Test files
public/                # Static assets
```

## Architecture

### API Integration

The application follows a vertical slice pattern with type-safe API integration:

1. **API Client** (`src/lib/api/client.ts`): Handles HTTP requests with Zod validation
2. **Hooks** (`src/lib/api/hooks.ts`): Provides TanStack Query wrappers
3. **Components** (`src/lib/components/`): Use hooks for data fetching

### State Management

- **TanStack Query**: Server state (API data)
- **Svelte Stores**: Client state (UI preferences)

### Type Safety

- **TypeScript**: Strict mode enabled
- **Zod**: Runtime validation of API responses
- **Branded Types**: Domain-specific type safety

## Testing

Run tests with:

```bash
npm run test
```

Tests are written with Vitest and cover:
- API client functionality
- Schema validation
- Component behavior

## Quality Assurance

The project includes:

- **Type Checking**: `npm run typecheck` (svelte-check)
- **Linting**: `npm run lint` (ESLint)
- **Formatting**: `npm run format` (Prettier)
- **Testing**: `npm run test` (Vitest)

## API Contract

The UI expects the service to provide:

### GET /api/v1/version

Returns version and environment information:

```json
{
  "version": "1.0.0",
  "environment": "development",
  "timestamp": "2024-01-30T20:00:00Z"
}
```

See `docs/api-contract.md` for complete API documentation.

## Dependencies

### Core
- **svelte**: ^4.2.18 - Reactive UI framework
- **sveltekit**: Latest - Full-stack framework
- **vite**: ^5.4.10 - Build tool

### Data & Validation
- **@tanstack/svelte-query**: ^5.51.23 - Data fetching and caching
- **zod**: ^3.22.0 - Runtime validation

### UI
- **lucide-svelte**: ^0.344.0 - Icon library

### Development
- **typescript**: ^5.6.3 - Type safety
- **vitest**: ^2.1.8 - Testing
- **eslint**: ^9.18.0 - Linting
- **prettier**: ^3.4.2 - Formatting

## Contributing

Follow the project's TypeScript and Svelte conventions. All code must:

1. Pass TypeScript type checking
2. Pass ESLint and Prettier
3. Have tests for new functionality
4. Include documentation for public APIs

## License

Proprietary - Research Mind Project
