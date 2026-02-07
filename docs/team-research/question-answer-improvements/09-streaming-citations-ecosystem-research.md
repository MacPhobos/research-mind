# Claude MPM Skills & Agents Ecosystem Research: Streaming Progress + Citation Enhancement

**Date**: 2026-02-07
**Researcher**: Research Agent (skills-agents-ecosystem)
**Task**: #5 - Research claude-mpm-skills & agents ecosystem for citation and progress support
**Context**: Investigating whether the skills/agents ecosystem can support structured progress reporting and citation metadata production for the Research Mind Q&A system.

---

## Executive Summary

The claude-mpm-skills and claude-mpm-agents ecosystems currently have **no built-in support for structured progress reporting** or **structured citation metadata**. Agent status communication relies on the SendMessage/TaskUpdate tools (text-based, unstructured), and citation handling exists only as free-text formatting conventions in agent prompts (e.g., `[Source: filename.ext, Section]`). However, the ecosystem's architecture is highly extensible and several concrete modification paths exist for both capabilities.

**Key Findings**:
1. **Progress reporting**: Agents report status via `SendMessage` and `TaskUpdate` (text blobs) with no structured intermediate markers. The PM tracks progress via TodoWrite/TaskUpdate states (`pending` → `in_progress` → `completed`), but this is task-level granularity, not step-level.
2. **Citation handling**: The research agent has citation formatting instructions in its prompt (text templates), but produces free-text citations, not structured metadata. The DSPy skill has a RAG example with `citations` as a field, but this is a code example, not a runtime capability.
3. **Feasibility**: Both capabilities can be added through (a) new skills defining output schemas, (b) agent prompt modifications, or (c) a combination. Skills are the preferred mechanism because they don't require agent rebuilds.

---

## Part 1: Skills/Agents for Progress Reporting

### 1.1 Current State of Progress Reporting

#### How Agents Currently Report Status

**Mechanism 1: TaskUpdate (Primary)**
- Agents use `TaskUpdate` with status field: `pending` → `in_progress` → `completed`
- Granularity: **task-level only** (no sub-step tracking)
- The `activeForm` field provides a present-continuous description shown as a spinner label
- Example: `TaskUpdate(taskId="5", status="in_progress", activeForm="Researching authentication patterns")`
- **Limitation**: Binary state transitions, no intermediate progress markers

**Mechanism 2: SendMessage (Inter-agent communication)**
- Agents use `SendMessage` with `type: "message"` to send DMs to team lead or peers
- Content is free-text (plain string), no structured schema
- Summary field is 5-10 words for UI preview
- **Limitation**: Unstructured text, no machine-parseable progress data

**Mechanism 3: PM TodoWrite Tracking**
- From `PM-INSTRUCTIONS.md:140-150`: PM uses TodoWrite with states `pending`, `in_progress`, `completed`, `ERROR - Attempt X/3`
- This tracks delegated tasks from PM's perspective, not agent internal progress
- **Limitation**: PM-centric, not agent-emitted

**Mechanism 4: Handoff Protocol (BASE-AGENT.md:65-80)**
- Agents include structured handoff information when completing work:
  - Which agent should continue
  - Summary of accomplished work
  - Remaining tasks for next agent
  - Relevant context and constraints
- **Limitation**: Only at completion, not during execution

#### What's Missing

There is **no mechanism** for agents to emit structured progress markers **during** execution. Specifically:
- No progress event schema (e.g., `{phase: "searching", step: 3, total: 5, detail: "Found 12 matches"}`)
- No standardized intermediate output format
- No way for the orchestrator to parse agent progress beyond task state changes
- No concept of "milestones" within a task
- No progress percentage or step counting

#### Relevant Patterns in the Ecosystem

**1. Response Format Templates (`templates/response-format.md`)**
- Defines structured JSON schema for PM session summaries
- Includes: `session_summary.approach`, `delegation_summary.tasks_delegated`, `verification_results`
- Pattern: This structured output approach could be adapted for progress markers
- Key insight: The ecosystem already has precedent for structured JSON output from agents

**2. Circuit Breakers (`templates/circuit-breakers.md`)**
- Automatic violation detection mechanisms that monitor agent behavior
- Pattern: If agents can be monitored for violations, they could also be monitored for progress emissions
- The circuit breaker pattern demonstrates that agent output CAN be parsed and acted upon

