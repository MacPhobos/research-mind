# Content Handling Architecture Analysis

**Research Date**: 2026-02-03
**Project**: research-mind
**Scope**: Backend, Frontend, and API Contract content handling implementation

---

## Executive Summary

This document provides a comprehensive analysis of the content handling implementation in the research-mind project. The architecture follows a **Strategy Pattern** (Retriever Pattern) for content type handling, with clear separation between API layer, service layer, and storage layer.

**Key Findings**:

1. Backend uses a well-designed **Retriever Protocol** with factory pattern for extensibility
2. Content is stored in isolated sandbox directories per session/content-item
3. Frontend uses TanStack Query with Zod validation for type-safe API calls
4. The API contract is versioned (v1.2.0) and well-documented

---

## 1. Backend Architecture

### 1.1 Database Models

#### Session Model

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/models/session.py`

```python
class Session(Base):
    __tablename__ = "sessions"

    session_id: str = Column(String(36), primary_key=True)
    name: str = Column(String(255), nullable=False)
    description: str | None = Column(Text, nullable=True)
    workspace_path: str | None = Column(String(512), nullable=True)
    is_indexed: bool = Column(Boolean, default=False)
    created_at: datetime = Column(DateTime(timezone=True), default=func.now())
    updated_at: datetime = Column(DateTime(timezone=True), default=func.now())

    # Relationship
    content_items = relationship("ContentItem", back_populates="session", cascade="all, delete-orphan")
```

#### ContentItem Model

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

class ContentItem(Base):
    __tablename__ = "content_items"

    content_id: str = Column(String(36), primary_key=True)
    session_id: str = Column(String(36), ForeignKey("sessions.session_id", ondelete="CASCADE"))
    content_type: str = Column(String(20), nullable=False)
    title: str = Column(String(512), nullable=False)
    source_ref: str | None = Column(String(2048), nullable=True)
    storage_path: str | None = Column(String(512), nullable=True)
    status: str = Column(String(20), default=ContentStatus.PENDING.value)
    error_message: str | None = Column(Text, nullable=True)
    size_bytes: int | None = Column(Integer, nullable=True)
    mime_type: str | None = Column(String(128), nullable=True)
    metadata_json = Column(JSON, nullable=True, default=dict)
    created_at: datetime = Column(DateTime(timezone=True), default=func.now())
    updated_at: datetime = Column(DateTime(timezone=True), default=func.now())
```

**Key Points**:

- `content_type` is stored as string matching ContentType enum values
- `status` tracks processing lifecycle (PENDING → PROCESSING → READY/ERROR)
- `storage_path` points to the sandbox directory for this content
- `source_ref` holds the original source (URL, filename, etc.)
- `metadata_json` stores arbitrary JSON metadata

### 1.2 Pydantic Schemas

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/schemas/content.py`

```python
class AddContentRequest(BaseModel):
    """Request schema for adding content (form data)."""
    content_type: str
    title: str | None = None
    source: str | None = None
    metadata: dict | None = None

class ContentItemResponse(BaseModel):
    """Response schema for content item."""
    content_id: str
    session_id: str
    content_type: str
    title: str
    source_ref: str | None
    storage_path: str | None
    status: str
    error_message: str | None
    size_bytes: int | None
    mime_type: str | None
    metadata: dict | None
    created_at: datetime
    updated_at: datetime
```

### 1.3 Sandbox Directory Structure

**Configuration** (`/Users/mac/workspace/research-mind/research-mind-service/app/core/config.py`):

```python
class Settings(BaseSettings):
    workspace_root: str = "./workspaces"
    content_sandbox_root: str = "./content_sandboxes"
    max_text_bytes: int = 10 * 1024 * 1024  # 10 MB
    max_url_response_bytes: int = 20 * 1024 * 1024  # 20 MB
