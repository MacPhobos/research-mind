# Content Item Architecture Research

**Date**: 2026-02-05
**Researcher**: Claude Code
**Scope**: research-mind-service codebase content management system

---

## Executive Summary

The research-mind-service implements a flexible content management system that supports five content types (Text, URL, File Upload, Git Repo, MCP Source) through a retriever pattern architecture. Content is stored in a session-scoped sandbox directory with each content item having its own subdirectory. The system uses SQLAlchemy ORM for persistence and Pydantic for API schemas.

---

## 1. Current Content Types

### 1.1 Supported Content Types (Enum)

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/models/content_item.py`

```python
class ContentType(str, enum.Enum):
    FILE_UPLOAD = "file_upload"
    TEXT = "text"
    URL = "url"
    GIT_REPO = "git_repo"
    MCP_SOURCE = "mcp_source"  # Placeholder - not implemented
```

### 1.2 Content Status Lifecycle

```python
class ContentStatus(str, enum.Enum):
    PENDING = "pending"        # Created, not processed
    PROCESSING = "processing"  # Retrieval in progress
    READY = "ready"           # Successfully retrieved
    ERROR = "error"           # Retrieval failed
```

### 1.3 Content Item Model

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/models/content_item.py`

| Field           | Type         | Description                                             |
| --------------- | ------------ | ------------------------------------------------------- |
| `content_id`    | String(36)   | UUID primary key                                        |
| `session_id`    | String(36)   | Foreign key to sessions table (CASCADE delete)          |
| `content_type`  | String(20)   | One of the ContentType enum values                      |
| `title`         | String(512)  | Human-readable label                                    |
| `source_ref`    | String(2048) | Original source reference (URL, text snippet, etc.)     |
| `storage_path`  | String(512)  | Relative path within session workspace                  |
| `status`        | String(20)   | ContentStatus enum value                                |
| `error_message` | Text         | Error details when status=error                         |
| `size_bytes`    | Integer      | Size of stored content                                  |
| `mime_type`     | String(128)  | MIME type of primary content file                       |
| `metadata_json` | JSON         | Flexible metadata (filename, headers, git commit, etc.) |
| `created_at`    | DateTime     | Creation timestamp (UTC)                                |
| `updated_at`    | DateTime     | Last update timestamp (UTC)                             |

**Indexes**: `session_id`, `status`, `content_type`

---

## 2. Session Sandbox Directory Structure

### 2.1 Configuration

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/core/config.py`

```python
# Root directory for all session data
content_sandbox_root: str = "./content_sandboxes"  # Development
# Production: /var/lib/research-mind/content_sandboxes
```

### 2.2 Directory Hierarchy

```
{content_sandbox_root}/
└── {session_id}/                    # Session workspace (= workspace_path)
    ├── {content_id_1}/              # Content item directory
    │   ├── content.txt              # Text content (for text type)
    │   ├── content.md               # Extracted markdown (for URL type)
    │   ├── {original_filename}      # Uploaded file (for file_upload type)
    │   ├── repo/                    # Cloned repository (for git_repo type)
    │   │   └── <git files>
    │   └── metadata.json            # Content-specific metadata
    │
    ├── {content_id_2}/
    │   └── ...
    │
    └── .mcp-vector-search/          # Vector index directory (after indexing)
```

### 2.3 Storage Path Semantics

- `storage_path` in ContentItem is the **relative** path within the session workspace
- Typically just the `content_id` (directory name)
- Full path: `{content_sandbox_root}/{session_id}/{storage_path}/`

### 2.4 Content Limits

| Setting                  | Default Value | Description                        |
| ------------------------ | ------------- | ---------------------------------- |
| `max_upload_bytes`       | 50 MB         | Maximum file upload size           |
| `max_text_bytes`         | 10 MB         | Maximum text content size          |
| `max_url_response_bytes` | 20 MB         | Maximum URL response size          |
| `max_workspace_bytes`    | 500 MB        | Maximum per-session workspace size |

---

## 3. API Contract Summary

**File**: `/Users/mac/workspace/research-mind/research-mind-service/docs/api-contract.md`

### 3.1 Content Endpoints

| Method   | Endpoint                                             | Description                       |
| -------- | ---------------------------------------------------- | --------------------------------- |
| `POST`   | `/api/v1/sessions/{session_id}/content`              | Add content (multipart/form-data) |
| `GET`    | `/api/v1/sessions/{session_id}/content`              | List content items (paginated)    |
| `GET`    | `/api/v1/sessions/{session_id}/content/{content_id}` | Get single content item           |
| `DELETE` | `/api/v1/sessions/{session_id}/content/{content_id}` | Delete content item               |
| `POST`   | `/api/v1/sessions/{session_id}/content/batch`        | Batch add URLs (up to 500)        |
| `POST`   | `/api/v1/content/extract-links`                      | Extract links from URL            |

### 3.2 Add Content Request (Form Fields)

| Field          | Type   | Required | Description                                    |
| -------------- | ------ | -------- | ---------------------------------------------- |
| `content_type` | string | Yes      | text, file_upload, url, git_repo, mcp_source   |
| `title`        | string | No       | Content title (max 512 chars)                  |
| `source`       | string | No       | Source reference (text content, URL, repo URL) |
| `metadata`     | string | No       | JSON string of additional metadata             |
| `file`         | file   | No       | File upload (required for file_upload type)    |

### 3.3 Content Item Response Schema

```typescript
interface ContentItem {
  content_id: string;
  session_id: string;
  content_type: string;
  title: string;
  source_ref?: string;
  storage_path?: string;
  status: string;
  error_message?: string;
  size_bytes?: number;
  mime_type?: string;
  metadata_json?: object;
  created_at: string;
  updated_at: string;
}
```

---

## 4. Content Processing Pipeline

### 4.1 Architecture Overview

```
[API Route] --> [ContentService] --> [RetrieverFactory] --> [Specific Retriever]
                      |                                            |
                      v                                            v
               [ContentItem DB]                          [Sandbox Files]
