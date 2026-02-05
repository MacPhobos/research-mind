# Document Content Retriever Implementation Plan

**Created**: 2026-02-05
**Status**: PENDING APPROVAL
**Author**: PM Agent

---

## 1. Overview

### 1.1 Objective

Add a new `document` content type that allows users to upload document files (PDF, DOCX, MD, TXT) and have the backend extract text content with structure preservation, storing it as markdown in the session sandbox directory.

### 1.2 Supported Formats

| Format     | Extension | Processing Method                  | Output        |
| ---------- | --------- | ---------------------------------- | ------------- |
| PDF        | `.pdf`    | PyMuPDF4LLM (structure detection)  | `content.md`  |
| Word       | `.docx`   | Mammoth → HTML → Markdown          | `content.md`  |
| Markdown   | `.md`     | Direct storage (no transformation) | `content.md`  |
| Plain Text | `.txt`    | Direct storage (no transformation) | `content.txt` |

### 1.3 Key Design Decisions

| Decision           | Choice                                            | Rationale                                                                              |
| ------------------ | ------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Content Type       | New `document` type (separate from `file_upload`) | Clear separation of intent; `file_upload` preserves files, `document` extracts content |
| PDF Processing     | PyMuPDF4LLM with structure detection              | Native markdown output, headers/lists/tables preserved                                 |
| Original File      | Discarded after extraction                        | User requirement; reduces storage                                                      |
| Metadata           | Extracted and stored in `metadata.json`           | Provides document context (title, author, page count)                                  |
| Partial Extraction | Fail entire operation                             | User requirement; ensures data integrity                                               |

---

## 2. Architecture

### 2.1 Component Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                         API Layer                                │
│  POST /api/v1/sessions/{id}/content (multipart/form-data)       │
│  content_type: "document", file: <uploaded file>                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ContentService                              │
│  - Validates file extension against allowed formats             │
│  - Creates ContentItem with type="document"                     │
│  - Delegates to RetrieverFactory                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     RetrieverFactory                             │
│  - Maps "document" → DocumentRetriever                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DocumentRetriever                             │
│  - Detects format from file extension                           │
│  - Routes to appropriate extractor                              │
│  - Extracts metadata                                            │
│  - Saves content.md/content.txt + metadata.json                 │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
    │PDFExtractor │   │DOCXExtractor│   │TextExtractor│
    │(pymupdf4llm)│   │(mammoth)    │   │(direct copy)│
    └─────────────┘   └─────────────┘   └─────────────┘
```

### 2.2 File Storage Structure

```
{content_sandbox_root}/{session_id}/{content_id}/
├── content.md          # Extracted content (PDF, DOCX, MD)
│   OR
├── content.txt         # Plain text content (TXT files only)
└── metadata.json       # Document metadata
```

**Note**: Original uploaded file is NOT retained after successful extraction.

### 2.3 Metadata Schema

```json
{
  "original_filename": "quarterly-report.pdf",
  "file_extension": ".pdf",
  "file_size_bytes": 2457600,
  "extraction_method": "pymupdf4llm",
  "extracted_at": "2026-02-05T14:30:00Z",
  "document_metadata": {
    "title": "Q4 2025 Quarterly Report",
    "author": "Finance Team",
    "page_count": 24,
    "creation_date": "2025-12-15T10:00:00Z",
    "modification_date": "2026-01-02T15:30:00Z"
  },
  "content_stats": {
    "character_count": 45230,
    "word_count": 7845,
    "line_count": 892
  }
}
```

---

## 3. API Contract Changes

### 3.1 Version Bump

**Current**: v1.7.0
**New**: v1.8.0 (minor version bump - new content type, backward compatible)

### 3.2 Updated ContentType Enum

```yaml
ContentType:
  type: string
  enum:
    - text
    - url
    - git_repo
    - file_upload
    - mcp_source
    - document # NEW