```

**Directory Layout**:

```
./content_sandboxes/
└── {session_id}/
    └── {content_id}/
        ├── content.txt      # For TEXT type
        ├── content.md       # For URL type (raw response)
        └── metadata.json    # Retrieval metadata
```

**Path Validation** (`/Users/mac/workspace/research-mind/research-mind-service/app/sandbox/path_validator.py`):

- Validates paths stay within sandbox boundaries
- Prevents directory traversal attacks
- Ensures consistent path handling

### 1.4 Retriever Pattern (Strategy Pattern)

The backend uses a **Strategy Pattern** implemented through a Protocol and Factory.

#### Base Protocol

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/base.py`

```python
@dataclass(frozen=True)
class RetrievalResult:
    """Result of content retrieval operation."""
    success: bool
    storage_path: str
    size_bytes: int
    mime_type: str | None
    title: str
    metadata: dict
    error_message: str | None = None

class ContentRetriever(Protocol):
    """Protocol defining the interface for content retrievers."""

    def retrieve(
        self,
        *,
        source: str | bytes,
        target_dir: Path,
        title: str | None = None,
        metadata: dict | None = None,
    ) -> RetrievalResult:
        """Retrieve content and store it in target directory."""
        ...
```

#### Factory

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
    """Get the appropriate retriever for a content type."""
    cls = _REGISTRY.get(content_type)
    if cls is None:
        raise ValueError(f"Unknown content type: {content_type}")
    return cls()
```

#### Text Retriever Implementation

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/text_retriever.py`

```python
class TextRetriever:
    """Retriever for plain text content."""

    def retrieve(
        self,
        *,
        source: str | bytes,
        target_dir: Path,
        title: str | None = None,
        metadata: dict | None = None,
    ) -> RetrievalResult:
        # Convert bytes to string if needed
        text = source.decode("utf-8") if isinstance(source, bytes) else source

        # Write content file
        content_path = target_dir / "content.txt"
        content_path.write_text(text, encoding="utf-8")

        # Write metadata
        meta = {
            "content_type": "text",
            "title": title or "Untitled",
            "retrieved_at": datetime.utcnow().isoformat(),
            **(metadata or {}),
        }
        metadata_path = target_dir / "metadata.json"
        metadata_path.write_text(json.dumps(meta, indent=2))

        return RetrievalResult(
            success=True,
            storage_path=str(content_path),
            size_bytes=len(text.encode("utf-8")),
            mime_type="text/plain",
            title=title or "Untitled",
            metadata=meta,
        )
```

#### URL Retriever Implementation

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/url_retriever.py`

```python
class UrlRetriever:
    """Retriever for URL content."""

    def retrieve(
        self,
        *,
        source: str | bytes,
        target_dir: Path,
        title: str | None = None,
        metadata: dict | None = None,
    ) -> RetrievalResult:
        url = source if isinstance(source, str) else source.decode("utf-8")

        # Fetch URL content
        with httpx.Client(timeout=30.0) as client:
            response = client.get(url, follow_redirects=True)
            response.raise_for_status()

        content = response.text
        content_type = response.headers.get("content-type", "text/html")

        # Write content file
        content_path = target_dir / "content.md"
        content_path.write_text(content, encoding="utf-8")

        # Extract title from HTML if not provided
        extracted_title = title or self._extract_title(content) or url

        # Write metadata
        meta = {
            "content_type": "url",
            "url": url,
            "title": extracted_title,
            "response_content_type": content_type,
            "retrieved_at": datetime.utcnow().isoformat(),
            **(metadata or {}),
        }
        metadata_path = target_dir / "metadata.json"
        metadata_path.write_text(json.dumps(meta, indent=2))

        return RetrievalResult(
            success=True,
            storage_path=str(content_path),
            size_bytes=len(content.encode("utf-8")),
            mime_type=content_type,
            title=extracted_title,
            metadata=meta,
        )
```

### 1.5 Content Service (Business Logic)

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/content_service.py`

