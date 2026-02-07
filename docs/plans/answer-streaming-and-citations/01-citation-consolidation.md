# Plan 01: Citation Consolidation

**Tier**: 1 (Do Immediately)
**Scope**: research-mind-service (CLAUDE.md template) + research-mind-ui (remove duplicate display)
**Goal**: Consolidate the two parallel citation mechanisms into a single structured approach using `SourceCitation` metadata + DB enrichment, and remove the competing markdown "Sources" section.
**Depends On**: None
**Effort**: 0.5-1 day

---

## Rationale

The devil's advocate analysis (Doc #10, "CC-3: The Two Citation Systems Problem Is Getting Worse, Not Better") identifies that the system currently has **two parallel citation mechanisms** that may both render for the same answer, creating user confusion:

1. **Inline markdown Citations** (from CLAUDE.md instructions): Claude generates a `## Sources` or `## References` section at the end of answers. The frontend detects this via regex in `wrapSourcesSection()` and styles it as a colored box with an accent bar.

2. **Structured SourceCitation metadata** (from `extract_citations()` regex): The backend extracts backtick-wrapped file paths from the answer text, creates `SourceCitation` objects, and sends them in the `complete` event metadata. The frontend renders these in a separate `sources-panel` below the answer.

Both mechanisms extract information from the **same answer text**. Both display citation-like content. Neither currently links to actual content files. Showing both creates visual noise and confuses users about which is authoritative.

The devil's advocate recommends (Doc #10, CC-3): **Pick ONE citation approach and commit to it. The structured SourceCitation path (regex extraction + DB enrichment) is the better choice because it's deterministic, machine-parseable, and extensible.**

---

## Current State

### Mechanism 1: Inline Markdown Sources Section

**Source of instruction**: `SANDBOX_CLAUDE_MD_TEMPLATE` in `research-mind-service/app/services/session_service.py`

The template includes:
```
## Output Format
- Include a "Sources" section at the end listing the files you referenced.
```

This causes Claude to produce text like:
```markdown
## Sources
- `079044a5/content.md` - Implementation plan
- `3f2a1b7c/content.md` - API reference
```

**Frontend rendering**: `research-mind-ui/src/lib/utils/markdown.ts` line 265-274:
```typescript
function wrapSourcesSection(html: string): string {
  const sourcesPattern = /<h2[^>]*>(Sources|References)<\/h2>/i;
  // ... wraps in <div class="sources-section">
}
```

**CSS styling**: `research-mind-ui/src/lib/components/chat/MarkdownContent.svelte` lines 211-245:
- Left border accent (3px solid)
- Background highlight
- Smaller heading (uppercase)

### Mechanism 2: Structured SourceCitation Metadata

