# Multi-URL Content Addition Implementation Plan

> **Version**: 1.0.0
> **Date**: 2026-02-04
> **Status**: Draft
> **Author**: Research Agent

---

## Executive Summary

This document outlines the implementation plan for adding the ability to extract multiple links from a webpage and add them as separate URL content items to a research session. This feature enables users to efficiently add related content from link-heavy pages (documentation indexes, resource lists, blog archives) without manually copying each URL.

### User Story

As a researcher, I want to provide a webpage URL containing many links and select which ones to add to my session, so that I can efficiently gather related content from index pages, documentation sites, or curated resource lists.

### High-Level Flow

```
1. User provides "parent" URL (e.g., documentation index page)
          ↓
2. Backend fetches page, extracts all links
          ↓
3. Backend returns categorized links to UI
          ↓
4. UI displays links with checkboxes for selection
          ↓
5. User selects desired links
          ↓
6. UI calls batch endpoint to add selected URLs
          ↓
7. Backend processes each URL using existing UrlRetriever
```

### Scope

**In Scope:**

- New endpoint for link extraction from a URL
- New batch content addition endpoint
- UI workflow for link selection
- Link categorization by source location (nav, main, footer)
- Relative to absolute URL conversion

**Out of Scope:**

- Recursive crawling (following links on extracted pages)
- Rate limiting (handled at infrastructure level)
- Authentication for protected pages
- JavaScript-rendered link extraction (Phase 2 consideration)

---

## Architecture Overview

### System Context

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           research-mind-ui                              │
│                                                                         │
│  ┌─────────────────────┐    ┌─────────────────────────────────────────┐│
│  │  AddContentForm     │    │          MultiUrlSelector               ││
│  │  (existing)         │    │  ┌─────────────────────────────────┐    ││
│  │                     │    │  │ Step 1: URL Input               │    ││
│  │  - Text             │    │  │ [Enter URL] [Extract Links]     │    ││
│  │  - URL (single)     │    │  └─────────────────────────────────┘    ││
│  │  - Git Repo         │    │  ┌─────────────────────────────────┐    ││
│  │                     │    │  │ Step 2: Loading State           │    ││
│  │  [NEW: Multi-URL]   │────│  │ Extracting links...             │    ││
│  │                     │    │  └─────────────────────────────────┘    ││
│  └─────────────────────┘    │  ┌─────────────────────────────────┐    ││
│                             │  │ Step 3: Link Selection          │    ││
│                             │  │ □ Select All  □ Filter by domain│    ││
│                             │  │ ─────────────────────────────── │    ││
│                             │  │ Main Content (12 links)         │    ││
│                             │  │ ☑ Link 1                        │    ││
│                             │  │ ☐ Link 2                        │    ││
│                             │  │ Navigation (5 links)            │    ││
│                             │  │ ☐ Link 3                        │    ││
│                             │  └─────────────────────────────────┘    ││
│                             │  ┌─────────────────────────────────┐    ││
│                             │  │ Step 4: Confirm                 │    ││
│                             │  │ [Cancel] [Add 5 URLs]           │    ││
│                             │  └─────────────────────────────────┘    ││
│                             └─────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTP
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        research-mind-service                            │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     routes/content.py                             │  │
│  │                                                                   │  │
│  │  POST /api/v1/content/extract-links                              │  │
│  │    → LinkExtractor.extract()                                     │  │
│  │    ← ExtractedLinksResponse                                      │  │
│  │                                                                   │  │
│  │  POST /api/v1/sessions/{session_id}/content/batch                │  │
│  │    → For each URL: content_service.add_content()                 │  │
│  │    ← BatchContentResponse                                        │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                    │                                    │
│                                    ▼                                    │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                  services/link_extractor.py (NEW)                 │  │
│  │                                                                   │  │
│  │  LinkExtractor                                                    │  │
│  │    ├─ fetch_page(url) → HTML                                     │  │
│  │    ├─ extract_links(html, base_url) → List[ExtractedLink]       │  │
│  │    ├─ categorize_links(links) → CategorizedLinks                │  │
│  │    └─ resolve_relative_urls(links, base_url)                    │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                    │                                    │
│  Uses existing:                    │                                    │
│  ┌─────────────────────┐  ┌──────────────────────────────────────────┐│
│  │ ExtractionPipeline  │  │        content_service.add_content()    ││
│  │ (for page fetch)    │  │        (processes each URL)             ││
│  └─────────────────────┘  └──────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component                       | Responsibility                                         |
| ------------------------------- | ------------------------------------------------------ |
| `LinkExtractor` (new)           | Fetch page HTML, parse links, categorize, resolve URLs |
| `routes/content.py`             | New endpoints for extract-links and batch add          |
| `content_service.py`            | Existing add_content used for batch processing         |
| `MultiUrlSelector.svelte` (new) | Multi-step UI for link extraction and selection        |
| `AddContentForm.svelte`         | Add new "Multi-URL" content type option                |