```python
async def add_content(
    db: AsyncSession,
    session_id: str,
    content_type: str,
    title: str | None = None,
    source: str | None = None,
    file: UploadFile | None = None,
    metadata: dict | None = None,
) -> ContentItem:
    """Add content to a session."""

    # 1. Validate session exists
    session = await get_session(db, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # 2. Create content record with PENDING status
    content_id = str(uuid4())
    content_item = ContentItem(
        content_id=content_id,
        session_id=session_id,
        content_type=content_type,
        title=title or "Untitled",
        source_ref=source,
        status=ContentStatus.PENDING.value,
        metadata_json=metadata or {},
    )
    db.add(content_item)
    await db.commit()

    # 3. Create sandbox directory
    target_dir = Path(settings.content_sandbox_root) / session_id / content_id
    target_dir.mkdir(parents=True, exist_ok=True)

    # 4. Update status to PROCESSING
    content_item.status = ContentStatus.PROCESSING.value
    await db.commit()

    try:
        # 5. Get appropriate retriever and process content
        retriever = get_retriever(content_type)

        # Determine source data
        if content_type == ContentType.FILE_UPLOAD.value and file:
            source_data = await file.read()
        else:
            source_data = source or ""

        result = retriever.retrieve(
            source=source_data,
            target_dir=target_dir,
            title=title,
            metadata=metadata,
        )

        # 6. Update content item with results
        content_item.storage_path = result.storage_path
        content_item.size_bytes = result.size_bytes
        content_item.mime_type = result.mime_type
        content_item.title = result.title
        content_item.metadata_json = result.metadata
        content_item.status = ContentStatus.READY.value

    except Exception as e:
        # Handle errors
        content_item.status = ContentStatus.ERROR.value
        content_item.error_message = str(e)

    await db.commit()
    await db.refresh(content_item)
    return content_item
```

**Processing Flow**:

```
1. Validate session exists
       ↓
2. Create ContentItem record (PENDING)
       ↓
3. Create sandbox directory
       ↓
4. Update status to PROCESSING
       ↓
5. Get retriever from factory
       ↓
6. Call retriever.retrieve()
       ↓
7. Update ContentItem with results (READY or ERROR)
```

### 1.6 REST API Routes

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/routes/content.py`

```python
@router.post("/{session_id}/content/", response_model=ContentItemResponse)
async def add_content(
    session_id: str,
    content_type: str = Form(...),
    title: str | None = Form(None),
    source: str | None = Form(None),
    file: UploadFile | None = File(None),
    metadata: str | None = Form(None),
    db: AsyncSession = Depends(get_db),
) -> ContentItemResponse:
    """Add content to a session."""
    metadata_dict = json.loads(metadata) if metadata else None

    content_item = await content_service.add_content(
        db=db,
        session_id=session_id,
        content_type=content_type,
        title=title,
        source=source,
        file=file,
        metadata=metadata_dict,
    )

    return ContentItemResponse.model_validate(content_item)