**Backend extraction**: `research-mind-service/app/services/chat_service.py` line 402-436:
```python
def extract_citations(content: str) -> list[SourceCitation]:
    path_pattern = rf"`((?:{uuid_full}|{uuid_short})/[^`]+)`"
    # ... extracts file_path, content_id, title
```

**Schema**: `research-mind-service/app/schemas/chat.py` line 106-115:
```python
class SourceCitation(BaseModel):
    file_path: str
    content_id: str | None
    title: str
```

**Frontend rendering**: `research-mind-ui/src/lib/components/chat/ChatMessage.svelte` lines 245-260:
```svelte
{#if displayMetadata()?.sources?.length}
  <div class="sources-panel">
    <h4>Sources</h4>
    <ul>{#each ... as source}<li><code>{source.title}</code></li>{/each}</ul>
  </div>
{/if}
```

### The Problem: Both Render Simultaneously

When Claude produces an answer with backtick-wrapped file paths AND a "## Sources" section, the user sees:

```
[Answer text with inline `079044a5/content.md` references]

┌─ Sources Section (from markdown) ─────────────┐
│ ## Sources                                      │
│ - 079044a5/content.md - Implementation plan     │
│ - 3f2a1b7c/content.md - API reference           │
└─────────────────────────────────────────────────┘

Sources (from metadata panel)
  content.md (079044a5...)
  content.md (3f2a1b7c...)
```

Two citation displays, same data, different formats. This is confusing.

---

## Implementation Plan

### Decision: Keep Structured SourceCitation, Remove Markdown Sources

**Why structured wins**:
- Deterministic: regex extraction is predictable, not subject to LLM formatting variation
- Extensible: can add `source_url`, `content_title`, `content_type` fields (Plan 02)
- Machine-parseable: enables click-to-navigate, expandable previews (Plan 05)
- Single rendering path: one component, one style, one behavior

**Why markdown Sources loses**:
- LLM-dependent: Claude may format Sources differently each time
- Unstructured: plain text, not parseable for linking
- Duplicate: shows the same information as structured citations
- Fragile: regex detection of `## Sources` heading may miss variants

### Step 1: Update CLAUDE.md Template to Remove Sources Section Instruction

**File**: `research-mind-service/app/services/session_service.py`

Find the `SANDBOX_CLAUDE_MD_TEMPLATE` string and modify the "Output Format" section.

**Current** (approximate):
```
## Output Format

- Use markdown formatting for structure (headings, lists, code blocks).
- Include a "Sources" section at the end listing the files you referenced.
- For code questions, include relevant code snippets with file paths.
```

**Proposed**:
```
## Output Format

- Use markdown formatting for structure (headings, lists, code blocks).
- Cite sources inline by referencing file paths in backticks (e.g., "According to `{content_id}/file.md`...").
- For code questions, include relevant code snippets with file paths.
- Do NOT include a separate "Sources" or "References" section at the end. Inline citations are sufficient.
```

The key change: remove the instruction to produce a `## Sources` section, and explicitly tell Claude NOT to produce one. This eliminates the markdown Sources mechanism at the source (the LLM instruction).

### Step 2: Remove `wrapSourcesSection()` from Markdown Parser

**File**: `research-mind-ui/src/lib/utils/markdown.ts`

The `wrapSourcesSection()` function (line 265-274) wraps any `## Sources` or `## References` heading in a styled container. Since we no longer instruct Claude to produce this section, the wrapper is unnecessary.

**Change**: Remove the `wrapSourcesSection()` function definition and its call site within `parseMarkdown()`.

If there is concern about backward compatibility (existing persisted messages that have a Sources section), keep `wrapSourcesSection()` but reduce its styling to be visually minimal -- a simple separator line rather than a prominently styled box. This way, old messages still render acceptably, but new messages won't have the section at all.

**Recommended approach**: Keep the function but make it a no-op for now:
```typescript
function wrapSourcesSection(html: string): string {
  // Deprecated: No longer wrapping sources section.
  // Claude is now instructed to cite inline only.
  // Keeping function signature for backward compatibility.
  return html;
}
```

### Step 3: Remove Sources Section CSS

**File**: `research-mind-ui/src/lib/components/chat/MarkdownContent.svelte`

Remove or comment out the `.sources-section` CSS styles (lines 211-245). Since `wrapSourcesSection()` no longer wraps anything, the CSS class is unreachable.

If keeping backward compatibility (Step 2 alternative), keep the CSS but simplify it to a subtle separator:
```css
.sources-section {
  margin-top: 1rem;
  padding-top: 0.75rem;
  border-top: 1px solid var(--border-color, #e0e0e0);
  font-size: 0.85em;
  opacity: 0.8;
}
```

### Step 4: Verify Structured SourceCitation Rendering

**File**: `research-mind-ui/src/lib/components/chat/ChatMessage.svelte`

Confirm the `sources-panel` renders correctly as the **sole** citation display. Currently (lines 245-260):

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

No changes needed here for this plan. The sources-panel becomes the single citation display. Plan 02 will enhance this with enriched metadata (source URLs, titles).

### Step 5: Update Existing Sandboxes (Optional)

Existing session sandboxes still have the old CLAUDE.md that instructs Claude to produce a Sources section. Two options:

**Option A (recommended)**: Don't retroactively update. Old sessions may still produce Sources sections from persisted answers. The reduced CSS styling (Step 3) handles this gracefully. New sessions get the updated template automatically.

**Option B**: Write a migration script to update all existing sandbox CLAUDE.md files:
```python
# scripts/update_sandbox_claude_md.py
from pathlib import Path
from app.services.session_service import SANDBOX_CLAUDE_MD_TEMPLATE

sandboxes_root = Path("content_sandboxes")
for sandbox_dir in sandboxes_root.iterdir():
    if sandbox_dir.is_dir():
        claude_md = sandbox_dir / "CLAUDE.md"
        if claude_md.exists():
            claude_md.write_text(SANDBOX_CLAUDE_MD_TEMPLATE)
```

---

## Files Modified

| File | Changes |
|------|---------|
| `research-mind-service/app/services/session_service.py` | Update `SANDBOX_CLAUDE_MD_TEMPLATE` -- remove Sources section instruction, add "Do NOT include Sources section" |
| `research-mind-ui/src/lib/utils/markdown.ts` | Make `wrapSourcesSection()` a no-op (or remove) |
| `research-mind-ui/src/lib/components/chat/MarkdownContent.svelte` | Simplify/remove `.sources-section` CSS |

No API contract changes. No database changes. No new files. No schema changes.

---

## API Contract Impact

None. The CLAUDE.md template is an internal instruction, not part of the API contract. The structured `SourceCitation` schema (API contract v1.9.0) is unchanged and remains the single citation mechanism.

---

## Acceptance Criteria

1. New sessions do NOT produce a `## Sources` section in Claude's answers
2. Structured `SourceCitation` metadata still appears in the `complete` event
3. The `sources-panel` in `ChatMessage.svelte` is the only citation display
4. Existing persisted messages with Sources sections render gracefully (not broken)
5. `extract_citations()` still correctly extracts backtick-wrapped file paths

---

## Validation

1. Create a new session with content
2. Ask 5 questions
3. Verify:
   - Claude cites file paths inline (in backticks)
   - Claude does NOT produce a `## Sources` section at the end
   - The `sources-panel` shows extracted citations
   - No duplicate citation displays
4. Load an old session with existing messages that have Sources sections
5. Verify old messages render acceptably (Sources section is subtle/minimal, not prominent)

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Claude still produces Sources section despite instruction not to | Medium | Low | The instruction "Do NOT include" is explicit; iterate on wording if needed |
| Removing Sources section reduces citation visibility | Low | Medium | Inline backtick citations + structured panel provide same information |
| Old persisted messages look broken without Sources CSS | Low | Low | Keep minimal CSS for backward compatibility |
| `extract_citations()` depends on Claude using backtick format | Medium | Medium | The CLAUDE.md instruction explicitly requests backtick format; already working in current system |

---

## Relationship to Other Plans

- **Plan 02 (Citation Enrichment)** builds directly on this plan's outcome. With only one citation mechanism, enrichment is straightforward -- enhance `SourceCitation` with DB-sourced metadata.
- **Plan 05 (Future)** can add click-to-navigate and expandable previews to the single `sources-panel`, without worrying about a competing markdown display.

---

## Research References

- Doc #06 Section 2.1-2.2: Describes both citation mechanisms and how they flow
- Doc #06 Section 5.1 (Cross-Cutting Concerns): Identifies the duplicate display problem
- Doc #07 Section 2.2: Current citation extraction status (Plan 06 partially implemented)
- Doc #08 Section 2.1: Confirms citations are NOT generated by claude-mpm
- Doc #10 CC-3: "The Two Citation Systems Problem Is Getting Worse, Not Better" -- recommends picking ONE approach
- Doc #10 Recommended Implementation Order, Tier 1, #4: "Consolidate citation approach"
