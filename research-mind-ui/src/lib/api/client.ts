import { z } from 'zod';

const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || 'http://localhost:15010';

// Request/Response Types
const VersionResponseSchema = z.object({
  version: z.string(),
  environment: z.string().optional(),
  timestamp: z.string().optional(),
});

export type VersionResponse = z.infer<typeof VersionResponseSchema>;

// API Client
export const apiClient = {
  async getVersion(): Promise<VersionResponse> {
    const response = await fetch(`${apiBaseUrl}/api/v1/version`);
    if (!response.ok) {
      throw new Error(`Failed to fetch version: ${response.statusText}`);
    }
    const data = await response.json();
    return VersionResponseSchema.parse(data);
  },
};