@router.get("/{session_id}/content/", response_model=ContentListResponse)
async def list_content(
    session_id: str,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
) -> ContentListResponse:
    """List content items for a session."""
    items, total = await content_service.list_content(db, session_id, limit, offset)
    return ContentListResponse(
        items=[ContentItemResponse.model_validate(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
    )

@router.delete("/{session_id}/content/{content_id}", status_code=204)
async def delete_content(
    session_id: str,
    content_id: str,
    db: AsyncSession = Depends(get_db),
) -> None:
    """Delete a content item."""
    await content_service.delete_content(db, session_id, content_id)
```

---

## 2. API Contract

**File**: `/Users/mac/workspace/research-mind/research-mind-service/docs/api-contract.md`

**Version**: 1.2.0

### Content Endpoints

| Method | Endpoint                                             | Description            |
| ------ | ---------------------------------------------------- | ---------------------- |
| POST   | `/api/v1/sessions/{session_id}/content/`             | Add content to session |
| GET    | `/api/v1/sessions/{session_id}/content/`             | List session content   |
| GET    | `/api/v1/sessions/{session_id}/content/{content_id}` | Get content item       |
| DELETE | `/api/v1/sessions/{session_id}/content/{content_id}` | Delete content item    |

### Content Types

```
text        - Plain text content
file_upload - Uploaded files
url         - Web URL content
git_repo    - Git repository (not yet implemented)
mcp_source  - MCP data source (not yet implemented)
```

### Content Status Flow

```
PENDING → PROCESSING → READY
                    ↘ ERROR
```

### Request/Response Schemas

**Add Content Request** (multipart/form-data):

```
content_type: string (required)
title: string (optional)
source: string (optional, required for text/url)
file: binary (optional, required for file_upload)
metadata: JSON string (optional)
```

**Content Item Response**:

```json
{
  "content_id": "uuid",
  "session_id": "uuid",
  "content_type": "text|url|file_upload|git_repo|mcp_source",
  "title": "string",
  "source_ref": "string|null",
  "storage_path": "string|null",
  "status": "pending|processing|ready|error",
  "error_message": "string|null",
  "size_bytes": "integer|null",
  "mime_type": "string|null",
  "metadata": "object|null",
  "created_at": "ISO8601 datetime",
  "updated_at": "ISO8601 datetime"
}
```

---

## 3. Frontend Architecture

### 3.1 API Client

**File**: `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/api/client.ts`

```typescript
// Zod schema for runtime validation
const ContentItemResponseSchema = z.object({
  content_id: z.string(),
  session_id: z.string(),
  content_type: z.string(),
  title: z.string(),
  source_ref: z.string().nullable(),
  storage_path: z.string().nullable(),
  status: z.string(),
  error_message: z.string().nullable(),
  size_bytes: z.number().nullable(),
  mime_type: z.string().nullable(),
  metadata: z.record(z.unknown()).nullable(),
  created_at: z.string(),
  updated_at: z.string(),
});

export const apiClient = {
  async addContent(
    sessionId: string,
    contentType: string,
    options?: {
      title?: string;
      source?: string;
      metadata?: Record<string, unknown>;
      file?: File;
    },
  ): Promise<ContentItemResponse> {
    const formData = new FormData();
    formData.append("content_type", contentType);

    if (options?.title) formData.append("title", options.title);
    if (options?.source) formData.append("source", options.source);
    if (options?.metadata)
      formData.append("metadata", JSON.stringify(options.metadata));
    if (options?.file) formData.append("file", options.file);

    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/content/`,
      {
        method: "POST",
        body: formData,
      },
    );

    if (!response.ok) {
      throw new ApiError(response.status, await response.text());
    }

    const data = await response.json();
    return ContentItemResponseSchema.parse(data);
  },

  async listContent(
    sessionId: string,
    limit = 50,
    offset = 0,
  ): Promise<ContentListResponse> {
    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/content/?limit=${limit}&offset=${offset}`,
    );

    if (!response.ok) {
      throw new ApiError(response.status, await response.text());
    }

    const data = await response.json();
    return ContentListResponseSchema.parse(data);
  },

  async deleteContent(sessionId: string, contentId: string): Promise<void> {
    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/content/${contentId}`,
      { method: "DELETE" },
    );

    if (!response.ok) {
      throw new ApiError(response.status, await response.text());
    }
  },
};
```

### 3.2 TanStack Query Hooks

**File**: `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/api/hooks.ts`

```typescript
/**
 * Query hook for listing content items for a session.
 */
export function useContentQuery(
  sessionId: string | undefined,
  limit = 50,
  offset = 0,
) {
  return createQuery<ContentListResponse, ApiError>({
    queryKey: queryKeys.content.list(sessionId ?? "", { limit, offset }),
    queryFn: () => apiClient.listContent(sessionId!, limit, offset),
    enabled: !!sessionId,
    staleTime: 30000, // 30 seconds
    gcTime: 300000, // 5 minutes
  });
}

/**
 * Mutation hook for adding content to a session.
 * Invalidates content list and session detail on success.
 */
export function useAddContentMutation() {
  const queryClient = useQueryClient();

  return createMutation<
    ContentItemResponse,
    ApiError,
    {
      sessionId: string;
      contentType: string;
      options?: {
        title?: string;
        source?: string;
        metadata?: Record<string, unknown>;
        file?: File;
      };
    }
  >({
    mutationFn: ({ sessionId, contentType, options }) =>
      apiClient.addContent(sessionId, contentType, options),
    onSuccess: (_data, variables) => {
      // Invalidate content list for this session
      queryClient.invalidateQueries({
        queryKey: queryKeys.content.all(variables.sessionId),
      });
      // Invalidate session detail (content_count may have changed)
      queryClient.invalidateQueries({
        queryKey: queryKeys.sessions.detail(variables.sessionId),
      });
    },
  });
}

/**
 * Mutation hook for deleting content from a session.
 */
export function useDeleteContentMutation() {
  const queryClient = useQueryClient();

  return createMutation<
    void,
    ApiError,
    { sessionId: string; contentId: string }
  >({
    mutationFn: ({ sessionId, contentId }) =>
      apiClient.deleteContent(sessionId, contentId),
    onSuccess: (_data, variables) => {
      queryClient.removeQueries({
        queryKey: queryKeys.content.detail(
          variables.sessionId,
          variables.contentId,
        ),
      });
      queryClient.invalidateQueries({
        queryKey: queryKeys.content.all(variables.sessionId),
      });
      queryClient.invalidateQueries({
        queryKey: queryKeys.sessions.detail(variables.sessionId),
      });
    },
  });
}
```

### 3.3 UI Components

#### AddContentForm Component

**File**: `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/components/sessions/AddContentForm.svelte`

```svelte
<script lang="ts">
  import { FileText, Link, Loader, X } from 'lucide-svelte';
  import { useAddContentMutation } from '$lib/api/hooks';
  import { toastStore } from '$lib/stores/toast';

  interface Props {
    sessionId: string;
    onSuccess?: () => void;
    onCancel?: () => void;
  }

  let { sessionId, onSuccess, onCancel }: Props = $props();

  const mutation = useAddContentMutation();

  // Form state using Svelte 5 runes
  let contentType = $state<'text' | 'url'>('text');
  let title = $state('');
  let source = $state('');
  let touched = $state({ title: false, source: false });

  // Validation using $derived
  const titleError = $derived(
    !touched.title ? null :
    title.trim().length === 0 ? 'Title is required' :
    title.trim().length > 255 ? 'Title must be 255 characters or fewer' :
    null
  );

  const sourceError = $derived(
    !touched.source ? null :
    source.trim().length === 0 ? (contentType === 'text' ? 'Content is required' : 'URL is required') :
    contentType === 'url' && !isValidUrl(source.trim()) ? 'Please enter a valid URL' :
    null
  );

  const isValid = $derived(
    title.trim().length > 0 &&
    title.trim().length <= 255 &&
    source.trim().length > 0 &&
    (contentType !== 'url' || isValidUrl(source.trim()))
  );

  async function handleSubmit(event: Event) {
    event.preventDefault();

    if (!isValid || $mutation.isPending) return;

    try {
      await $mutation.mutateAsync({
        sessionId,
        contentType,
        options: {
          title: title.trim(),
          source: source.trim(),
        },
      });

      toastStore.success('Content added successfully');

      // Reset form
      title = '';
      source = '';
      touched = { title: false, source: false };

      onSuccess?.();
    } catch {
      toastStore.error($mutation.error?.message || 'Failed to add content');
    }
  }
</script>
```

**Key Features**:

- Supports `text` and `url` content types via toggle buttons
- Uses Svelte 5 runes (`$state`, `$derived`) for reactive state
- Form validation with touched state tracking
- Uses TanStack Query mutation for API calls
- Toast notifications for success/error feedback

#### ContentList Component

**File**: `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/components/sessions/ContentList.svelte`

```svelte
<script lang="ts">
  import { FileText, Link, Trash2, AlertCircle } from 'lucide-svelte';
  import type { ContentItemResponse } from '$lib/api/client';
  import { useDeleteContentMutation } from '$lib/api/hooks';
  import { toastStore } from '$lib/stores/toast';
  import StatusBadge from '$lib/components/shared/StatusBadge.svelte';
  import ConfirmDialog from '$lib/components/shared/ConfirmDialog.svelte';
  import EmptyState from '$lib/components/shared/EmptyState.svelte';

  interface Props {
    sessionId: string;
    items: ContentItemResponse[];
    isLoading?: boolean;
  }

  let { sessionId, items, isLoading = false }: Props = $props();

  const deleteMutation = useDeleteContentMutation();

  // State for delete confirmation
  let showDeleteConfirm = $state(false);
  let contentToDelete = $state<ContentItemResponse | null>(null);

  function getContentIcon(contentType: string) {
    switch (contentType) {
      case 'url':
        return Link;
      case 'text':
      default:
        return FileText;
    }
  }

  async function confirmDelete() {
    if (!contentToDelete) return;

    try {
      await $deleteMutation.mutateAsync({
        sessionId,
        contentId: contentToDelete.content_id,
      });
      toastStore.success('Content deleted successfully');
    } catch {
      toastStore.error($deleteMutation.error?.message || 'Failed to delete content');
    } finally {
      showDeleteConfirm = false;
      contentToDelete = null;
    }
  }
</script>
```

**Key Features**:

- Displays content items with type-specific icons
- Shows status badges (pending, processing, ready, error)
- Delete confirmation dialog
- Loading skeleton states
- Empty state for no content

---

## 4. Content Type Handling Flow

### 4.1 Text Content Flow

```
Frontend                           Backend
   │                                  │
   │ POST /sessions/{id}/content/     │
   │ FormData:                        │
   │   content_type: "text"           │
   │   title: "My Notes"              │
   │   source: "Text content..."      │
   ├─────────────────────────────────►│
   │                                  │
   │                         Create ContentItem (PENDING)
   │                                  │
   │                         Create sandbox directory
   │                         ./content_sandboxes/{session_id}/{content_id}/
   │                                  │
   │                         Update status to PROCESSING
   │                                  │
   │                         TextRetriever.retrieve()
   │                           → Write content.txt
   │                           → Write metadata.json
   │                                  │
   │                         Update ContentItem (READY)
   │                           storage_path: "content.txt"
   │                           size_bytes: 1234
   │                           mime_type: "text/plain"
   │                                  │
   │◄─────────────────────────────────┤
   │ ContentItemResponse              │
```

### 4.2 URL Content Flow

```
Frontend                           Backend                        External
   │                                  │                              │
   │ POST /sessions/{id}/content/     │                              │
   │ FormData:                        │                              │
   │   content_type: "url"            │                              │
   │   title: "Article"               │                              │
   │   source: "https://..."          │                              │
   ├─────────────────────────────────►│                              │
   │                                  │                              │
   │                         Create ContentItem (PENDING)            │
   │                                  │                              │
   │                         Create sandbox directory                │
   │                                  │                              │
   │                         Update status to PROCESSING             │
   │                                  │                              │
   │                         UrlRetriever.retrieve()                 │
   │                                  │ GET https://...              │
   │                                  ├─────────────────────────────►│
   │                                  │◄─────────────────────────────┤
   │                                  │ HTML response                │
   │                                  │                              │
   │                           → Write content.md                    │
   │                           → Write metadata.json                 │
   │                           → Extract title from HTML             │
   │                                  │                              │
   │                         Update ContentItem (READY)              │
   │                           storage_path: "content.md"            │
   │                           mime_type: "text/html"                │
   │                                  │                              │
   │◄─────────────────────────────────┤                              │
   │ ContentItemResponse              │                              │
```

---

## 5. Extension Patterns

### 5.1 Adding a New Content Type

To add a new content type (e.g., `pdf`):

**1. Add to ContentType enum**:

```python
# app/models/content_item.py
class ContentType(str, enum.Enum):
    # ... existing types
    PDF = "pdf"
```

**2. Create retriever class**:

```python
# app/services/retrievers/pdf_retriever.py
class PdfRetriever:
    def retrieve(
        self,
        *,
        source: str | bytes,
        target_dir: Path,
        title: str | None = None,
        metadata: dict | None = None,
    ) -> RetrievalResult:
        # Implementation
        pass
```

**3. Register in factory**:

```python
# app/services/retrievers/factory.py
_REGISTRY: dict[str, type] = {
    # ... existing types
    ContentType.PDF.value: PdfRetriever,
}
```

**4. Update API contract**:

```markdown
## Content Types

- pdf - PDF document content (NEW)
```

**5. Update frontend**:

- Add type to content type selector
- Add appropriate icon
- Update validation if needed

### 5.2 Service Layer Patterns to Follow

1. **Use Dependency Injection**: Pass `db: AsyncSession` as parameter
2. **Validate First**: Check session exists before creating content
3. **Status Transitions**: PENDING → PROCESSING → READY/ERROR
4. **Error Handling**: Catch exceptions and set ERROR status with message
5. **Sandbox Isolation**: Each content item gets its own directory
6. **Metadata Preservation**: Store retrieval metadata in JSON file

---

## 6. Summary

### Architecture Strengths

1. **Clean Separation**: API layer, service layer, and retriever layer are well-separated
2. **Extensible Design**: Strategy pattern makes adding new content types straightforward
3. **Type Safety**: Zod validation on frontend, Pydantic on backend
4. **Status Tracking**: Clear lifecycle states for content processing
5. **Sandbox Isolation**: Each content item has isolated storage

### Areas for Future Enhancement

1. **Async Processing**: Consider background tasks for large content (git repos)
2. **Content Transformation**: Add processing pipeline for content normalization
3. **Caching**: Add content caching for frequently accessed items
4. **Search Integration**: Index content for full-text search
5. **Streaming**: Support streaming for large file uploads

### Key Files Reference

| Category              | File Path                                                                                               |
| --------------------- | ------------------------------------------------------------------------------------------------------- |
| **Models**            | `/Users/mac/workspace/research-mind/research-mind-service/app/models/content_item.py`                   |
| **Schemas**           | `/Users/mac/workspace/research-mind/research-mind-service/app/schemas/content.py`                       |
| **Routes**            | `/Users/mac/workspace/research-mind/research-mind-service/app/routes/content.py`                        |
| **Service**           | `/Users/mac/workspace/research-mind/research-mind-service/app/services/content_service.py`              |
| **Retriever Base**    | `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/base.py`              |
| **Retriever Factory** | `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/factory.py`           |
| **Text Retriever**    | `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/text_retriever.py`    |
| **URL Retriever**     | `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/url_retriever.py`     |
| **Config**            | `/Users/mac/workspace/research-mind/research-mind-service/app/core/config.py`                           |
| **API Contract**      | `/Users/mac/workspace/research-mind/research-mind-service/docs/api-contract.md`                         |
| **Frontend Client**   | `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/api/client.ts`                             |
| **Frontend Hooks**    | `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/api/hooks.ts`                              |
| **AddContentForm**    | `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/components/sessions/AddContentForm.svelte` |
| **ContentList**       | `/Users/mac/workspace/research-mind/research-mind-ui/src/lib/components/sessions/ContentList.svelte`    |

---

_Research conducted by Claude Code Research Agent_