**3. Progressive Disclosure in Skills (`CLAUDE.md` for skills repo)**
- Skills use `progressive_disclosure` YAML frontmatter with entry/full content tiers
- Pattern: Progressive loading could inspire progressive progress reporting

### 1.2 Proposed Modifications for Progress Reporting

#### Option A: New Skill - "Structured Progress Reporting" (Recommended)

Create a new skill that instructs agents on how to emit progress markers as structured comments or output blocks during execution.

**Proposed Skill: `universal-collaboration-progress-reporting`**

```yaml
---
name: progress-reporting
description: Structured progress emission patterns for agent execution transparency
progressive_disclosure:
  entry_point:
    summary: "Emit structured progress markers during agent execution"
    when_to_use:
      - "Long-running research or analysis tasks"
      - "Multi-step implementation work"
      - "When orchestrator needs intermediate status"
    quick_start:
      - "Emit PROGRESS markers at each phase transition"
      - "Use structured JSON within text output"
      - "Include phase, step, total, and detail fields"
  token_estimate:
    entry: 80
    full: 2000
---

# Structured Progress Reporting

## Progress Marker Format

When executing multi-step tasks, emit progress markers as structured blocks:

### Standard Marker (in agent text output)
<!-- PROGRESS: {"phase": "searching", "step": 2, "total": 5, "detail": "Scanning 47 files for auth patterns"} -->

### Phase Transitions
Recognized phases: planning, searching, analyzing, synthesizing, capturing

### Emission Rules
- Emit at each major phase transition
- Emit when significant work is completed within a phase
- Include quantifiable metrics when available (files scanned, matches found)
- Keep detail field under 100 characters
```

**Advantages**:
- No agent rebuild required (skill loaded at startup)
- Can be selectively deployed per project
- Progressive disclosure keeps token cost low (~80 entry tokens)
- Agents naturally incorporate skill instructions into their behavior

**Limitations**:
- Relies on agent compliance (soft enforcement, not hard protocol)
- Output is in agent text stream, needs parsing by orchestrator
- No guarantee of consistent emission timing

#### Option B: Agent Prompt Modification

Modify the Research agent (`agents/universal/research.md`) to include progress emission instructions directly in its prompt.

**Location to modify**: After "Research Methodology" section (line ~630), add:

```markdown
## Progress Reporting

During multi-step research, emit structured progress markers:

### At Each Phase
1. **Planning**: <!-- PROGRESS: {"phase": "planning", ...} -->
2. **Discovery**: <!-- PROGRESS: {"phase": "searching", ...} -->
3. **Analysis**: <!-- PROGRESS: {"phase": "analyzing", ...} -->
4. **Synthesis**: <!-- PROGRESS: {"phase": "synthesizing", ...} -->
5. **Capture**: <!-- PROGRESS: {"phase": "capturing", ...} -->
```

**Advantages**:
- Direct integration with research agent's existing methodology
- Can be specific to research phases (not generic)
- Hard-coded in agent template, guaranteed to be present

**Limitations**:
- Requires agent rebuild (`build-agent.py --all`)
- Requires redeployment to all projects using the research agent
- Only affects research agent; other agents need separate modifications

#### Option C: Modify BASE-AGENT.md (Ecosystem-Wide)

Add progress reporting to `agents/BASE-AGENT.md` so ALL agents inherit the behavior.

**Location**: After "Output Format Standards" section (line ~43):

```markdown
## Progress Reporting

All agents should emit structured progress markers during long-running tasks:

### When to Emit
- Task will take more than 30 seconds
- Multiple distinct phases in the work
- Orchestrator benefits from intermediate visibility

### Format
<!-- PROGRESS: {"phase": "...", "step": N, "total": M, "detail": "..."} -->
```

**Advantages**: Universal, all agents inherit the behavior
**Limitations**: May add unnecessary overhead to simple agents; requires full rebuild

#### Recommendation

**Option A (New Skill)** is the best approach because:
1. No rebuilds required
2. Selective deployment (only projects that need progress reporting)
3. Can evolve independently of agent templates
4. Follows the ecosystem's existing pattern of skills providing behavioral guidance
5. Can be combined with Option B for research-specific enhancements later

### 1.3 How Progress Markers Would Flow to the Service

```
Agent Text Output (with PROGRESS markers)
    ↓
Claude Code API Response (streamed)
    ↓
claude-mpm orchestrator (parses text, extracts markers)
    ↓
research-mind-service (receives structured progress events)
    ↓
SSE stream to research-mind-ui (real-time progress display)
```

