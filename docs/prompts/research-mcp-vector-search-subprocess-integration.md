# Research Prompt: mcp-vector-search Subprocess Integration

**Status**: PENDING APPROVAL
**Date Created**: 2026-01-31
**Target Agent**: Research
**Deliverable**: `docs/research2/mcp-vector-search-subprocess-integration-research.md`

---

## Executive Summary

This research investigates how to integrate **mcp-vector-search as a subprocess** within research-mind-service, replacing the previous (incorrect) assumption that mcp-vector-search could be embedded as a Python library.

The new architecture:

1. **Indexing**: research-mind-service spawns `mcp-vector-search index/reindex` subprocess with workspace directory as working directory
2. **Search**: Deferred to later phase (user will query through Claude Code interface, which uses mcp-vector-search MCP)
3. **Index Storage**: Automatic within sandbox directory (`.chromadb/`, embeddings cache, etc.)
4. **Isolation**: Each workspace maintains its own independent mcp-vector-search instance and index

---

## Research Objectives

Investigate and document the following aspects of mcp-vector-search CLI integration:

### 1. CLI Commands & Capabilities

**Investigate**:

- Exact signature and behavior of `mcp-vector-search index` command
- Exact signature and behavior of `mcp-vector-search reindex` command
- Differences between `index` and `reindex` (when to use each)
- All CLI flags and options (especially `--help`, `--project-root`, `--force`, etc.)
- Exit codes and error handling (what indicates success vs. failure)
- How mcp-vector-search determines "project root" if not explicitly specified

**Document**:

- Complete CLI reference with examples
- When to use `index` vs. `reindex`
- Error conditions and how to detect them from subprocess exit code

### 2. Subprocess Working Directory Behavior

**Investigate**:

- How does mcp-vector-search determine which directory to index?
- If we change process working directory to `/path/to/sandbox` before spawning, will it automatically index that directory?
- Does mcp-vector-search search for `.git/` or other markers to find project root?
- What happens if we run `mcp-vector-search index` from within the sandbox directory?
- Can we pass an explicit project root via CLI flag (e.g., `--project-root /path/to/sandbox`)?

**Document**:

- Exact mechanism for working directory detection
- Step-by-step example: "To index `/tmp/my-workspace`, do X, Y, Z"
- Confirmed working approach with code example

### 3. Index Storage & Artifacts

**Investigate**:

- Where are index artifacts stored (`.chromadb/`, embeddings cache, etc.)?
- Are they stored relative to project root or working directory?
- If mcp-vector-search is run from `sandbox/` as working directory, where do artifacts live?
- What files/directories should NOT be committed to version control?
- How large is a typical index for a medium-sized codebase (e.g., 100 files, 50k LOC)?

**Document**:

- Complete list of artifact files/directories and their purposes
- Directory structure after indexing
- Disk space requirements and performance characteristics

### 4. Incremental Indexing (index vs. reindex)

**Investigate**:

- What does `mcp-vector-search reindex` do differently from `index`?
- Does `reindex` detect which files changed since last index?
- Does `reindex` require the index to already exist, or can it create one?
- What's the performance difference (time, resources) between `index` and `reindex`?
- Are there file change detection mechanisms (watching, checksums, timestamps)?

**Document**:

- Decision tree: when to use `index` vs. `reindex`
- Performance comparison with metrics
- Change detection strategy (if any)

### 5. Subprocess Integration Patterns

**Investigate**:

- Typical subprocess invocation in Python (using `subprocess`, `subprocess.run`, etc.)
- How to handle stdout/stderr from mcp-vector-search
- Timeout handling (what's a reasonable timeout for typical workspaces?)
- How to detect success/failure from exit code
- Handling of signals/interrupts

**Document**:

- Python code example: subprocess invocation with error handling
- Recommended timeout values
- Logging/debugging patterns

### 6. Multiple Workspace Isolation

**Investigate**:

- Can two separate `mcp-vector-search` processes run simultaneously on different workspace directories?
- Do they interfere with each other?
- Is there any shared state or locking mechanism?
- If two processes try to index the same directory, what happens?

**Document**:

- Confirmed: Each instance maintains isolated index
- Thread-safety / process-safety characteristics
- Concurrency limitations (if any)

---

## Constraints & Assumptions

Based on earlier discovery:

- ✅ **Confirmed**: mcp-vector-search exposes **MCP tools** (search_code, index_project, etc.) via MCP protocol
- ✅ **Confirmed**: mcp-vector-search uses **stdio transport** (one client only)
- ✅ **Confirmed**: mcp-vector-search is **NOT** embeddable as a Python library
- ✅ **New assumption**: mcp-vector-search CLI can be invoked as subprocess to index/reindex

**Verify during research**:

- That the above assumption is correct
- That subprocess invocation doesn't require special setup or configuration

---

## Research Methodology

1. **CLI Exploration**:

   - Run `mcp-vector-search --help` to see available commands
   - Run `mcp-vector-search index --help` and `mcp-vector-search reindex --help`
   - Document exact output

2. **Practical Testing** (in `/Users/mac/workspace/research-mind/mcp-vector-search` directory):

   - Create a test directory with sample Python files
   - Run `mcp-vector-search index` from that directory
   - Observe what artifacts are created
   - Measure time, disk space, memory usage
   - Run `mcp-vector-search reindex` on the same directory
   - Compare performance

3. **Source Code Review**:

   - Examine mcp-vector-search source code (available locally in monorepo)
   - Look for CLI entry points, argument parsing
   - Understand how working directory / project root is determined
   - Identify any undocumented flags or behaviors

4. **Documentation Review**:
   - Check if mcp-vector-search has official docs on CLI usage
   - Look for README, docs/, examples/ in the project
   - Note any version-specific behaviors

---

## Deliverable Format

Create `docs/research2/mcp-vector-search-subprocess-integration-research.md` with the following structure:

```markdown
# mcp-vector-search Subprocess Integration Research

**Date**: 2026-01-31
**Researcher**: [Agent Name]
**Status**: DRAFT (requires approval before implementation)

## 1. CLI Reference

### 1.1 `mcp-vector-search index`

[Complete documentation with examples]

### 1.2 `mcp-vector-search reindex`

[Complete documentation with examples]

### 1.3 Other Relevant Commands

[Any other commands worth noting]

## 2. Working Directory & Project Root

[How mcp-vector-search determines what to index]
[Confirmed approach with example]

## 3. Index Storage & Artifacts

[Where artifacts are stored]
[Complete file listing]
[Disk space requirements]

## 4. Incremental Indexing Strategy

[index vs. reindex decision tree]
[Performance characteristics]

## 5. Subprocess Integration

[Python code example]
[Error handling]
[Timeout recommendations]
[Logging patterns]

## 6. Multi-Instance Isolation

[Confirmation of isolation]
[Concurrency characteristics]

## 7. Testing Results

[Test setup and results]
[Performance measurements]
[Artifacts observed]

## 8. Open Questions & Gaps

[Any unresolved questions]
[Limitations discovered]
[Recommendations for clarification]

## 9. Architecture Decision Summary

[Clear summary of what IS possible with subprocess integration]
[What is NOT possible]
[Recommended approach for research-mind-service]
```

---

## Acceptance Criteria

The research document must:

- [ ] Contain complete, accurate CLI reference for `index` and `reindex` commands
- [ ] Include step-by-step example of "index a sandbox directory from Python"
- [ ] Confirm isolation between multiple mcp-vector-search instances
- [ ] Provide Python code example for subprocess invocation with error handling
- [ ] Document where index artifacts are stored and their purposes
- [ ] Compare performance of `index` vs. `reindex`
- [ ] Address all 6 research objectives above
- [ ] Clearly distinguish between "confirmed working," "untested," and "not possible"
- [ ] Include actual test results and measurements
- [ ] Be ready for immediate handoff to implementation planning phase

---

## Critical Notes for Researcher

⚠️ **Do not make assumptions** — verify everything through:

1. CLI `--help` output
2. Actual testing with sample directories
3. Source code inspection (available in `mcp-vector-search/` directory in monorepo)

⚠️ **Focus on practical integration** — the goal is to make research-mind-service spawn `mcp-vector-search index` as a subprocess when a new workspace is registered.

⚠️ **Test isolation thoroughly** — confirm that two separate `mcp-vector-search` processes don't interfere with each other's indexes.

⚠️ **Document for developers** — future engineers will use these findings to implement Phase 1.1 service architecture. Be clear and specific.

---

## Success Metrics

- [ ] All 6 research objectives fully addressed
- [ ] At least 3 practical examples with working code
- [ ] Performance metrics documented
- [ ] Isolation verified through testing
- [ ] Clear, actionable recommendations for implementation team
- [ ] Ready for user approval before proceeding to Phase planning updates

---

## Next Steps (After User Approval)

Once this research is approved:

1. **Update research documentation** to correct legacy assumptions
2. **Update implementation plans** to reflect subprocess architecture
3. **Rename plan documents** as needed to match new approach
4. **Begin Phase 1.1 detailed planning** with subprocess integration as foundation
