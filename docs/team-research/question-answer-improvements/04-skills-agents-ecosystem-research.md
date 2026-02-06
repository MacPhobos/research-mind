# Claude MPM Skills & Agents Ecosystem Research for Q&A Optimization

**Date**: 2026-02-06
**Researcher**: Research Agent
**Task**: #5 - Research claude-mpm skills and agents ecosystem for Q&A optimization
**Context**: Research Mind Q&A system optimization - identifying minimal agent/skill set for fast startup while maintaining Q&A quality

---

## Executive Summary

Research Mind currently deploys **49 agents** and **142 skills** at startup. For a Q&A system answering questions about session sandbox content, this is massively over-provisioned. The project is a Python (FastAPI) + SvelteKit (TypeScript) monorepo, but the Q&A task primarily exercises the **research/analysis** capabilities, not engineering/ops/qa capabilities.

**Key Finding**: Only **5-7 agents** and **15-25 skills** are needed for high-quality Q&A. This represents a **~85% reduction in agents** and **~83% reduction in skills**, which should dramatically reduce startup/sync time from 3-15s to under 1s.

---

## Part 1: Skills Ecosystem Analysis

### Source Repository
- **Location**: `/Users/mac/workspace/claude-mpm-skills/`
- **Total Skills Available**: 110 production-ready skills
- **Manifest**: `manifest.json` (v1.0.3)
- **Structure**: `toolchains/` (language/framework-specific) + `universal/` (cross-cutting)

### Skill Structure Format

Each skill follows this structure:
```
.claude/skills/{category-toolchain-framework}/
  ├── skill.md           # Main skill content (YAML frontmatter + markdown)
  ├── metadata.json      # Metadata (optional)
  └── .etag_cache.json   # Cache for remote updates (optional)
```

**Skill.md Format** (progressive disclosure):
```yaml
---
name: skill-name
description: Brief description
---
progressive_disclosure:
  entry_point:
    summary: "One-line summary"  # 60-200 tokens
    when_to_use: [...]
    quick_start: [...]
  token_estimate:
    entry: 75
    full: 4000-5000
```

**Token Economics**:
- Entry point: 60-200 tokens per skill
- Full documentation: 3,000-18,500 tokens per skill
- Discovery phase (all 110 entries): ~66,690 tokens
- Full load (all 110 skills): ~512,411 tokens
- Progressive loading saves ~87% during discovery

### Currently Deployed Skills in Research Mind (142)

The project currently syncs **142 skills** including:

| Category | Count | Examples |
|----------|-------|---------|
| MPM Framework Skills | 21 | mpm, mpm-config, mpm-doctor, mpm-status, mpm-session-pause/resume, etc. |
| Design/Creative Skills | 8 | skills-canvas-design, skills-doc-coauthoring, skills-theme-factory, etc. |
| AI/LLM Skills | 9 | dspy, langchain, langgraph, mcp, anthropic-sdk, session-compression, etc. |
| Elixir Skills | 4 | ecto-patterns, phoenix-api-channels, phoenix-liveview, phoenix-ops |
| JavaScript Skills | 10 | react, svelte, vue, nextjs, playwright, vite, biome, etc. |
| Next.js Skills | 3 | nextjs-core, nextjs-v16, validated-handler |
| PHP Skills | 5 | wordpress-*, espocrm |
| Python Skills | 9 | asyncio, celery, django, fastapi, flask, pytest, pydantic, mypy, pyright |
| Rust Skills | 2 | desktop-applications, tauri |
| TypeScript Skills | 14 | core, drizzle, kysely, fastify, trpc, turborepo, zustand, zod, etc. |
| UI Skills | 4 | daisyui, headlessui, shadcn, tailwind |
| Platform Skills | 17 | digitalocean-*, vercel-*, netlify, neon, supabase, better-auth-* |
| Universal Skills | 36 | git-workflow, TDD, debugging, api-docs, security-scanning, etc. |

### Complete Skill Catalog from Manifest (110 skills)

#### Toolchains: AI (7 skills)
| Skill | Entry/Full Tokens | Description |
|-------|------------------|-------------|
| anthropic-sdk | 85/5000 | Anthropic Claude API patterns |
| dspy | 75/5500 | Automatic prompt optimization |
| langchain | 85/5200 | LLM application framework |
| langgraph | 80/5800 | Stateful multi-agent orchestration |
| mcp | 78/4850 | Model Context Protocol |
| openrouter | 75/4180 | Unified LLM API access |
| session-compression | 75/5500 | Context window compression |