**Critical dependency**: The claude-mpm orchestrator (the PM or the Task tool runner) would need to be taught to parse `<!-- PROGRESS: {...} -->` markers from agent output and forward them as structured events. This is a claude-mpm runtime change, not a skills/agents change.

---

## Part 2: Skills/Agents for Citation Enhancement

### 2.1 Current Citation Handling in the Ecosystem

#### Research Agent Citation Instructions

From `agents/universal/research.md` (the Q&A Assistant design, lines 560-600 in previous research):

```
### Citation Extraction
- Every claim must reference specific source documents
- Use format: [Source: filename.ext, Section/Page]
- If information comes from multiple sources, cite all
- If no source supports a claim, explicitly state it
```

**Assessment**: This is a **text-level instruction** in the agent prompt. It tells the agent to produce citations in a specific text format, but:
- No structured metadata schema (just text patterns)
- No machine-parseable citation data
- No file path resolution (just filenames, not absolute paths)
- No page/section coordinates that could link to specific content
- No separation between citation display text and citation metadata

#### DSPy Skill Citation Pattern

From `toolchains/ai/frameworks/dspy/SKILL.md` (lines 995-1044):

```python
self.generate = dspy.ChainOfThought(
    "question, context -> answer, citations"
)
# ...
return dspy.Prediction(
    answer=result.answer,
    citations=result.citations,
    passages=candidates
)
```

**Assessment**: This is a **code example** showing how to structure citations in a DSPy RAG pipeline. It demonstrates:
- Citations as a distinct output field (separate from answer)
- Citations linked to passages (source material)
- Machine-parseable output structure (Prediction object)

**Relevance**: This pattern could inform our citation metadata schema. The key insight is separating `answer` from `citations` from `passages/sources`.

#### Work Capture Citations

From the research agent's work capture system (`research.md`, lines 188-196):

```
- Use descriptive filenames: {topic}-{type}-{YYYY-MM-DD}.md
- Include structured sections: Summary, Questions, Findings, Recommendations, References
```

**Assessment**: The "References" section in research outputs is the closest existing pattern to structured citations, but it's still a markdown section, not structured metadata.

#### PM Response Format Citations

From `templates/response-format.md`:

```json
"assertions_made": {
    "claim1": "evidence_source (e.g., 'QA verified with curl', 'Engineer confirmed in logs')",
    "claim2": "verification_method"
}
```

**Assessment**: The PM tracks claims→evidence mappings, which is structurally similar to answer→citation mappings. This is the closest existing structured citation pattern in the ecosystem.

### 2.2 What Skills Know About Session Sandbox Paths

**Finding: Skills have NO awareness of session sandbox file paths.**

Skills are static markdown files loaded at startup as system prompt context. They:
- Cannot access runtime state (file paths, session IDs, working directories)
- Cannot reference dynamic content (sandbox contents change per session)
- Provide behavioral guidance, not runtime data

**However, agents CAN access file paths** via their tools:
- `Read` tool provides file contents with line numbers
- `Glob` tool finds files by pattern
- `Grep` tool searches content within files
- These tools return absolute paths that could be captured as citation metadata

The gap is: agents use these tools to find information but don't capture tool invocation metadata (which file, which line numbers) as structured citation data alongside the answer.

### 2.3 Existing Citation-Related Skills or Patterns

**No dedicated citation skill exists** in the claude-mpm-skills repository (110 skills scanned).

The closest patterns are:
1. **`universal-web-api-documentation`**: Provides API documentation patterns, but no citation metadata
2. **`toolchains-ai-frameworks-dspy`**: Has RAG+citation code examples (described above)
3. **`universal-data-json-data-handling`**: JSON processing patterns that could format citation metadata
4. **`toolchains-ai-techniques-session-compression`**: Context management that could preserve citation chains
5. **`universal-main-skill-creator`**: The skill creation guide that could be used to create a citation skill

No skill handles:
- Web scraping with source attribution
- Content caching with provenance tracking
- Structured citation metadata production
- Source reference linking/resolution

### 2.4 Proposed Modifications for Citation Enhancement

#### Option A: New Skill - "Structured Citation Production" (Recommended)

Create a skill that instructs agents to produce structured citation metadata alongside their answers.

**Proposed Skill: `universal-data-citation-metadata`**

