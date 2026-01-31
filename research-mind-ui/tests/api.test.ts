import { describe, it, expect, vi } from 'vitest';
import { apiClient } from '../src/lib/api/client';

describe('API Client', () => {
  it('should have getVersion method', () => {
    expect(apiClient.getVersion).toBeDefined();
    expect(typeof apiClient.getVersion).toBe('function');
  });

  it('should return version response schema', async () => {
    // Mock fetch for testing
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ version: '1.0.0', environment: 'test' }),
      } as Response)
    );

    const result = await apiClient.getVersion();
    expect(result).toHaveProperty('version');
    expect(typeof result.version).toBe('string');
  });

  it('should handle fetch errors', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: false,
        statusText: 'Not Found',
      } as Response)
    );

    await expect(apiClient.getVersion()).rejects.toThrow('Failed to fetch version');
  });
});
