# Content Retrievers and Content Types Analysis

**Date**: 2026-02-03
**Scope**: research-mind monorepo (service + UI)
**Purpose**: Comprehensive analysis of content retrieval system for potential GIT repo retriever implementation

---

## Executive Summary

**Key Finding**: A GitRepoRetriever already exists and is fully implemented in the codebase at `research-mind-service/app/services/retrievers/git_repo.py`. The retriever uses shallow cloning via subprocess and is registered in the factory. The UI simply does not expose the `git_repo` content type yet.

**Recommendation**: Enable GIT repo content type in UI (minimal work) rather than building a new retriever.

---

## 1. Content Types Architecture

### 1.1 API Contract Definition

**File**: `/Users/mac/workspace/research-mind/research-mind-service/docs/api-contract.md`

The API contract defines 5 content types:

| Content Type  | Description         | Status                         |
| ------------- | ------------------- | ------------------------------ |
| `text`        | Plain text content  | Implemented                    |
| `file_upload` | Uploaded files      | Implemented                    |
| `url`         | Web page URLs       | Implemented                    |
| `git_repo`    | Git repository URLs | **Implemented** (backend only) |
| `mcp_source`  | MCP tool sources    | Stub only                      |

Content statuses: `pending`, `processing`, `ready`, `error`

### 1.2 Backend Model

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/models/content_item.py`

```python
class ContentType(str, enum.Enum):
    FILE_UPLOAD = "file_upload"
    TEXT = "text"
    URL = "url"
    GIT_REPO = "git_repo"
    MCP_SOURCE = "mcp_source"