#### Toolchains: Python (10 skills)
| Skill | Entry/Full Tokens |
|-------|------------------|
| asyncio | 72/4200 |
| celery | 65/5000 |
| django | 85/5000 |
| fastapi-local-dev | 173/1625 |
| flask | 75/4300 |
| mypy | 75/4300 |
| pydantic | 70/5500 |
| pyright | 70/4000 |
| pytest | 70/4200 |
| sqlalchemy | 80/5000 |

#### Toolchains: TypeScript (14 skills)
| Skill | Entry/Full Tokens |
|-------|------------------|
| typescript-core | 180/4500 |
| drizzle-migrations | 250/5000 |
| drizzle-orm | 75/4200 |
| fastify | 130/5200 |
| jest-typescript | 75/4500 |
| kysely | 68/4167 |
| nodejs-backend | 75/4700 |
| prisma-orm | 75/4800 |
| tanstack-query | 70/5500 |
| trpc | 70/5000 |
| turborepo | 70/5500 |
| vitest | 78/3200 |
| zod | 65/5000 |
| zustand | 70/4500 |

#### Toolchains: JavaScript (12 skills)
| Skill | Entry/Full Tokens |
|-------|------------------|
| biome | 70/3500 |
| cypress | 130/5200 |
| express-production | 120/14500 |
| nextjs | 64/1926 |
| playwright | 85/4700 |
| react | 55/4578 |
| react-state-machines | 150/18500 |
| svelte | 85/4500 |
| svelte5-runes-static | 90/6000 |
| sveltekit | 80/5000 |
| vite | 75/4000 |
| vue | 80/5000 |

#### Toolchains: Other Languages
- **Elixir** (4): ecto-patterns, phoenix-api-channels, phoenix-liveview, phoenix-ops
- **Golang** (7): cli, concurrency, database, grpc, http-frameworks, observability, testing
- **Rust** (4): axum, clap, desktop-applications, tauri
- **PHP** (6): espocrm, wordpress-* (5 variants)
- **Next.js** (3): nextjs-core, nextjs-v16, validated-handler

#### Toolchains: Platforms (25 skills)
- DigitalOcean (9): agentic-cloud, compute, containers, databases, management, networking, overview, storage, teams
- Vercel (9): ai, deployments, functions, networking, observability, overview, security, storage, teams
- Better Auth (4): authentication, core, integrations, plugins
- Others (3): neon, netlify, supabase

#### Toolchains: UI (4 skills)
daisyui, headlessui, shadcn-ui, tailwind

#### Toolchains: Universal (7 skills)
api-security-review, dependency-audit, docker, emergency-release, github-actions, graphql, pr-quality-checklist

#### Universal Skills (35 skills)
api-design-patterns, api-documentation, artifacts-builder, brainstorming, bug-fix-verification, condition-based-waiting, database-migration, dispatching-parallel-agents, env-manager, git-workflow, git-worktrees, internal-comms, json-data-handling, kubernetes, mcp-builder, opentelemetry, pre-merge-verification, requesting-code-review, root-cause-tracing, screenshot-verification, security-scanning, skill-creator, software-patterns, stacked-prs, systematic-debugging, terraform, test-driven-development, test-quality-inspector, testing-anti-patterns, threat-modeling, verification-before-completion, web-performance-optimization, webapp-testing, writing-plans, xlsx

### Skill Relevance Rating for Q&A Use Case

#### HIGH Relevance (directly useful for Q&A)

| Skill | Tokens (entry/full) | Why Relevant |
|-------|---------------------|-------------|
| `toolchains-ai-techniques-session-compression` | 75/5500 | Context window management for long Q&A sessions |
| `toolchains-ai-protocols-mcp` | 78/4850 | MCP protocol for tool use in Q&A pipeline |
| `toolchains-ai-sdks-anthropic` | 85/5000 | Claude API patterns for Q&A generation |
| `toolchains-python-validation-pydantic` | 70/5500 | Request/response validation in Q&A API |
| `toolchains-python-frameworks-fastapi-local-dev` | 173/1625 | Backend framework patterns |
| `toolchains-python-async-asyncio` | 72/4200 | Async patterns for concurrent Q&A |
| `universal-debugging-systematic-debugging` | 58/673 | Debugging Q&A pipeline issues |
| `universal-debugging-root-cause-tracing` | 56/1454 | Tracing Q&A failures |
| `universal-data-json-data-handling` | 53/1136 | JSON processing for Q&A data |
| `universal-web-api-design-patterns` | 85/8500 | API patterns for Q&A endpoints |