---

## API Contract Additions

### New Endpoint: Extract Links

#### `POST /api/v1/content/extract-links`

Extract all links from a given URL for user selection.

**Request Body**

```json
{
  "url": "https://docs.example.com/guides/",
  "include_external": true
}
```

| Field              | Type    | Required | Default | Description                       |
| ------------------ | ------- | -------- | ------- | --------------------------------- |
| `url`              | string  | yes      | -       | URL to extract links from         |
| `include_external` | boolean | no       | true    | Include links to external domains |

**Response** `200 OK`

```json
{
  "source_url": "https://docs.example.com/guides/",
  "source_title": "Documentation Guides",
  "extracted_at": "2026-02-04T10:30:00Z",
  "link_count": 42,
  "categories": {
    "main_content": [
      {
        "url": "https://docs.example.com/guides/getting-started",
        "text": "Getting Started Guide",
        "is_external": false,
        "source_element": "main"
      },
      {
        "url": "https://docs.example.com/guides/authentication",
        "text": "Authentication",
        "is_external": false,
        "source_element": "main"
      }
    ],
    "navigation": [
      {
        "url": "https://docs.example.com/",
        "text": "Home",
        "is_external": false,
        "source_element": "nav"
      }
    ],
    "sidebar": [],
    "footer": [],
    "other": []
  }
}
```

**Response Schema**

```typescript
interface ExtractedLink {
  url: string; // Absolute URL
  text: string; // Link text content
  is_external: boolean; // True if different domain
  source_element: string; // nav, main, aside, footer, header, other
}

interface ExtractedLinksResponse {
  source_url: string; // Original URL
  source_title: string; // Page title
  extracted_at: string; // ISO 8601 timestamp
  link_count: number; // Total links found
  categories: {
    main_content: ExtractedLink[]; // Links in <main>, <article>, content divs
    navigation: ExtractedLink[]; // Links in <nav>
    sidebar: ExtractedLink[]; // Links in <aside>
    footer: ExtractedLink[]; // Links in <footer>
    other: ExtractedLink[]; // Links not categorized elsewhere
  };
}
```

**Error Responses**

| Status | Code                | Description                   |
| ------ | ------------------- | ----------------------------- |
| 400    | `INVALID_URL`       | URL is malformed or empty     |
| 400    | `EXTRACTION_FAILED` | Failed to fetch or parse page |
| 408    | `TIMEOUT`           | Page fetch timed out          |
| 429    | `RATE_LIMITED`      | Too many requests             |

**curl Example**

```bash
curl -X POST http://localhost:15010/api/v1/content/extract-links \
  -H "Content-Type: application/json" \
  -d '{"url": "https://docs.example.com/guides/", "include_external": false}'
```

---

### New Endpoint: Batch Add Content

#### `POST /api/v1/sessions/{session_id}/content/batch`

Add multiple URL content items to a session in a single request.

**Path Parameters**

| Parameter    | Type   | Description  |
| ------------ | ------ | ------------ |
| `session_id` | string | Session UUID |

**Request Body**

```json
{
  "urls": [
    {
      "url": "https://docs.example.com/guides/getting-started",
      "title": "Getting Started Guide"
    },
    {
      "url": "https://docs.example.com/guides/authentication",
      "title": "Authentication"
    }
  ],
  "source_url": "https://docs.example.com/guides/"
}
```

| Field          | Type   | Required | Description                      |
| -------------- | ------ | -------- | -------------------------------- |
| `urls`         | array  | yes      | Array of URL objects to add      |
| `urls[].url`   | string | yes      | URL to fetch and add             |
| `urls[].title` | string | no       | Optional title override          |
| `source_url`   | string | no       | Parent URL for metadata tracking |

**Response** `201 Created`