class ContentStatus(str, enum.Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    READY = "ready"
    ERROR = "error"
```

### 1.3 UI Implementation Gap

**File**: `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/components/sessions/AddContentForm.svelte`

The UI currently only exposes 2 content types:

```typescript
type ContentType = "text" | "url";

const contentTypes = [
  { value: "text", label: "Text" },
  { value: "url", label: "URL" },
] as const;
```

**Gap**: `git_repo` and `file_upload` are not exposed in the UI form.

---

## 2. Content Retriever System

### 2.1 Retriever Protocol

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/base.py`

All retrievers implement this protocol:

```python
@dataclass(frozen=True)
class RetrievalResult:
    success: bool
    storage_path: str  # Relative path within session workspace
    size_bytes: int
    mime_type: str | None
    title: str
    metadata: dict
    error_message: str | None = None

class ContentRetriever(Protocol):
    def retrieve(
        self,
        *,
        source: str | bytes,
        target_dir: Path,
        title: str | None = None,
        metadata: dict | None = None,
    ) -> RetrievalResult:
        ...
```

### 2.2 Factory Pattern

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/factory.py`

```python
_REGISTRY: dict[str, type] = {
    ContentType.FILE_UPLOAD.value: FileUploadRetriever,
    ContentType.TEXT.value: TextRetriever,
    ContentType.URL.value: UrlRetriever,
    ContentType.GIT_REPO.value: GitRepoRetriever,
    ContentType.MCP_SOURCE.value: McpSourceRetriever,
}

def get_retriever(content_type: str) -> ContentRetriever:
    cls = _REGISTRY.get(content_type)
    if cls is None:
        raise ValueError(f"Unknown content type: {content_type}")
    return cls()
```

### 2.3 Implemented Retrievers

| Retriever           | File                | Status       | Output Structure               |
| ------------------- | ------------------- | ------------ | ------------------------------ |
| TextRetriever       | `text_retriever.py` | Complete     | `content.txt`, `metadata.json` |
| FileUploadRetriever | `file_upload.py`    | Complete     | Original file, `metadata.json` |
| UrlRetriever        | `url_retriever.py`  | Complete     | `content.md`, `metadata.json`  |
| GitRepoRetriever    | `git_repo.py`       | **Complete** | `repo/`, `metadata.json`       |
| McpSourceRetriever  | `mcp_source.py`     | Stub         | Not implemented                |

---

## 3. GitRepoRetriever Analysis (Existing Implementation)

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/git_repo.py`

### 3.1 Implementation Details

```python
class GitRepoRetriever:
    def __init__(self, timeout: int | None = None, depth: int | None = None):
        self._timeout = timeout if timeout is not None else settings.git_clone_timeout
        self._depth = depth if depth is not None else settings.git_clone_depth

    def retrieve(
        self,
        *,
        source: str,
        target_dir: Path,
        title: str | None = None,
        metadata: dict | None = None,
    ) -> RetrievalResult:
        clone_url = source
        repo_dir = target_dir / "repo"

        # Title extraction from URL
        resolved_title = title or clone_url.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git")

        # Git clone command
        cmd = ["git", "clone", "--depth", str(self._depth),
               "--single-branch", clone_url, str(repo_dir)]

        # Uses subprocess.run with:
        # - Configurable timeout
        # - Error handling for timeout, git not found, clone failure
        # - Writes metadata.json with clone_url, depth, total_bytes
```

### 3.2 Configuration Settings

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/core/config.py`

```python
git_clone_timeout: int = 120  # seconds
git_clone_depth: int = 1  # shallow clone depth
```

### 3.3 Output Structure

For a git repo content item:

```
{content_sandbox_root}/{session_id}/{content_id}/
├── repo/           # Cloned repository
│   ├── .git/
│   └── ...         # Repository files
└── metadata.json   # Clone metadata
```

### 3.4 Error Handling

The retriever handles:

- `subprocess.TimeoutExpired` - Returns error result with "clone_timeout" type
- `FileNotFoundError` - Returns error for "git not found"
- Non-zero exit codes - Returns error with stderr output

---

## 4. Session Sandbox Architecture

### 4.1 Directory Structure

**Configuration**: `/Users/mac/workspace/research-mind/research-mind-service/app/core/config.py`

```python
content_sandbox_root: str = "./content_sandboxes"
# Development: ./content_sandboxes (relative to service root)
# Production: /var/lib/research-mind/content_sandboxes
```

### 4.2 Content Storage Pattern

```
{content_sandbox_root}/
└── {session_id}/               # Session workspace
    ├── {content_id_1}/         # Content item 1
    │   ├── content.md          # (URL type)
    │   └── metadata.json
    ├── {content_id_2}/         # Content item 2
    │   ├── content.txt         # (Text type)
    │   └── metadata.json
    ├── {content_id_3}/         # Content item 3
    │   ├── repo/               # (Git repo type)
    │   │   └── ...
    │   └── metadata.json
    └── .mcp-vector-search/     # Vector search index (if indexed)
```

### 4.3 Session Model

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/models/session.py`

```python
class Session(Base):
    session_id = Column(String(36), primary_key=True)
    workspace_path = Column(String(512), nullable=False, unique=True)

    def is_indexed(self) -> bool:
        """Check if session has vector search index."""
        if not self.workspace_path:
            return False
        index_path = Path(self.workspace_path) / ".mcp-vector-search"
        return index_path.is_dir()
```

---

## 5. Content Service Flow

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/content_service.py`

### 5.1 Add Content Flow

```python
async def add_content(
    session_id: str,
    content_type: str,
    source: str | bytes,
    title: str | None,
    metadata: dict | None,
    db: Session,
) -> ContentItem:
    # 1. Create content item record (status=PENDING)
    content_item = ContentItem(
        session_id=session_id,
        content_type=content_type,
        title=title or "Untitled",
        source_ref=source if isinstance(source, str) else None,
        status=ContentStatus.PENDING,
    )
    db.add(content_item)
    db.commit()

    # 2. Get retriever from factory
    retriever = get_retriever(content_type)

    # 3. Build target directory
    target_dir = Path(settings.content_sandbox_root) / session_id / content_item.content_id
    target_dir.mkdir(parents=True, exist_ok=True)

    # 4. Execute retrieval
    result = retriever.retrieve(
        source=source,
        target_dir=target_dir,
        title=title,
        metadata=metadata,
    )

    # 5. Update content item with result
    content_item.status = ContentStatus.READY if result.success else ContentStatus.ERROR
    content_item.storage_path = result.storage_path
    content_item.size_bytes = result.size_bytes
    content_item.error_message = result.error_message
    db.commit()

    return content_item
```

---

## 6. UI Integration Analysis

### 6.1 API Client

**File**: `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/api/client.ts`

The API client already supports all content types via FormData:

```typescript
async addContent(
  sessionId: string,
  params: {
    contentType: string;  // Can be 'git_repo'
    title?: string;
    source?: string;      // Git URL goes here
    metadata?: Record<string, unknown>;
    file?: File;
  }
): Promise<ContentItemResponse> {
  const formData = new FormData();
  formData.append('content_type', params.contentType);
  // ... rest of FormData handling
}
```

### 6.2 TanStack Query Hooks

**File**: `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/api/hooks.ts`

Mutations are content-type agnostic:

```typescript
export function useAddContentMutation() {
  const queryClient = useQueryClient();
  return createMutation({
    mutationFn: ({ sessionId, params }) =>
      apiClient.addContent(sessionId, params),
    onSuccess: (_, { sessionId }) => {
      queryClient.invalidateQueries({ queryKey: ["content", sessionId] });
      queryClient.invalidateQueries({ queryKey: ["session", sessionId] });
    },
  });
}
```

### 6.3 Content List Component

**File**: `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/components/sessions/ContentList.svelte`

Already handles git_repo type display (uses generic FileText icon as fallback):

```typescript
function getContentIcon(contentType: string) {
  switch (contentType) {
    case "url":
      return Link;
    case "text":
    default:
      return FileText; // git_repo falls through to this
  }
}
```

---

## 7. Recommendations

### 7.1 Immediate Action: Enable GIT Repo in UI

**Priority**: High
**Effort**: Low (< 1 hour)

Modify `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/components/sessions/AddContentForm.svelte`:

```typescript
// Change from:
type ContentType = "text" | "url";

// To:
type ContentType = "text" | "url" | "git_repo";

const contentTypes = [
  { value: "text", label: "Text" },
  { value: "url", label: "URL" },
  { value: "git_repo", label: "Git Repository" }, // Add this
] as const;
```

Add validation for git_repo URLs:

```typescript
function validateGitUrl(url: string): boolean {
  // Accept HTTPS and SSH git URLs
  const httpsPattern = /^https:\/\/[\w.-]+\/[\w.-]+\/[\w.-]+(\.git)?$/;
  const sshPattern = /^git@[\w.-]+:[\w.-]+\/[\w.-]+(\.git)?$/;
  return httpsPattern.test(url) || sshPattern.test(url);
}
```

### 7.2 Enhancement: Add Git-Specific Icon

**Priority**: Low
**Effort**: Minimal

In ContentList.svelte:

```typescript
import { FileText, Link, GitBranch } from "lucide-svelte";

function getContentIcon(contentType: string) {
  switch (contentType) {
    case "url":
      return Link;
    case "git_repo":
      return GitBranch; // Add this
    case "text":
    default:
      return FileText;
  }
}
```

### 7.3 Future Enhancement: Clone Progress

**Priority**: Medium
**Effort**: Medium (requires WebSocket or polling)

Current limitation: Clone is synchronous with no progress feedback. For large repos, consider:

1. Make clone async with background job
2. Add `progress` status to ContentStatus enum
3. Implement polling or WebSocket for progress updates

### 7.4 Future Enhancement: Branch/Commit Selection

**Priority**: Low
**Effort**: Medium

Current limitation: Only clones default branch at depth 1. Could add:

```python
class GitRepoRetriever:
    def __init__(
        self,
        timeout: int | None = None,
        depth: int | None = None,
        branch: str | None = None,  # Add branch selection
        commit: str | None = None,  # Add commit checkout
    ):
        ...
```

---

## 8. File Reference Summary

### Backend (research-mind-service)

| File                                        | Purpose                                                    |
| ------------------------------------------- | ---------------------------------------------------------- |
| `app/models/content_item.py`                | ContentType and ContentStatus enums, ContentItem ORM model |
| `app/services/retrievers/base.py`           | ContentRetriever protocol, RetrievalResult dataclass       |
| `app/services/retrievers/factory.py`        | Retriever registry and factory function                    |
| `app/services/retrievers/git_repo.py`       | **GitRepoRetriever implementation**                        |
| `app/services/retrievers/url_retriever.py`  | UrlRetriever with extraction pipeline                      |
| `app/services/retrievers/text_retriever.py` | Simple TextRetriever                                       |
| `app/services/retrievers/file_upload.py`    | FileUploadRetriever                                        |
| `app/services/retrievers/mcp_source.py`     | McpSourceRetriever stub                                    |
| `app/services/content_service.py`           | Content management business logic                          |
| `app/routes/content.py`                     | REST endpoints for content operations                      |
| `app/schemas/content.py`                    | Pydantic request/response schemas                          |
| `app/core/config.py`                        | Settings including git_clone_timeout, git_clone_depth      |
| `app/models/session.py`                     | Session model with workspace_path                          |
| `docs/api-contract.md`                      | API contract (source of truth)                             |

### Frontend (research-mind-ui)

| File                                                | Purpose                                      |
| --------------------------------------------------- | -------------------------------------------- |
| `src/lib/components/sessions/AddContentForm.svelte` | Content addition form (needs git_repo type)  |
| `src/lib/components/sessions/ContentList.svelte`    | Content item display (works with all types)  |
| `src/lib/api/client.ts`                             | API client (supports all content types)      |
| `src/lib/api/hooks.ts`                              | TanStack Query hooks (content-type agnostic) |
| `src/lib/api/generated.ts`                          | Auto-generated types from OpenAPI            |
| `docs/api-contract.md`                              | API contract copy (must match service)       |

---

## 9. Conclusion

The research-mind codebase already has a complete GitRepoRetriever implementation. The backend fully supports `git_repo` content type including:

- Shallow cloning with configurable depth
- Timeout handling
- Error reporting
- Metadata generation

The only gap is UI exposure. Enabling git_repo in AddContentForm.svelte is a minimal change that would make the existing functionality accessible to users.

**No new retriever implementation is needed.**