```

### 3.3 Request Format

**Endpoint**: `POST /api/v1/sessions/{session_id}/content`
**Content-Type**: `multipart/form-data`

| Field          | Type     | Required | Description                                    |
| -------------- | -------- | -------- | ---------------------------------------------- |
| `content_type` | string   | Yes      | Must be `"document"`                           |
| `file`         | file     | Yes      | Document file (PDF, DOCX, MD, TXT)             |
| `title`        | string   | No       | Optional title override (defaults to filename) |
| `tags`         | string[] | No       | Optional tags for categorization               |

### 3.4 Response Format

**Success (201 Created)**:

```json
{
  "id": "uuid",
  "session_id": "uuid",
  "content_type": "document",
  "title": "quarterly-report.pdf",
  "status": "ready",
  "metadata": {
    "original_filename": "quarterly-report.pdf",
    "file_extension": ".pdf",
    "extraction_method": "pymupdf4llm",
    "document_metadata": {
      "title": "Q4 2025 Quarterly Report",
      "page_count": 24
    },
    "content_stats": {
      "word_count": 7845
    }
  },
  "created_at": "2026-02-05T14:30:00Z"
}
```

**Error (400 Bad Request - Unsupported Format)**:

```json
{
  "detail": "Unsupported document format: .xlsx. Supported formats: .pdf, .docx, .md, .txt"
}
```

**Error (422 Unprocessable Entity - Extraction Failed)**:

```json
{
  "detail": "Failed to extract content from document: PDF is encrypted and requires a password"
}
```

### 3.5 API Contract Changelog Entry

```markdown
## v1.8.0 (2026-02-XX)

### Added

- New `document` content type for extracting text from uploaded documents
- Supported formats: PDF, DOCX, MD, TXT
- PDF extraction with structure detection (headers, paragraphs, lists)
- DOCX to markdown conversion
- Document metadata extraction (title, author, page count)
```

---

## 4. Implementation Details

### 4.1 New Dependencies

Add to `pyproject.toml`:

```toml
[project.dependencies]
# ... existing dependencies ...

# Document extraction
pymupdf = ">=1.24.0"           # PDF handling (PyMuPDF/fitz)
pymupdf4llm = ">=0.2.0"        # PDF to markdown with structure
mammoth = ">=1.6.0"            # DOCX to HTML extraction
markdownify = ">=0.13.0"       # HTML to markdown conversion
```

**License Notes**:

- `pymupdf` / `pymupdf4llm`: AGPL-3.0 (acceptable for open-source project)
- `mammoth`: BSD-2-Clause
- `markdownify`: MIT

### 4.2 New Files

```
research-mind-service/
├── app/
│   ├── services/
│   │   └── retrievers/
│   │       └── document.py           # NEW: DocumentRetriever
│   └── services/
│       └── extractors/
│           └── document/             # NEW: Document extractors
│               ├── __init__.py
│               ├── base.py           # Base extractor protocol
│               ├── pdf.py            # PDF extractor (pymupdf4llm)
│               ├── docx.py           # DOCX extractor (mammoth)
│               └── text.py           # TXT/MD extractor (direct)
└── tests/
    └── services/
        └── extractors/
            └── document/             # NEW: Extractor tests
                ├── test_pdf.py
                ├── test_docx.py
                └── test_text.py
```

### 4.3 Modified Files

| File                                 | Change                                        |
| ------------------------------------ | --------------------------------------------- |
| `app/models/content_item.py`         | Add `document` to `ContentType` enum          |
| `app/services/retrievers/factory.py` | Register `DocumentRetriever`                  |
| `app/services/content_service.py`    | Handle `document` content type in add_content |
| `docs/api-contract.md`               | Document new content type                     |
| `pyproject.toml`                     | Add new dependencies                          |

---

## 5. DocumentRetriever Implementation

### 5.1 Retriever Class

```python
# app/services/retrievers/document.py