```json
{
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "source_url": "https://docs.example.com/guides/",
  "total_requested": 5,
  "successful": 4,
  "failed": 1,
  "items": [
    {
      "content_id": "b1c2d3e4-f5g6-7890-hijk-lm1234567890",
      "url": "https://docs.example.com/guides/getting-started",
      "status": "ready",
      "title": "Getting Started Guide"
    },
    {
      "content_id": "c2d3e4f5-g6h7-8901-ijkl-mn2345678901",
      "url": "https://docs.example.com/guides/authentication",
      "status": "ready",
      "title": "Authentication"
    },
    {
      "content_id": null,
      "url": "https://docs.example.com/guides/private",
      "status": "error",
      "title": null,
      "error": "HTTP 403: Forbidden"
    }
  ]
}
```

**Response Schema**

```typescript
interface BatchContentItem {
  content_id: string | null; // UUID if successful, null if failed
  url: string; // Requested URL
  status: "ready" | "processing" | "error";
  title: string | null; // Resolved title
  error?: string; // Error message if failed
}

interface BatchContentResponse {
  session_id: string;
  source_url: string | null; // Parent URL if provided
  total_requested: number;
  successful: number;
  failed: number;
  items: BatchContentItem[];
}
```

**Error Responses**

| Status | Code                | Description                     |
| ------ | ------------------- | ------------------------------- |
| 400    | `EMPTY_URL_LIST`    | urls array is empty             |
| 400    | `TOO_MANY_URLS`     | Exceeds maximum batch size (50) |
| 404    | `SESSION_NOT_FOUND` | Session does not exist          |

**curl Example**

```bash
curl -X POST http://localhost:15010/api/v1/sessions/{session_id}/content/batch \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      {"url": "https://example.com/page1", "title": "Page 1"},
      {"url": "https://example.com/page2"}
    ],
    "source_url": "https://example.com/"
  }'
```

---

## Backend Implementation

### Phase 1: Link Extraction Service

**New Files:**

- `app/services/link_extractor.py`
- `app/schemas/links.py`

**Modified Files:**

- `app/routes/content.py` (add extract-links endpoint)

#### Link Extractor Design

```python
# app/services/link_extractor.py

from dataclasses import dataclass
from urllib.parse import urljoin, urlparse
from bs4 import BeautifulSoup
import httpx

@dataclass
class ExtractedLink:
    url: str
    text: str
    is_external: bool
    source_element: str  # nav, main, aside, footer, header, other

@dataclass
class CategorizedLinks:
    main_content: list[ExtractedLink]
    navigation: list[ExtractedLink]
    sidebar: list[ExtractedLink]
    footer: list[ExtractedLink]
    other: list[ExtractedLink]

class LinkExtractor:
    """Extract and categorize links from HTML pages."""

    def __init__(self, timeout: int = 30):
        self.timeout = timeout

    async def extract(
        self,
        url: str,
        include_external: bool = True
    ) -> CategorizedLinks:
        """Fetch page and extract categorized links."""
        html = await self._fetch_page(url)
        links = self._parse_links(html, url)

        if not include_external:
            base_domain = urlparse(url).netloc
            links = [l for l in links if not l.is_external]

        return self._categorize_links(links)

    async def _fetch_page(self, url: str) -> str:
        """Fetch HTML content from URL."""
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(url, follow_redirects=True)
            response.raise_for_status()
            return response.text

    def _parse_links(self, html: str, base_url: str) -> list[ExtractedLink]:
        """Parse all anchor tags from HTML."""
        soup = BeautifulSoup(html, 'lxml')
        base_domain = urlparse(base_url).netloc
        links = []

        for anchor in soup.find_all('a', href=True):
            href = anchor['href']

            # Skip non-http links
            if href.startswith(('#', 'javascript:', 'mailto:', 'tel:')):
                continue

            # Resolve relative URLs
            absolute_url = urljoin(base_url, href)

            # Determine if external
            link_domain = urlparse(absolute_url).netloc
            is_external = link_domain != base_domain

            # Get link text
            text = anchor.get_text(strip=True) or absolute_url

            # Determine source element
            source_element = self._get_source_element(anchor)

            links.append(ExtractedLink(
                url=absolute_url,
                text=text[:255],  # Truncate long text
                is_external=is_external,
                source_element=source_element
            ))

        # Deduplicate by URL, keeping first occurrence
        seen = set()
        unique_links = []
        for link in links:
            if link.url not in seen:
                seen.add(link.url)
                unique_links.append(link)

        return unique_links

    def _get_source_element(self, anchor) -> str:
        """Determine which semantic element contains the anchor."""
        for parent in anchor.parents:
            tag = parent.name
            if tag == 'nav':
                return 'nav'
            elif tag == 'main':
                return 'main'
            elif tag == 'article':
                return 'main'
            elif tag == 'aside':
                return 'aside'
            elif tag == 'footer':
                return 'footer'
            elif tag == 'header':
                return 'header'
            elif tag == 'body':
                break
        return 'other'

    def _categorize_links(self, links: list[ExtractedLink]) -> CategorizedLinks:
        """Group links by source element."""
        categories = CategorizedLinks(
            main_content=[],
            navigation=[],
            sidebar=[],
            footer=[],
            other=[]
        )

        for link in links:
            if link.source_element in ('main', 'article'):
                categories.main_content.append(link)
            elif link.source_element == 'nav':
                categories.navigation.append(link)
            elif link.source_element == 'aside':
                categories.sidebar.append(link)
            elif link.source_element == 'footer':
                categories.footer.append(link)
            else:
                categories.other.append(link)

        return categories
```

