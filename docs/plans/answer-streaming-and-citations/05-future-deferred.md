# Plan 05: Future / Deferred Items

**Tier**: 4 (Evaluate After Plans 01-04)
**Scope**: Reference document -- no implementation
**Goal**: Document deferred features, their rationale for deferral, conditions under which to revisit, and preliminary designs for future implementation.

---

## Overview

The devil's advocate analysis (Doc #10) rated several proposals as "Nice-to-have" or "Over-engineered" and recommended deferring them. This document catalogs those items with enough context to revisit them after Plans 00-04 are complete and their impact is measured.

---

## Deferred Item 1: Content File Serving Endpoint

### What

A new API endpoint to serve the actual text content of files in the session sandbox:

```
GET /api/v1/sessions/{session_id}/content/{content_id}/file/{filename}
```

### Why It Was Proposed

Doc #07 (Section 2.4, Approach B) proposes this to enable "view source" for citations -- clicking a citation loads the actual scraped content, not just metadata.

### Why It Was Deferred

Doc #10 (Critique 6) identifies **scope creep risk**:
- Once a file server exists, requests expand: PDFs, images, binary files, code highlighting, large file pagination
- Security surface area increases: path traversal, content-type negotiation, access control
- Effort is underestimated (not just a route -- needs content-type detection, size limits, range requests, caching headers)

### Condition to Revisit

After Plan 02 (Citation Enrichment) ships, evaluate user feedback:
- Do users click source URLs for URL-type content? (If yes, the existing `source_url` may suffice)
- Do users request "view source" for document/text content? (If yes, consider this endpoint)

### Simpler Alternative: `content_preview` Field

Doc #10 suggests adding a `content_preview` field to the existing content item API response instead of a new file-serving endpoint:

```json
{
  "content_id": "...",
  "title": "...",
  "content_preview": "First 500 characters of the content...",
  "full_text_available": true
}
```

This adds one field to an existing endpoint, requires no new route or file-serving infrastructure, and gives the UI enough for inline previews.

**Implementation sketch**:
- **File**: `research-mind-service/app/services/content_service.py` -- in `get_content()`, read first 500 chars of the content file
- **File**: `research-mind-service/app/schemas/content.py` -- add `content_preview` and `full_text_available` to `ContentItemResponse`
- **Security**: Read only from the content item's directory, not arbitrary paths
- **Performance**: Lazy loading (only read file when content_preview is requested)

---

## Deferred Item 2: Expandable Inline Citation Previews

### What