```

### 4.2 Retriever Pattern

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/base.py`

All retrievers implement the `ContentRetriever` protocol:

```python
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

**RetrievalResult** dataclass:

- `success: bool`
- `storage_path: str` (relative path)
- `size_bytes: int`
- `mime_type: str | None`
- `title: str`
- `metadata: dict`
- `error_message: str | None`

### 4.3 Retriever Factory

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/retrievers/factory.py`

```python
_REGISTRY: dict[str, type] = {
    "file_upload": FileUploadRetriever,
    "text": TextRetriever,
    "url": UrlRetriever,
    "git_repo": GitRepoRetriever,
    "mcp_source": McpSourceRetriever,  # Stub
}
```

### 4.4 Individual Retrievers

#### Text Retriever

**File**: `app/services/retrievers/text_retriever.py`

- Accepts raw text string
- Writes to `content.txt`
- Creates `metadata.json`
- MIME type: `text/plain`

#### File Upload Retriever

**File**: `app/services/retrievers/file_upload.py`

- Accepts raw bytes from upload
- Preserves original filename
- Detects MIME type via `mimetypes.guess_type()`
- Size validation against `max_upload_bytes`

#### URL Retriever

**File**: `app/services/retrievers/url_retriever.py`

- Uses `ExtractionPipeline` for content extraction
- Multi-tier approach:
  1. Static HTML extraction (trafilatura + newspaper4k)
  2. JavaScript rendering via Playwright (if static fails)
- Writes extracted markdown to `content.md`
- Includes extraction metadata (word_count, extraction_method, warnings)

#### Git Repo Retriever

**File**: `app/services/retrievers/git_repo.py`

- Executes `git clone --depth N --single-branch`
- Clones to `{content_dir}/repo/`
- Configurable timeout and depth
- Calculates total repository size

#### MCP Source Retriever

**File**: `app/services/retrievers/mcp_source.py`

- **Placeholder/Stub** - returns error "not yet implemented"

### 4.5 URL Extraction Pipeline

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/extractors/pipeline.py`

```
ExtractionPipeline
    |
    +--> _fetch_url() [httpx async client]
    |
    +--> HTMLExtractor [trafilatura + newspaper4k]
    |
    +--> (fallback) JSExtractor [Playwright]
```

**Exception Hierarchy**:

- `ExtractionError` (base)
  - `NetworkError`
  - `ContentTypeError`
  - `EmptyContentError`
  - `RateLimitError`
  - `ContentTooLargeError`

---

## 5. Content Service Workflow

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/services/content_service.py`

### 5.1 Add Content Flow

1. **Validate session exists** - raises 404 if not found
2. **Generate content_id** - UUID4
3. **Create ContentItem record** - status=PROCESSING
4. **Create target directory** - `{sandbox}/{session_id}/{content_id}/`
5. **Get retriever** - from factory by content_type
6. **Call retriever.retrieve()** - passes source, target_dir, title, metadata
7. **Update ContentItem** - status=READY or ERROR, update metadata
8. **Touch session** - mark_accessed()
9. **Return response**

### 5.2 Batch Add Content Flow

1. **Validate session exists**
2. **Query existing content** by source_ref for duplicate detection
3. **Track seen URLs** in batch for intra-batch deduplication
4. **For each URL**:
   - Skip if duplicate (existing or within batch)
   - Call `add_content()` for non-duplicates
   - Capture result or error
5. **Return BatchContentResponse** with summary counts

### 5.3 Delete Content Flow

1. **Validate session exists**
2. **Query content item**
3. **Delete database record**
4. **Remove storage directory** - `shutil.rmtree()`

---

## 6. Security: Path Validation

**File**: `/Users/mac/workspace/research-mind/research-mind-service/app/sandbox/path_validator.py`

### 6.1 PathValidator Class

Validates all file paths to prevent:

- Directory traversal attacks (`../`)
- URL-encoded traversal (`%2e%2e%2f`)
- Symlink escapes
- Hidden file access (`.` prefix)
- System path access (`/etc`, `/root`, etc.)