#### MEDIUM Relevance (useful for development but not Q&A runtime)

| Skill | Tokens (entry/full) | Why Relevant |
|-------|---------------------|-------------|
| `toolchains-python-testing-pytest` | 70/4200 | Testing Q&A functionality |
| `toolchains-python-data-sqlalchemy` | 80/5000 | Database patterns for session storage |
| `toolchains-javascript-frameworks-svelte` | 85/4500 | UI development for Q&A interface |
| `toolchains-javascript-frameworks-sveltekit` | 80/5000 | Frontend framework |
| `toolchains-ui-styling-tailwind` | 75/4500 | UI styling |
| `universal-testing-test-driven-development` | 56/2221 | Test patterns |
| `universal-collaboration-git-workflow` | 62/1862 | Version control |
| `toolchains-universal-infrastructure-docker` | 75/5500 | Containerization |

#### LOW/NONE Relevance (not needed for Q&A)

| Category | Skills Count | Examples |
|----------|-------------|---------|
| Elixir | 4 | ecto, phoenix-* (project doesn't use Elixir) |
| PHP | 6 | wordpress-*, espocrm (project doesn't use PHP) |
| Rust | 4 | axum, clap, desktop-apps, tauri (not used) |
| Golang | 7 | All Go skills (not used) |
| Next.js | 3 | Not used in this project (uses SvelteKit) |
| DigitalOcean | 9 | Platform not in use |
| Vercel | 9 | Platform not in use |
| Better Auth | 4 | Auth library not in use |
| React | 2 | UI framework not in use (uses Svelte) |
| Vue | 1 | UI framework not in use |
| WordPress | 5 | CMS not in use |
| Creative/Design | 8 | canvas-design, theme-factory, etc. |
| Enterprise Infra | 5 | kubernetes, terraform, opentelemetry, threat-modeling |

### Skill Deployment Mechanism

Skills are deployed via `claude-mpm` during startup:
1. MPM reads `configuration.yaml` -> `agent_sync.sources`
2. Fetches skills from GitHub raw content or local cache
3. Writes to `.claude/skills/{skill-name}/skill.md`
4. Claude Code loads all files in `.claude/skills/` at startup as system prompt context

**Critical insight**: Skills are loaded as part of Claude Code's system prompt. More skills = more tokens in every API call = slower and more expensive.

### Creating Custom Skills

Custom skills follow the standard format:
```
.claude/skills/{skill-name}/
  └── skill.md
```

Skill.md requires:
- YAML frontmatter with `name`, `description`
- Progressive disclosure with `entry_point` and `when_to_use`
- Core content sections (Concepts, Patterns, Best Practices, Examples)
- Token budget: entry 60-200, full 3,000-6,000

---

## Part 2: Agents Ecosystem Analysis

### Source Repository
- **Location**: `/Users/mac/workspace/claude-mpm-agents/`
- **Total Agents Available**: 44 agent templates
- **Build System**: `build-agent.py` (Python, flattens inheritance chain)
- **Inheritance**: BASE-AGENT.md at root, category, and subcategory levels

### Agent Structure Format

Each agent is a Markdown file with YAML frontmatter:

```yaml
---
name: Agent Name
description: Agent purpose and capabilities
agent_id: unique-identifier
agent_type: engineer|qa|ops|universal|documentation
model: sonnet|opus|haiku
version: 2.0.0
tags: [...]
category: engineering|qa|ops|research
temperature: 0.2
max_tokens: 4096
timeout: 900
capabilities:
  memory_limit: 2048
  cpu_limit: 50
  network_access: true
dependencies:
  python: [...]
  system: [...]
skills:
  - skill-name-1
  - skill-name-2
---
# Agent-specific instructions...
```

**Build Process**:
```
Agent MD + Directory BASE-AGENT.md + Parent BASE-AGENT.md + Root BASE-AGENT.md
    -> build-agent.py
        -> Flattened agent in dist/agents/
```

**Inheritance Chain Example** (python-engineer):
```
python-engineer.md (150 lines, Python-specific)
  + agents/engineer/BASE-AGENT.md (300 lines, SOLID principles)
  + agents/BASE-AGENT.md (200 lines, universal git/memory/handoff)
= ~650 lines total flattened agent
```

### Complete Agent Catalog (44 agents)

#### Claude MPM Framework Agents (2)
| Agent | File | Q&A Relevance |
|-------|------|--------------|
| MPM Agent Manager | `claude-mpm/mpm-agent-manager.md` | LOW |
| MPM Skills Manager | `claude-mpm/mpm-skills-manager.md` | LOW |

#### Universal Agents (6)
| Agent | File | Q&A Relevance |
|-------|------|--------------|
| **Research** | `universal/research.md` | **HIGH** - codebase investigation, analysis, pattern extraction |
| **Code Analyzer** | `universal/code-analyzer.md` | **HIGH** - code analysis, AST parsing, pattern detection |
| **Memory Manager** | `universal/memory-manager-agent.md` | **MEDIUM** - context retention across Q&A sessions |
| Product Owner | `universal/product-owner.md` | NONE |
| Project Organizer | `ops/project-organizer.md` | NONE |
| Content Agent | `universal/content-agent.md` | LOW |

#### Engineering Agents (25)
| Agent | File | Q&A Relevance |
|-------|------|--------------|
| **Python Engineer** | `engineer/backend/python-engineer.md` | **MEDIUM** - backend Q&A pipeline dev |
| **Svelte Engineer** | `engineer/frontend/svelte-engineer.md` | **MEDIUM** - Q&A UI development |
| Engineer (core) | `engineer/core/engineer.md` | LOW |
| Web UI | `engineer/frontend/web-ui.md` | LOW |
| React Engineer | `engineer/frontend/react-engineer.md` | NONE |
| Next.js Engineer | `engineer/frontend/nextjs-engineer.md` | NONE |
| Go Engineer | `engineer/backend/golang-engineer.md` | NONE |
| Java Engineer | `engineer/backend/java-engineer.md` | NONE |
| JavaScript Engineer | `engineer/backend/javascript-engineer.md` | NONE |
| NestJS Engineer | `engineer/backend/nestjs-engineer.md` | NONE |
| Phoenix Engineer | `engineer/backend/phoenix-engineer.md` | NONE |
| PHP Engineer | `engineer/backend/php-engineer.md` | NONE |
| Ruby Engineer | `engineer/backend/ruby-engineer.md` | NONE |
| Rust Engineer | `engineer/backend/rust-engineer.md` | NONE |
| Dart Engineer | `engineer/mobile/dart-engineer.md` | NONE |
| Tauri Engineer | `engineer/mobile/tauri-engineer.md` | NONE |
| TypeScript Engineer | `engineer/data/typescript-engineer.md` | LOW |
| Data Engineer | `engineer/data/data-engineer.md` | NONE |
| Refactoring Engineer | `engineer/specialized/refactoring-engineer.md` | NONE |
| Prompt Engineer | `engineer/specialized/prompt-engineer.md` | LOW |
| ImageMagick | `engineer/specialized/imagemagick.md` | NONE |
| Agentic Coder Optimizer | `ops/agentic-coder-optimizer.md` | NONE |

#### QA Agents (3)
| Agent | File | Q&A Relevance |
|-------|------|--------------|
| QA | `qa/qa.md` | LOW |
| API QA | `qa/api-qa.md` | LOW |
| Web QA | `qa/web-qa.md` | LOW |

#### Ops Agents (8)
| Agent | File | Q&A Relevance |
|-------|------|--------------|
| Ops (core) | `ops/core/ops.md` | NONE |
| Local Ops | `ops/platform/local-ops.md` | NONE |
| Vercel Ops | `ops/platform/vercel-ops.md` | NONE |
| GCP Ops | `ops/platform/gcp-ops.md` | NONE |
| Clerk Ops | `ops/platform/clerk-ops.md` | NONE |
| DigitalOcean Ops | `ops/platform/digitalocean-ops.md` | NONE |
| Version Control | `ops/tooling/version-control.md` | LOW |
| Tmux Agent | `ops/tooling/tmux-agent.md` | NONE |

#### Security & Documentation (3)
| Agent | File | Q&A Relevance |
|-------|------|--------------|
| Security | `security/security.md` | NONE |
| Documentation | `documentation/documentation.md` | LOW |
| Ticketing | `documentation/ticketing.md` | NONE |

### Currently Deployed Agents in Research Mind (49)

All 44 agents from the repo are deployed plus duplicates (e.g., `qa.md` + `qa-agent.md`, `web-qa.md` + `web-qa-agent.md`, `ops.md` + `ops-agent.md`). This includes every agent regardless of project relevance.

**Total agent lines**: ~29,883 lines across all 49 files.

### Agent Memory Routing

From root `BASE-AGENT.md` (`agents/BASE-AGENT.md:30-41`):

```markdown
## Memory Routing
All agents participate in the memory system:
- Domain-specific knowledge and patterns
- Anti-patterns and common mistakes
- Best practices and conventions
- Project-specific constraints
```

The Memory Manager agent provides:
- Three-tier memory architecture (CLAUDE.md, project, user)
- Dynamic memory loading via runtime hooks (no restart required)
- Memory file size limit: 80KB per file
- Memory consolidation and deduplication
- Cross-agent memory integration

**Q&A Potential**: Memory routing could cache:
- Frequently-asked Q&A patterns
- Common document insights and extracted facts
- Session-specific context for faster repeat queries
- Document structure maps for efficient retrieval

### Auto-Deploy Detection System

From `AUTO-DEPLOY-INDEX.md`:

**Universal (always deployed)**: mpm-agent-manager, memory-manager, research, code-analyzer, documentation, ticketing

**Language detection**: Scans for indicator files (pyproject.toml, package.json, etc.) and deploys relevant engineers + QA + ops + security.

**Override mechanism** via `.claude-mpm/agent-config.json`:
```json
{
  "auto_deploy": true,
  "override_agents": {
    "include": ["specific-agents-to-add"],
    "exclude": ["agents-to-remove"]
  },
  "deployment_priority": ["universal/*", "engineer/*", "qa/*", "ops/*"]
}
```

**Default deployment sets**:
- **Minimal** (micro projects): Universal + primary language engineer + generic QA/Ops
- **Standard** (most projects): All detected language/framework agents
- **Full** (enterprise): All detected + specialized agents

---

## Part 3: Recommendations for Q&A Optimization

### 3.1 Minimal Agent Set for Q&A

#### Runtime Q&A Mode (3 agents - answering questions only)

| Agent | Rationale | Model |
|-------|-----------|-------|
| **Research** | Core Q&A: document investigation, analysis, pattern extraction | sonnet |
| **Code Analyzer** | Document analysis, content understanding, pattern detection | sonnet |
| **Memory Manager** | Session context retention, Q&A pattern caching | haiku |

#### Development Mode (7 agents - building/maintaining Q&A features)

| Agent | Rationale | Model |
|-------|-----------|-------|
| Research | Core analysis | sonnet |
| Code Analyzer | Code analysis | sonnet |
| Memory Manager | Context retention | haiku |
| **Python Engineer** | Backend Q&A pipeline development | sonnet |
| **Svelte Engineer** | Frontend Q&A UI development | sonnet |
| **QA** | Testing Q&A features | sonnet |
| **Version Control** | Git operations | haiku |

#### Agents to EXCLUDE from Q&A deployment (42 of 49)

All agents not listed above, specifically:
- All 20+ language engineers (Go, Java, JS, NestJS, Phoenix, PHP, Ruby, Rust, Dart, Tauri, TypeScript, Data, Core, Web UI, React, Next.js, Refactoring, Prompt, ImageMagick)
- All 6 ops agents (core ops, local-ops, vercel, gcp, clerk, digitalocean)
- API QA, Web QA
- Security
- Documentation, Ticketing
- MPM Agent Manager, MPM Skills Manager
- Product Owner, Content Agent, Project Organizer, Agentic Coder Optimizer, Tmux Agent

### 3.2 Minimal Skill Set for Q&A

#### Core Q&A Skills (always needed - 10 skills, ~684 entry tokens)

| Skill | Entry Tokens | Full Tokens | Purpose |
|-------|-------------|-------------|---------|
| `toolchains-ai-techniques-session-compression` | 75 | 5,500 | Context management |
| `toolchains-ai-protocols-mcp` | 78 | 4,850 | Tool protocol |
| `toolchains-ai-sdks-anthropic` | 85 | 5,000 | Claude API patterns |
| `toolchains-python-validation-pydantic` | 70 | 5,500 | Data validation |
| `toolchains-python-async-asyncio` | 72 | 4,200 | Async patterns |
| `universal-debugging-systematic-debugging` | 58 | 673 | Debugging |
| `universal-debugging-root-cause-tracing` | 56 | 1,454 | Error tracing |
| `universal-data-json-data-handling` | 53 | 1,136 | JSON processing |
| `universal-web-api-design-patterns` | 85 | 8,500 | API patterns |
| `universal-web-api-documentation` | 52 | 2,366 | API docs |

#### Development Skills (when building features - 8 additional)

| Skill | Entry Tokens | Purpose |
|-------|-------------|---------|
| `toolchains-python-frameworks-fastapi-local-dev` | 173 | Backend framework |
| `toolchains-python-testing-pytest` | 70 | Testing |
| `toolchains-python-data-sqlalchemy` | 80 | Database |
| `toolchains-javascript-frameworks-svelte` | 85 | UI framework |
| `toolchains-javascript-frameworks-sveltekit` | 80 | Frontend framework |
| `toolchains-ui-styling-tailwind` | 75 | Styling |
| `universal-testing-test-driven-development` | 56 | TDD |
| `universal-collaboration-git-workflow` | 62 | Git workflow |

#### MPM Framework Skills (minimal - 4 skills)

| Skill | Purpose |
|-------|---------|
| `mpm` | Core MPM framework |
| `mpm-config` | Configuration |
| `mpm-status` | Status checks |
| `mpm-help` | Help reference |

#### Skills to EXCLUDE (120+ of 142 currently deployed)

- All Elixir skills (4)
- All PHP skills (5)
- All Rust skills (2)
- All Golang skills (0 deployed, 7 available)
- All Next.js-specific skills (3)
- All React skills (2)
- All Vue skills (1)
- All DigitalOcean skills (9)
- All Vercel skills (8+)
- All Better Auth skills (4)
- All Creative/Design skills (8)
- All WordPress skills (5)
- Most MPM administrative skills (17 of 21): mpm-bug-reporting, mpm-circuit-breaker-enforcement, mpm-delegation-patterns, mpm-doctor, mpm-git-file-tracking, mpm-init, mpm-postmortem, mpm-pr-workflow, mpm-session-management, mpm-session-pause, mpm-session-resume, mpm-teaching-mode, mpm-ticket-view, mpm-ticketing-integration, mpm-tool-usage-guide, mpm-verification-protocols, mpm-agent-update-workflow
- TypeScript ORM/state skills: drizzle, kysely, prisma, trpc, turborepo, zustand, tanstack-query, zod, fastify, vitest, jest, typescript-core, nodejs-backend
- Platform skills: neon, netlify, supabase, graphql
- Python skills not needed: celery, django, flask, mypy, pyright
- JavaScript tools: biome, playwright, cypress, vite, express, react-state-machines
- UI components: daisyui, headlessui, shadcn
- Enterprise infra: kubernetes, terraform, opentelemetry, threat-modeling
- Universal extras: artifacts-builder, skill-creator, mcp-builder, brainstorming, stacked-prs, git-worktrees, xlsx, internal-comms, env-manager, dispatching-parallel-agents, requesting-code-review, writing-plans, condition-based-waiting, webapp-testing, test-quality-inspector, testing-anti-patterns, security-scanning, software-patterns, database-migration, pre-merge-verification, screenshot-verification, bug-fix-verification, web-performance-optimization, dependency-audit, github-actions, docker, api-security-review, emergency-release, pr-quality-checklist

### 3.3 Custom Agent Design: "Q&A Assistant"

```yaml
---
name: QA Assistant
description: >
  Specialized agent for answering questions about documents in Research Mind
  session sandboxes. Combines document analysis, citation extraction, and
  confidence scoring.
agent_id: qa-assistant
agent_type: research
resource_tier: standard
tags:
  - question-answering
  - document-analysis
  - citation-extraction
  - confidence-scoring
  - research-mind
category: research
temperature: 0.2
max_tokens: 8192
timeout: 300
capabilities:
  memory_limit: 4096
  cpu_limit: 60
  network_access: false
dependencies:
  python: []
  system: []
skills:
  - session-compression
  - systematic-debugging
  - json-data-handling
  - api-design-patterns
---

# Q&A Assistant Agent

You are a specialized question-answering assistant for Research Mind. Your job
is to analyze documents in a session sandbox and provide accurate, cited answers
to user questions.

## Core Capabilities

### Document Analysis
- Read and understand documents in the session sandbox directory
- Extract key entities, concepts, and relationships
- Build a mental model of the document corpus

### Question Answering
- Parse user questions to identify intent and required information
- Search relevant documents for answers
- Synthesize information from multiple sources when needed
- Always cite specific documents and sections

### Citation Extraction
- Every claim must reference specific source documents
- Use format: [Source: filename.ext, Section/Page]
- If information comes from multiple sources, cite all
- If no source supports a claim, explicitly state it

### Confidence Scoring
- Rate confidence: HIGH (>90%), MEDIUM (60-90%), LOW (<60%)
- Factors: number of supporting sources, clarity of evidence, directness
- If confidence is LOW, suggest what additional information would help

## Answer Format

### Answer
[Concise answer to the question]

### Evidence
- [Key point 1] -- [Source: document.pdf, p.3]
- [Key point 2] -- [Source: notes.md, Section "Architecture"]

### Confidence: HIGH/MEDIUM/LOW
[Brief explanation of confidence level]

### Related Questions
- [Suggested follow-up question 1]
- [Suggested follow-up question 2]

## Constraints
- Never fabricate information not found in session documents
- Always distinguish between facts from documents and inferences
- If a question cannot be answered from available documents, say so clearly
- Keep answers concise but complete
```

### 3.4 Custom Skill Design: "Document Q&A Patterns"

**File**: `.claude/skills/research-mind-qa-patterns/skill.md`

```markdown
---
name: document-qa-patterns
description: >
  Patterns for document-based question answering with citation and confidence scoring
---

# Document Q&A Patterns

## Question Processing Pipeline

### 1. Question Classification
- **Factual**: "What is X?" -> Direct lookup
- **Analytical**: "Why does X happen?" -> Multi-source synthesis
- **Comparative**: "How does X compare to Y?" -> Cross-document analysis
- **Procedural**: "How do I do X?" -> Step extraction

### 2. Document Retrieval Strategy
- Full-text search for key terms
- Semantic similarity for conceptual matches
- Section-level granularity for precision
- Cross-reference related documents

### 3. Answer Synthesis
- Start with most relevant source
- Add supporting evidence from other sources
- Note contradictions between sources
- Distinguish facts from inferences

### 4. Citation Format
[Source: filename.ext, Section "heading" or Page N]

### 5. Confidence Scoring
- HIGH (>90%): Direct statement in source, multiple corroborating sources
- MEDIUM (60-90%): Inference from source, single source only
- LOW (<60%): Tangential reference, requires significant interpretation
```

### 3.5 Custom Skill Design: "Research Mind Session Management"

**File**: `.claude/skills/research-mind-session/skill.md`

```markdown
---
name: research-mind-session
description: Session sandbox management patterns for Research Mind Q&A
---

# Research Mind Session Management

## Session Lifecycle

### 1. Session Creation
- Create sandbox directory with unique session ID
- Copy/link source documents
- Build document manifest (filename, type, size, checksum)

### 2. Document Indexing
- Extract text from all documents
- Build full-text search index
- Identify document structure (headings, sections, pages)
- Create document summary for each file

### 3. Q&A Turn Management
- Parse incoming question
- Check Q&A history for context (follow-up detection)
- Execute document search
- Generate answer with citations
- Store Q&A turn in session history

### 4. Session Persistence
- Save session state to database
- Preserve Q&A history for conversation continuity
- Cache document indexes for fast subsequent queries
```

---

## Part 4: Implementation Plan

### 4.1 Configuration Change (Immediate - Zero Code)

Create `.claude-mpm/agent-config.json` with explicit include/exclude:

```json
{
  "auto_deploy": true,
  "override_agents": {
    "include": [
      "universal/research",
      "universal/code-analyzer",
      "universal/memory-manager"
    ],
    "exclude": [
      "engineer/backend/golang-engineer",
      "engineer/backend/java-engineer",
      "engineer/backend/javascript-engineer",
      "engineer/backend/nestjs-engineer",
      "engineer/backend/phoenix-engineer",
      "engineer/backend/php-engineer",
      "engineer/backend/ruby-engineer",
      "engineer/backend/rust-engineer",
      "engineer/core/engineer",
      "engineer/data/data-engineer",
      "engineer/data/typescript-engineer",
      "engineer/frontend/nextjs-engineer",
      "engineer/frontend/react-engineer",
      "engineer/frontend/web-ui",
      "engineer/mobile/dart-engineer",
      "engineer/mobile/tauri-engineer",
      "engineer/specialized/imagemagick",
      "engineer/specialized/prompt-engineer",
      "engineer/specialized/refactoring-engineer",
      "ops/agentic-coder-optimizer",
      "ops/core/ops",
      "ops/platform/clerk-ops",
      "ops/platform/digitalocean-ops",
      "ops/platform/gcp-ops",
      "ops/platform/local-ops",
      "ops/platform/vercel-ops",
      "ops/project-organizer",
      "ops/tooling/tmux-agent",
      "ops/tooling/version-control",
      "qa/api-qa",
      "qa/qa",
      "qa/web-qa",
      "security/security",
      "documentation/documentation",
      "documentation/ticketing",
      "claude-mpm/mpm-agent-manager",
      "claude-mpm/mpm-skills-manager",
      "universal/content-agent",
      "universal/product-owner"
    ]
  }
}
```

### 4.2 Skill Pruning Strategy

Manually remove unwanted skill directories from `.claude/skills/` or configure skill filtering in `configuration.yaml`.

**Skills to KEEP** (22 total, ~1,400 entry tokens):
```
mpm
mpm-config
mpm-status
mpm-help
toolchains-ai-techniques-session-compression
toolchains-ai-protocols-mcp
toolchains-ai-sdks-anthropic
toolchains-python-validation-pydantic
toolchains-python-async-asyncio
toolchains-python-frameworks-fastapi-local-dev
toolchains-python-testing-pytest
toolchains-python-data-sqlalchemy
toolchains-javascript-frameworks-svelte
toolchains-javascript-frameworks-sveltekit
toolchains-ui-styling-tailwind
universal-debugging-systematic-debugging
universal-debugging-root-cause-tracing
universal-data-json-data-handling
universal-web-api-design-patterns
universal-web-api-documentation
universal-testing-test-driven-development
universal-collaboration-git-workflow
```

### 4.3 Custom Agent/Skill Deployment

1. Create `qa-assistant.md` in `.claude/agents/` (Section 3.3)
2. Create `research-mind-qa-patterns/skill.md` in `.claude/skills/` (Section 3.4)
3. Create `research-mind-session/skill.md` in `.claude/skills/` (Section 3.5)

### 4.4 Impact Estimates

| Metric | Current | Optimized (Q&A) | Optimized (Dev) | Reduction |
|--------|---------|-----------------|-----------------|-----------|
| Agents deployed | 49 | 3-4 | 7 | 85-94% |
| Skills deployed | 142 | 14 | 22 | 85-90% |
| Entry tokens (skills) | ~9,500 | ~684 | ~1,400 | 85-93% |
| Agent file lines | ~29,883 | ~3,000 | ~5,000 | 83-90% |
| Estimated startup sync | 3-15s | <1s | <2s | ~90% |

### 4.5 Two-Mode Configuration (Recommended)

Maintain two profiles switchable via environment variable:

**Q&A_MODE=runtime** (minimal, fast):
- 3 agents: Research, Code Analyzer, Memory Manager
- 14 skills: 10 core + 4 MPM
- Optimized for speed and Q&A quality

**Q&A_MODE=development** (full dev capability):
- 7 agents: + Python Engineer, Svelte Engineer, QA, Version Control
- 22 skills: + dev/test/framework skills
- Full development capability with Q&A

---

## Part 5: Key File Paths Reference

### Skills Repository
| Path | Description |
|------|-------------|
| `/Users/mac/workspace/claude-mpm-skills/` | Root directory |
| `/Users/mac/workspace/claude-mpm-skills/manifest.json` | Skill manifest (v1.0.3) |
| `/Users/mac/workspace/claude-mpm-skills/CLAUDE.md` | Skill creation guide |
| `/Users/mac/workspace/claude-mpm-skills/toolchains/` | Language/framework skills (76) |
| `/Users/mac/workspace/claude-mpm-skills/universal/` | Cross-cutting skills (35) |
| `/Users/mac/workspace/claude-mpm-skills/examples/` | Example skill templates |

### Agents Repository
| Path | Description |
|------|-------------|
| `/Users/mac/workspace/claude-mpm-agents/` | Root directory |
| `/Users/mac/workspace/claude-mpm-agents/agents/` | Agent templates (44) |
| `/Users/mac/workspace/claude-mpm-agents/agents/BASE-AGENT.md` | Root-level base agent |
| `/Users/mac/workspace/claude-mpm-agents/build-agent.py` | Build/flatten script |
| `/Users/mac/workspace/claude-mpm-agents/AUTO-DEPLOY-INDEX.md` | Auto-deploy rules |
| `/Users/mac/workspace/claude-mpm-agents/templates/` | Reference materials |

### Research Mind Deployed
| Path | Description |
|------|-------------|
| `/Users/mac/workspace/research-mind/.claude/agents/` | 49 deployed agents |
| `/Users/mac/workspace/research-mind/.claude/skills/` | 142 deployed skills |
| `/Users/mac/workspace/research-mind/.claude-mpm/configuration.yaml` | MPM config |
| `/Users/mac/workspace/research-mind/.claude-mpm/skills_config.json` | Per-agent skill mapping |

### Override Mechanisms
| Path | Description |
|------|-------------|
| `.claude-mpm/agent-config.json` | Agent include/exclude overrides |
| `.claude-mpm/configuration.yaml` -> `agent_deployment.disabled_agents` | Disable specific agents |
| `.claude-mpm/configuration.yaml` -> `agent_deployment.excluded_agents` | Exclude agents from sync |
