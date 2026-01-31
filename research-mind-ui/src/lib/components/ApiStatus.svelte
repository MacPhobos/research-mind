<script lang="ts">
  interface ApiStatusProps {
    query: {
      isPending: boolean;
      isError: boolean;
      data?: any;
      error?: Error | null;
    };
  }

  let { query }: ApiStatusProps = $props();
</script>

<div class="status">
  {#if query.isPending}
    <div class="loading">
      <span class="spinner"></span>
      Loading API status...
    </div>
  {:else if query.isError}
    <div class="error">
      <span class="icon">⚠️</span>
      Error: {query.error?.message || 'Unknown error'}
    </div>
  {:else if query.data}
    <div class="success">
      <span class="icon">✓</span>
      <div>
        <p><strong>API Status: Connected</strong></p>
        <pre>{JSON.stringify(query.data, null, 2)}</pre>
      </div>
    </div>
  {:else}
    <div class="idle">No data</div>
  {/if}
</div>

<style>
  .status {
    padding: 1rem;
    border-radius: 4px;
  }

  .loading {
    display: flex;
    align-items: center;
    color: #0066cc;
  }

  .spinner {
    display: inline-block;
    width: 20px;
    height: 20px;
    border: 3px solid #ddd;
    border-top-color: #0066cc;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
    margin-right: 10px;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  .success {
    background: #f0f8f0;
    border-left: 4px solid #00aa00;
    display: flex;
    gap: 1rem;
  }

  .error {
    background: #fff5f5;
    border-left: 4px solid #cc0000;
    color: #cc0000;
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .idle {
    color: #999;
  }

  .icon {
    font-size: 1.5rem;
  }

  pre {
    background: #f5f5f5;
    padding: 1rem;
    border-radius: 4px;
    overflow-x: auto;
    font-size: 0.85rem;
    margin: 0.5rem 0 0 0;
  }

  p {
    margin: 0;
  }
</style>