#### Schemas

```python
# app/schemas/links.py

from pydantic import BaseModel, Field, HttpUrl
from datetime import datetime

class ExtractLinksRequest(BaseModel):
    url: HttpUrl = Field(..., description="URL to extract links from")
    include_external: bool = Field(True, description="Include external domain links")

class ExtractedLinkSchema(BaseModel):
    url: str
    text: str
    is_external: bool
    source_element: str

class ExtractedLinksResponse(BaseModel):
    source_url: str
    source_title: str
    extracted_at: datetime
    link_count: int
    categories: dict[str, list[ExtractedLinkSchema]]

class BatchUrlItem(BaseModel):
    url: HttpUrl
    title: str | None = None

class BatchAddContentRequest(BaseModel):
    urls: list[BatchUrlItem] = Field(..., min_length=1, max_length=50)
    source_url: str | None = None

class BatchContentItemResponse(BaseModel):
    content_id: str | None
    url: str
    status: str
    title: str | None
    error: str | None = None

class BatchContentResponse(BaseModel):
    session_id: str
    source_url: str | None
    total_requested: int
    successful: int
    failed: int
    items: list[BatchContentItemResponse]
```

### Phase 2: API Endpoints

**Modified File:** `app/routes/content.py`

```python
# Add to app/routes/content.py

from app.services.link_extractor import LinkExtractor
from app.schemas.links import (
    ExtractLinksRequest,
    ExtractedLinksResponse,
    BatchAddContentRequest,
    BatchContentResponse,
)

# Create separate router for non-session endpoints
content_utils_router = APIRouter(prefix="/api/v1/content", tags=["content"])

@content_utils_router.post("/extract-links", response_model=ExtractedLinksResponse)
async def extract_links(request: ExtractLinksRequest) -> ExtractedLinksResponse:
    """Extract links from a URL for user selection."""
    extractor = LinkExtractor()

    try:
        categories = await extractor.extract(
            str(request.url),
            include_external=request.include_external
        )
    except httpx.HTTPError as e:
        raise HTTPException(
            status_code=400,
            detail={"error": {"code": "EXTRACTION_FAILED", "message": str(e)}}
        )

    # Get page title
    # ... implementation

    return ExtractedLinksResponse(...)


@router.post("/batch", response_model=BatchContentResponse, status_code=201)
def batch_add_content(
    session_id: str,
    request: BatchAddContentRequest,
    db: Session = Depends(get_db),
) -> BatchContentResponse:
    """Add multiple URL content items to a session."""

    # Validate session exists
    _get_session_or_raise(db, session_id)

    results = []
    successful = 0
    failed = 0

    for url_item in request.urls:
        try:
            content_request = AddContentRequest(
                content_type="url",
                title=url_item.title,
                source=str(url_item.url),
                metadata={"batch_source": request.source_url} if request.source_url else None
            )

            item = content_service.add_content(db, session_id, content_request)

            results.append(BatchContentItemResponse(
                content_id=item.content_id,
                url=str(url_item.url),
                status=item.status,
                title=item.title
            ))
            successful += 1

        except Exception as e:
            results.append(BatchContentItemResponse(
                content_id=None,
                url=str(url_item.url),
                status="error",
                title=None,
                error=str(e)
            ))
            failed += 1

    return BatchContentResponse(
        session_id=session_id,
        source_url=request.source_url,
        total_requested=len(request.urls),
        successful=successful,
        failed=failed,
        items=results
    )
```

### Dependencies Update

Add BeautifulSoup to `pyproject.toml`:

```toml
dependencies = [
    # ... existing dependencies
    "beautifulsoup4>=4.12.0",
    "lxml>=5.0.0",  # For faster parsing
]
```

---

## Frontend Implementation

### Phase 3: UI Components

**New Files:**