Citations in the sources panel can be clicked to expand a preview snippet inline (Doc #06 Section 2.4, Pattern 2):

```
Sources:
> api-contract.md (079044a5)        <-- Click to expand
v architecture-overview.md (3f2a1b7c) <-- Expanded
  | "The system uses a two-stage SSE streaming protocol
  |  where Stage 1 events go to the collapsible accordion..."
  | [Open in Overview -->]
```

### Why It Was Proposed

Doc #06 identifies this as the best UX pattern for citation interaction -- shows context without leaving the page, uses progressive disclosure.

### Why It Was Deferred

Requires the content file serving endpoint (Deferred Item 1) or the `content_preview` field alternative. Until the backend can serve content text, the frontend has nothing to display in the preview.

### Condition to Revisit

After the `content_preview` field is implemented (if Item 1's alternative is chosen), implement expandable previews as a frontend-only feature using the existing content API.

### Implementation Sketch

1. Add a TanStack Query hook for fetching content text:
   ```typescript
   const contentPreview = createQuery({
     queryKey: ['content-preview', sessionId, contentId],
     queryFn: () => fetchContentItem(sessionId, contentId),
     enabled: expanded,
   });
   ```

2. Add expand/collapse state per citation in `ChatMessage.svelte`

3. On expand: fetch the content item (which now includes `content_preview`), display the preview text below the citation

4. Add a "View full content" link to the content item in the Overview tab

---

## Deferred Item 3: Citation Deep Linking to Overview Tab

### What

Citations link to the content item in the Overview tab via URL hash: `/sessions/{id}#content-{content_id}` (Doc #06 Section 2.5, Phase 1).

### Why It Was Proposed

Doc #06 identifies this as the simplest way to make citations interactive -- zero new endpoints, uses existing UI.

### Why It Was Deferred

Doc #10 (Critique 2) rates this as a "dead-end UX": navigating to a different tab that shows only metadata (title, type, source_ref, size) provides minimal value. The user leaves the chat, finds the content item, and sees... a title and a URL. Three clicks for marginal benefit.

### Condition to Revisit

If the Overview tab is enhanced to show content text (via the `content_preview` approach), deep linking becomes more valuable. Also revisit if users explicitly request the ability to navigate from citations to content items.

### Implementation Sketch (if revisited)

1. **File**: `research-mind-ui/src/lib/components/sessions/ContentList.svelte` -- add `id="content-{content_id}"` to each content item element

2. **File**: `research-mind-ui/src/routes/sessions/[id]/+page.svelte` -- add scroll-to-anchor behavior on hash change

3. **File**: `research-mind-ui/src/lib/components/chat/ChatMessage.svelte` -- make citations with resolved content_id into `<a>` tags

---

## Deferred Item 4: Incremental Answer Display (Token Streaming)

### What

Add `--include-partial-messages` to the claude-mpm command so the UI can display the answer as it's being composed, token by token, instead of waiting for the complete answer (Doc #08 Section 1.8, Option A).

### Why It Was Proposed

This eliminates the "silence gap" entirely by showing answer text as it's generated, similar to ChatGPT's typing effect.

### Why It Was Deferred

Doc #10 (Critique 7) clarifies this is a **separate feature** from progress indicators:
- Progress indicators = status about what the system is doing (Plan 03/04)
- Token streaming = incremental display of the answer being composed

Additionally:
- `stream_event` tokens are currently classified as Stage 1 (EXPANDABLE) by `classify_event()`. To show them as incremental answer display in Stage 2, the classification logic would need to change -- a breaking change to the two-stage architecture.
- The two-stage architecture was deliberately designed to separate "process noise" (Stage 1) from "final answer" (Stage 2). Token streaming blurs this distinction.

### Condition to Revisit

After Plans 03-04 ship, measure user satisfaction:
- If users report the 10-30s wait is still frustrating despite progress indicators, token streaming is warranted
- If Plan 00's measurement shows average gap < 10s, progress indicators may be sufficient

### Implementation Sketch (if revisited)

1. **Backend**: Add `--include-partial-messages` to the claude-mpm command in `chat_service.py`

2. **Backend**: Create a new event classification for `stream_event` tokens:
   - Route them to Stage 2 (PRIMARY) instead of Stage 1 (EXPANDABLE)
   - Or create a new Stage 3 for "in-progress answer" content

3. **Frontend**: In `useChatStream.svelte.ts`, handle `stream_event` tokens by appending to a running `partialAnswer` state variable

4. **Frontend**: In `ChatMessage.svelte`, render `partialAnswer` in the primary answer area with a cursor/typing indicator

5. **Frontend**: When the `assistant` event arrives with the complete answer, replace `partialAnswer` with the final content

**Architectural impact**: This is a non-trivial change to the two-stage streaming design. Budget 3-5 days for design + implementation + testing.

---

## Deferred Item 5: Citation Metadata Skill for Skills/Agents Ecosystem

### What

Create a new skill (`universal-data-citation-metadata`) that instructs agents to produce structured citation metadata as HTML comment blocks (Doc #09 Section 2.4, Option A):

```html
<!-- CITATIONS: [
  {"id": "c1", "source_file": "docs/auth.md", "location": {"line_start": 45}, ...}
] -->
```

### Why It Was Proposed

Doc #09 proposes this to give agents the ability to produce machine-parseable citation data alongside answers.

### Why It Was Deferred

Doc #10 (Critiques 10-11) identifies two fundamental problems:
1. **Architecture is wrong**: The proposed flow (Agent -> claude-mpm orchestrator -> service) fails because claude-mpm replaces itself with Claude Code via `os.execvpe()`. There is no persistent orchestrator to parse markers.
2. **LLM-structured output is unreliable**: Field omission, format drift, inconsistent IDs, hallucinated paths, and relevance inflation are all common with LLM-generated structured data. The current deterministic regex approach + DB enrichment achieves 90% of the value with 10% of the complexity.

### Condition to Revisit

Only if:
- The regex extraction approach proves insufficient (>30% of citations are wrong or missing)
- AND a reliable structured output mechanism becomes available (e.g., Claude's tool_use output, not text-embedded markers)
- AND the service can parse the markers (the service reads stdout directly, so this is feasible)

### Alternative Approach (Preferred)

Instead of agent-side structured output, enhance the service-side extraction:
- Improve the regex in `extract_citations()` to handle more citation patterns
- Add citation validation (verify cited files exist in the sandbox before enriching)
- Add relevance scoring if mcp-vector-search similarity scores become available

---

## Deferred Item 6: Progress Reporting Skill

### What

Create a skill (`universal-collaboration-progress-reporting`) that instructs agents to emit structured progress markers as HTML comment blocks (Doc #09 Section 1.2, Option A).

### Why It Was Deferred

Same architectural issue as Item 5: no persistent orchestrator to parse markers. Additionally, Doc #10 (Critique 10) notes that "service-side detection is simpler and doesn't require agent compliance."

Plan 03 (Backend Progress Events) achieves the same goal through reliable backend signal detection, without depending on agent compliance.

### Condition to Revisit

Only if the backend progress events (Plan 03) prove insufficient and agent-level progress granularity is needed (e.g., "reading file X", "searching for Y").

---

## Deferred Item 7: Content Manifest JSON in Sandbox

### What

Create a `_content_manifest.json` file in each session sandbox that maps content_id to source URL, title, and type (Doc #08 Section 2.7, Approach 2):

```json
{
  "079044a5-...": {
    "source_url": "https://example.com/article",
    "title": "Example Article",
    "type": "url"
  }
}
```

### Why It Was Proposed

This gives Claude access to source metadata during Q&A, enabling it to include source URLs in citations (richer than just file paths).

### Why It Was Deferred

Plan 02 (Citation Enrichment) achieves the same result through post-extraction DB enrichment, without modifying the sandbox setup or adding files that Claude might confuse with actual content.

### Condition to Revisit

If the CLAUDE.md instruction improvements fail to produce good inline citations (Claude doesn't cite file paths consistently), the manifest approach provides an alternative: Claude reads the manifest and produces richer citations directly.

### Implementation Sketch (if revisited)

1. **File**: `research-mind-service/app/services/session_service.py` -- after sandbox creation, write `_content_manifest.json`

2. **File**: `research-mind-service/app/services/content_service.py` -- update manifest when content is added/removed

3. **File**: CLAUDE.md template -- add instruction to read `_content_manifest.json` for source metadata

---

## Priority Matrix

| Item | Impact | Effort | Risk | Revisit After |
|------|--------|--------|------|---------------|
| 1. Content File Serving | High | Medium | Medium (scope creep) | Plan 02 user feedback |
| 2. Expandable Previews | High | Medium | Low | Item 1 or alternative |
| 3. Deep Linking | Low | Small | Low | Overview tab enhancement |
| 4. Token Streaming | High | Large | Medium (architectural) | Plans 03-04 user feedback |
| 5. Citation Skill | Low | Medium | High (unreliable) | Never (prefer regex) |
| 6. Progress Skill | Low | Medium | Medium (unnecessary) | Never (Plan 03 suffices) |
| 7. Content Manifest | Medium | Small | Low | Plan 02 validation |

---

*This document is a reference for future planning. Items should be revisited based on the conditions specified, not on a fixed timeline.*
