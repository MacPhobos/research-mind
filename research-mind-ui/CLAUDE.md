# Research Mind UI - Claude Guide

## Quick Start

```bash
npm install
npm run dev          # Start dev server on :15000
npm run typecheck    # Type checking
npm run lint         # Linting
npm run test         # Tests
```

## Architecture

### Vertical Slice Pattern

```
Feature → Route → Component → Hook → API Client → Zod Schema
```

Example: Getting API version
1. `src/routes/+page.svelte` requests version
2. Calls `useVersionQuery()` hook
3. Hook uses `apiClient.getVersion()`
4. Client validates with `VersionResponseSchema` (Zod)

### Key Files

- **API Client**: `src/lib/api/client.ts` - Type-safe HTTP + Zod validation
- **Hooks**: `src/lib/api/hooks.ts` - TanStack Query wrappers
- **Components**: `src/lib/components/` - Reusable UI
- **Stores**: `src/lib/stores/` - Client state (Svelte stores)
- **Utils**: `src/lib/utils/` - Helpers

## Type Safety

### Zod for Runtime Validation

Always validate API responses:

```typescript
import { z } from 'zod';

const UserSchema = z.object({
  id: z.string(),
  name: z.string(),
  email: z.string().email(),
});

export type User = z.infer<typeof UserSchema>;

export async function getUser(id: string): Promise<User> {
  const response = await fetch(`/api/users/${id}`);
  const data = await response.json();
  return UserSchema.parse(data); // Runtime validation
}
```

### Component Props

Use interfaces for component props:

```svelte
<script lang="ts">
  interface Props {
    title: string;
    count: number;
    onChange: (value: number) => void;
  }

  let { title, count, onChange }: Props = $props();
</script>
```

## Testing

### Test Structure

```typescript
import { describe, it, expect, vi } from 'vitest';
import { apiClient } from '../src/lib/api/client';

describe('API Client', () => {
  it('should fetch data', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ version: '1.0.0' }),
      } as Response)
    );

    const result = await apiClient.getVersion();
    expect(result.version).toBe('1.0.0');
  });
});
```

### Running Tests

```bash
npm run test           # Run all tests
npm run test:ui        # Run with UI
npm run test -- --coverage  # With coverage
```

## Common Tasks

### Adding a New API Endpoint

1. **Define schema** in `src/lib/api/client.ts`:
```typescript
const UserListSchema = z.array(UserSchema);
```

2. **Add method** to `apiClient`:
```typescript
export const apiClient = {
  async getUsers(): Promise<User[]> {
    const response = await fetch(`${apiBaseUrl}/api/users`);
    if (!response.ok) throw new Error('Failed to fetch users');
    const data = await response.json();
    return UserListSchema.parse(data);
  },
};
```

3. **Create hook** in `src/lib/api/hooks.ts`:
```typescript
export function useUsersQuery() {
  return useQuery({
    queryKey: ['users'],
    queryFn: () => apiClient.getUsers(),
    staleTime: 60000,
  });
}
```

4. **Use in component**:
```svelte
<script lang="ts">
  import { useUsersQuery } from '$lib/api/hooks';
  const usersQuery = useUsersQuery();
</script>

{#if $usersQuery.isPending}
  Loading...
{:else if $usersQuery.isError}
  Error: {$usersQuery.error.message}
{:else}
  {#each $usersQuery.data as user}
    <div>{user.name}</div>
  {/each}
{/if}
```

### Adding a New Component

1. Create file: `src/lib/components/UserCard.svelte`
2. Define props interface
3. Use runes (`$props()`, `$derived()`)
4. Style with scoped CSS

```svelte
<script lang="ts">
  interface Props {
    user: { id: string; name: string; email: string };
    onSelect?: (id: string) => void;
  }

  let { user, onSelect }: Props = $props();
</script>

<div class="card" onclick={() => onSelect?.(user.id)}>
  <h3>{user.name}</h3>
  <p>{user.email}</p>
</div>

<style>
  .card {
    padding: 1rem;
    border: 1px solid #ddd;
    border-radius: 4px;
    cursor: pointer;
  }
</style>
```

### Adding a Store

Create `src/lib/stores/mystore.ts`:

```typescript
import { writable } from 'svelte/store';

interface State {
  count: number;
}

const { subscribe, set, update } = writable<State>({ count: 0 });

export const myStore = {
  subscribe,
  increment: () => update((s) => ({ ...s, count: s.count + 1 })),
  decrement: () => update((s) => ({ ...s, count: s.count - 1 })),
};
```

Use in component:

```svelte
<script lang="ts">
  import { myStore } from '$lib/stores/mystore';
</script>

<p>Count: {$myStore.count}</p>
<button onclick={() => myStore.increment()}>+</button>
```

## Environment Variables

Create `.env.local`:

```
VITE_API_BASE_URL=http://localhost:15010
```

Access in code:

```typescript
const apiUrl = import.meta.env.VITE_API_BASE_URL;
const isDev = import.meta.env.DEV;
```

## Quality Checklist

Before committing:

- [ ] `npm run typecheck` passes
- [ ] `npm run lint` passes
- [ ] `npm run test` passes
- [ ] New code has tests
- [ ] No `any` types
- [ ] Component props typed
- [ ] API responses validated with Zod

## Performance Tips

1. **Lazy load routes**: SvelteKit does this automatically
2. **Use TanStack Query**: Automatic caching + refetching
3. **Memoize expensive operations**: `$derived` (Svelte 5)
4. **Avoid rerenders**: Use stores for shared state
5. **Code split**: Async route imports handled by SvelteKit

## Debugging

### Check Types

```bash
npm run typecheck
```

### Debug Tests

```bash
npm run test -- --inspect-brk
```

### Browser DevTools

SvelteKit includes HMR. DevTools work normally.

## Useful Links

- [SvelteKit Docs](https://kit.svelte.dev)
- [Svelte Docs](https://svelte.dev)
- [TanStack Query Docs](https://tanstack.com/query/latest)
- [Zod Docs](https://zod.dev)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)

## Troubleshooting

### Port 15000 Already in Use

```bash
lsof -i :15000
kill -9 <PID>
```

### Module Not Found

Check imports use correct paths:
- `$lib` → `src/lib`
- `$routes` → `src/routes`

### Type Errors

Run `npm run typecheck` to see full errors.

## Support

For questions or issues, see docs/api-contract.md and README.md