- `src/lib/components/sessions/MultiUrlSelector.svelte`
- `src/lib/api/hooks-links.ts` (or add to existing hooks.ts)

**Modified Files:**

- `src/lib/components/sessions/AddContentForm.svelte`
- `src/lib/api/client.ts`

#### MultiUrlSelector Component

```svelte
<!-- src/lib/components/sessions/MultiUrlSelector.svelte -->
<script lang="ts">
  import { Link, Loader, Check, ChevronDown, ChevronRight, X } from 'lucide-svelte';
  import { useExtractLinksMutation, useBatchAddContentMutation } from '$lib/api/hooks';
  import { toastStore } from '$lib/stores/toast';

  interface Props {
    sessionId: string;
    onSuccess?: () => void;
    onCancel?: () => void;
  }

  let { sessionId, onSuccess, onCancel }: Props = $props();

  // Step state
  type Step = 'input' | 'loading' | 'select' | 'adding';
  let currentStep = $state<Step>('input');

  // Form state
  let sourceUrl = $state('');
  let includeExternal = $state(true);
  let extractedLinks = $state<ExtractedLinksResponse | null>(null);
  let selectedUrls = $state<Set<string>>(new Set());

  // Category expansion state
  let expandedCategories = $state<Set<string>>(new Set(['main_content']));

  // Mutations
  const extractMutation = useExtractLinksMutation();
  const batchMutation = useBatchAddContentMutation();

  // Computed
  const totalLinks = $derived(extractedLinks?.link_count ?? 0);
  const selectedCount = $derived(selectedUrls.size);

  async function handleExtract() {
    if (!sourceUrl.trim()) return;

    currentStep = 'loading';

    try {
      const result = await $extractMutation.mutateAsync({
        url: sourceUrl.trim(),
        include_external: includeExternal
      });

      extractedLinks = result;
      currentStep = 'select';
    } catch {
      toastStore.error('Failed to extract links');
      currentStep = 'input';
    }
  }

  async function handleAdd() {
    if (selectedUrls.size === 0) return;

    currentStep = 'adding';

    const urlsToAdd = Array.from(selectedUrls).map(url => {
      // Find the link to get its text as title
      for (const category of Object.values(extractedLinks?.categories ?? {})) {
        const link = category.find(l => l.url === url);
        if (link) return { url, title: link.text };
      }
      return { url };
    });

    try {
      const result = await $batchMutation.mutateAsync({
        sessionId,
        urls: urlsToAdd,
        source_url: sourceUrl
      });

      toastStore.success(`Added ${result.successful} of ${result.total_requested} URLs`);
      onSuccess?.();
    } catch {
      toastStore.error('Failed to add content');
      currentStep = 'select';
    }
  }

  function toggleCategory(category: string) {
    if (expandedCategories.has(category)) {
      expandedCategories.delete(category);
    } else {
      expandedCategories.add(category);
    }
    expandedCategories = new Set(expandedCategories);
  }

  function toggleUrl(url: string) {
    if (selectedUrls.has(url)) {
      selectedUrls.delete(url);
    } else {
      selectedUrls.add(url);
    }
    selectedUrls = new Set(selectedUrls);
  }

  function selectAll() {
    for (const category of Object.values(extractedLinks?.categories ?? {})) {
      for (const link of category) {
        selectedUrls.add(link.url);
      }
    }
    selectedUrls = new Set(selectedUrls);
  }

  function deselectAll() {
    selectedUrls.clear();
    selectedUrls = new Set(selectedUrls);
  }
</script>

<div class="multi-url-selector">
  {#if currentStep === 'input'}
    <div class="step-input">
      <h3>Extract Links from Page</h3>
      <p class="description">
        Enter a URL to extract all links from that page. You'll be able to
        select which ones to add to your session.
      </p>

      <div class="form-group">
        <label for="source-url">Page URL</label>
        <input
          id="source-url"
          type="url"
          bind:value={sourceUrl}
          placeholder="https://docs.example.com/guides/"
        />
      </div>

      <label class="checkbox-label">
        <input type="checkbox" bind:checked={includeExternal} />
        Include links to external sites
      </label>

      <div class="actions">
        {#if onCancel}
          <button type="button" class="cancel-btn" onclick={onCancel}>Cancel</button>
        {/if}
        <button
          type="button"
          class="primary-btn"
          onclick={handleExtract}
          disabled={!sourceUrl.trim()}
        >
          Extract Links
        </button>
      </div>
    </div>

  {:else if currentStep === 'loading'}
    <div class="step-loading">
      <Loader size={32} class="spinner" />
      <p>Extracting links from page...</p>
    </div>

  {:else if currentStep === 'select'}
    <div class="step-select">
      <div class="header">
        <h3>Select Links to Add</h3>
        <p class="source-info">
          From: <a href={sourceUrl} target="_blank">{extractedLinks?.source_title}</a>
        </p>
      </div>

      <div class="selection-controls">
        <button onclick={selectAll}>Select All ({totalLinks})</button>
        <button onclick={deselectAll}>Deselect All</button>
        <span class="selection-count">{selectedCount} selected</span>
      </div>

      <div class="categories">
        {#each Object.entries(extractedLinks?.categories ?? {}) as [category, links]}
          {#if links.length > 0}
            <div class="category">
              <button
                class="category-header"
                onclick={() => toggleCategory(category)}
              >
                {#if expandedCategories.has(category)}
                  <ChevronDown size={16} />
                {:else}
                  <ChevronRight size={16} />
                {/if}
                <span class="category-name">
                  {category.replace('_', ' ')}
                </span>
                <span class="category-count">({links.length})</span>
              </button>

              {#if expandedCategories.has(category)}
                <div class="links-list">
                  {#each links as link}
                    <label class="link-item">
                      <input
                        type="checkbox"
                        checked={selectedUrls.has(link.url)}
                        onchange={() => toggleUrl(link.url)}
                      />
                      <span class="link-text">{link.text}</span>
                      {#if link.is_external}
                        <span class="external-badge">external</span>
                      {/if}
                    </label>
                  {/each}
                </div>
              {/if}
            </div>
          {/if}
        {/each}
      </div>

      <div class="actions">
        <button type="button" class="cancel-btn" onclick={onCancel}>Cancel</button>
        <button
          type="button"
          class="primary-btn"
          onclick={handleAdd}
          disabled={selectedCount === 0}
        >
          Add {selectedCount} URL{selectedCount !== 1 ? 's' : ''}
        </button>
      </div>
    </div>

  {:else if currentStep === 'adding'}
    <div class="step-loading">
      <Loader size={32} class="spinner" />
      <p>Adding {selectedCount} URLs to session...</p>
    </div>
  {/if}
</div>

<style>
  /* Component styles */
  .multi-url-selector {
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
    border-radius: var(--border-radius-lg);
    padding: var(--space-5);
  }

  /* ... additional styles ... */
</style>
```