```yaml
---
name: citation-metadata
description: Structured citation metadata production for research and Q&A answers
progressive_disclosure:
  entry_point:
    summary: "Produce machine-parseable citation metadata alongside text answers"
    when_to_use:
      - "Q&A systems requiring source attribution"
      - "Research outputs needing provenance tracking"
      - "Any answer that references specific documents or files"
    quick_start:
      - "Include CITATIONS block after answer text"
      - "Use JSON array of citation objects"
      - "Each citation: source_file, location, excerpt, confidence"
  token_estimate:
    entry: 85
    full: 2500
---

# Structured Citation Metadata

## Citation Schema

When producing answers that reference source documents, include structured citation metadata:

### Citation Block Format (in agent output)
<!-- CITATIONS: [
  {
    "id": "c1",
    "source_file": "docs/architecture.md",
    "source_type": "file",
    "location": {"line_start": 45, "line_end": 52, "section": "Authentication"},
    "excerpt": "The system uses JWT tokens with 24h expiry...",
    "relevance": "direct",
    "confidence": 0.95
  },
  {
    "id": "c2",
    "source_file": "https://example.com/docs/auth",
    "source_type": "url",
    "location": {"section": "Token Management"},
    "excerpt": "Best practice is to use refresh tokens alongside...",
    "relevance": "supporting",
    "confidence": 0.8
  }
] -->

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | Unique citation ID for cross-referencing (c1, c2, ...) |
| source_file | string | yes | File path or URL of the source |
| source_type | enum | yes | "file", "url", "memory", "inference" |
| location | object | no | Where in the source: line_start/end, section, page |
| excerpt | string | yes | Relevant text excerpt (max 200 chars) |
| relevance | enum | yes | "direct" (answers question), "supporting" (corroborates), "contextual" (background) |
| confidence | float | yes | 0.0-1.0 confidence that this source supports the claim |

### Inline Citation References

In the answer text, reference citations with [c1], [c2] markers:

"The authentication system uses JWT tokens [c1] following industry best practices for token lifecycle management [c2]."

### When Source Type is "inference"

When the answer involves reasoning beyond what's directly stated in sources:

{
  "id": "c3",
  "source_file": null,
  "source_type": "inference",
  "location": null,
  "excerpt": "Inferred from combination of auth config and middleware patterns",
  "relevance": "contextual",
  "confidence": 0.6
}
```

**Advantages**:
- Provides a complete, machine-parseable citation schema
- Inline markers [c1] in text connect to structured metadata
- Captures file paths, line numbers, excerpts, and confidence
- Distinguishes source types (file, URL, inference)
- Compatible with existing agent tools (Read returns line numbers, Grep returns file paths)
- No agent rebuild required

**Limitations**:
- Agents must be trained to produce this format (soft enforcement)
- Parsing `<!-- CITATIONS: [...] -->` blocks requires orchestrator support
- Citation quality depends on agent diligence

#### Option B: Modify Research Agent Prompt

Add citation metadata production instructions directly to the research agent:

**Location**: After "Citation Extraction" section in research.md

```markdown
### Structured Citation Metadata

In addition to inline citations, produce a CITATIONS metadata block:

<!-- CITATIONS: [
  {"id": "c1", "source_file": "...", "source_type": "file",
   "location": {"line_start": N, "line_end": M},
   "excerpt": "...", "relevance": "direct", "confidence": 0.9}
] -->

Capture the following from tool outputs:
- From Read tool: file path and line numbers
- From Grep tool: file path, matched lines, surrounding context
- From WebFetch: URL and extracted section
- From WebSearch: URL and result snippet
```

#### Option C: Combined Approach (Recommended for Maximum Coverage)

1. **Create the `universal-data-citation-metadata` skill** (Option A) for ecosystem-wide availability
2. **Also modify the research agent prompt** (Option B) for research-specific citation enhancement
3. **Also add citation tracking to the Q&A Assistant agent design** (from prior research) as a core capability

This gives us:
- Generic skill available to any agent
- Research-specific enhancements
- Q&A-specific integration

### 2.5 How Citation Metadata Would Flow to the Service

```
Agent produces answer with inline markers [c1], [c2]
    + CITATIONS metadata block
    ↓
Claude Code API Response (text with embedded metadata)
    ↓
claude-mpm orchestrator (extracts CITATIONS blocks)
    ↓
research-mind-service receives:
    {
      "answer_text": "The system uses JWT...[c1]...[c2]",
      "citations": [
        {"id": "c1", "source_file": "docs/auth.md", "line_start": 45, ...},
        {"id": "c2", "source_file": "https://...", ...}
      ]
    }
    ↓
research-mind-ui renders:
    - Answer text with clickable citation links
    - Citation panel showing sources with excerpts
    - File-based citations link to sandbox viewer
    - URL-based citations link to external source
```

