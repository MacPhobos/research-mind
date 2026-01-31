import { createQuery } from '@tanstack/svelte-query';
import { apiClient, type VersionResponse } from './client';

export function useVersionQuery() {
  return createQuery<VersionResponse>({
    queryKey: ['version'],
    queryFn: () => apiClient.getVersion(),
    staleTime: 60000, // 1 minute
    gcTime: 300000, // 5 minutes (formerly cacheTime)
  });
}