### Phase 4: API Client Updates

```typescript
// Add to src/lib/api/client.ts

export interface ExtractLinksRequest {
  url: string;
  include_external?: boolean;
}

export interface ExtractedLink {
  url: string;
  text: string;
  is_external: boolean;
  source_element: string;
}

export interface ExtractedLinksResponse {
  source_url: string;
  source_title: string;
  extracted_at: string;
  link_count: number;
  categories: {
    main_content: ExtractedLink[];
    navigation: ExtractedLink[];
    sidebar: ExtractedLink[];
    footer: ExtractedLink[];
    other: ExtractedLink[];
  };
}

export interface BatchUrlItem {
  url: string;
  title?: string;
}

export interface BatchAddContentRequest {
  urls: BatchUrlItem[];
  source_url?: string;
}

export interface BatchContentResponse {
  session_id: string;
  source_url: string | null;
  total_requested: number;
  successful: number;
  failed: number;
  items: Array<{
    content_id: string | null;
    url: string;
    status: string;
    title: string | null;
    error?: string;
  }>;
}

export const apiClient = {
  // ... existing methods

  async extractLinks(
    request: ExtractLinksRequest,
  ): Promise<ExtractedLinksResponse> {
    const response = await fetch(`${apiBaseUrl}/api/v1/content/extract-links`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(request),
    });
    if (!response.ok) {
      const error = await response.json();
      throw new Error(
        error.detail?.error?.message || "Failed to extract links",
      );
    }
    return response.json();
  },

  async batchAddContent(
    sessionId: string,
    request: BatchAddContentRequest,
  ): Promise<BatchContentResponse> {
    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/content/batch`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(request),
      },
    );
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail?.error?.message || "Failed to add content");
    }
    return response.json();
  },
};
```

---

## Testing Strategy

### Backend Tests

**New Test File:** `tests/test_link_extractor.py`

```python
import pytest
from app.services.link_extractor import LinkExtractor