---

## Part 3: Feasibility Assessment

### 3.1 Progress Reporting Feasibility

| Aspect | Assessment | Confidence |
|--------|-----------|------------|
| Skill creation | **Easy** - standard skill format, ~2000 tokens | HIGH |
| Agent compliance | **Medium** - depends on prompt following, not enforceable | MEDIUM |
| Orchestrator parsing | **Medium** - requires claude-mpm runtime change to extract markers | MEDIUM |
| Service integration | **Easy** - markers map directly to SSE events | HIGH |
| UI rendering | **Easy** - progress bar/stepper component | HIGH |
| **Overall** | **Feasible with moderate effort** | HIGH |

**Effort Estimate**: Skill creation (1 hour) + agent prompt updates (1 hour) + orchestrator parsing (4-8 hours) + service SSE forwarding (2 hours)

### 3.2 Citation Enhancement Feasibility

| Aspect | Assessment | Confidence |
|--------|-----------|------------|
| Skill creation | **Easy** - standard skill format, ~2500 tokens | HIGH |
| Agent compliance | **Medium-High** - research agent already cites, just needs structure | HIGH |
| Schema design | **Done** - proposed schema covers file, URL, inference sources | HIGH |
| Orchestrator parsing | **Medium** - extract CITATIONS blocks from text output | MEDIUM |
| Service integration | **Medium** - new citation model, API changes needed | MEDIUM |
| UI rendering | **Medium** - citation panel, inline linking, source viewer | MEDIUM |
| **Overall** | **Feasible with moderate-high effort** | HIGH |

**Effort Estimate**: Skill creation (1 hour) + agent prompt updates (2 hours) + orchestrator parsing (4-8 hours) + service API (4 hours) + UI citation panel (4-6 hours)

### 3.3 Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Agents ignore skill instructions | Progress/citation data missing | Medium | Combine skill with agent prompt modification (belt + suspenders) |
| Parsing overhead for markers | Latency increase in orchestrator | Low | HTML comments are trivial to regex parse |
| Citation accuracy | Wrong file/line references | Medium | Validate citations against actual file contents before serving |
| Token cost increase | More tokens per agent response | Low | Progress markers: ~50 tokens; citations: ~200-500 tokens |
| Schema evolution | Breaking changes to citation format | Low | Version the schema in the CITATIONS block |

### 3.4 Comparison: Skill vs Agent Modification vs Both

| Criterion | Skill Only | Agent Mod Only | Both (Recommended) |
|-----------|-----------|---------------|-------------------|
| Deployment speed | Fast (no rebuild) | Slow (rebuild required) | Medium |
| Ecosystem coverage | All agents | Single agent | Best of both |
| Enforcement | Soft | Medium | Strongest |
| Maintenance | Independent | Coupled to agent | Slightly more |
| Token overhead | Low | Low | Low (no duplication) |
| Reusability | High (any project) | Low (agent-specific) | High |

---

## Part 4: Integration Architecture Proposal

### 4.1 Proposed New Skills

| Skill Name | Purpose | Tokens (entry/full) | Priority |
|------------|---------|--------------------:|----------|
| `universal-collaboration-progress-reporting` | Structured progress markers | ~80 / ~2000 | P1 |
| `universal-data-citation-metadata` | Structured citation production | ~85 / ~2500 | P1 |

### 4.2 Proposed Agent Modifications

| Agent | Modification | Impact |
|-------|-------------|--------|
| `universal/research.md` | Add progress reporting phases + citation metadata sections | Research-specific enhancements |
| `BASE-AGENT.md` (root) | Add optional progress reporting awareness (3-5 lines) | All agents aware of progress concept |

### 4.3 Proposed Orchestrator Changes (claude-mpm)

| Component | Change | Purpose |
|-----------|--------|---------|
| Agent output parser | Extract `<!-- PROGRESS: {...} -->` blocks | Progress event forwarding |
| Agent output parser | Extract `<!-- CITATIONS: [...] -->` blocks | Citation metadata extraction |
| SendMessage handler | Forward extracted data as structured events | Service integration |

### 4.4 No-Change Items

