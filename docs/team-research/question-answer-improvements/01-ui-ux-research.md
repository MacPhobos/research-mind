# UI/UX Research: Question-Answering System in Research Mind

**Date**: 2026-02-06
**Researcher**: UI/UX Research Agent
**Scope**: `research-mind-ui/` - SvelteKit frontend for Research Mind Q&A system
**API Contract Version**: 1.8.0

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Current State Analysis](#current-state-analysis)
4. [User Flow Analysis](#user-flow-analysis)
5. [Component Deep Dive](#component-deep-dive)
6. [Gap Analysis](#gap-analysis)
7. [Recommendations](#recommendations)
8. [File Reference Index](#file-reference-index)

---

## Executive Summary

Research Mind's UI is a SvelteKit 5 application with a well-structured Q&A interface built around a session-based paradigm. The system supports:

- **Session creation and management** with content ingestion (text, URLs, files, git repos, documents)
- **Workspace indexing** via mcp-vector-search for enabling Q&A
- **Two-stage SSE streaming** for chat responses (expandable process output + primary answer)
- **Chat export** (PDF/Markdown) for individual Q&A pairs or full history

**Key Strengths**: Type-safe architecture (Zod + generated types), two-stage streaming with good UX separation, markdown rendering with syntax highlighting (Shiki), responsive design.

**Key Gaps**: No source citations/evidence display, no confidence indicators, no answer quality feedback mechanism, no context visibility (what content was used to answer), limited search/retrieval transparency, no suggested follow-up questions, chat height constrained to 600px max.

---

## Architecture Overview

### Tech Stack

| Layer | Technology | File |
|-------|------------|------|
| Framework | SvelteKit 5 (Runes API) | `svelte.config.js` |
| Language | TypeScript 5.6+ strict | `tsconfig.json` |
| Data Fetching | TanStack Query | `src/lib/api/hooks.ts` |
| API Client | Zod-validated fetch | `src/lib/api/client.ts` |
| Type Generation | openapi-typescript from FastAPI | `src/lib/api/generated.ts` |
| UI Components | bits-ui (headless) + custom CSS | `src/lib/components/` |
| Markdown | marked + DOMPurify + Shiki | `src/lib/utils/markdown.ts` |
| Icons | lucide-svelte | Various components |
| State | Svelte 5 Runes ($state, $derived, $effect) + Svelte stores | `src/lib/stores/` |

### Component Architecture (Chat System)

```
routes/sessions/[id]/chat/+page.svelte
  └── SessionChat.svelte (main container)
        ├── ChatMessage.svelte (per-message display)
        │     ├── MarkdownContent.svelte (assistant responses)
        │     └── ExportDialog.svelte (per-message export)
        ├── ConfirmDialog.svelte (clear history)
        └── ExportDialog.svelte (full history export)

State/Data Flow:
  useChatStream.svelte.ts → SSE EventSource → Two-stage content
  hooks.ts → TanStack Query mutations/queries → API client
  client.ts → Zod validation → fetch() → Backend API
```

### Data Flow: Question → Answer

```
User types question
  ↓
SessionChat.handleSubmit()
  ↓
useSendChatMessageMutation → POST /api/v1/sessions/{id}/chat
  ↓
Backend returns { message_id, stream_url }
  ↓
createChatStream().connect(stream_url) → EventSource SSE
  ↓
Stage 1 events (init_text, system_init, system_hook, stream_token)
  → Accumulated in stage1Content (expandable accordion)
  ↓
Stage 2 events (assistant, result)
  → Displayed as primary answer with metadata
  ↓
Complete event → Close EventSource → Invalidate queries → Refetch messages
```

---

## Current State Analysis

### 3.1 Chat Page (`routes/sessions/[id]/chat/+page.svelte`)

**File**: `src/routes/sessions/[id]/chat/+page.svelte` (47 lines)

- Minimal wrapper that passes `sessionId` and `isIndexed` to `SessionChat`
- Uses `useIndexStatusQuery` to check if session is indexed before enabling chat
- Layout: `height: calc(100vh - 300px)` with `min-height: 500px` and overrides `.session-chat` max-height to `none`

**Observation**: The page is well-structured but doesn't provide any context about *what* content is available in the session. A user arriving at the chat tab has no visibility into what knowledge base they're querying.

### 3.2 Session Chat Container (`lib/components/chat/SessionChat.svelte`)

**File**: `src/lib/components/chat/SessionChat.svelte` (653 lines)

**Core functionality**:
- **Message display**: Combines API-fetched messages with streaming placeholder
- **Input area**: Textarea with Ctrl+Enter submit, 3-row default, resizable
- **Streaming**: Integrates `createChatStream()` hook for SSE handling
- **Actions**: Send, Clear History (with confirmation), Export (with dialog)
- **Guards**: Prevents sending when not indexed, during streaming, or during mutations
- **Auto-scroll**: Smooth scroll to bottom on new messages

**State management**:
```typescript
let inputContent = $state('');        // User input
const stream = createChatStream();    // SSE stream state
const streamingMessage = $derived();  // Synthetic message during streaming
const displayMessages = $derived();   // Merged API + streaming messages
```

**Key observations**:
1. The `max-height: 600px` on `.session-chat` limits the chat area unnecessarily (overridden by the page to `none`)
2. No message retry capability - if a message fails, user must retype
3. No optimistic UI updates - user message doesn't appear until API confirms
4. `staleTime: 0` on chat messages query means refetch on every focus

### 3.3 Chat Message Display (`lib/components/chat/ChatMessage.svelte`)

**File**: `src/lib/components/chat/ChatMessage.svelte` (542 lines)

**Two-stage display architecture**:

```
┌─────────────────────────────────┐
│ [Avatar] Role        Timestamp  │
│ ┌─ Expandable Section ────────┐ │  ← Stage 1 (collapsible)
│ │ [▶] Full Process Output     │ │
│ │     [Hook] started          │ │
│ │     [Init] model: claude... │ │
│ └─────────────────────────────┘ │
│                                 │
│ The answer is that...           │  ← Stage 2 (primary, markdown)
│ - Point 1                       │
│ - Point 2                       │
│                                 │
│ Duration: 3.1s | Tokens: 542   │  ← Metadata footer
│                                 │  ← Export button (hover)
└─────────────────────────────────┘
```

**Features**:
- User messages: plain text with line-break handling
- Assistant messages: full markdown rendering via `MarkdownContent`
- Expandable Stage 1 content with slide transition
- Streaming indicator (spinner + "Typing...")
- Metadata footer: duration, token count (in/out), cost in USD
- Per-message export button (appears on hover, assistant messages only)

**Key observations**:
1. **No source citations**: The answer displays raw content without linking back to which content items or documents were used
2. **No confidence indicator**: There's no visual cue about answer reliability
3. **No copy button on the entire answer**: Only code blocks have copy buttons (via MarkdownContent), not the full response
4. **No feedback mechanism**: Users can't rate answers as helpful/unhelpful
5. The metadata footer shows technical metrics (tokens, cost) but not user-relevant ones (sources used, confidence)

### 3.4 SSE Streaming Hook (`lib/hooks/useChatStream.svelte.ts`)

**File**: `src/lib/hooks/useChatStream.svelte.ts` (317 lines)

**Event handling**:

| Event Type | Stage | Action |
|------------|-------|--------|
| `start` | - | Reset state, capture message_id |
| `init_text` | 1 | Append to stage1Content |
| `system_init` | 1 | Format and append to stage1Content |
| `system_hook` | 1 | Format hook events to stage1Content |
| `stream_token` | 1 | Append token to stage1Content |
| `assistant` | 2 | Set stage2Content (replaces) |
| `result` | 2 | Set stage2Content + metadata, close stream |
| `error` | - | Set error state, close stream |
| `heartbeat` | - | No-op (keep-alive) |
| `chunk` | legacy | Append to stage1Content |
| `complete` | legacy | Fallback content capture, close stream |

**Key observations**:
1. **No reconnection logic**: If the SSE connection drops, `onerror` sets status to 'error' and disconnects permanently. No retry/backoff.
2. **Stage 2 content arrives as a complete replacement** (`stage2Content = data.content`), not incrementally. This means the user sees nothing in the primary area until the full answer is ready. The streaming experience is only visible in Stage 1 (expandable accordion).
3. **No streaming of the actual answer text**: `STREAM_TOKEN` goes to Stage 1 (expandable), and `ASSISTANT` event arrives as complete content. Users don't see the answer being typed character by character.
4. Backend-side behavior is the bottleneck - the SSE protocol supports token-level streaming but the backend sends the complete assistant message as one event.

### 3.5 Markdown Rendering (`lib/utils/markdown.ts`)

**File**: `src/lib/utils/markdown.ts` (325 lines)

**Features**:
- `marked` for Markdown → HTML conversion
- `DOMPurify` for XSS sanitization (whitelist-only)
- `Shiki` for syntax highlighting (9 languages supported)
- Copy buttons on code blocks with "Copied!" feedback
- Streaming support: auto-closes incomplete code fences
- External links get `rel="noopener noreferrer" target="_blank"`

**Quality**: Well-implemented with security-first approach (DOMPurify config is strict). The streaming code fence handling is a nice touch for live rendering.

### 3.6 API Client & Hooks

**File**: `src/lib/api/client.ts` (742 lines)
**File**: `src/lib/api/hooks.ts` (534 lines)

**Chat-related API surface**:

| Operation | Client Method | Hook | Cache Strategy |
|-----------|--------------|------|----------------|
| Send message | `sendChatMessage()` | `useSendChatMessageMutation()` | Invalidates chat list |
| List messages | `listChatMessages()` | `useChatMessagesQuery()` | staleTime: 0, gcTime: 60s |
| Get message | `getChatMessage()` | `useChatMessageQuery()` | staleTime: 30s |
| Delete message | `deleteChatMessage()` | `useDeleteChatMessageMutation()` | Removes + invalidates |
| Clear history | `clearChatHistory()` | `useClearChatHistoryMutation()` | Removes all + invalidates |
| Export history | `exportChatHistory()` | `useExportChatHistoryMutation()` | No caching |
| Export single | `exportSingleMessage()` | `useExportSingleMessageMutation()` | No caching |
| Get stream URL | `getFullStreamUrl()` | (used in stream hook) | N/A |

**All methods use Zod runtime validation**, which provides excellent type safety at the API boundary.

### 3.7 Content Management UI

**File**: `src/lib/components/sessions/AddContentForm.svelte` (643 lines)
**File**: `src/lib/components/sessions/ContentList.svelte` (345 lines)

The content management UI allows:
- Adding text, URLs, multi-URL (link extraction), git repos, documents
- Viewing content list with type icons, status badges, size, timestamps
- Deleting content items with confirmation

**Key observation**: Content management is on the "Overview" tab, completely separated from the "Chat" tab. When chatting, users have no visibility into what content they're querying or how much of it is relevant to their question.

### 3.8 Session Navigation

**File**: `src/lib/components/layout/SessionTabs.svelte` (93 lines)

Tabs: **Chat** | Overview | Indexing | Audit Log | Settings

Chat is listed first, indicating it's the primary interaction mode. However, the tab separation means switching between understanding content and asking questions requires navigation.

---

## User Flow Analysis

### 4.1 Happy Path: First Question in a Session

```
1. User navigates to /sessions/{id}/chat
     │
     ├─ IndexStatusQuery fires → checks if session is indexed
     │
2. IF NOT INDEXED:
     │  ├─ Warning banner: "Session not indexed"
     │  ├─ Textarea disabled, placeholder: "Index session to enable chat"
     │  └─ User must navigate to Indexing tab → trigger index → return to Chat
     │
3. IF INDEXED:
     │  ├─ Empty state: MessageSquare icon + "No messages yet"
     │  ├─ Textarea active, placeholder: "Ask about your session content..."
     │
4. User types question, presses Ctrl+Enter or clicks Send
     │
5. POST /api/v1/sessions/{id}/chat → { message_id, stream_url }
     │  ├─ Input cleared immediately
     │  ├─ User message appears (via query refetch)
     │
6. EventSource connects to stream_url
     │  ├─ Stage 1: Process output accumulates (hidden in accordion)
     │  ├─ Streaming indicator: "Typing..." with spinner
     │  ├─ If Stage 1 only: "Generating response..." placeholder
     │
7. Stage 2 arrives: Full answer replaces placeholder
     │  ├─ Markdown rendered with Shiki highlighting
     │  ├─ Auto-scroll to bottom
     │
8. Complete event: Metadata footer appears
     │  ├─ Duration, token count, cost
     │  └─ Export button becomes visible on hover
```

### 4.2 Error Paths

```
Network Error During Streaming:
  → "Connection lost" error message below messages
  → Stream stops, no retry
  → User must manually re-ask the question

Session Not Indexed:
  → Warning banner with instructions
  → Chat input disabled
  → No direct action (must navigate to Indexing tab)

Send Message Failure:
  → Error handled by TanStack Query
  → Console error logged
  → No user-visible retry option
  → Input was already cleared (content lost!)
```

### 4.3 Content → Question Flow (Cross-Tab)

```
Overview Tab                    Chat Tab
┌──────────────┐              ┌──────────────┐
│ Add Content  │              │              │
│ [Text/URL/   │──navigate──→│ Ask Question │
│  File/Repo]  │              │              │
│              │              │ Answer with  │
│ Content List │   no link    │ NO reference │
│ (5 items)    │←─back to────│ to sources   │
│              │              │              │
└──────────────┘              └──────────────┘

Missing: Bidirectional context between content and questions
```

---

## Component Deep Dive

### 5.1 Streaming UX Timing

The two-stage streaming creates a specific user experience timeline:

```
Time  0s: User submits question
Time  0s: Input cleared, "Sending..." mutation pending
Time ~1s: Stream connects → "Connecting..."
Time ~2s: Stage 1 starts → Init text, hooks (hidden in accordion)
Time ~3s: Stage 1 continues → "Generating response..." shown in primary area
Time ~5-30s: Stage 2 arrives → Full answer appears at once
Time ~5-30s: Complete event → Metadata footer, export button

User perception:
  0-1s: "My question was sent"
  1-5s: "Something is happening" (spinner, accordion activity)
  5s+:  "Answer appeared all at once"
```

**This is fundamentally different from ChatGPT-style token streaming** where users see words appear incrementally. The current UX shows the answer as a "big reveal" after the processing phase.

### 5.2 Responsive Design

Mobile breakpoint at 480px:
- Chat container removes max-height constraint
- Input actions stack vertically
- Session tabs use smaller font with horizontal scroll

Desktop layout:
- Session detail maxes at 1500px width
- Chat area uses `calc(100vh - 300px)` height
- Messages area scrollable with smooth auto-scroll

### 5.3 Accessibility

**Good**:
- Expandable accordion has `aria-expanded` and `aria-controls`
- Session tabs use `role="tablist"` and `aria-selected`
- Focus-visible styles on all interactive elements
- Keyboard support for accordion (Enter/Space)

**Missing**:
- Live region announcements for streaming status changes
- ARIA labels on the send button states
- Screen reader announcement when answer completes
- No skip-to-content for the message list

---

## Gap Analysis

### 6.1 Source Citations & Evidence

**Current**: Assistant answers contain no references to which content items were used to formulate the response. The backend uses `claude-mpm` which internally does retrieval, but this context is not surfaced.

**Impact**: Users cannot verify answer accuracy, cannot trace claims back to source material, and cannot assess whether the system used the right content.

**API Gap**: The `ChatMessageResponse` schema has no field for source citations. The SSE stream events don't include retrieval results.

### 6.2 Confidence Indicators

**Current**: No indication of answer quality or confidence. All answers look equally authoritative regardless of whether the system found strong relevant content or is generating based on weak context.

**Impact**: Users may over-trust weak answers or under-trust strong ones. No way to calibrate expectations.

### 6.3 Answer Quality Feedback

**Current**: No mechanism for users to rate answers. The only actions are export and delete.

**Impact**: No feedback loop for improving the system. No way to flag incorrect or incomplete answers.

### 6.4 Context Visibility

**Current**: The Chat tab shows only messages. Users must navigate to Overview tab to see content. No indication of which/how much content is indexed.

**Impact**: Users ask questions without understanding the knowledge base scope. Leads to questions that can't be answered by the available content.

### 6.5 Streaming Answer Text

**Current**: `STREAM_TOKEN` events go to Stage 1 (expandable/hidden). The primary answer area shows "Generating response..." until the complete `assistant` event arrives.

**Impact**: Long wait times (5-30s+) with no visible progress in the answer area. Users don't get the "typing" experience that makes chat AI feel responsive.

### 6.6 Suggested Follow-ups

**Current**: After an answer, the chat simply waits for the next input. No suggested follow-up questions.

**Impact**: Users may not know what else to ask. Missed opportunity to guide deeper exploration.

### 6.7 Search/Retrieval Transparency

**Current**: The retrieval process is invisible. Stage 1 shows system init and hooks but not the actual search queries or retrieved chunks.

**Impact**: Users can't understand why certain answers were given or why some topics yield poor results.

### 6.8 Error Recovery

**Current**:
- Stream errors have no retry mechanism
- Failed sends lose the user's input (cleared before confirmation)
- SSE disconnect is permanent (no reconnection)

**Impact**: Poor resilience. Users lose work on failures.

### 6.9 Answer Copy

**Current**: Only code blocks within markdown have copy buttons. No way to copy the full answer.

**Impact**: Users must manually select and copy assistant responses.

### 6.10 Chat Context Indicators

**Current**: No display of how many content items are indexed, when indexing last happened, or how much content is available for Q&A.

**Impact**: Users don't know the scope of what the system can answer.

---

## Recommendations

### Priority 1: Critical (High Impact, Directly Improves Q&A Quality)

#### R1: Add Source Citations to Answers
**Priority**: P0
**Effort**: Large (requires backend API changes)

**What**: Display which content items were used to generate each answer, with clickable references.

**UI Changes**:
- Add a "Sources" section below each assistant message
- Show content item title, type icon, and relevance snippet
- Link to the content item (or preview)

**API Contract Changes Needed**:
- Add `sources` field to `ChatMessageResponse`:
  ```typescript
  sources?: Array<{
    content_id: string;
    title: string;
    content_type: string;
    relevance_score?: number;
    snippet?: string;
  }>;
  ```
- Add source data to SSE `result` event

**Files to modify**:
- `src/lib/components/chat/ChatMessage.svelte` - Add sources section
- `src/lib/api/client.ts` - Update schema
- `src/lib/types/chat.ts` - Add source types
- New component: `src/lib/components/chat/SourceCitations.svelte`

#### R2: Stream Answer Text to Primary Display
**Priority**: P0
**Effort**: Medium (requires backend SSE changes)

**What**: Route `STREAM_TOKEN` events to Stage 2 (primary area) so users see the answer being typed character by character.

**Current**: `STREAM_TOKEN` → `stage1Content` (hidden accordion)
**Proposed**: `STREAM_TOKEN` → `stage2Content` (visible primary area), with `assistant` event confirming final content

**Files to modify**:
- `src/lib/hooks/useChatStream.svelte.ts`:72-95 - Route STREAM_TOKEN to stage2Content
- `src/lib/components/chat/ChatMessage.svelte` - Already handles streaming content display
- Backend: Emit STREAM_TOKEN events with answer content, not just process output

#### R3: Preserve Input on Send Failure
**Priority**: P1
**Effort**: Small

**What**: Don't clear the textarea until the message is confirmed sent. If the send fails, restore the input.

**Current flow** (`SessionChat.svelte:122-128`):
```typescript
inputContent = '';  // Cleared BEFORE await
const response = await $sendMutation.mutateAsync(...);
```

**Proposed flow**:
```typescript
const savedContent = inputContent;
inputContent = '';
try {
  const response = await $sendMutation.mutateAsync(...);
} catch {
  inputContent = savedContent; // Restore on failure
}
```

**Files to modify**:
- `src/lib/components/chat/SessionChat.svelte`:119-148

### Priority 2: High (Significant UX Improvement)

#### R4: Add Context Panel / Content Summary in Chat
**Priority**: P2
**Effort**: Medium

**What**: Show a collapsible sidebar or header in the Chat tab that summarizes what content is available for Q&A.

**Design**:
```
┌──────────────────────────────────────┐
│ Session: "OAuth Research"            │
│ 5 items indexed | Last indexed: 2m   │
│ [Text(2) | URL(2) | PDF(1)]         │
│ ▸ View content details              │
├──────────────────────────────────────┤
│ Chat messages...                     │
```

**Files to modify**:
- `src/routes/sessions/[id]/chat/+page.svelte` - Add content summary query
- New component: `src/lib/components/chat/ChatContextBar.svelte`

#### R5: Add Answer Copy Button
**Priority**: P2
**Effort**: Small

**What**: Add a "Copy" button next to the Export button on assistant messages.

**Files to modify**:
- `src/lib/components/chat/ChatMessage.svelte`:152-166 - Add copy button in header

#### R6: SSE Reconnection with Backoff
**Priority**: P2
**Effort**: Medium

**What**: Implement exponential backoff reconnection when SSE connection drops.

**Current** (`useChatStream.svelte.ts:227-233`):
```typescript
eventSource.onerror = () => {
  error = 'Connection lost';
  status = 'error';
  disconnect();
};
```

**Proposed**: Add retry logic with 1s, 2s, 4s, 8s backoff up to 3 retries.

**Files to modify**:
- `src/lib/hooks/useChatStream.svelte.ts`:226-238

#### R7: Suggested Follow-up Questions
**Priority**: P2
**Effort**: Medium (requires backend)

**What**: After an answer completes, show 2-3 suggested follow-up questions as clickable chips.

**API Changes Needed**:
- Add `suggested_questions` field to SSE `result` or `complete` event
- Or generate client-side based on the answer content

**Files to modify**:
- `src/lib/components/chat/ChatMessage.svelte` - Add suggestions section
- `src/lib/components/chat/SessionChat.svelte` - Handle suggestion click → fill input
- New component: `src/lib/components/chat/SuggestedQuestions.svelte`

### Priority 3: Medium (Polish & Enhancement)

#### R8: Confidence/Quality Indicator
**Priority**: P3
**Effort**: Medium (requires backend)

**What**: Display a visual confidence indicator on each answer based on retrieval quality.

**Options**:
- Traffic light (green/yellow/red) based on relevance scores
- Text label: "High confidence" / "Limited sources" / "No direct matches"
- Percentage bar

**API Changes Needed**:
- Add confidence metadata to ChatMessage or SSE result event

#### R9: Answer Feedback (Thumbs Up/Down)
**Priority**: P3
**Effort**: Medium (requires new API endpoint)

**What**: Allow users to rate answers with thumbs up/down, with optional text feedback.

**New API endpoint needed**:
- `POST /api/v1/sessions/{session_id}/chat/{message_id}/feedback`

**Files to modify**:
- `src/lib/components/chat/ChatMessage.svelte` - Add feedback buttons
- `src/lib/api/client.ts` - Add feedback method
- `src/lib/api/hooks.ts` - Add feedback mutation

#### R10: Live Region Announcements for Accessibility
**Priority**: P3
**Effort**: Small

**What**: Add ARIA live regions to announce streaming status changes to screen readers.

**Files to modify**:
- `src/lib/components/chat/SessionChat.svelte` - Add `aria-live="polite"` region
- `src/lib/components/chat/ChatMessage.svelte` - Announce when answer completes

#### R11: Search Preview Before Asking
**Priority**: P3
**Effort**: Large (requires Search API - currently planned)

**What**: Before submitting a question, show a preview of relevant content that would be used. This leverages the planned `POST /api/v1/sessions/{session_id}/search` endpoint.

**Dependency**: Search API endpoint (currently marked as "Planned" in API contract)

#### R12: Optimistic UI for User Messages
**Priority**: P3
**Effort**: Small

**What**: Show the user's message immediately in the chat (with a "sending" indicator) rather than waiting for the API response and query refetch.

**Files to modify**:
- `src/lib/components/chat/SessionChat.svelte`:91-101 - Add optimistic message to displayMessages

---

## File Reference Index

### Core Chat Files

| File | Purpose | Lines |
|------|---------|-------|
| `src/routes/sessions/[id]/chat/+page.svelte` | Chat page route | 47 |
| `src/lib/components/chat/SessionChat.svelte` | Main chat container | 653 |
| `src/lib/components/chat/ChatMessage.svelte` | Individual message display | 542 |
| `src/lib/components/chat/MarkdownContent.svelte` | Markdown renderer component | 233 |
| `src/lib/components/chat/ExportDialog.svelte` | Export format picker dialog | 337 |
| `src/lib/components/chat/index.ts` | Chat component barrel export | ~5 |
| `src/lib/hooks/useChatStream.svelte.ts` | SSE streaming hook (Svelte 5 Runes) | 317 |
| `src/lib/types/chat.ts` | Chat streaming type definitions | 154 |
| `src/lib/utils/markdown.ts` | Markdown parsing + Shiki + DOMPurify | 325 |
| `src/lib/utils/download.ts` | Blob download utility | ~10 |

### API Layer Files

| File | Purpose | Lines |
|------|---------|-------|
| `src/lib/api/client.ts` | API client with Zod validation | 742 |
| `src/lib/api/hooks.ts` | TanStack Query hooks for all endpoints | 534 |
| `src/lib/api/generated.ts` | Auto-generated types from OpenAPI | auto |
| `src/lib/api/errors.ts` | ApiError class | ~30 |
| `src/lib/api/queryKeys.ts` | TanStack Query key definitions | ~50 |
| `src/lib/api/reactiveQuery.svelte.ts` | Svelte 5 reactive store adapter | ~30 |

### Session/Content Management Files

| File | Purpose | Lines |
|------|---------|-------|
| `src/routes/sessions/[id]/+page.svelte` | Session overview with content | 382 |
| `src/routes/sessions/[id]/+layout.svelte` | Session detail layout | 105 |
| `src/routes/sessions/[id]/+layout.ts` | Session ID extraction | ~10 |
| `src/lib/components/sessions/ContentList.svelte` | Content items list | 345 |
| `src/lib/components/sessions/AddContentForm.svelte` | Add content form (5 types) | 643 |
| `src/lib/components/sessions/MultiUrlSelector.svelte` | Multi-URL link extractor | ~300 |
| `src/lib/components/layout/SessionTabs.svelte` | Tab navigation | 93 |
| `src/lib/components/layout/SessionHeader.svelte` | Session name/description | ~80 |

### Layout & Shared

| File | Purpose | Lines |
|------|---------|-------|
| `src/routes/+layout.svelte` | Root layout | ~20 |
| `src/lib/components/layout/AppShell.svelte` | App shell with header | 34 |
| `src/lib/components/layout/Header.svelte` | Top navigation header | ~60 |
| `src/lib/components/layout/Sidebar.svelte` | Session list sidebar | ~100 |
| `src/lib/stores/ui.ts` | UI state (sidebar, theme) | 22 |
| `src/lib/stores/toast.ts` | Toast notification store | ~50 |
| `src/app.css` | Global CSS design system | 220 |

### API Contract

| File | Purpose |
|------|---------|
| `docs/api-contract.md` | Full API contract (v1.8.0) |

---

## Summary of Key Findings

1. **The Q&A system is architecturally sound** with clean separation of concerns, type safety, and a well-designed streaming protocol.

2. **The biggest UX gap is lack of source citations** - users cannot verify where answers come from or assess their reliability.

3. **Streaming feels like a "big reveal"** rather than progressive typing because answer tokens go to the hidden expandable section, not the primary display.

4. **Content and chat are siloed in separate tabs** with no cross-referencing, making it hard for users to understand the scope of what they're querying.

5. **Error recovery is weak** - no SSE reconnection, no input preservation on failures, no retry mechanisms.

6. **The foundation is excellent for improvements** - the two-stage SSE architecture, Zod validation, TanStack Query caching, and component structure all provide strong foundations for adding citations, confidence indicators, and enhanced streaming.

---

*Research completed 2026-02-06. All file paths relative to `research-mind-ui/` unless otherwise noted.*