class TestLinkExtractor:
    def test_parse_links_extracts_all_anchors(self):
        html = """
        <html>
        <body>
            <nav><a href="/home">Home</a></nav>
            <main><a href="/article">Article</a></main>
        </body>
        </html>
        """
        extractor = LinkExtractor()
        links = extractor._parse_links(html, "https://example.com")

        assert len(links) == 2
        assert links[0].source_element == "nav"
        assert links[1].source_element == "main"

    def test_resolve_relative_urls(self):
        html = '<a href="/path/to/page">Link</a>'
        extractor = LinkExtractor()
        links = extractor._parse_links(html, "https://example.com/base/")

        assert links[0].url == "https://example.com/path/to/page"

    def test_detect_external_links(self):
        html = '<a href="https://other.com/page">External</a>'
        extractor = LinkExtractor()
        links = extractor._parse_links(html, "https://example.com")

        assert links[0].is_external is True

    def test_skip_non_http_links(self):
        html = """
        <a href="#anchor">Anchor</a>
        <a href="javascript:void(0)">JS</a>
        <a href="mailto:test@example.com">Email</a>
        <a href="https://example.com">Valid</a>
        """
        extractor = LinkExtractor()
        links = extractor._parse_links(html, "https://example.com")

        assert len(links) == 1
        assert links[0].url == "https://example.com"

    def test_deduplicate_links(self):
        html = """
        <a href="/page">Link 1</a>
        <a href="/page">Link 2</a>
        """
        extractor = LinkExtractor()
        links = extractor._parse_links(html, "https://example.com")

        assert len(links) == 1
```

**New Test File:** `tests/test_content_batch.py`

```python
import pytest
from fastapi.testclient import TestClient

def test_batch_add_content_success(client, db_session, test_session):
    response = client.post(
        f"/api/v1/sessions/{test_session.session_id}/content/batch",
        json={
            "urls": [
                {"url": "https://example.com/page1", "title": "Page 1"},
                {"url": "https://example.com/page2"}
            ],
            "source_url": "https://example.com/"
        }
    )

    assert response.status_code == 201
    data = response.json()
    assert data["total_requested"] == 2
    assert data["session_id"] == test_session.session_id

def test_batch_add_empty_list(client, test_session):
    response = client.post(
        f"/api/v1/sessions/{test_session.session_id}/content/batch",
        json={"urls": []}
    )

    assert response.status_code == 422  # Validation error

def test_batch_add_exceeds_limit(client, test_session):
    urls = [{"url": f"https://example.com/page{i}"} for i in range(51)]
    response = client.post(
        f"/api/v1/sessions/{test_session.session_id}/content/batch",
        json={"urls": urls}
    )

    assert response.status_code == 422  # Exceeds max_length=50
```

### Frontend Tests

**New Test File:** `tests/multi-url.test.ts`

```typescript
import { describe, it, expect, vi } from "vitest";
import { apiClient } from "../src/lib/api/client";

