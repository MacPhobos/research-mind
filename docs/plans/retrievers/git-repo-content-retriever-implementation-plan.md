# Git Repository Content Retriever Implementation Plan

**Version**: 1.0.0
**Created**: 2026-02-03
**Status**: Awaiting Approval

## Executive Summary

This plan enables users to add Git repositories as content items to research sessions. **The backend GitRepoRetriever is already fully implemented** - this plan focuses on exposing the capability in the UI and adding appropriate validation/display enhancements.

### Scope

| Component                       | Work Required                                       |
| ------------------------------- | --------------------------------------------------- |
| Backend (research-mind-service) | **None** - GitRepoRetriever already implemented     |
| Frontend (research-mind-ui)     | Add git_repo to AddContentForm, validation, display |
| API Contract                    | **None** - git_repo already defined                 |

### Effort Estimate

**Total: ~2-4 hours** (primarily UI work)

---

## Architecture Discovery

### Backend Status: Complete

**GitRepoRetriever** (`research-mind-service/app/services/retrievers/git_repo.py`):

- Shallow cloning with `--depth 1 --single-branch`
- Configurable timeout (default: 120 seconds)
- Configurable clone depth (default: 1)
- Title extraction from URL (repo name)
- Error handling for timeout, git not found, clone failures
- Metadata includes: clone URL, depth, total bytes

**Factory Registration** (`research-mind-service/app/services/retrievers/factory.py`):

```python
ContentType.GIT_REPO: GitRepoRetriever()
```

**Configuration** (`research-mind-service/app/core/config.py`):

```python
git_clone_timeout: int = 120  # seconds
git_clone_depth: int = 1      # shallow clone
```

### API Contract Status: Complete

From `docs/api-contract.md`:

```
ContentType enum:
- text
- url
- file_upload
- git_repo      # Already defined
- mcp_source
```

### Frontend Gap

**AddContentForm.svelte** currently only exposes:

```typescript
const contentTypes = [
  { value: "text", label: "Text" },
  { value: "url", label: "URL" },
];
```

**git_repo is NOT exposed to users**.

---

## Implementation Tasks

### Phase 1: Enable Git Repository Content Type (Required)

#### Task 1.1: Add git_repo to AddContentForm

**File**: `research-mind-ui/src/lib/components/sessions/AddContentForm.svelte`

**Changes**:

1. Add `git_repo` to contentTypes array
2. Add conditional input field for git URL
3. Add client-side validation for git URLs

**Acceptance Criteria**:

- [ ] git_repo appears in content type dropdown
- [ ] Git URL input field shows when git_repo selected
- [ ] Basic URL validation (starts with http/https/git@)
- [ ] Form submits correctly to backend

#### Task 1.2: Add Git URL Validation

**Validation Rules**:

```typescript
function isValidGitUrl(url: string): boolean {
  // HTTPS URLs: https://github.com/user/repo.git
  // SSH URLs: git@github.com:user/repo.git
  // Git protocol: git://github.com/user/repo.git
  const patterns = [
    /^https?:\/\/.+\.git$/,
    /^https?:\/\/[^\/]+\/.+$/, // GitHub/GitLab without .git suffix
    /^git@.+:.+\.git$/,
    /^git:\/\/.+\.git$/,
  ];
  return patterns.some((p) => p.test(url));
}
```

### Phase 2: Display Enhancements (Recommended)

#### Task 2.1: Add Git-Specific Icon

**File**: `research-mind-ui/src/lib/components/sessions/ContentList.svelte`

**Changes**:

```typescript
import { GitBranch, FileText, Link, File } from "lucide-svelte";

function getContentIcon(type: string) {
  switch (type) {
    case "text":
      return FileText;
    case "url":
      return Link;
    case "git_repo":
      return GitBranch; // Add this
    default:
      return File;
  }
}
```

#### Task 2.2: Display Clone Metadata

When displaying git_repo content items, show:

- Repository name (extracted from URL)
- Clone status (success/failed)
- Repository size (from metadata.size_bytes)

### Phase 3: Optional Enhancements (Future)

These are NOT required for initial implementation:

1. **Branch Selection**: Allow users to specify branch (default: default branch)
2. **Commit SHA**: Allow cloning specific commit
3. **Clone Progress**: Add async job polling for large repos
4. **Sparse Checkout**: Clone only specific directories

---

## Testing Requirements

### Unit Tests

1. **Git URL validation**: Test valid/invalid URL patterns
2. **Form submission**: Test git_repo type submits correctly

### Integration Tests

1. **Clone public repo**: Submit git_repo, verify clone completes
2. **Invalid URL**: Submit malformed URL, verify error handling
3. **Display**: Verify git_repo items display correctly in ContentList

### Manual Testing

1. Add a public GitHub repo to a session
2. Verify clone completes within timeout
3. Verify metadata displays correctly
4. Verify error message for invalid URL

---

## Files to Modify

| File                                                                 | Change                                   |
| -------------------------------------------------------------------- | ---------------------------------------- |
| `research-mind-ui/src/lib/components/sessions/AddContentForm.svelte` | Add git_repo type, URL input, validation |
| `research-mind-ui/src/lib/components/sessions/ContentList.svelte`    | Add GitBranch icon                       |

### Files NOT Modified (Already Complete)

- `research-mind-service/app/services/retrievers/git_repo.py`
- `research-mind-service/app/services/retrievers/factory.py`
- `research-mind-service/app/core/config.py`
- `docs/api-contract.md`

---

## Assumptions

1. **No Authentication Required**: Public repos clone without credentials
2. **User Environment Handles Auth**: Private repos use existing git credentials (SSH keys, credential manager)
3. **Shallow Clone Sufficient**: `--depth 1` provides enough context for research
4. **Default Branch Only**: No branch selection in initial implementation

---

## Risks and Mitigations

| Risk                | Likelihood | Impact | Mitigation                     |
| ------------------- | ---------- | ------ | ------------------------------ |
| Large repos timeout | Medium     | Low    | 120s timeout, shallow clone    |
| Private repo fails  | Low        | Low    | Clear error message, user docs |
| Invalid git URL     | Medium     | Low    | Client-side validation         |

---

## Success Criteria

1. Users can select "Git Repository" as content type
2. Users can enter a git URL (HTTPS or SSH)
3. Valid repos clone successfully into session sandbox
4. Invalid URLs show clear error messages
5. Git content displays with appropriate icon in content list

---

## Implementation Order

1. **Task 1.1**: Add git_repo to AddContentForm (blocking)
2. **Task 1.2**: Add Git URL validation (blocking)
3. **Task 2.1**: Add GitBranch icon (non-blocking)
4. **Task 2.2**: Display clone metadata (non-blocking)

**Recommended approach**: Implement Tasks 1.1 + 1.2 together, then 2.1 + 2.2 together.

---

## Approval Checklist

- [ ] Plan reviewed by stakeholder
- [ ] Scope confirmed (UI-only changes)
- [ ] Testing requirements approved
- [ ] Implementation order accepted

**Awaiting approval to proceed.**
