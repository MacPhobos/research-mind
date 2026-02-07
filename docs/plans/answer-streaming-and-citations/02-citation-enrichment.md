# Plan 02: Citation Enrichment via DB Lookup

**Tier**: 2 (Do Next)
**Scope**: research-mind-service (backend enrichment + API contract) + research-mind-ui (display enriched fields)
**Goal**: Enrich `SourceCitation` objects with source URLs, content titles, and content types by cross-referencing `content_id` with the `content_items` database table, so citations display meaningful information instead of just file paths.
**Depends On**: Plan 01 (Citation Consolidation) -- must have a single citation mechanism before enriching it
**Effort**: 2-3 days

---

## Rationale

After Plan 01 consolidates to a single structured citation approach, the `SourceCitation` objects contain:
- `file_path`: e.g., `079044a5/content.md` (raw path from Claude's answer)
- `content_id`: e.g., `079044a5` (8-hex prefix or full UUID)
- `title`: e.g., `content.md` (filename portion)

This is the bare minimum. Users see `content.md (079044a5...)` -- which tells them almost nothing about the source. The `content_items` database table already stores rich metadata for every content item:
- `title`: e.g., "How to Build a REST API" (human-readable)
- `source_ref`: e.g., `https://example.com/article` (original URL)
- `content_type`: e.g., "url", "document", "text"

By cross-referencing `content_id` from citations with the DB, citations become meaningful: "How to Build a REST API (example.com)" instead of "content.md (079044a5...)".

See Doc #07 Section 2.4 (Approach A: Enrich Citations at Extraction Time) and Doc #10 Tier 2, #5 (Citation enrichment via DB).

---

## Current State

### SourceCitation Schema (API Contract v1.9.0)

**File**: `research-mind-service/app/schemas/chat.py` (lines 106-115)

```python
class SourceCitation(BaseModel):
    file_path: str           # "uuid/filename" or "8hex/filename"
    content_id: str | None   # UUID or 8-hex prefix
    title: str               # Filename portion
```

### extract_citations() Function

**File**: `research-mind-service/app/services/chat_service.py` (lines 402-436)

```python
def extract_citations(content: str) -> list[SourceCitation]:
    uuid_short = r"[0-9a-f]{8}"
    uuid_full = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
    path_pattern = rf"`((?:{uuid_full}|{uuid_short})/[^`]+)`"
    # ... regex extraction, deduplication by file_path
```

### ContentItem Model

**File**: `research-mind-service/app/models/content_item.py` (lines 47-101)

Key fields:
- `content_id`: `String(36)` -- full UUID
- `session_id`: `String(36)` -- parent session
- `title`: `String(512)` -- human-readable title
- `source_ref`: `String(2048)` -- original URL or source reference
- `content_type`: `String(50)` -- "text", "url", "document", "git_repo", etc.
- `status`: `String(50)` -- "ready", "processing", etc.

### DB Access During Streaming

**Architectural challenge** (Doc #10, Critique 5): The streaming generator `stream_claude_mpm_response()` does not hold a database session. The DB connection is only created in the `finally` block of `event_generator()` for persistence.

Doc #10 recommends the simplest approach: **Enrich citations during the persistence phase (after streaming completes), not during streaming.** This means first-view citations are basic (file paths only), but persisted messages have enriched citations.

**However**, a cleaner approach exists: enrich citations in the route handler's `event_generator()` between receiving the `complete` event from the streaming generator and yielding it to the SSE response. This provides enriched citations on first view.

---

## Implementation Plan

### Step 1: Extend SourceCitation Schema

**File**: `research-mind-service/app/schemas/chat.py`

Add three new optional fields to `SourceCitation`:

```python
class SourceCitation(BaseModel):
    file_path: str                    # Existing: "uuid/filename" from answer text
    content_id: str | None = None     # Existing: UUID or 8-hex prefix
    title: str                        # Existing: filename portion of path
    # NEW fields (populated by DB enrichment):
    source_url: str | None = None     # Original URL (from content_items.source_ref)
    content_title: str | None = None  # Content item title (from content_items.title)
    content_type: str | None = None   # "url", "document", "text", etc.
```

All new fields are optional (nullable). Unenriched citations work exactly as before.

### Step 2: Create Citation Enrichment Function

**File**: `research-mind-service/app/services/chat_service.py`

Add a new function after `extract_citations()`:

```python
async def enrich_citations(
    citations: list[SourceCitation],
    session_id: str,
    db: Session,
) -> list[SourceCitation]:
    """Cross-reference citations with ContentItem DB records to add metadata."""
    if not citations:
        return citations

    from app.models.content_item import ContentItem

    for citation in citations:
        if not citation.content_id:
            continue

        content_id = citation.content_id

        # Try exact match first (full UUID)
        content_item = db.query(ContentItem).filter(
            ContentItem.session_id == session_id,
            ContentItem.content_id == content_id,
        ).first()

        # If no exact match and content_id looks like an 8-hex prefix, try LIKE
        if content_item is None and len(content_id) == 8:
            content_item = db.query(ContentItem).filter(
                ContentItem.session_id == session_id,
                ContentItem.content_id.like(f"{content_id}%"),
            ).first()

        if content_item:
            citation.source_url = content_item.source_ref
            citation.content_title = content_item.title
            citation.content_type = content_item.content_type
            # Also resolve the full content_id if we matched by prefix
            if len(content_id) == 8 and content_item.content_id:
                citation.content_id = content_item.content_id

    return citations
```

**Design decisions**:
- 8-hex prefix resolution uses `LIKE` query (Doc #07 Section 2.3)
- One query per citation (simple, adequate for 3-10 citations per answer)
- Modifies citations in place for simplicity
- Uses the existing SQLAlchemy session pattern

### Step 3: Wire Enrichment into the Event Generator

**File**: `research-mind-service/app/routes/chat.py`

The enrichment should happen in `event_generator()` (the route handler's async generator), which has access to the DB session via FastAPI dependency injection.

Find the section where `complete` events from `stream_claude_mpm_response()` are processed. Before yielding the `complete` event to the SSE response, enrich the citations:

```python
# Inside event_generator(), where the complete event is being processed:
if event_type == "complete" and metadata and metadata.sources:
    # Enrich citations with DB metadata before sending to client
    from app.services.chat_service import enrich_citations
    metadata.sources = await enrich_citations(
        metadata.sources,
        session_id,
        db,
    )
```

**Important architectural note**: The `event_generator()` already holds a DB session for the final persistence step. Enrichment uses the same session, adding minimal overhead (3-10 simple queries, indexed by content_id).

**Alternative approach** (if modifying event_generator flow is complex): Enrich during the persistence phase in the `finally` block:

```python
# In the finally block, after persisting the assistant message:
if metadata and metadata.sources:
    enriched_sources = await enrich_citations(metadata.sources, session_id, db)
    # Update the persisted message metadata
    assistant_msg.metadata_json["sources"] = [s.model_dump() for s in enriched_sources]
    db.commit()
```

This approach means first-view citations are basic, but reloaded messages show enriched citations. The trade-off is simpler implementation at the cost of slightly degraded first-view UX.

### Step 4: Update API Contract

**File**: `research-mind-service/docs/api-contract.md`

Update the `SourceCitation` schema section (around line 1573):

```typescript
interface SourceCitation {
  file_path: string;           // Full path: "uuid/filename" or "8hex/filename"
  content_id?: string;         // UUID or 8-hex prefix extracted from path
  title: string;               // Filename portion of the path
  source_url?: string;         // Original URL of the content item (from DB)
  content_title?: string;      // Human-readable title of the content item (from DB)
  content_type?: string;       // Content type: "url", "document", "text", etc. (from DB)
}
```

Add changelog entry:
```
| 1.10.0 | 2026-XX-XX | Extended SourceCitation with optional `source_url`, `content_title`, and `content_type` fields populated via DB enrichment of content_id. |
```

Version bump: 1.9.0 -> 1.10.0 (minor -- new optional fields, backward compatible).

### Step 5: Copy Contract and Regenerate Frontend Types

Follow the standard API contract sync workflow:

1. Copy contract: `cp research-mind-service/docs/api-contract.md research-mind-ui/docs/api-contract.md`
2. Start the service: `make dev`
3. Regenerate types: `make gen-client`
4. Verify the generated types include the new fields

### Step 6: Update Frontend SourceCitation Type

**File**: `research-mind-ui/src/lib/types/chat.ts`

Update the `SourceCitation` interface (lines 49-53):

```typescript
export interface SourceCitation {
  file_path: string;
  content_id?: string;
  title: string;
  source_url?: string;       // NEW
  content_title?: string;    // NEW
  content_type?: string;     // NEW
}
```

### Step 7: Update Sources Panel Rendering

**File**: `research-mind-ui/src/lib/components/chat/ChatMessage.svelte`

Replace the current basic citation rendering (lines 245-260) with enriched rendering:

```svelte
{#if displayMetadata()?.sources?.length}
  <div class="sources-panel">
    <h4>Sources</h4>
    <ul>
      {#each displayMetadata().sources as source}
        <li class="source-item">
          <span class="source-title">
            {source.content_title || source.title}
          </span>
          {#if source.content_type}
            <span class="source-type">{source.content_type}</span>
          {/if}
          {#if source.source_url}
            <a
              href={source.source_url}
              target="_blank"
              rel="noopener noreferrer"
              class="source-link"
            >
              {new URL(source.source_url).hostname}
            </a>
          {:else if source.content_id}
            <span class="content-id">({source.content_id.slice(0, 8)}...)</span>
          {/if}
        </li>
      {/each}
    </ul>
  </div>
{/if}
```

Add CSS for the enriched display:

```css
.source-item {
  display: flex;
  align-items: center;
  gap: var(--space-2, 0.5rem);
  flex-wrap: wrap;
}

.source-title {
  font-weight: 500;
}

.source-type {
  font-size: var(--font-size-xs, 0.75rem);
  color: var(--text-muted);
  background: var(--bg-secondary);
  padding: 0.1rem 0.4rem;
  border-radius: var(--border-radius-sm, 0.25rem);
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.source-link {
  font-size: var(--font-size-xs, 0.75rem);
  color: var(--primary-color);
  text-decoration: none;
}

.source-link:hover {
  text-decoration: underline;
}
```

### Step 8: Handle URL Parsing Errors

The `new URL(source.source_url).hostname` call may throw if `source_url` is not a valid URL (e.g., for `text` or `git_repo` content types where `source_ref` might be a path, not a URL).

Add a safe URL display helper:

```typescript
function displaySourceUrl(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url.length > 40 ? url.slice(0, 40) + '...' : url;
  }
}
```

---

## Files Modified

### Backend

| File | Changes |
|------|---------|
| `research-mind-service/app/schemas/chat.py` | Add `source_url`, `content_title`, `content_type` fields to `SourceCitation` |
| `research-mind-service/app/services/chat_service.py` | Add `enrich_citations()` function |
| `research-mind-service/app/routes/chat.py` | Call `enrich_citations()` in event_generator before yielding complete event |
| `research-mind-service/docs/api-contract.md` | Extend `SourceCitation` schema, version bump to 1.10.0 |

### Frontend

| File | Changes |
|------|---------|
| `research-mind-ui/docs/api-contract.md` | Sync from service |
| `research-mind-ui/src/lib/api/generated.ts` | Regenerated (auto) |
| `research-mind-ui/src/lib/types/chat.ts` | Add 3 new fields to `SourceCitation` interface |
| `research-mind-ui/src/lib/components/chat/ChatMessage.svelte` | Update sources-panel to display enriched fields |

---

## API Contract Impact

**Version bump**: 1.9.0 -> 1.10.0 (minor)

**Change type**: Additive -- 3 new optional fields on existing `SourceCitation` schema. Fully backward compatible. Clients that don't read the new fields continue to work unchanged.

---

## Acceptance Criteria

1. `SourceCitation` objects in the `complete` event include `source_url`, `content_title`, and `content_type` when the `content_id` matches a DB record
2. 8-hex prefix content IDs are resolved to full UUIDs via `LIKE` query
3. Citations for `url` content type show the human-readable title and a clickable hostname link
4. Citations for `text` or `document` content type show the content title without a link
5. Unenriched citations (no DB match) still render correctly with the filename fallback
6. No performance degradation -- enrichment adds <100ms for typical 3-10 citations
7. Both `api-contract.md` files are identical after sync
8. Frontend tests pass with regenerated types

---

## Validation

1. Create a session with 3+ content items (at least one URL, one document, one text)
2. Ask a question that references content from all three
3. Inspect the SSE `complete` event metadata:
   - `sources[].source_url` should be populated for URL content
   - `sources[].content_title` should be populated for all matched content
   - `sources[].content_type` should reflect the content type
4. Verify the sources-panel in the UI shows:
   - Human-readable titles (not just "content.md")
   - Clickable hostname links for URL content
   - Content type badges
5. Ask a question where Claude cites a file with an 8-hex prefix
6. Verify the prefix is resolved to the full UUID in the enriched citation

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| 8-hex prefix matches multiple content items | Low | Medium | Use `LIKE` with `session_id` filter + take first match; ambiguity unlikely within a session |
| DB enrichment slows down the complete event | Low | Low | 3-10 simple indexed queries add <50ms; measure after implementation |
| `source_ref` is not always a URL | Medium | Low | The `displaySourceUrl()` helper handles non-URL source_refs gracefully |
| DB session lifetime issues in event_generator | Medium | Medium | Use the existing DB session that event_generator already holds for persistence |
| Claude cites files that don't exist in the sandbox | Medium | Low | Enrichment simply leaves new fields as null; citation still shows file_path as fallback |

---

## Relationship to Other Plans

- **Plan 01 (Citation Consolidation)**: Must be complete first. This plan builds on having a single citation mechanism.
- **Plan 05 (Future)**: Expandable inline previews and click-to-navigate will use the enriched `source_url` and resolved `content_id` from this plan.

---

## Research References

- Doc #07 Section 2.4, Approach A: "Enrich Citations at Extraction Time (Backend)" -- this plan implements this approach
- Doc #07 Section 2.3: "Content Serving Gap Analysis" -- identifies the enrichment fields needed
- Doc #07 Section 2.6: "API Contract Changes for Citation Linking" -- schema extension design
- Doc #08 Section 2.6-2.7: "Where Source URLs Could Come From" + "How Citations Could Include File Paths" -- Approach 3 (post-extraction enrichment)
- Doc #10 Critique 5: "Citation Enrichment DB Access Is Architecturally Awkward" -- informs the implementation approach (enrich in event_generator, not streaming generator)
- Doc #10 Tier 2, #5: "Citation enrichment via DB" -- rated as Must-have