from pathlib import Path
from typing import Protocol
import json
from datetime import datetime

from app.services.retrievers.base import ContentRetriever, RetrievalResult
from app.services.extractors.document import (
    PDFExtractor,
    DOCXExtractor,
    TextExtractor,
)


SUPPORTED_EXTENSIONS = {".pdf", ".docx", ".md", ".txt"}


class DocumentRetriever(ContentRetriever):
    """Retrieves and extracts content from document files."""

    EXTRACTOR_MAP = {
        ".pdf": PDFExtractor,
        ".docx": DOCXExtractor,
        ".md": TextExtractor,
        ".txt": TextExtractor,
    }

    async def retrieve(
        self,
        source: Path,  # Uploaded temp file path
        destination: Path,  # Content sandbox directory
        metadata: dict | None = None,
    ) -> RetrievalResult:
        """Extract content from document and save to sandbox."""

        # 1. Validate file extension
        extension = source.suffix.lower()
        if extension not in SUPPORTED_EXTENSIONS:
            raise ValueError(
                f"Unsupported document format: {extension}. "
                f"Supported formats: {', '.join(sorted(SUPPORTED_EXTENSIONS))}"
            )

        # 2. Get appropriate extractor
        extractor_class = self.EXTRACTOR_MAP[extension]
        extractor = extractor_class()

        # 3. Extract content (raises on failure - no partial extraction)
        extraction_result = await extractor.extract(source)

        # 4. Determine output filename
        output_filename = "content.txt" if extension == ".txt" else "content.md"
        output_path = destination / output_filename

        # 5. Write extracted content
        destination.mkdir(parents=True, exist_ok=True)
        output_path.write_text(extraction_result.content, encoding="utf-8")

        # 6. Build and save metadata
        full_metadata = {
            "original_filename": source.name,
            "file_extension": extension,
            "file_size_bytes": source.stat().st_size,
            "extraction_method": extractor.method_name,
            "extracted_at": datetime.utcnow().isoformat() + "Z",
            "document_metadata": extraction_result.document_metadata,
            "content_stats": {
                "character_count": len(extraction_result.content),
                "word_count": len(extraction_result.content.split()),
                "line_count": extraction_result.content.count("\n") + 1,
            },
        }

        metadata_path = destination / "metadata.json"
        metadata_path.write_text(
            json.dumps(full_metadata, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

        # 7. Original file is NOT copied (discarded per requirements)

        return RetrievalResult(
            success=True,
            content_path=output_path,
            metadata=full_metadata,
        )
```

### 5.2 PDF Extractor

```python
# app/services/extractors/document/pdf.py

from pathlib import Path
from dataclasses import dataclass
import pymupdf4llm
import fitz  # PyMuPDF


@dataclass
class ExtractionResult:
    content: str
    document_metadata: dict


class PDFExtractor:
    """Extract text from PDF with structure detection."""

    method_name = "pymupdf4llm"

    async def extract(self, source: Path) -> ExtractionResult:
        """Extract markdown content from PDF."""

        # Open PDF to check for encryption and get metadata
        doc = fitz.open(str(source))

        try:
            # Check for encryption
            if doc.is_encrypted:
                raise ValueError(
                    "PDF is encrypted and requires a password. "
                    "Please provide an unencrypted document."
                )

            # Extract document metadata
            pdf_metadata = doc.metadata or {}
            document_metadata = {
                "title": pdf_metadata.get("title") or None,
                "author": pdf_metadata.get("author") or None,
                "subject": pdf_metadata.get("subject") or None,
                "page_count": len(doc),
                "creation_date": pdf_metadata.get("creationDate") or None,
                "modification_date": pdf_metadata.get("modDate") or None,
            }
            # Remove None values
            document_metadata = {k: v for k, v in document_metadata.items() if v is not None}

        finally:
            doc.close()

        # Extract content with structure detection
        # pymupdf4llm handles headers, lists, tables automatically
        markdown_content = pymupdf4llm.to_markdown(
            str(source),
            page_chunks=False,  # Return single string, not list
        )

        if not markdown_content or not markdown_content.strip():
            raise ValueError(
                "No text content could be extracted from PDF. "
                "The document may be image-only or corrupted."
            )

        return ExtractionResult(
            content=markdown_content.strip(),
            document_metadata=document_metadata,
        )
```

### 5.3 DOCX Extractor

```python
# app/services/extractors/document/docx.py

from pathlib import Path
from dataclasses import dataclass
import mammoth
from markdownify import markdownify as md
from docx import Document  # python-docx for metadata


@dataclass
class ExtractionResult:
    content: str
    document_metadata: dict


class DOCXExtractor:
    """Extract markdown from DOCX using Mammoth."""

    method_name = "mammoth"

    async def extract(self, source: Path) -> ExtractionResult:
        """Extract markdown content from DOCX."""

        # Extract metadata using python-docx
        document_metadata = {}
        try:
            doc = Document(str(source))
            core_props = doc.core_properties
            document_metadata = {
                "title": core_props.title or None,
                "author": core_props.author or None,
                "subject": core_props.subject or None,
                "created": core_props.created.isoformat() if core_props.created else None,
                "modified": core_props.modified.isoformat() if core_props.modified else None,
            }
            # Remove None values
            document_metadata = {k: v for k, v in document_metadata.items() if v is not None}
        except Exception:
            # Metadata extraction is best-effort
            pass

        # Convert DOCX to HTML using Mammoth
        with open(source, "rb") as f:
            result = mammoth.convert_to_html(f)
            html_content = result.value

        if not html_content or not html_content.strip():
            raise ValueError(
                "No content could be extracted from DOCX. "
                "The document may be empty or corrupted."
            )

        # Convert HTML to Markdown
        markdown_content = md(
            html_content,
            heading_style="ATX",        # Use # style headings
            bullets="-",                 # Use - for unordered lists
            strip=["script", "style"],  # Remove script/style tags
        )

        return ExtractionResult(
            content=markdown_content.strip(),
            document_metadata=document_metadata,
        )
```

### 5.4 Text/Markdown Extractor

```python
# app/services/extractors/document/text.py

from pathlib import Path
from dataclasses import dataclass


@dataclass
class ExtractionResult:
    content: str
    document_metadata: dict


class TextExtractor:
    """Direct extraction for TXT and MD files."""

    method_name = "direct"

    async def extract(self, source: Path) -> ExtractionResult:
        """Read text content directly."""

        # Try multiple encodings
        encodings = ["utf-8", "utf-8-sig", "latin-1", "cp1252"]
        content = None

        for encoding in encodings:
            try:
                content = source.read_text(encoding=encoding)
                break
            except UnicodeDecodeError:
                continue

        if content is None:
            raise ValueError(
                "Unable to decode text file. "
                "Please ensure the file uses UTF-8 or Latin-1 encoding."
            )

        if not content.strip():
            raise ValueError("Text file is empty.")

        # Minimal metadata for text files
        document_metadata = {
            "encoding_detected": encoding,
        }

        return ExtractionResult(
            content=content,
            document_metadata=document_metadata,
        )
```

---

## 6. Error Handling

### 6.1 Error Categories

| Error Type         | HTTP Status              | Example                  |
| ------------------ | ------------------------ | ------------------------ |
| Unsupported format | 400 Bad Request          | `.xlsx`, `.pptx`, `.csv` |
| Encrypted document | 422 Unprocessable Entity | Password-protected PDF   |
| Corrupted document | 422 Unprocessable Entity | Malformed PDF structure  |
| Empty document     | 422 Unprocessable Entity | No extractable text      |
| Encoding error     | 422 Unprocessable Entity | Unknown text encoding    |
| File too large     | 413 Payload Too Large    | Exceeds 50MB limit       |

### 6.2 Error Messages

All error messages should be user-friendly and actionable:

```python
ERROR_MESSAGES = {
    "unsupported_format": (
        "Unsupported document format: {ext}. "
        "Supported formats: .pdf, .docx, .md, .txt"
    ),
    "encrypted_pdf": (
        "PDF is encrypted and requires a password. "
        "Please provide an unencrypted document."
    ),
    "empty_document": (
        "No text content could be extracted from the document. "
        "The document may be empty or contain only images."
    ),
    "corrupted_document": (
        "The document appears to be corrupted or malformed. "
        "Please verify the file is valid."
    ),
    "encoding_error": (
        "Unable to decode text file. "
        "Please ensure the file uses UTF-8 or Latin-1 encoding."
    ),
}
```

### 6.3 Failure Behavior

Per requirements, **any extraction failure fails the entire operation**:

- No partial content is stored
- No ContentItem is created in database
- Uploaded file is discarded
- Clear error message returned to user

---

## 7. Testing Strategy

### 7.1 Unit Tests

**PDF Extractor Tests** (`tests/services/extractors/document/test_pdf.py`):

- `test_extract_simple_pdf` - Basic text extraction
- `test_extract_pdf_with_headers` - Structure detection (H1, H2, H3)
- `test_extract_pdf_with_lists` - Ordered and unordered lists
- `test_extract_pdf_with_tables` - Table preservation
- `test_extract_pdf_metadata` - Title, author, page count
- `test_encrypted_pdf_raises_error` - Password-protected PDF
- `test_image_only_pdf_raises_error` - No text content
- `test_corrupted_pdf_raises_error` - Malformed PDF

**DOCX Extractor Tests** (`tests/services/extractors/document/test_docx.py`):

- `test_extract_simple_docx` - Basic text extraction
- `test_extract_docx_with_formatting` - Bold, italic, headings
- `test_extract_docx_with_lists` - Bullet and numbered lists
- `test_extract_docx_metadata` - Document properties
- `test_empty_docx_raises_error` - Empty document
- `test_corrupted_docx_raises_error` - Malformed DOCX

**Text Extractor Tests** (`tests/services/extractors/document/test_text.py`):

- `test_extract_utf8_text` - Standard UTF-8
- `test_extract_utf8_bom_text` - UTF-8 with BOM
- `test_extract_latin1_text` - Latin-1 encoding
- `test_extract_markdown_file` - Markdown passthrough
- `test_empty_text_raises_error` - Empty file
- `test_binary_file_raises_error` - Non-text content

### 7.2 Integration Tests

**DocumentRetriever Tests** (`tests/services/retrievers/test_document.py`):

- `test_retrieve_pdf_creates_markdown_file`
- `test_retrieve_docx_creates_markdown_file`
- `test_retrieve_txt_creates_text_file`
- `test_retrieve_md_creates_markdown_file`
- `test_metadata_json_created`
- `test_original_file_not_retained`
- `test_unsupported_extension_raises_error`

### 7.3 API Tests

**Content Endpoint Tests** (`tests/routes/test_content.py`):

- `test_add_document_pdf_success`
- `test_add_document_docx_success`
- `test_add_document_txt_success`
- `test_add_document_unsupported_format_400`
- `test_add_document_encrypted_pdf_422`
- `test_add_document_too_large_413`

### 7.4 Test Fixtures

Create test fixtures directory with sample documents:

```
tests/fixtures/documents/
├── simple.pdf            # Basic text PDF
├── structured.pdf        # PDF with headers, lists, tables
├── encrypted.pdf         # Password-protected PDF
├── image-only.pdf        # PDF with only images
├── simple.docx           # Basic text DOCX
├── formatted.docx        # DOCX with formatting
├── simple.txt            # UTF-8 text file
├── latin1.txt            # Latin-1 encoded file
└── sample.md             # Markdown file
```

---

## 8. Implementation Phases

### Phase 1: Core Infrastructure (Day 1)

1. Add dependencies to `pyproject.toml`
2. Update `ContentType` enum in models
3. Create base extractor protocol
4. Create directory structure for new files

### Phase 2: Extractors (Day 2)

1. Implement `PDFExtractor` with tests
2. Implement `DOCXExtractor` with tests
3. Implement `TextExtractor` with tests
4. Create test fixtures

### Phase 3: DocumentRetriever (Day 3)

1. Implement `DocumentRetriever`
2. Register in `RetrieverFactory`
3. Integration tests for retriever

### Phase 4: API Integration (Day 4)

1. Update `ContentService` to handle document type
2. Update API contract documentation (v1.8.0)
3. API endpoint tests
4. Error handling tests

### Phase 5: Documentation & QA (Day 5)

1. Update API contract in both locations
2. Regenerate frontend types (`make gen-client`)
3. Full regression testing
4. Manual QA verification

---

## 9. Acceptance Criteria

### 9.1 Functional Requirements

- [ ] PDF files extract to markdown with headers, paragraphs preserved
- [ ] DOCX files convert to markdown via Mammoth
- [ ] TXT files store as plain text
- [ ] MD files store as-is (no transformation)
- [ ] Document metadata extracted and stored in metadata.json
- [ ] Original uploaded file is NOT retained after extraction
- [ ] Unsupported formats return 400 error
- [ ] Encrypted PDFs return 422 error with clear message
- [ ] Empty documents return 422 error

### 9.2 Non-Functional Requirements

- [ ] PDF extraction completes in <5 seconds for documents <100 pages
- [ ] DOCX extraction completes in <3 seconds for typical documents
- [ ] Memory usage stays under 500MB during extraction
- [ ] All new code has >90% test coverage

### 9.3 Contract Requirements

- [ ] API contract updated to v1.8.0
- [ ] Both api-contract.md files are identical
- [ ] Frontend types regenerated successfully
- [ ] Changelog entry added

---

## 10. Risks and Mitigations

| Risk                     | Impact                    | Mitigation                                                                |
| ------------------------ | ------------------------- | ------------------------------------------------------------------------- |
| PyMuPDF AGPL license     | May affect commercial use | Project is open-source; acceptable. Document in README if license changes |
| Large PDF memory usage   | OOM on big documents      | Add 100-page limit initially; can increase after testing                  |
| Complex PDF layouts      | Poor markdown output      | Accept best-effort; most documents will work well                         |
| Mammoth missing features | Some DOCX formatting lost | Accept limitations; Mammoth handles 95% of cases                          |

---

## 11. Future Enhancements (Out of Scope)

These are explicitly NOT part of this implementation but noted for future consideration:

1. **Additional formats**: `.xlsx`, `.pptx`, `.csv`, `.rtf`
2. **OCR for image PDFs**: Integrate Tesseract for image-only PDFs
3. **Background processing**: Queue large documents for async extraction
4. **Content deduplication**: Hash-based detection of duplicate uploads
5. **Original file retention**: Optional flag to keep original alongside extracted

---

## Approval

**Awaiting approval to proceed with implementation.**

- [ ] Approved by: **\*\***\_\_\_\_**\*\***
- [ ] Date: **\*\***\_\_\_\_**\*\***

---

## References

- [PyMuPDF4LLM Documentation](https://pymupdf.readthedocs.io/en/latest/pymupdf4llm/)
- [Mammoth Documentation](https://github.com/mwilliamson/python-mammoth)
- [Markdownify Documentation](https://github.com/matthewwithanm/python-markdownify)
- Content Architecture Research: `docs/research/content-item-architecture-2026-02-05.md`
- PDF Library Comparison: `docs/research/pdf-text-extraction-libraries-comparison-2026-02-05.md`