### 6.2 Validation Steps

1. URL-decode the path (twice, for double-encoding)
2. Resolve to absolute path
3. Verify path is within workspace root
4. Block hidden files (components starting with `.`)
5. Block system paths
6. Block symlinks anywhere in path chain

### 6.3 Methods

- `validate_path(path)` - general path validation
- `safe_read(path)` - validate + read file
- `safe_list_dir(path)` - validate + list directory
- `validate_workspace_for_subprocess(path)` - strict validation for subprocess cwd

---

## 7. Dependencies (pyproject.toml)

**File**: `/Users/mac/workspace/research-mind/research-mind-service/pyproject.toml`

### 7.1 Content Processing Libraries

| Library                  | Purpose                             |
| ------------------------ | ----------------------------------- |
| `trafilatura>=1.12.0`    | HTML content extraction             |
| `newspaper4k>=0.9.0`     | News article extraction             |
| `playwright>=1.45.0`     | JavaScript-rendered page extraction |
| `beautifulsoup4>=4.12.0` | HTML parsing                        |
| `lxml>=5.0.0`            | XML/HTML processing                 |
| `httpx>=0.25.0`          | Async HTTP client                   |

### 7.2 Document Processing (Existing)

| Library            | Purpose             |
| ------------------ | ------------------- |
| `weasyprint>=62.0` | PDF generation      |
| `markdown>=3.5.0`  | Markdown processing |

### 7.3 Missing/Potential Libraries

For PDF document content extraction (if needed in future):

- `pypdf` or `PyPDF2` - PDF text extraction
- `pdfplumber` - PDF table/text extraction
- `pymupdf` (fitz) - Fast PDF processing

For Office documents:

- `python-docx` - DOCX reading
- `openpyxl` - XLSX reading
- `python-pptx` - PPTX reading

---

## 8. Key Code Locations Summary

| Component                 | File Path                                   |
| ------------------------- | ------------------------------------------- |
| **Content Model**         | `app/models/content_item.py`                |
| **Content Schemas**       | `app/schemas/content.py`                    |
| **Content Routes**        | `app/routes/content.py`                     |
| **Content Service**       | `app/services/content_service.py`           |
| **Retriever Base**        | `app/services/retrievers/base.py`           |
| **Retriever Factory**     | `app/services/retrievers/factory.py`        |
| **Text Retriever**        | `app/services/retrievers/text_retriever.py` |
| **URL Retriever**         | `app/services/retrievers/url_retriever.py`  |
| **Git Retriever**         | `app/services/retrievers/git_repo.py`       |
| **File Upload Retriever** | `app/services/retrievers/file_upload.py`    |
| **MCP Retriever (Stub)**  | `app/services/retrievers/mcp_source.py`     |
| **Extraction Pipeline**   | `app/services/extractors/pipeline.py`       |
| **HTML Extractor**        | `app/services/extractors/html_extractor.py` |
| **JS Extractor**          | `app/services/extractors/js_extractor.py`   |
| **Path Validator**        | `app/sandbox/path_validator.py`             |
| **Configuration**         | `app/core/config.py`                        |
| **API Contract**          | `docs/api-contract.md`                      |
| **Session Model**         | `app/models/session.py`                     |

---

## 9. Architectural Patterns

### 9.1 Strengths

1. **Strategy Pattern** - Retrievers implement a common protocol, factory selects implementation
2. **Clear separation** - Routes -> Service -> Retrievers -> Storage
3. **Async extraction** - URL processing uses async pipeline for performance
4. **Flexible metadata** - JSON column allows content-type-specific data
5. **Security-first** - PathValidator prevents traversal and symlink attacks
6. **Graceful degradation** - URL extraction falls back from static to JS rendering

### 9.2 Extension Points

1. **New content types** - Add to ContentType enum and create retriever class
2. **New extraction methods** - Add extractors to pipeline
3. **Metadata enrichment** - Extend metadata_json schema per content type

### 9.3 Current Limitations

1. **MCP Source not implemented** - Stub only
2. **No PDF text extraction** - Files stored but not extracted
3. **No Office document extraction** - Files stored but not extracted
4. **Synchronous retrieval** - Long operations block request
5. **No background processing** - No job queue for async retrieval

---

## 10. Recommendations for Future Development

### 10.1 Immediate (If extending content types)

1. Add document content extraction libraries (pypdf, python-docx)
2. Create `FileContentExtractor` for extracting text from uploaded files
3. Consider async processing with job queue for large files

### 10.2 Medium-term

1. Implement MCP Source retriever for MCP tool integration
2. Add retry mechanism for failed retrievals
3. Consider content deduplication by hash
4. Add preview generation for binary content types

### 10.3 Architecture Considerations

1. Background job processing (Celery, RQ) for long-running retrievals
2. Content versioning for updates
3. Streaming upload for large files
4. CDN integration for content serving

---

**End of Research Document**