describe("Multi-URL API", () => {
  it("should extract links from URL", async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            source_url: "https://example.com/",
            source_title: "Example",
            link_count: 5,
            categories: {
              main_content: [
                {
                  url: "https://example.com/page1",
                  text: "Page 1",
                  is_external: false,
                },
              ],
              navigation: [],
              sidebar: [],
              footer: [],
              other: [],
            },
          }),
      } as Response),
    );

    const result = await apiClient.extractLinks({
      url: "https://example.com/",
      include_external: true,
    });

    expect(result.link_count).toBe(5);
    expect(result.categories.main_content).toHaveLength(1);
  });

  it("should batch add content", async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            session_id: "test-session",
            total_requested: 2,
            successful: 2,
            failed: 0,
            items: [],
          }),
      } as Response),
    );

    const result = await apiClient.batchAddContent("test-session", {
      urls: [
        { url: "https://example.com/page1" },
        { url: "https://example.com/page2" },
      ],
    });

    expect(result.successful).toBe(2);
  });
});
```

---

## Open Questions and Decisions

### Design Decisions Required

| Question                           | Options                                   | Recommendation                              |
| ---------------------------------- | ----------------------------------------- | ------------------------------------------- |
| **Batch size limit**               | 20, 50, 100                               | **50** - Balance between usability and load |
| **Async vs sync batch processing** | Process sequentially, parallel with limit | **Sequential** initially, async queue later |
| **Link categorization accuracy**   | Basic semantic elements only, ML-based    | **Basic semantic** - sufficient for MVP     |
| **External link handling**         | Always show, always hide, user choice     | **User choice** with default include        |
| **Duplicate URL detection**        | Per-session, per-batch only               | **Per-batch** only for MVP                  |

### Technical Decisions

| Question              | Options                                            | Recommendation                                           |
| --------------------- | -------------------------------------------------- | -------------------------------------------------------- |
| **HTML parser**       | BeautifulSoup + lxml, trafilatura only, selectolax | **BeautifulSoup + lxml** - battle-tested, feature-rich   |
| **URL validation**    | Pydantic HttpUrl, custom regex, httpx probe        | **Pydantic HttpUrl** - consistent with existing patterns |
| **Progress feedback** | Polling, SSE, WebSocket                            | **None for MVP** - batch completes in <30s typically     |

### UX Questions

| Question                     | Options                                  | Recommendation                                |
| ---------------------------- | ---------------------------------------- | --------------------------------------------- |
| **Empty state handling**     | Error, warning, auto-close               | **Warning** with helpful message              |
| **Partial failure handling** | Retry failed, ignore, require all        | **Show results** with retry option for failed |
| **Category default state**   | All expanded, main_content expanded only | **main_content expanded** - most relevant     |

---

## Effort Estimates

### Phase Breakdown

| Phase       | Description            | Effort    | Dependencies |
| ----------- | ---------------------- | --------- | ------------ |
| **Phase 1** | Link Extractor Service | 4-6 hours | None         |
| **Phase 2** | API Endpoints          | 3-4 hours | Phase 1      |
| **Phase 3** | UI Components          | 6-8 hours | Phase 2      |
| **Phase 4** | API Client & Hooks     | 2-3 hours | Phase 2      |
| **Phase 5** | Integration Testing    | 3-4 hours | All          |
| **Phase 6** | Contract Sync & Types  | 1-2 hours | All          |

### Total Estimate

- **Minimum**: 19 hours (2.5 dev days)
- **Expected**: 24 hours (3 dev days)
- **Maximum**: 32 hours (4 dev days)

### Suggested Implementation Order

1. **Day 1**:

   - Phase 1 (Link Extractor)
   - Phase 2 (API Endpoints)
   - Update API contract

2. **Day 2**:

   - Phase 4 (Client & Hooks)
   - Phase 3 (UI Components - basic)
   - Contract sync & type generation

3. **Day 3**:
   - Phase 3 (UI polish)
   - Phase 5 (Testing)
   - Documentation updates

---

## Contract Change Checklist

When implementing this feature:

- [ ] Updated `research-mind-service/docs/api-contract.md` (add new endpoints)
- [ ] Version bumped to 1.6.0
- [ ] Changelog entry added
- [ ] Backend schemas created (`app/schemas/links.py`)
- [ ] Backend endpoints implemented
- [ ] Backend tests pass (`make test`)
- [ ] Contract copied to `research-mind-ui/docs/api-contract.md`
- [ ] Frontend types regenerated (`npm run gen:api`)
- [ ] Frontend components created
- [ ] Frontend tests pass (`npm run test`)
- [ ] Both `api-contract.md` files are identical

---

## Appendix

### A. Link Categorization Rules

| Source Element | Category     | Notes                     |
| -------------- | ------------ | ------------------------- |
| `<nav>`        | navigation   | Primary navigation links  |
| `<main>`       | main_content | Primary page content      |
| `<article>`    | main_content | Article content           |
| `<aside>`      | sidebar      | Sidebars, related content |
| `<footer>`     | footer       | Footer links              |
| `<header>`     | other        | Header (non-nav) links    |
| Other          | other        | Uncategorized             |

### B. URL Filtering Rules

| Pattern                  | Action                     |
| ------------------------ | -------------------------- |
| `#anchor`                | Skip (fragment only)       |
| `javascript:*`           | Skip                       |
| `mailto:*`               | Skip                       |
| `tel:*`                  | Skip                       |
| `data:*`                 | Skip                       |
| Relative paths           | Resolve to absolute        |
| Protocol-relative (`//`) | Resolve with base protocol |

### C. References

- [BeautifulSoup Documentation](https://beautiful-soup-4.readthedocs.io/en/latest/)
- [Trafilatura Documentation](https://trafilatura.readthedocs.io/en/latest/)
- [httpx Documentation](https://www.python-httpx.org/)
- [TanStack Query Svelte](https://tanstack.com/query/latest/docs/framework/svelte/overview)
- [Existing API Contract](/Users/mac/workspace/research-mind/research-mind-service/docs/api-contract.md)
- [AddContentForm.svelte](/Users/mac/workspace/research-mind/research-mind-ui/src/lib/components/sessions/AddContentForm.svelte)

---

_This document is a living specification. Update as implementation progresses._