These elements of the ecosystem do NOT need modification:
- Skill creation process (existing format works)
- Agent build system (`build-agent.py`)
- Agent inheritance chain (BASE-AGENT.md hierarchy)
- Skill manifest format (`manifest.json`)
- Agent auto-deploy logic
- Memory routing system
- Handoff protocol (already adequate for completion)

---

## Part 5: Recommendations

### Immediate Actions (No Ecosystem Changes Required)

1. **Define the citation metadata JSON schema** - Can be done as a specification document before any skill/agent work
2. **Define the progress marker JSON schema** - Same as above
3. **Prototype in the research-mind-service** - Add support for parsing these markers from raw text output, even before agents produce them (enables testing)

### Short-Term (New Skills)

4. **Create `universal-data-citation-metadata` skill** in claude-mpm-skills repo
5. **Create `universal-collaboration-progress-reporting` skill** in claude-mpm-skills repo
6. **Deploy skills to research-mind project** via `configuration.yaml`

### Medium-Term (Agent + Orchestrator)

7. **Modify research agent prompt** to include citation and progress instructions
8. **Add marker extraction to claude-mpm orchestrator** (parsing `<!-- PROGRESS -->` and `<!-- CITATIONS -->` from agent text output)
9. **Connect extracted data to research-mind-service SSE pipeline**

### Long-Term (Ecosystem Enhancement)

10. **Propose formal progress protocol** for claude-mpm (not just text markers, but a dedicated tool or message type)
11. **Add citation validation** - verify cited files/lines exist before serving to UI
12. **Build citation indexing** - pre-index sandbox files for efficient citation linking

---

## Appendix A: Key File Paths Reference

### Skills Repository
| Path | Description |
|------|-------------|
| `/Users/mac/workspace/claude-mpm-skills/manifest.json` | Skill manifest (v1.0.3, 110 skills) |
| `/Users/mac/workspace/claude-mpm-skills/CLAUDE.md` | Skill creation guide |
| `/Users/mac/workspace/claude-mpm-skills/universal/` | Universal skills (35) |
| `/Users/mac/workspace/claude-mpm-skills/toolchains/ai/frameworks/dspy/SKILL.md` | DSPy skill with citation RAG example |

### Agents Repository
| Path | Description |
|------|-------------|
| `/Users/mac/workspace/claude-mpm-agents/agents/BASE-AGENT.md` | Root base agent (handoff protocol, output format) |
| `/Users/mac/workspace/claude-mpm-agents/agents/universal/research.md` | Research agent (v5.0.0, 1254 lines) |
| `/Users/mac/workspace/claude-mpm-agents/agents/universal/code-analyzer.md` | Code analyzer agent |
| `/Users/mac/workspace/claude-mpm-agents/templates/response-format.md` | PM structured JSON output templates |
| `/Users/mac/workspace/claude-mpm-agents/templates/PM-INSTRUCTIONS.md` | PM delegation/tracking instructions |
| `/Users/mac/workspace/claude-mpm-agents/templates/circuit-breakers.md` | Violation detection patterns |

### Research Mind (Deployed)
| Path | Description |
|------|-------------|
| `/Users/mac/workspace/research-mind/.claude/agents/` | 49 deployed agents |
| `/Users/mac/workspace/research-mind/.claude/skills/` | 142 deployed skills |
| `/Users/mac/workspace/research-mind/.claude-mpm/configuration.yaml` | MPM configuration |

---

## Appendix B: Existing Structured Output Patterns

### PM Response Format (agents can learn from this pattern)
```json
{
  "assertions_made": {
    "claim": "evidence_source"
  },
  "verification_results": {
    "evidence_type": "fetch_response|test_output|log_analysis",
    "verification_evidence": "actual output data"
  }
}
```

### Research Agent Work Capture (current)
```
docs/research/{topic}-{type}-{YYYY-MM-DD}.md
Sections: Summary, Questions, Findings, Recommendations, References
```

### Agent Handoff Protocol (current)
```
- Which agent should continue
- Summary of accomplished work
- Remaining tasks for next agent
- Relevant context and constraints
```

### Proposed Progress Marker (new)
```html
<!-- PROGRESS: {"phase": "analyzing", "step": 3, "total": 5, "detail": "Cross-referencing 12 source files"} -->
```

### Proposed Citation Block (new)
```html
<!-- CITATIONS: [
  {"id": "c1", "source_file": "auth.md", "source_type": "file", "location": {"line_start": 45}, "excerpt": "JWT tokens with 24h expiry", "relevance": "direct", "confidence": 0.95}
] -->
```
