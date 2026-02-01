# Goal

Do a FINAL verification audit of the phased plan docs in:

- docs/plans/

…against research sources in:

- docs/research/
- docs/research2/

I want you to catch:

- omissions (important requirements/constraints not covered)
- contradictions (plan conflicts with research)
- unjustified plan items (plan claims without research support)
- sequencing/dependency errors across phases
- “looks fine but will fail in reality” issues (operability, testing, security, migration, rollout)

This is an AUDIT, not a rewrite-first task.

# Files in scope

Plans (treat ordering by filename prefix):

- docs/plans/IMPLEMENTATION_ROADMAP.md
- docs/plans/IMPLEMENTATION_PLAN.md
- docs/plans/00-PHASE_1_0_ENVIRONMENT_SETUP.md
- docs/plans/01-PHASE_1_FOUNDATION.md
- docs/plans/01_1_1-SERVICE_ARCHITECTURE.md
- docs/plans/01_1_2-SESSION_MANAGEMENT.md
- docs/plans/01_1_3-INDEXING_OPERATIONS.md
- docs/plans/01_1_4-PATH_VALIDATOR.md
- docs/plans/01_1_5-AUDIT_LOGGING.md
- docs/plans/01_1_6-AGENT_INTEGRATION.md
- docs/plans/01_1_7-INTEGRATION_TESTS.md
- docs/plans/01_1_8-DOCUMENTATION_RELEASE.md
- docs/plans/02-PHASE_2_COST_QUALITY.md
- docs/plans/03-PHASE_3_RERANKING_UX.md
- docs/plans/04-PHASE_4_OPERATIONS_SCALE.md

Research sources:

- docs/research/\*
- docs/research2/\*

Important: docs/research/PLAN_VS_RESEARCH_ANALYSIS.md and docs/research2/IMPLEMENTATION_PLAN_ANALYSIS.md are “analysis artifacts”.
Use them as hints, but ALWAYS verify claims by tracing back to primary research docs, not just those analyses.

# Outputs (must create these files)

Create a directory docs/verification/ and write:

1. docs/verification/verification-report.md
2. docs/verification/traceability-matrix.md
3. docs/verification/fixlist.md

# Hard rules

- Do not invent facts.
- Every finding must cite:
  - plan file + section heading (or a short snippet)
  - AND at least one research source file + section heading/snippet that supports or conflicts
- If research is unclear, mark “UNRESOLVED” and state what proof is missing and how to obtain it.
- Prefer high-signal issues. Skip bikeshedding.
- Severity levels: Blocker / High / Medium / Low.
- Focus especially on: dependency ordering, feasibility, security/privacy, operational readiness, testing/rollout completeness, and interface/data contract correctness.

# Method

## Step 0 — Build an inventory (lightweight)

- Enumerate plan files and research files.
- Extract a compact structure per plan file:
  - goals/outcomes
  - deliverables
  - dependencies/prereqs
  - interfaces/contracts mentioned (API, CLI, filesystem, IPC)
  - acceptance criteria / definition-of-done (if missing, note it)
  - rollout / backout plan (if missing, note it)

## Step 1 — Extract “Research Claims” index

From docs/research and docs/research2, extract the key claims into an internal list:

- requirements (functional + non-functional)
- constraints (stack decisions, deployment constraints, sandboxing/containment, packaging/install)
- risks and mitigations
- integration specifics (especially MCP vector search integration docs)
- open questions

Represent each claim with:

- Claim ID (C###)
- summary
- source (file + section)
- confidence (High/Med/Low)

## Step 2 — Traceability mapping (bidirectional)

A) Claims → Plan coverage

- For every High-confidence claim, find where it’s addressed in the plan phases.
- If not addressed: OMISSION (severity depends on impact).

B) Plan items → Research justification

- For each major deliverable/task in plans, map to one or more claims.
- If no supporting claim: UNJUSTIFIED (ask if it should be removed or research added).

## Step 3 — Cross-phase sequencing & dependency validation

Check for:

- prerequisites missing before dependent tasks
- phase gates missing (what makes it safe to move on)
- integration tests introduced too late or without required scaffolding
- operational items postponed until it’s too late (logging/metrics/runbooks/alerts)

## Step 4 — Critical issue checklist (must explicitly evaluate)

Security/containment:

- sandbox boundaries, subprocess containment, file access controls
- secrets handling
- authn/authz if any external surface exists
- audit logging completeness and tamper-resistance assumptions

Reliability/operability:

- metrics/logs/tracing strategy
- failure modes + retries/backoff/idempotency
- runbooks and incident response
- rollout/backout plan

Data correctness:

- indexing consistency, re-index strategy, reconciliation
- path validation edge cases
- session lifecycle edge cases

Quality/testing:

- contract tests (API/IPC)
- integration/e2e coverage aligned with risks
- performance/cost tests if cost/quality is a phase

## Step 5 — Write output files

### 1) verification-report.md

Include:

- Overall confidence (High/Med/Low) with a blunt explanation
- Top 5 critical issues (Blocker/High)
- Top 5 omissions
- Top 5 sequencing/dependency errors
- Findings table grouped by:
  - OMISSION / CONTRADICTION / UNJUSTIFIED / VAGUE / SEQUENCING / RISK
    Each row:
- ID
- Severity
- Type
- Plan ref
- Research ref
- Why it matters
- Recommended fix (concrete)

### 2) traceability-matrix.md

Two tables:

- Claims → Plan coverage (Claim ID, claim, source, covered-by or MISSING)
- Plan → Claim justification (Plan item, phase file, supported Claim IDs or UNJUSTIFIED)

### 3) fixlist.md

Prioritized tasks:

- [P0/P1/P2] Task summary (file:section)
  - Reason
  - Evidence (plan ref + research ref)
  - Proposed patch (exact bullets or small text edits)

# Execution instructions

- Use ripgrep-style searching to connect terms across docs.
- When quoting, keep it short (<=2 lines); otherwise reference headings.
- Be strict: if a plan depends on something not proven in research, mark it.

Now execute the audit and create the three output files in docs/verification/.
