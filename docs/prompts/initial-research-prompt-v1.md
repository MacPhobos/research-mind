# Claude Code Prompt — Research-Mind Deep Research (mcp-vector-search + claude-mpm)

> Copy/paste this entire prompt into Claude Code (or your agent runner) at the **monorepo root**.

---

## Goal

Perform **in-depth research** to design and validate the _Research-Mind_ architecture centered on the concept of a **research session sandbox**. Use the existing local clones:

- `mcp-vector-search/` (reference, **read-only**)
- `claude-mpm/` (reference, **read-only**)

Produce a set of **actionable research notes + implementation blueprints** in `docs/research/`.

You must not modify reference projects during research.

---

## Hard Constraints (non-negotiable)

1. **Read-only research phase for reference repos**
   - You may read from:
     - `mcp-vector-search/**`
     - `claude-mpm/**`
   - You must **never** modify anything inside those directories during research.
2. All research outputs must be written under:
   - `docs/research/`
3. Research must assume this architecture boundary:
   - `research-mind-ui` talks only to `research-mind-service`
   - `research-mind-service` talks to:
     - `mcp-vector-search` via a **REST API** (to trigger indexing/search actions)
     - `claude-mpm` as the agent runtime to answer questions using:
       - vector search results from `mcp-vector-search` (scoped to a sandbox)
       - raw sandbox files (scoped to a sandbox)
4. **Scope enforcement is infrastructure-level**: Do not rely on “prompting” alone to keep claude-mpm sandbox-only. Research must identify enforceable controls (path allowlists, server-side session scoping, etc.).

---

## Context / Problem Statement

Understanding internal topics is slow and scattered. Indexing “everything” leads to diluted/incorrect answers. The proposed solution is a **research session sandbox** composed of selected content entities (wiki/docs/pdfs/repos/transcripts) pulled into a session directory. Only that sandbox gets indexed/searched and used for answers.

The system is:

- `research-mind` (ui + service): orchestrates sessions and content ingestion into sandboxes
- `mcp-vector-search`: indexing/search layer (needs REST API additions)
- `claude-mpm`: agentic question answering using sandbox + mcp-vector-search

Known concept problems:

- multi-user spin-up time
- indexing latency
- claude-mpm launch latency
- storage cost/pruning
- LLM/provider cost

---

## What To Research

### A) mcp-vector-search: Indexing / Search / API exposure

Research and document:

1. **Current capabilities**
   - How it indexes directories
   - Supported file types / parsers
   - How chunking/metadata is represented
   - How search works (vector-only vs hybrid, filters, reranking if any)
   - How it stores indices (per directory? per collection? config?)
2. **How to add a REST API (FastAPI preferred) without rewriting core logic**
   - Identify the “entry points” to trigger:
     - initial indexing
     - incremental reindexing
     - entity reindexing (subdir)
     - stats (doc/chunk counts, last indexed time, embed model)
     - search (with mandatory session scoping)
   - Determine best approach:
     - wrapper service that imports mcp-vector-search as a library
     - or embedding REST inside mcp-vector-search
3. **Compartmentalization strategy**
   - How to enforce per-session isolation for indexing/search:
     - separate collections / partitions / namespaces (recommended)
     - enforce `session_id` as mandatory filter
   - Identify what changes are required to support:
     - many sandboxes (multi-tenant)
     - incremental updates
     - dedupe / hashing
4. **Operational characteristics**
   - indexing latency drivers
   - memory/CPU footprint
   - caching opportunities
   - job/queue integration points

**Deliverable**: A concrete API proposal for a `mcp-vector-search` REST surface:

- endpoints
- request/response schemas
- job model (async indexing with progress)
- scoping rules

---

### B) claude-mpm: Sandbox-scoped agent runtime

Research and document:

1. **How to run claude-mpm**
   - How sessions/workspaces are defined
   - How it accesses filesystem
   - How tool/MCP connections are configured
2. **How to ensure claude-mpm uses only sandbox scope**
   - filesystem allowlist enforcement (e.g., only `{SESSION_DIR}`)
   - disable network by default (unless explicitly enabled)
   - enforce that vector-search calls include `session_id` and can’t escape scope
   - how to log tool calls for auditing (search queries, files read)
3. **Agent/skill customization for Research-Mind**
   - identify existing agents/skills patterns that fit:
     - query understanding
     - multi-stage retrieval
     - evidence pack assembly
     - citation + confidence
   - propose a minimal set of agents/skills:
     - “Retriever”
     - “Reranker” (optional)
     - “Synthesizer w/ citations”
     - “Coverage/Gap detector”
4. **Latency and cost controls**
   - warm pools vs per-request startup
   - token budgeting, “cheap mode vs deep mode” policies
   - maximum tool calls per answer
   - caching (retrieval results, summaries)

**Deliverable**: A “runtime containment plan” (practical, enforceable) and a minimal agent strategy for high-precision answers.

---

## Required Outputs (Write These Files)

Create `docs/research/` if it doesn’t exist, then write:

1. `docs/research/mcp-vector-search-capabilities.md`

   - architecture + how indexing/search works today
   - key modules/files (with paths) and why they matter
   - extension points for REST API and session scoping
   - risks/unknowns

2. `docs/research/mcp-vector-search-rest-api-proposal.md`

   - recommended architecture (wrapper vs embedded)
   - endpoint list + schemas
   - async job model (index/reindex)
   - mandatory session scoping rules
   - example requests/responses
   - minimal security considerations

3. `docs/research/claude-mpm-capabilities.md`

   - how to run, configure tools, and scope filesystem access
   - where to implement guardrails
   - key modules/files (with paths)

4. `docs/research/claude-mpm-sandbox-containment-plan.md`

   - enforceable controls (not prompt-only)
   - audit logging plan
   - operational recommendations (warm pool, quotas)

5. `docs/research/combined-architecture-recommendations.md`
   - your final “tell it like it is” recommendations:
     - what to build first
     - what to avoid
     - how to reduce latency/cost
   - an “MVP slice” (smallest usable end-to-end)
   - a “next slice” (improvements: hybrid retrieval, reranking, dedupe, TTL pruning)
   - a short risk register (top 8 risks with mitigations)

---

## Research Method (Do This, Don’t Hand-Wave)

1. **Map the code**
   - Identify key packages/modules and entry points.
   - Write down file paths and brief notes as you go.
2. **Trace the flow**
   - For indexing: find how a directory becomes chunks/embeddings/index.
   - For search: find how a query becomes results + metadata.
3. **Propose minimal changes**
   - Prefer wrappers/adapters over rewrites.
   - Keep the system multi-tenant from day one (session scoping).
4. **Design for observability**
   - indexing job progress and errors
   - search query logs (with session_id)
   - claude-mpm tool call logs
5. **Be explicit about unknowns**
   - If a detail isn’t clear from repo code, list it under “Open Questions” per file.

---

## Acceptance Criteria (Your Work Is “Done” When…)

- All required markdown files exist under `docs/research/`.
- Each document includes concrete file paths and how they connect.
- The REST API proposal includes:
  - job-based indexing
  - stats endpoint
  - search endpoint with mandatory `session_id`
- The containment plan explains enforceable sandbox-only rules (path allowlist + server-side scoping).
- The combined recommendations include a practical MVP and cost/latency controls.

---

## Start Now

You are at the monorepo root. Begin by scanning:

- `mcp-vector-search/README*`, `pyproject.toml`, `src/**` (or equivalent)
- `claude-mpm/README*`, configuration docs, and code modules for tool/FS access

Then produce the required outputs in `docs/research/`.
