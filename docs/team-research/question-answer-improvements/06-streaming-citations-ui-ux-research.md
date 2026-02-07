# UI/UX Research: Streaming Progress in Accordion & Source Citations UX

**Date**: 2026-02-07
**Researcher**: UI/UX Research Agent
**Scope**: `research-mind-ui/` - SvelteKit 5 frontend
**API Contract Version**: 1.9.0
**Task**: Team research task #3 — Streaming progress display & citation linking UX

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Item 1: Streaming Progress in Accordion](#item-1-streaming-progress-in-accordion)
   - [Current State Analysis](#11-current-state-analysis)
   - [SSE Event Flow Timeline](#12-sse-event-flow-timeline)
   - [Root Cause: Why the Accordion Stalls](#13-root-cause-why-the-accordion-stalls)
   - [Proposed Solutions](#14-proposed-solutions)
   - [Component Changes Required](#15-component-changes-required)
   - [Complexity Assessment](#16-complexity-assessment)
3. [Item 2: Source Citations UX](#item-2-source-citations-ux)
   - [Current State Analysis](#21-current-state-analysis)
   - [How Citations Currently Flow](#22-how-citations-currently-flow)
   - [Sandbox Content Accessibility](#23-sandbox-content-accessibility)
   - [UX Patterns for Interactive Citations](#24-ux-patterns-for-interactive-citations)
   - [Proposed Approach](#25-proposed-approach)
   - [Component Changes Required](#26-component-changes-required)
   - [Complexity Assessment](#27-complexity-assessment)
4. [Component Inventory](#component-inventory)
5. [Cross-Cutting Concerns](#cross-cutting-concerns)
6. [Implementation Priority](#implementation-priority)
7. [File Reference Index](#file-reference-index)

---

## Executive Summary

This research examines two specific UI/UX improvements for the Research Mind Q&A system:

**Item 1 — Streaming Progress in Accordion**: The expandable accordion currently shows only initialization messages (agent sync, hook events) and then goes silent until the final answer arrives. The root cause is that after initialization, `stream_token` events carry Claude Code's internal process output (tool calls, file reads, thinking), which are all accumulated in `stage1Content` and hidden inside the collapsed accordion. The user sees "Generating response..." for 5-30+ seconds with no visible progress. **Solution**: Parse `stream_token` events to extract meaningful status lines (tool calls, file reads, search queries) and display them as a progress ticker in the accordion toggle bar — without changing the final answer display.

**Item 2 — Source Citations UX**: The system has two citation mechanisms: (1) inline markdown citations from enhanced CLAUDE.md (rendered in the answer body with `wrapSourcesSection()`), and (2) structured `SourceCitation` metadata from the API (rendered in `.sources-panel`). Neither currently links to actual scraped content. **Solution**: Make citations clickable by linking `content_id` to the existing `GET /api/v1/sessions/{session_id}/content/{content_id}` endpoint, with expandable inline previews or navigation to the Overview tab's content list.

**Key finding**: Both features can be implemented with UI-only changes (no API contract modifications needed). The existing SSE event data and API endpoints provide sufficient information.

---

## Item 1: Streaming Progress in Accordion

### 1.1 Current State Analysis

#### The Two-Stage Architecture

The chat streaming system uses a two-stage content separation:

| Stage | Content Target | Visibility | Event Types |
|-------|---------------|------------|-------------|
| Stage 1 (Expandable) | `stage1Content` | Hidden in collapsible accordion | `init_text`, `system_init`, `system_hook`, `stream_token` |
| Stage 2 (Primary) | `stage2Content` | Visible main answer area | `assistant`, `result` |

**Key file**: `src/lib/hooks/useChatStream.svelte.ts` (319 lines)

The streaming hook (`createChatStream()`) handles events in `handleEvent()` at line 65:

```typescript
// Stage 1: Expandable content
case ChatStreamEventType.INIT_TEXT:
  stage1Content += (data.content as string) + '\n';
  break;

case ChatStreamEventType.SYSTEM_INIT:
case ChatStreamEventType.SYSTEM_HOOK:
  stage1Content += formatted + '\n';
  break;

case ChatStreamEventType.STREAM_TOKEN:
  // Token streaming (Stage 1)
  stage1Content += data.content as string ?? '';
  break;
```

#### What the User Actually Sees

```
Time  0s: User submits question
Time  0s: Input cleared, mutation fires
Time ~1s: SSE connects → status: "connecting"
Time ~2s: init_text events → "Syncing agents...", "Starting Claude Code..."
          ↳ Accordion shows: "Full Process Output" + green pulsing dot
Time ~3s: system_hook events → "[Hook] ... started", "[Hook] ... completed"
          ↳ Accordion continues accumulating text (collapsed by default)
Time ~3s: stage1Content has ~5-8 lines of init text
          ↳ Primary area shows: "Generating response..." with spinner

==== GAP: 5-30+ seconds of silence ====

Time ~5-30s: stream_token events may arrive (Claude Code's internal output)
             BUT these are appended to stage1Content (hidden/collapsed)
             ↳ User sees NO change — "Generating response..." persists

Time ~30s+: assistant event → stage2Content populated → answer appears
Time ~30s+: result event → metadata footer shows duration/tokens/cost
```

#### The Accordion Component (ChatMessage.svelte, lines 172-203)

```svelte
{#if !isUser && hasExpandableContent}
  <div class="expandable-section">
    <button class="expand-toggle" onclick={() => (expanded = !expanded)}>
      <span class="toggle-icon">
        {#if expanded}<ChevronDown />{:else}<ChevronRight />{/if}
      </span>
      <span class="toggle-text">Full Process Output</span>
      {#if isStreaming}
        <span class="streaming-dot" aria-label="Streaming"></span>
      {/if}
    </button>

    {#if expanded}
      <pre id="stage1-content" class="stage1-content" transition:slide>
        {stage1Content}
      </pre>
    {/if}
  </div>
{/if}
```

**Observations**:
1. The accordion toggle shows "Full Process Output" + a green pulsing dot during streaming
2. The pulsing dot indicates *something* is happening, but provides zero specifics
3. The actual content is only visible if the user manually expands the accordion
4. Most users will NOT expand it — they watch the primary area

### 1.2 SSE Event Flow Timeline

Based on the event type definitions in `src/lib/types/chat.ts`:

```
[init_text] "Syncing agents..."                    ← Visible in accordion
[init_text] "Starting Claude Code..."              ← Visible in accordion
[system_init] {"type":"system","subtype":"init"}   ← Formatted: "[Init] Session initialized (model: ...)"
[system_hook] {"hook_name":"pre-query","subtype":"hook_started"} ← Formatted: "[Hook] pre-query started"
[system_hook] {"hook_name":"pre-query","subtype":"hook_response"} ← "[Hook] pre-query completed"

---- LONG GAP: Claude Code is working internally ----

[stream_token] content...   ← Tokens trickle in (if backend emits them)
[stream_token] content...   ← These go to stage1Content (hidden)
[stream_token] content...

[assistant] "The answer is..."  ← Complete answer, shown in primary area
[result] { content: "...", metadata: {...}, sources: [...] }  ← Final with metadata
```

The `stream_token` events during the "long gap" are the key data source for progress display. They contain Claude Code's operational output — tool call notifications, file reads, search queries, reasoning fragments.

### 1.3 Root Cause: Why the Accordion Stalls

Three factors combine to create the stalled UX:

1. **Accordion collapsed by default**: `let expanded = $state(false)` — users don't see `stage1Content` accumulating
2. **Toggle label is static**: "Full Process Output" doesn't change regardless of what's happening
3. **No progress extraction**: `stream_token` content is raw text dumped into `stage1Content` without parsing for meaningful status updates

The streaming dot (`class="streaming-dot"`) provides the only visual feedback, but it's a single pulsing green circle that conveys nothing about *what* is happening.

### 1.4 Proposed Solutions

#### Approach A: Progress Ticker in Accordion Toggle Bar (Recommended)

Display the last meaningful status line directly in the accordion toggle bar, replacing/supplementing the static "Full Process Output" text.

**Concept**:
```
Before:  [▶] Full Process Output  🟢
After:   [▶] Full Process Output  🟢  Reading file: api-contract.md
After:   [▶] Full Process Output  🟢  Searching for: "authentication patterns"
After:   [▶] Full Process Output  🟢  Analyzing 3 source files...
```

**Implementation**:

1. Add a `latestStatus` derived state that extracts the most recent meaningful line from `stage1Content`
2. Parse `stream_token` content for recognizable patterns:
   - Tool call names (Read, Grep, Glob, etc.)
   - File paths being accessed
   - Search queries being performed
   - Processing milestones
3. Display in the toggle bar with CSS text-overflow: ellipsis for long lines

**Where to implement**:
- **ChatMessage.svelte**: Add `latestStatus` parsing + display in toggle bar
- **useChatStream.svelte.ts**: Optionally add a dedicated `latestProgressLine` state variable

**Advantages**:
- No changes to final answer display
- No backend changes needed
- Leverages existing `stream_token` data
- Works with accordion collapsed (most users' default)
- Progressive enhancement — falls back gracefully if no progress tokens arrive

#### Approach B: Dedicated Progress Bar Below Accordion

Add a separate progress indicator area between the accordion and the "Generating response..." placeholder.

**Concept**:
```
┌─ Expandable Section ────────────┐
│ [▶] Full Process Output    🟢  │
└─────────────────────────────────┘
┌─ Progress ──────────────────────┐  ← NEW
│ 📖 Reading api-contract.md      │
│ 🔍 Searching: "auth patterns"   │
│ ⏳ Processing 3 sources...       │
└─────────────────────────────────┘
┌─ Primary Answer ────────────────┐
│ [spinner] Generating response... │
└─────────────────────────────────┘
```

**Advantages**: More space for status info, can show last 2-3 status lines
**Disadvantages**: More visual complexity, additional DOM elements, may feel cluttered

#### Approach C: Animated Status in Primary Placeholder

Replace the static "Generating response..." with a dynamic status that cycles through progress updates.

**Concept**: The "Generating response..." text becomes "Reading api-contract.md..." then "Searching for patterns..." etc.

**Disadvantages**: Risks feeling busy/distracting, may conflict with Stage 2 content arrival

**Recommendation**: **Approach A** (Progress Ticker in Toggle Bar) is the best balance of informativeness, simplicity, and non-intrusiveness.

### 1.5 Component Changes Required

#### For Approach A (Recommended):

**File 1: `src/lib/hooks/useChatStream.svelte.ts`**

Add a new reactive state for the latest progress line:

```typescript
let latestProgressLine = $state('');

// In handleEvent(), for STREAM_TOKEN:
case ChatStreamEventType.STREAM_TOKEN: {
  const tokenContent = data.content as string ?? '';
  stage1Content += tokenContent;
  // Extract progress status from token content
  const progressLine = extractProgressLine(tokenContent);
  if (progressLine) {
    latestProgressLine = progressLine;
  }
  break;
}
```

Add a new getter:
```typescript
get latestProgressLine() {
  return latestProgressLine;
},
```

Add a helper function:
```typescript
function extractProgressLine(content: string): string | null {
  // Parse for common Claude Code tool patterns
  const patterns = [
    /(?:Reading|Read) (?:file[s]?|content):?\s*(.+)/i,
    /(?:Searching|Search|Grep|Glob):?\s*(.+)/i,
    /(?:Writing|Write|Edit):?\s*(.+)/i,
    /(?:Running|Bash|Execute):?\s*(.+)/i,
    /Tool:\s*(.+)/i,
    /(?:Analyzing|Processing|Indexing):?\s*(.+)/i,
  ];

  const lines = content.split('\n').filter(l => l.trim());
  for (const line of lines.reverse()) {
    for (const pattern of patterns) {
      const match = line.match(pattern);
      if (match) return line.trim().slice(0, 80);
    }
  }
  return null;
}
```

**File 2: `src/lib/components/chat/SessionChat.svelte`**

Pass the new prop to ChatMessage:

```svelte
<ChatMessage
  {message}
  {sessionId}
  isStreaming={stream.isStreaming && message.message_id === stream.messageId}
  stage1Content={message.message_id === stream.messageId ? stream.stage1Content : ''}
  stage2Content={message.message_id === stream.messageId ? stream.stage2Content : ''}
  streamMetadata={message.message_id === stream.messageId ? stream.metadata : null}
  latestProgressLine={message.message_id === stream.messageId ? stream.latestProgressLine : ''}
/>
```

**File 3: `src/lib/components/chat/ChatMessage.svelte`**

Add the prop and display in toggle bar:

```svelte
<!-- In Props interface -->
latestProgressLine?: string;

<!-- In the expand-toggle button -->
<button class="expand-toggle" ...>
  <span class="toggle-icon">...</span>
  <span class="toggle-text">Full Process Output</span>
  {#if isStreaming}
    <span class="streaming-dot"></span>
    {#if latestProgressLine}
      <span class="progress-status">{latestProgressLine}</span>
    {/if}
  {/if}
</button>
```

CSS addition:
```css
.progress-status {
  font-size: var(--font-size-xs);
  color: var(--text-muted);
  max-width: 300px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  opacity: 0.8;
}
```

### 1.6 Complexity Assessment

| Factor | Assessment |
|--------|-----------|
| **Files changed** | 3 (useChatStream, SessionChat, ChatMessage) |
| **Lines of code** | ~40-60 new lines |
| **Backend changes** | None required |
| **API contract changes** | None required |
| **Risk to final answer** | Zero (only modifies accordion toggle area) |
| **Test impact** | Minimal (new unit test for extractProgressLine()) |
| **Biggest unknown** | What content `stream_token` events actually contain during queries — may need real-world testing to tune the regex patterns |
| **Effort estimate** | Small-Medium |

**Critical dependency**: This approach depends on the backend actually emitting `stream_token` events during the Claude Code processing phase. If the backend only emits `init_text` at startup and then jumps directly to `assistant`/`result`, the progress ticker will have nothing to show. Verification needed: Run a live query and inspect the actual SSE event stream to confirm `stream_token` events are emitted during processing.

---

## Item 2: Source Citations UX

### 2.1 Current State Analysis

The citation system has two parallel mechanisms, both already partially implemented:

#### Mechanism 1: Inline Markdown Citations (from Enhanced CLAUDE.md)

The CLAUDE.md template in the session sandbox instructs Claude to include file path references inline and a "Sources" section at the end of answers. These are rendered as standard markdown.

**File**: `src/lib/utils/markdown.ts` (line 265-274)

```typescript
function wrapSourcesSection(html: string): string {
  const sourcesPattern = /<h2[^>]*>(Sources|References)<\/h2>/i;
  const match = html.match(sourcesPattern);
  if (match && match.index !== undefined) {
    const beforeSources = html.slice(0, match.index);
    const sourcesSection = html.slice(match.index);
    return `${beforeSources}<div class="sources-section">${sourcesSection}</div>`;
  }
  return html;
}
```

This wraps any `## Sources` or `## References` heading and all content after it in a styled `<div class="sources-section">`, giving it a visual accent bar and distinct background.

**CSS styling** in `src/lib/components/chat/MarkdownContent.svelte` (lines 211-245):
- Left border accent (`3px solid var(--primary-color)`)
- Background highlight (`var(--bg-secondary)`)
- Smaller heading (`var(--font-size-xs)`, uppercase)
- Compact list styling

**Current appearance**: The Sources section renders as a styled box at the end of the answer, but citations are plain text — not clickable, not linked to actual content.

#### Mechanism 2: Structured SourceCitation Metadata (from API)

The API contract v1.9.0 added `SourceCitation` objects to the streaming result metadata:

**File**: `src/lib/types/chat.ts` (lines 49-53)

```typescript
export interface SourceCitation {
  file_path: string;
  content_id?: string;
  title: string;
}
```

**File**: `src/lib/components/chat/ChatMessage.svelte` (lines 245-260)

```svelte
{#if displayMetadata()?.sources?.length}
  <div class="sources-panel">
    <h4>Sources</h4>
    <ul>
      {#each displayMetadata().sources as source}
        <li>
          <code>{source.title}</code>
          {#if source.content_id}
            <span class="content-id">({source.content_id.slice(0, 8)}...)</span>
          {/if}
        </li>
      {/each}
    </ul>
  </div>
{/if}
```

**Current appearance**: A compact panel below the answer with file titles in monospace and truncated content IDs. Not clickable.

### 2.2 How Citations Currently Flow

```
Claude Code reads files in sandbox → generates answer with inline refs
     ↓
Backend extracts citations from answer text (regex: UUID/filename patterns)
     ↓
Backend sends:
  1. `assistant` event → answer text with inline markdown refs
  2. `result` event → metadata.sources: SourceCitation[]
     ↓
UI renders:
  1. MarkdownContent → wrapSourcesSection() → styled "Sources" box in answer
  2. ChatMessage → sources-panel → structured citation list below answer
```

**Observation**: There are potentially TWO citation displays for the same answer — the markdown-rendered Sources section (from the answer text) AND the structured sources-panel (from metadata). These may be duplicative or complementary depending on whether the backend successfully extracts structured citations.

### 2.3 Sandbox Content Accessibility

**Q: Can the UI currently access the scraped content files in the sandbox?**

**Existing API endpoints**:

| Endpoint | Purpose | Returns |
|----------|---------|---------|
| `GET /sessions/{id}/content` | List all content items | Array of `ContentItemResponse` (metadata only) |
| `GET /sessions/{id}/content/{content_id}` | Get single content item | `ContentItemResponse` (metadata only) |

**Critical finding**: The `ContentItemResponse` includes:
- `content_id` (UUID)
- `title` (display name)
- `content_type` (text, url, git_repo, document)
- `source_ref` (original URL or path)
- `storage_path` (server-side path — NOT accessible from UI)
- `status`, `size_bytes`, `mime_type`, `metadata_json`

**There is NO endpoint to read the actual file content of a content item.** The `storage_path` is a server-side filesystem path that the UI cannot access. The API only returns metadata about content items, not their contents.

**Gap**: To make citations link to actual scraped content, we need either:
1. A new API endpoint: `GET /sessions/{id}/content/{content_id}/text` — returns the stored text content
2. A file serving endpoint for sandbox files
3. Client-side navigation to the content item in the Overview tab (metadata only, no content preview)

### 2.4 UX Patterns for Interactive Citations

#### Pattern 1: Inline Footnote Links (Lightweight)

Citations appear as superscript numbers in the answer text, linking to a footer section.

```
According to the API contract¹, the system uses SSE streaming².

---
¹ api-contract.md — "Chat endpoints use Server-Sent Events..."
² architecture-overview.md — "Streaming is implemented via..."
```

**Pros**: Familiar academic/Wikipedia pattern, minimal screen impact
**Cons**: Requires parsing answer text to insert superscript markers, brittle

#### Pattern 2: Expandable Inline Previews (Medium)

Citations in the sources section can be clicked to expand a preview snippet inline.

```
Sources:
▸ api-contract.md (079044a5)        ← Click to expand
▾ architecture-overview.md (3f2a1b7c) ← Expanded
  │ "The system uses a two-stage SSE streaming protocol
  │  where Stage 1 events go to the collapsible accordion
  │  and Stage 2 events populate the primary answer area."
  │ [Open in Overview →]
```

**Pros**: Shows context without leaving the page, progressive disclosure
**Cons**: Requires content text endpoint, expands the answer area

#### Pattern 3: Side Panel (Rich)

Clicking a citation opens a side panel with the full source content, highlighted at the relevant section.

```
┌─── Chat ────────────────┬──── Source ──────────────┐
│ The system uses SSE     │ api-contract.md          │
│ streaming [1].          │ ─────────────────────────│
│                         │ ...                      │
│ Sources:                │ The chat streaming uses  │
│ [1] api-contract.md ←── │ ▶ Server-Sent Events    │
│                         │ with a two-stage design  │
│                         │ ...                      │
└─────────────────────────┴──────────────────────────┘
```

**Pros**: Full context, doesn't disrupt chat flow
**Cons**: Complex layout, requires significant screen real estate, needs new content-read endpoint

#### Pattern 4: Link to Content in Overview Tab (Simplest)

Citations link to the content item in the existing Overview tab, using the `content_id`.

```
Sources:
🔗 api-contract.md (079044a5)  → navigates to /sessions/{id}#content-079044a5
🔗 architecture.md (3f2a1b7c)  → navigates to /sessions/{id}#content-3f2a1b7c
```

**Pros**: Zero new endpoints, uses existing UI, immediate implementation
**Cons**: Leaves the chat tab, loses conversation context, Overview tab shows metadata only (not content text)

### 2.5 Proposed Approach

**Phase 1 (No API changes): Clickable Links to Content Items**

Make citations in both the sources-panel and the inline Sources section clickable, linking to the content item in the Overview tab.

For the **structured sources-panel** (ChatMessage.svelte):
- If `source.content_id` is present and matches a known content item, render as an `<a>` tag linking to `/sessions/{sessionId}#content-{content_id}`
- If no `content_id`, render as non-clickable text (current behavior)

For the **inline markdown Sources section** (MarkdownContent.svelte):
- Post-process the rendered HTML to detect backtick-wrapped UUID/filename patterns
- Convert them to links targeting the content item in the Overview tab
- E.g., `<code>079044a5/api-contract.md</code>` → `<a href="/sessions/{id}#content-079044a5"><code>079044a5/api-contract.md</code></a>`

**Phase 2 (Requires new API endpoint): Expandable Inline Previews**

Add a content text endpoint to the backend:
```
GET /api/v1/sessions/{session_id}/content/{content_id}/text
→ Returns: { content_text: string, truncated: boolean }
```

Then implement expandable inline previews in the sources-panel:
- Click on a citation → fetch first 500 chars of content text
- Display as an expandable preview below the citation
- Include a "View full content →" link to the Overview tab

### 2.6 Component Changes Required

#### Phase 1 (Link to Content):

**File 1: `src/lib/components/chat/ChatMessage.svelte`**

Make structured citations clickable:

```svelte
<!-- Current -->
<li>
  <code>{source.title}</code>
  {#if source.content_id}
    <span class="content-id">({source.content_id.slice(0, 8)}...)</span>
  {/if}
</li>

<!-- Proposed -->
<li>
  {#if source.content_id && sessionId}
    <a href="/sessions/{sessionId}#content-{source.content_id}" class="source-link">
      <code>{source.title}</code>
      <span class="content-id">({source.content_id.slice(0, 8)}...)</span>
    </a>
  {:else}
    <code>{source.title}</code>
  {/if}
</li>
```

Add CSS for `.source-link`:
```css
.sources-panel a.source-link {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  text-decoration: none;
  color: inherit;
  border-radius: var(--border-radius-sm);
  padding: 2px 4px;
  margin: -2px -4px;
  transition: background var(--transition-fast);
}

.sources-panel a.source-link:hover {
  background: var(--bg-hover);
  color: var(--primary-color);
}
```

**File 2: `src/lib/utils/markdown.ts`**

Enhance `wrapSourcesSection()` to also linkify content paths:

```typescript
function linkifyContentPaths(html: string, sessionId?: string): string {
  if (!sessionId) return html;

  // Match backtick-wrapped UUID/filename patterns inside the sources section
  // Pattern: <code>UUID_PREFIX/filename</code>
  const uuidPathPattern = /<code>([0-9a-f]{8}(?:-[0-9a-f]{4}){0,3}[^<]*\/[^<]+)<\/code>/gi;

  return html.replace(uuidPathPattern, (match, path) => {
    const parts = path.split('/');
    const contentId = parts[0];
    return `<a href="/sessions/${sessionId}#content-${contentId}" class="citation-link">${match}</a>`;
  });
}
```

**Note**: This requires passing `sessionId` through to `parseMarkdown()`, which currently doesn't receive it. The `MarkdownContent` component would need a new `sessionId` prop.

**File 3: `src/lib/components/chat/MarkdownContent.svelte`**

Add sessionId prop and pass to parser:

```svelte
interface Props {
  content: string;
  isStreaming?: boolean;
  sessionId?: string;  // NEW
}

let { content, isStreaming = false, sessionId }: Props = $props();

const renderedHtml = $derived(parseMarkdown(content, isStreaming, sessionId));
```

#### Phase 2 (Expandable Previews — Future):

Additional changes needed:
- New API endpoint: `GET /sessions/{id}/content/{content_id}/text`
- New Zod schema for content text response
- New TanStack Query hook for fetching content text
- Expand/collapse state per citation in ChatMessage
- Loading state while fetching content preview

### 2.7 Complexity Assessment

#### Phase 1 (Link to Content)

| Factor | Assessment |
|--------|-----------|
| **Files changed** | 3 (ChatMessage, MarkdownContent, markdown.ts) |
| **Lines of code** | ~30-50 new lines |
| **Backend changes** | None |
| **API contract changes** | None |
| **Risk to final answer** | Low (only adds clickable links, doesn't modify content) |
| **Test impact** | Unit test for linkifyContentPaths regex |
| **Biggest unknown** | Whether `content_id` in SourceCitation reliably matches `content_id` in ContentItemResponse — may need UUID prefix matching |
| **Effort estimate** | Small |

#### Phase 2 (Expandable Previews)

| Factor | Assessment |
|--------|-----------|
| **Files changed** | 5+ (backend + frontend) |
| **Lines of code** | ~150-200 |
| **Backend changes** | New endpoint for content text retrieval |
| **API contract changes** | Version bump (minor — new endpoint) |
| **Risk** | Medium (new endpoint needs security review for content access) |
| **Effort estimate** | Medium-Large |

---

## Component Inventory

### Components Affected by Item 1 (Streaming Progress)

| Component | File | Changes |
|-----------|------|---------|
| `useChatStream` | `src/lib/hooks/useChatStream.svelte.ts` | Add `latestProgressLine` state + `extractProgressLine()` helper |
| `SessionChat` | `src/lib/components/chat/SessionChat.svelte` | Pass `latestProgressLine` prop to ChatMessage |
| `ChatMessage` | `src/lib/components/chat/ChatMessage.svelte` | Display progress line in accordion toggle bar |

### Components Affected by Item 2 (Citation UX)

| Component | File | Changes |
|-----------|------|---------|
| `ChatMessage` | `src/lib/components/chat/ChatMessage.svelte` | Make structured citations clickable links |
| `MarkdownContent` | `src/lib/components/chat/MarkdownContent.svelte` | Add `sessionId` prop, pass to parser |
| `markdown.ts` | `src/lib/utils/markdown.ts` | Add `linkifyContentPaths()`, update `parseMarkdown()` signature |

### Components NOT Changed

| Component | File | Reason |
|-----------|------|--------|
| `SessionChat` (for citations) | `src/lib/components/chat/SessionChat.svelte` | Already passes `sessionId` to ChatMessage |
| `ExportDialog` | `src/lib/components/chat/ExportDialog.svelte` | No impact |
| `ContentList` | `src/lib/components/sessions/ContentList.svelte` | May need anchor targets (`id="content-{content_id}"`) for deep linking |
| `Overview Page` | `src/routes/sessions/[id]/+page.svelte` | May need scroll-to-anchor logic for `#content-{content_id}` |

---

## Cross-Cutting Concerns

### Concern 1: Duplicate Citation Displays

Both the inline markdown "Sources" section (from answer text) and the structured `sources-panel` (from metadata) may render simultaneously, showing duplicate citation information.

**Recommendation**: Implement a detection mechanism:
- If `displayMetadata()?.sources?.length > 0`, suppress the markdown Sources section (or vice versa)
- OR: Only render the structured sources-panel when structured data is available, and fall back to the markdown Sources section when it's not

### Concern 2: Content ID Matching

`SourceCitation.content_id` may be a full UUID or an 8-character hex prefix. The content items in the Overview tab use full UUIDs. Matching strategy:
- Full UUID match → direct link
- 8-char prefix match → search content items by prefix, link to first match
- No match → render without link

### Concern 3: stream_token Content Variability

The content of `stream_token` events depends on what the Claude Code backend emits. If the backend sends raw JSON tool call data, the `extractProgressLine()` function needs to handle structured data, not just plain text lines.

**Mitigation**: Start with simple text pattern matching. Add JSON parsing support after observing real event data. Include a fallback that shows a generic "Processing..." if no patterns match.

### Concern 4: Deep Linking to Overview Tab

For citation links (`/sessions/{id}#content-{content_id}`), the Overview tab needs:
1. Anchor `id` attributes on content items: `<div id="content-{content_id}" ...>`
2. Scroll-to-anchor behavior on page load/navigation
3. Highlight animation on the target content item

This is a small change to `ContentList.svelte` (add `id` attribute) and the session overview page (add scroll-to-anchor on hash change).

### Concern 5: Accessibility

- **Progress ticker**: Add `aria-live="polite"` to the progress status span so screen readers announce changes
- **Clickable citations**: Ensure links have descriptive `aria-label` attributes
- **Expandable previews (Phase 2)**: Use `aria-expanded` attributes

---

## Implementation Priority

| Priority | Feature | Effort | Impact | Dependencies |
|----------|---------|--------|--------|--------------|
| **P0** | Streaming progress ticker in accordion toggle | Small-Medium | High — eliminates the "stalled" feeling | None (UI-only) |
| **P0** | Clickable structured citations (sources-panel) | Small | Medium — enables content navigation | None (UI-only) |
| **P1** | Linkified inline markdown citations | Small | Medium — consistent with structured citations | sessionId prop threading |
| **P1** | Deep linking anchors in Overview tab | Small | Low-Medium — completes the citation link target | ContentList.svelte change |
| **P2** | Duplicate citation display resolution | Small | Medium — reduces visual clutter | Both citation mechanisms working |
| **P3** | Expandable inline previews | Medium-Large | High — rich UX but needs new API endpoint | New backend endpoint |

---

## File Reference Index

### Core Files Analyzed

| File | Lines | Purpose | Relevance |
|------|-------|---------|-----------|
| `src/lib/hooks/useChatStream.svelte.ts` | 319 | SSE streaming hook with two-stage content | **Primary** — progress extraction point |
| `src/lib/types/chat.ts` | 165 | Stream event types, SourceCitation interface | **Primary** — citation type definitions |
| `src/lib/components/chat/ChatMessage.svelte` | 604 | Message display with accordion + sources panel | **Primary** — both features render here |
| `src/lib/components/chat/SessionChat.svelte` | 653 | Chat container, passes stream state to ChatMessage | **Secondary** — prop threading |
| `src/lib/components/chat/MarkdownContent.svelte` | 269 | Markdown renderer with sources-section styling | **Primary** — inline citation linkification |
| `src/lib/utils/markdown.ts` | 346 | Markdown parsing, DOMPurify, wrapSourcesSection() | **Primary** — citation post-processing |
| `src/lib/api/client.ts` | 742 | API client with Zod schemas | **Reference** — content item schema |
| `src/routes/sessions/[id]/chat/+page.svelte` | 47 | Chat page route | **Reference** — layout context |

### API Contract References

| Section | Version | Relevance |
|---------|---------|-----------|
| SourceCitation schema | v1.9.0 | Structured citation data format |
| ChatStreamResultMetadata.sources | v1.9.0 | Where structured citations arrive in SSE |
| GET /sessions/{id}/content/{content_id} | v1.2.0 | Content item metadata (no text content) |
| Content Management endpoints | v1.2.0 | Content item CRUD (metadata only) |

### Existing Plans & Research

| Document | Relevance |
|----------|-----------|
| `docs/plans/question-answer-improvements/06-source-citations-in-ui.md` | Previous citation plan — Phase 1 CSS + Phase 2 structured |
| `docs/team-research/question-answer-improvements/01-ui-ux-research.md` | Original UX gap analysis identifying both issues |

---

*Research completed 2026-02-07. All file paths relative to `research-mind-ui/` unless otherwise noted.*
