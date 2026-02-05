# Chat Export Implementation Plan

## Overview

This document outlines the implementation plan for adding chat export functionality to the research-mind application. Users will be able to export chat history in PDF or Markdown format, either as a full conversation export or as individual question/answer pairs.

**Version**: 1.0.0
**Created**: 2026-02-04
**Status**: Draft

---

## Table of Contents

1. [Requirements Summary](#requirements-summary)
2. [API Contract Changes](#api-contract-changes)
3. [Backend Implementation](#backend-implementation)
4. [Frontend Implementation](#frontend-implementation)
5. [Test Requirements](#test-requirements)
6. [Implementation Phases](#implementation-phases)
7. [Technical Decisions](#technical-decisions)
8. [Appendix](#appendix)

---

## Requirements Summary

### User Stories

1. **US-1**: As a user, I want to export my entire chat history so I can save conversations for future reference.
2. **US-2**: As a user, I want to export a specific question/answer pair so I can share individual insights.
3. **US-3**: As a user, I want to choose between PDF and Markdown formats based on my needs.

### Functional Requirements

| ID   | Requirement                                                                  | Priority |
| ---- | ---------------------------------------------------------------------------- | -------- |
| FR-1 | Export full chat history button in bottom bar (left of "clear chat history") | P1       |
| FR-2 | Export specific Q/A button next to each assistant response                   | P1       |
| FR-3 | Format selection dialog (PDF/Markdown)                                       | P1       |
| FR-4 | Download button triggers browser download                                    | P1       |
| FR-5 | Generate exports on-demand (no permanent storage)                            | P1       |
| FR-6 | Include metadata (session name, date, timestamps) in export                  | P2       |
| FR-7 | Preserve markdown formatting in exports                                      | P2       |

### Non-Functional Requirements

| ID    | Requirement                                                                 |
| ----- | --------------------------------------------------------------------------- |
| NFR-1 | Export generation must complete within 10 seconds for typical conversations |
| NFR-2 | PDF must be properly formatted with readable typography                     |
| NFR-3 | Markdown export must be valid GitHub-flavored markdown                      |
| NFR-4 | No files stored on server after download (stateless)                        |

---

## API Contract Changes

### Version Bump

- **Current Version**: 1.6.0
- **New Version**: 1.7.0 (minor - new endpoints, no breaking changes)

### New Endpoints

#### 1. Export Full Chat History

```
POST /api/v1/sessions/{session_id}/chat/export
```

**Description**: Generate and download full chat history in specified format.

**Path Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| session_id | uuid | Yes | Session UUID |

**Request Body**:

```json
{
  "format": "pdf" | "markdown",
  "include_metadata": true,
  "include_timestamps": true
}
```

**Request Schema**:
| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| format | string | Yes | - | Export format: "pdf" or "markdown" |
| include_metadata | boolean | No | true | Include session name, export date |
| include_timestamps | boolean | No | true | Include message timestamps |

**Response**: Binary file download

**Response Headers**:

```
Content-Type: application/pdf (for PDF)
Content-Type: text/markdown; charset=utf-8 (for Markdown)
Content-Disposition: attachment; filename="chat-export-{session_id}-{timestamp}.{ext}"
```

**Error Responses**:
| Status | Error Code | Description |
|--------|------------|-------------|
| 400 | INVALID_FORMAT | Format must be "pdf" or "markdown" |
| 404 | SESSION_NOT_FOUND | Session does not exist |
| 404 | NO_CHAT_MESSAGES | No messages to export |
| 500 | EXPORT_GENERATION_FAILED | Failed to generate export file |

#### 2. Export Single Q/A Pair

```
POST /api/v1/sessions/{session_id}/chat/{message_id}/export
```

**Description**: Generate and download a specific question/answer pair.

**Path Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| session_id | uuid | Yes | Session UUID |
| message_id | uuid | Yes | Assistant message UUID (will include preceding user message) |

**Request Body**:

```json
{
  "format": "pdf" | "markdown",
  "include_metadata": true,
  "include_timestamps": true
}
```

**Response**: Binary file download (same headers as full export)

**Error Responses**:
| Status | Error Code | Description |
|--------|------------|-------------|
| 400 | INVALID_FORMAT | Format must be "pdf" or "markdown" |
| 400 | NOT_ASSISTANT_MESSAGE | Can only export from assistant messages |
| 404 | SESSION_NOT_FOUND | Session does not exist |
| 404 | CHAT_MESSAGE_NOT_FOUND | Message does not exist |
| 404 | NO_PRECEDING_USER_MESSAGE | Assistant message has no preceding user question |
| 500 | EXPORT_GENERATION_FAILED | Failed to generate export file |

### New Schemas

#### ChatExportRequest

```python
class ChatExportFormat(str, Enum):
    PDF = "pdf"
    MARKDOWN = "markdown"

class ChatExportRequest(BaseModel):
    format: ChatExportFormat
    include_metadata: bool = True
    include_timestamps: bool = True
```

### Contract Changelog Entry

```markdown
### [1.7.0] - 2026-02-XX

#### Added

- POST `/api/v1/sessions/{session_id}/chat/export` - Export full chat history
- POST `/api/v1/sessions/{session_id}/chat/{message_id}/export` - Export single Q/A pair
- `ChatExportRequest` schema for export configuration
- `ChatExportFormat` enum: "pdf", "markdown"
- New error codes: INVALID_FORMAT, NO_CHAT_MESSAGES, EXPORT_GENERATION_FAILED, NOT_ASSISTANT_MESSAGE, NO_PRECEDING_USER_MESSAGE
```

---

## Backend Implementation

### Directory Structure

```
research-mind-service/
├── app/
│   ├── schemas/
│   │   └── chat.py              # Add ChatExportRequest, ChatExportFormat
│   ├── routes/
│   │   └── chat.py              # Add export endpoints
│   ├── services/
│   │   └── export/              # NEW directory
│   │       ├── __init__.py
│   │       ├── base.py          # Abstract exporter interface
│   │       ├── markdown.py      # Markdown exporter
│   │       ├── pdf.py           # PDF exporter
│   │       └── templates/       # PDF templates (if using HTML-to-PDF)
│   │           └── chat.html
│   └── core/
│       └── exceptions.py        # Add new exception classes
├── tests/
│   └── routes/
│       └── test_chat_export.py  # NEW test file
└── pyproject.toml               # Add PDF library dependency
```

### Schema Changes (app/schemas/chat.py)

Add the following to the existing `chat.py` schema file:

```python
from enum import Enum
from pydantic import BaseModel


class ChatExportFormat(str, Enum):
    """Supported export formats for chat history."""
    PDF = "pdf"
    MARKDOWN = "markdown"


class ChatExportRequest(BaseModel):
    """Request body for chat export endpoints."""
    format: ChatExportFormat
    include_metadata: bool = True
    include_timestamps: bool = True

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "format": "pdf",
                    "include_metadata": True,
                    "include_timestamps": True
                }
            ]
        }
    }
```

### Exception Classes (app/core/exceptions.py)

Add new exception classes:

```python
class ExportError(AppError):
    """Base exception for export-related errors."""
    pass


class InvalidExportFormatError(ExportError):
    """Raised when an invalid export format is specified."""
    def __init__(self, format_value: str):
        super().__init__(
            status_code=400,
            error_code="INVALID_FORMAT",
            message=f"Invalid export format: {format_value}. Must be 'pdf' or 'markdown'."
        )


class NoChatMessagesError(ExportError):
    """Raised when there are no messages to export."""
    def __init__(self, session_id: str):
        super().__init__(
            status_code=404,
            error_code="NO_CHAT_MESSAGES",
            message=f"No chat messages found for session {session_id}"
        )


class ExportGenerationError(ExportError):
    """Raised when export file generation fails."""
    def __init__(self, detail: str = ""):
        super().__init__(
            status_code=500,
            error_code="EXPORT_GENERATION_FAILED",
            message=f"Failed to generate export file. {detail}".strip()
        )


class NotAssistantMessageError(ExportError):
    """Raised when trying to export from a non-assistant message."""
    def __init__(self, message_id: str):
        super().__init__(
            status_code=400,
            error_code="NOT_ASSISTANT_MESSAGE",
            message=f"Message {message_id} is not an assistant message. Single export must target assistant messages."
        )


class NoPrecedingUserMessageError(ExportError):
    """Raised when assistant message has no preceding user question."""
    def __init__(self, message_id: str):
        super().__init__(
            status_code=404,
            error_code="NO_PRECEDING_USER_MESSAGE",
            message=f"No preceding user message found for assistant message {message_id}"
        )
```

### Export Service Interface (app/services/export/base.py)

```python
from abc import ABC, abstractmethod
from typing import List
from dataclasses import dataclass
from datetime import datetime

from app.models.chat_message import ChatMessage
from app.models.session import Session


@dataclass
class ExportMetadata:
    """Metadata to include in export."""
    session_name: str
    session_id: str
    export_date: datetime
    message_count: int
    include_timestamps: bool


class ChatExporter(ABC):
    """Abstract base class for chat exporters."""

    @property
    @abstractmethod
    def content_type(self) -> str:
        """MIME type for the export format."""
        pass

    @property
    @abstractmethod
    def file_extension(self) -> str:
        """File extension for the export format."""
        pass

    @abstractmethod
    def export(
        self,
        messages: List[ChatMessage],
        metadata: ExportMetadata,
    ) -> bytes:
        """
        Generate export content from chat messages.

        Args:
            messages: List of chat messages to export (ordered by created_at)
            metadata: Export metadata configuration

        Returns:
            Binary content of the export file

        Raises:
            ExportGenerationError: If export generation fails
        """
        pass

    def generate_filename(self, session_id: str) -> str:
        """Generate filename for the export."""
        timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
        return f"chat-export-{session_id[:8]}-{timestamp}.{self.file_extension}"
```

### Markdown Exporter (app/services/export/markdown.py)

```python
from typing import List
from datetime import datetime

from app.models.chat_message import ChatMessage, ChatRole
from app.services.export.base import ChatExporter, ExportMetadata


class MarkdownExporter(ChatExporter):
    """Export chat history to Markdown format."""

    @property
    def content_type(self) -> str:
        return "text/markdown; charset=utf-8"

    @property
    def file_extension(self) -> str:
        return "md"

    def export(
        self,
        messages: List[ChatMessage],
        metadata: ExportMetadata,
    ) -> bytes:
        """Generate Markdown export content."""
        lines: List[str] = []

        # Header with metadata
        if metadata:
            lines.extend([
                f"# Chat Export: {metadata.session_name}",
                "",
                f"**Session ID**: `{metadata.session_id}`  ",
                f"**Exported**: {metadata.export_date.strftime('%Y-%m-%d %H:%M:%S UTC')}  ",
                f"**Messages**: {metadata.message_count}",
                "",
                "---",
                "",
            ])

        # Messages
        for message in messages:
            role_label = "**User**" if message.role == ChatRole.USER else "**Assistant**"

            # Timestamp line
            if metadata.include_timestamps and message.created_at:
                timestamp = message.created_at.strftime("%Y-%m-%d %H:%M:%S")
                lines.append(f"### {role_label} ({timestamp})")
            else:
                lines.append(f"### {role_label}")

            lines.append("")

            # Message content (already markdown, preserve as-is)
            lines.append(message.content)
            lines.append("")
            lines.append("---")
            lines.append("")

        content = "\n".join(lines)
        return content.encode("utf-8")
```

### PDF Exporter (app/services/export/pdf.py)

**Recommended Library**: `weasyprint` (HTML/CSS to PDF, good markdown support)

**Alternative Options**:

1. `weasyprint` - HTML/CSS to PDF, excellent for styled documents
2. `reportlab` - Lower-level, more control but more complex
3. `fpdf2` - Lightweight, but limited styling
4. `pdfkit` / `wkhtmltopdf` - External dependency, but powerful

**Selected Approach**: Use `weasyprint` with a simple HTML template for clean, styled output.

````python
from typing import List
from datetime import datetime
import html as html_lib

from app.models.chat_message import ChatMessage, ChatRole
from app.services.export.base import ChatExporter, ExportMetadata
from app.core.exceptions import ExportGenerationError

# Conditional import - weasyprint may not be installed
try:
    from weasyprint import HTML, CSS
    WEASYPRINT_AVAILABLE = True
except ImportError:
    WEASYPRINT_AVAILABLE = False


class PDFExporter(ChatExporter):
    """Export chat history to PDF format."""

    CSS_STYLES = """
        @page {
            size: A4;
            margin: 2cm;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            font-size: 11pt;
            line-height: 1.5;
            color: #333;
        }
        h1 {
            font-size: 18pt;
            color: #1a1a1a;
            border-bottom: 2px solid #0066cc;
            padding-bottom: 0.5em;
            margin-bottom: 1em;
        }
        .metadata {
            font-size: 10pt;
            color: #666;
            margin-bottom: 2em;
        }
        .metadata p {
            margin: 0.2em 0;
        }
        .message {
            margin-bottom: 1.5em;
            page-break-inside: avoid;
        }
        .message-header {
            font-weight: bold;
            font-size: 11pt;
            margin-bottom: 0.5em;
            padding: 0.5em;
            border-radius: 4px;
        }
        .message-header.user {
            background-color: #e3f2fd;
            color: #1565c0;
        }
        .message-header.assistant {
            background-color: #f3e5f5;
            color: #7b1fa2;
        }
        .message-content {
            padding: 0.5em 1em;
            background-color: #fafafa;
            border-left: 3px solid #ddd;
            white-space: pre-wrap;
        }
        .timestamp {
            font-size: 9pt;
            color: #888;
            font-weight: normal;
        }
        hr {
            border: none;
            border-top: 1px solid #eee;
            margin: 1em 0;
        }
        code {
            background-color: #f5f5f5;
            padding: 0.2em 0.4em;
            border-radius: 3px;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 10pt;
        }
        pre {
            background-color: #f5f5f5;
            padding: 1em;
            border-radius: 4px;
            overflow-x: auto;
            font-family: 'SF Mono', Monaco, Consolas, monospace;
            font-size: 10pt;
        }
    """

    @property
    def content_type(self) -> str:
        return "application/pdf"

    @property
    def file_extension(self) -> str:
        return "pdf"

    def export(
        self,
        messages: List[ChatMessage],
        metadata: ExportMetadata,
    ) -> bytes:
        """Generate PDF export content."""
        if not WEASYPRINT_AVAILABLE:
            raise ExportGenerationError("PDF export requires weasyprint library")

        try:
            html_content = self._generate_html(messages, metadata)
            html_doc = HTML(string=html_content)
            css = CSS(string=self.CSS_STYLES)
            pdf_bytes = html_doc.write_pdf(stylesheets=[css])
            return pdf_bytes
        except Exception as e:
            raise ExportGenerationError(f"PDF generation failed: {str(e)}")

    def _generate_html(
        self,
        messages: List[ChatMessage],
        metadata: ExportMetadata,
    ) -> str:
        """Generate HTML content for PDF conversion."""
        lines: List[str] = [
            "<!DOCTYPE html>",
            "<html>",
            "<head><meta charset='utf-8'></head>",
            "<body>",
        ]

        # Header with metadata
        if metadata:
            lines.extend([
                f"<h1>Chat Export: {html_lib.escape(metadata.session_name)}</h1>",
                "<div class='metadata'>",
                f"<p><strong>Session ID:</strong> <code>{metadata.session_id}</code></p>",
                f"<p><strong>Exported:</strong> {metadata.export_date.strftime('%Y-%m-%d %H:%M:%S UTC')}</p>",
                f"<p><strong>Messages:</strong> {metadata.message_count}</p>",
                "</div>",
                "<hr>",
            ])

        # Messages
        for message in messages:
            role_class = "user" if message.role == ChatRole.USER else "assistant"
            role_label = "User" if message.role == ChatRole.USER else "Assistant"

            timestamp_html = ""
            if metadata.include_timestamps and message.created_at:
                timestamp = message.created_at.strftime("%Y-%m-%d %H:%M:%S")
                timestamp_html = f" <span class='timestamp'>({timestamp})</span>"

            # Escape content but preserve some markdown-like formatting
            content = html_lib.escape(message.content)
            # Simple code block handling (``` blocks)
            content = self._convert_code_blocks(content)
            # Simple inline code handling
            content = self._convert_inline_code(content)
            # Preserve line breaks
            content = content.replace("\n", "<br>")

            lines.extend([
                "<div class='message'>",
                f"<div class='message-header {role_class}'>{role_label}{timestamp_html}</div>",
                f"<div class='message-content'>{content}</div>",
                "</div>",
            ])

        lines.extend([
            "</body>",
            "</html>",
        ])

        return "\n".join(lines)

    def _convert_code_blocks(self, text: str) -> str:
        """Convert markdown code blocks to HTML pre tags."""
        import re
        # Match ```language\ncode\n```
        pattern = r"```(\w*)\n(.*?)\n```"
        return re.sub(pattern, r"<pre><code>\2</code></pre>", text, flags=re.DOTALL)

    def _convert_inline_code(self, text: str) -> str:
        """Convert markdown inline code to HTML code tags."""
        import re
        # Match `code`
        pattern = r"`([^`]+)`"
        return re.sub(pattern, r"<code>\1</code>", text)
````

### Export Factory (app/services/export/**init**.py)

```python
from typing import Dict, Type

from app.schemas.chat import ChatExportFormat
from app.services.export.base import ChatExporter
from app.services.export.markdown import MarkdownExporter
from app.services.export.pdf import PDFExporter


_EXPORTERS: Dict[ChatExportFormat, Type[ChatExporter]] = {
    ChatExportFormat.PDF: PDFExporter,
    ChatExportFormat.MARKDOWN: MarkdownExporter,
}


def get_exporter(format: ChatExportFormat) -> ChatExporter:
    """
    Factory function to get the appropriate exporter for a format.

    Args:
        format: The export format

    Returns:
        An instance of the appropriate ChatExporter

    Raises:
        InvalidExportFormatError: If format is not supported
    """
    exporter_class = _EXPORTERS.get(format)
    if exporter_class is None:
        from app.core.exceptions import InvalidExportFormatError
        raise InvalidExportFormatError(str(format))
    return exporter_class()


__all__ = [
    "ChatExporter",
    "get_exporter",
    "MarkdownExporter",
    "PDFExporter",
]
```

### Route Implementation (app/routes/chat.py)

Add the following endpoints to the existing `chat.py` routes file:

```python
from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, Path
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.exceptions import (
    SessionNotFoundError,
    ChatMessageNotFoundError,
    NoChatMessagesError,
    NotAssistantMessageError,
    NoPrecedingUserMessageError,
)
from app.models.chat_message import ChatMessage, ChatRole
from app.models.session import Session
from app.schemas.chat import ChatExportRequest
from app.services.export import get_exporter
from app.services.export.base import ExportMetadata


@router.post(
    "/{session_id}/chat/export",
    summary="Export full chat history",
    description="Generate and download full chat history in specified format",
    responses={
        200: {
            "description": "Export file",
            "content": {
                "application/pdf": {},
                "text/markdown": {},
            },
        },
        404: {"description": "Session not found or no messages"},
    },
)
async def export_chat_history(
    session_id: str = Path(..., description="Session UUID"),
    request: ChatExportRequest = ...,
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Export full chat history for a session."""
    # Verify session exists
    session = await db.get(Session, session_id)
    if not session:
        raise SessionNotFoundError(session_id)

    # Get all messages ordered by created_at
    messages: List[ChatMessage] = await _get_session_messages(db, session_id)

    if not messages:
        raise NoChatMessagesError(session_id)

    # Build export metadata
    metadata = ExportMetadata(
        session_name=session.name or "Untitled Session",
        session_id=session_id,
        export_date=datetime.utcnow(),
        message_count=len(messages),
        include_timestamps=request.include_timestamps,
    ) if request.include_metadata else None

    # Generate export
    exporter = get_exporter(request.format)
    content = exporter.export(messages, metadata)
    filename = exporter.generate_filename(session_id)

    return Response(
        content=content,
        media_type=exporter.content_type,
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
        },
    )


@router.post(
    "/{session_id}/chat/{message_id}/export",
    summary="Export single Q/A pair",
    description="Generate and download a specific question/answer pair",
    responses={
        200: {
            "description": "Export file",
            "content": {
                "application/pdf": {},
                "text/markdown": {},
            },
        },
        400: {"description": "Invalid message type"},
        404: {"description": "Session, message, or preceding message not found"},
    },
)
async def export_single_message(
    session_id: str = Path(..., description="Session UUID"),
    message_id: str = Path(..., description="Assistant message UUID"),
    request: ChatExportRequest = ...,
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Export a single Q/A pair (user question + assistant answer)."""
    # Verify session exists
    session = await db.get(Session, session_id)
    if not session:
        raise SessionNotFoundError(session_id)

    # Get the target message
    message = await db.get(ChatMessage, message_id)
    if not message or message.session_id != session_id:
        raise ChatMessageNotFoundError(message_id)

    # Verify it's an assistant message
    if message.role != ChatRole.ASSISTANT:
        raise NotAssistantMessageError(message_id)

    # Get preceding user message
    user_message = await _get_preceding_user_message(db, session_id, message.created_at)
    if not user_message:
        raise NoPrecedingUserMessageError(message_id)

    # Build message pair
    messages = [user_message, message]

    # Build export metadata
    metadata = ExportMetadata(
        session_name=session.name or "Untitled Session",
        session_id=session_id,
        export_date=datetime.utcnow(),
        message_count=2,
        include_timestamps=request.include_timestamps,
    ) if request.include_metadata else None

    # Generate export
    exporter = get_exporter(request.format)
    content = exporter.export(messages, metadata)
    filename = exporter.generate_filename(f"{session_id}-{message_id[:8]}")

    return Response(
        content=content,
        media_type=exporter.content_type,
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
        },
    )


async def _get_session_messages(
    db: AsyncSession,
    session_id: str,
) -> List[ChatMessage]:
    """Get all messages for a session ordered by created_at."""
    from sqlalchemy import select

    result = await db.execute(
        select(ChatMessage)
        .where(ChatMessage.session_id == session_id)
        .order_by(ChatMessage.created_at)
    )
    return list(result.scalars().all())


async def _get_preceding_user_message(
    db: AsyncSession,
    session_id: str,
    before_time: datetime,
) -> ChatMessage | None:
    """Get the most recent user message before a given time."""
    from sqlalchemy import select

    result = await db.execute(
        select(ChatMessage)
        .where(
            ChatMessage.session_id == session_id,
            ChatMessage.role == ChatRole.USER,
            ChatMessage.created_at < before_time,
        )
        .order_by(ChatMessage.created_at.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()
```

### Dependency Addition (pyproject.toml)

Add weasyprint to dependencies:

```toml
[project]
dependencies = [
    # ... existing dependencies ...
    "weasyprint>=62.0",
]
```

**Note**: weasyprint has system dependencies (pango, cairo, etc.). Document installation requirements:

```bash
# macOS
brew install pango

# Ubuntu/Debian
apt-get install libpango-1.0-0 libpangocairo-1.0-0

# Alpine (Docker)
apk add pango cairo gdk-pixbuf
```

---

## Frontend Implementation

### Directory Structure

```
research-mind-ui/
├── src/
│   ├── lib/
│   │   ├── api/
│   │   │   ├── client.ts         # Add export methods
│   │   │   ├── hooks.ts          # Add export mutation hooks
│   │   │   └── queryKeys.ts      # Add export query keys (if needed)
│   │   ├── components/
│   │   │   ├── chat/
│   │   │   │   ├── SessionChat.svelte    # Add export button to bottom bar
│   │   │   │   ├── ChatMessage.svelte    # Add export button to each message
│   │   │   │   └── ExportDialog.svelte   # NEW - Format selection dialog
│   │   │   └── shared/
│   │   │       └── ConfirmDialog.svelte  # Reference for dialog pattern
│   │   └── utils/
│   │       └── download.ts       # NEW - Download helper utility
└── tests/
    └── export.test.ts            # NEW - Export tests
```

### API Client Updates (src/lib/api/client.ts)

Add the following to the API client:

```typescript
// Types
export type ChatExportFormat = "pdf" | "markdown";

export interface ChatExportRequest {
  format: ChatExportFormat;
  include_metadata?: boolean;
  include_timestamps?: boolean;
}

// Add to apiClient object
export const apiClient = {
  // ... existing methods ...

  /**
   * Export full chat history for a session.
   * Returns a Blob for download.
   */
  async exportChatHistory(
    sessionId: string,
    request: ChatExportRequest,
  ): Promise<{ blob: Blob; filename: string }> {
    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/chat/export`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(request),
      },
    );

    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      throw new ApiError(
        response.status,
        error.error_code || "EXPORT_FAILED",
        error.message || "Failed to export chat history",
      );
    }

    // Extract filename from Content-Disposition header
    const contentDisposition = response.headers.get("Content-Disposition");
    const filenameMatch = contentDisposition?.match(/filename="(.+)"/);
    const filename =
      filenameMatch?.[1] ||
      `chat-export.${request.format === "pdf" ? "pdf" : "md"}`;

    const blob = await response.blob();
    return { blob, filename };
  },

  /**
   * Export a single Q/A pair.
   * Returns a Blob for download.
   */
  async exportSingleMessage(
    sessionId: string,
    messageId: string,
    request: ChatExportRequest,
  ): Promise<{ blob: Blob; filename: string }> {
    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/chat/${messageId}/export`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(request),
      },
    );

    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      throw new ApiError(
        response.status,
        error.error_code || "EXPORT_FAILED",
        error.message || "Failed to export message",
      );
    }

    const contentDisposition = response.headers.get("Content-Disposition");
    const filenameMatch = contentDisposition?.match(/filename="(.+)"/);
    const filename =
      filenameMatch?.[1] ||
      `chat-export.${request.format === "pdf" ? "pdf" : "md"}`;

    const blob = await response.blob();
    return { blob, filename };
  },
};
```

### TanStack Query Hooks (src/lib/api/hooks.ts)

Add export mutation hooks:

```typescript
import type { ChatExportFormat, ChatExportRequest } from "./client";

/**
 * Mutation hook for exporting full chat history.
 */
export function useExportChatHistoryMutation() {
  return createMutation<
    { blob: Blob; filename: string },
    ApiError,
    { sessionId: string; request: ChatExportRequest }
  >({
    mutationFn: ({ sessionId, request }) =>
      apiClient.exportChatHistory(sessionId, request),
    // No cache invalidation needed - export doesn't modify data
  });
}

/**
 * Mutation hook for exporting a single Q/A pair.
 */
export function useExportSingleMessageMutation() {
  return createMutation<
    { blob: Blob; filename: string },
    ApiError,
    { sessionId: string; messageId: string; request: ChatExportRequest }
  >({
    mutationFn: ({ sessionId, messageId, request }) =>
      apiClient.exportSingleMessage(sessionId, messageId, request),
    // No cache invalidation needed - export doesn't modify data
  });
}
```

### Download Utility (src/lib/utils/download.ts)

```typescript
/**
 * Trigger a browser download for a Blob.
 */
export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
```

### Export Dialog Component (src/lib/components/chat/ExportDialog.svelte)

```svelte
<script lang="ts">
  import { Dialog } from 'bits-ui';
  import { X, FileText, File, Download, Loader } from 'lucide-svelte';
  import type { ChatExportFormat } from '$lib/api/client';

  interface Props {
    open: boolean;
    title?: string;
    description?: string;
    isLoading?: boolean;
    onExport: (format: ChatExportFormat) => void;
    onCancel: () => void;
  }

  let {
    open = $bindable(false),
    title = 'Export Chat',
    description = 'Choose a format for your export',
    isLoading = false,
    onExport,
    onCancel,
  }: Props = $props();

  let selectedFormat: ChatExportFormat = $state('markdown');
  let includeMetadata = $state(true);
  let includeTimestamps = $state(true);

  function handleExport() {
    onExport(selectedFormat);
  }

  function handleCancel() {
    open = false;
    onCancel();
  }

  function handleOpenChange(newOpen: boolean) {
    if (!newOpen && !isLoading) {
      handleCancel();
    }
  }
</script>

<Dialog.Root bind:open onOpenChange={handleOpenChange}>
  <Dialog.Portal>
    <Dialog.Overlay class="dialog-overlay" />
    <Dialog.Content class="dialog-content">
      <div class="dialog-header">
        <Dialog.Title class="dialog-title">{title}</Dialog.Title>
        <Dialog.Description class="dialog-description">{description}</Dialog.Description>
        <button
          class="dialog-close"
          onclick={handleCancel}
          disabled={isLoading}
          aria-label="Close"
        >
          <X size={20} />
        </button>
      </div>

      <div class="dialog-body">
        <div class="format-selection">
          <label class="format-label">Format</label>
          <div class="format-options">
            <button
              class="format-option"
              class:selected={selectedFormat === 'markdown'}
              onclick={() => (selectedFormat = 'markdown')}
              disabled={isLoading}
            >
              <FileText size={24} />
              <span class="format-name">Markdown</span>
              <span class="format-desc">Plain text, editable</span>
            </button>
            <button
              class="format-option"
              class:selected={selectedFormat === 'pdf'}
              onclick={() => (selectedFormat = 'pdf')}
              disabled={isLoading}
            >
              <File size={24} />
              <span class="format-name">PDF</span>
              <span class="format-desc">Formatted, printable</span>
            </button>
          </div>
        </div>

        <div class="options">
          <label class="checkbox-label">
            <input type="checkbox" bind:checked={includeMetadata} disabled={isLoading} />
            <span>Include session metadata</span>
          </label>
          <label class="checkbox-label">
            <input type="checkbox" bind:checked={includeTimestamps} disabled={isLoading} />
            <span>Include timestamps</span>
          </label>
        </div>
      </div>

      <div class="dialog-footer">
        <button class="btn btn-secondary" onclick={handleCancel} disabled={isLoading}>
          Cancel
        </button>
        <button class="btn btn-primary" onclick={handleExport} disabled={isLoading}>
          {#if isLoading}
            <Loader size={16} class="spinner" />
            Exporting...
          {:else}
            <Download size={16} />
            Export
          {/if}
        </button>
      </div>
    </Dialog.Content>
  </Dialog.Portal>
</Dialog.Root>

<style>
  :global(.dialog-overlay) {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    z-index: 50;
  }

  :global(.dialog-content) {
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    background: white;
    border-radius: 8px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
    padding: 1.5rem;
    width: 90%;
    max-width: 420px;
    z-index: 51;
  }

  .dialog-header {
    position: relative;
    margin-bottom: 1.5rem;
  }

  :global(.dialog-title) {
    font-size: 1.25rem;
    font-weight: 600;
    color: #1a1a1a;
    margin: 0;
  }

  :global(.dialog-description) {
    font-size: 0.875rem;
    color: #666;
    margin-top: 0.25rem;
  }

  .dialog-close {
    position: absolute;
    top: -0.5rem;
    right: -0.5rem;
    background: none;
    border: none;
    padding: 0.5rem;
    cursor: pointer;
    color: #666;
    border-radius: 4px;
  }

  .dialog-close:hover {
    background: #f5f5f5;
  }

  .dialog-close:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .dialog-body {
    margin-bottom: 1.5rem;
  }

  .format-selection {
    margin-bottom: 1.5rem;
  }

  .format-label {
    display: block;
    font-size: 0.875rem;
    font-weight: 500;
    color: #333;
    margin-bottom: 0.5rem;
  }

  .format-options {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.75rem;
  }

  .format-option {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 1rem;
    border: 2px solid #e5e5e5;
    border-radius: 8px;
    background: white;
    cursor: pointer;
    transition: all 0.15s;
  }

  .format-option:hover:not(:disabled) {
    border-color: #ccc;
  }

  .format-option.selected {
    border-color: var(--primary-color, #0066cc);
    background: #f0f7ff;
  }

  .format-option:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .format-name {
    font-weight: 500;
    margin-top: 0.5rem;
    color: #333;
  }

  .format-desc {
    font-size: 0.75rem;
    color: #666;
    margin-top: 0.25rem;
  }

  .options {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .checkbox-label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.875rem;
    color: #333;
    cursor: pointer;
  }

  .checkbox-label input {
    width: 1rem;
    height: 1rem;
  }

  .dialog-footer {
    display: flex;
    justify-content: flex-end;
    gap: 0.75rem;
  }

  .btn {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    border-radius: 6px;
    font-size: 0.875rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.15s;
  }

  .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn-secondary {
    background: white;
    border: 1px solid #e5e5e5;
    color: #333;
  }

  .btn-secondary:hover:not(:disabled) {
    background: #f5f5f5;
  }

  .btn-primary {
    background: var(--primary-color, #0066cc);
    border: 1px solid var(--primary-color, #0066cc);
    color: white;
  }

  .btn-primary:hover:not(:disabled) {
    background: #0052a3;
  }

  :global(.spinner) {
    animation: spin 1s linear infinite;
  }

  @keyframes spin {
    from {
      transform: rotate(0deg);
    }
    to {
      transform: rotate(360deg);
    }
  }
</style>
```

### SessionChat.svelte Updates

Add export button to bottom bar (left of clear chat history button):

```svelte
<!-- Add to script section -->
<script lang="ts">
  import { Download } from 'lucide-svelte';
  import ExportDialog from './ExportDialog.svelte';
  import { useExportChatHistoryMutation } from '$lib/api/hooks';
  import { downloadBlob } from '$lib/utils/download';
  import type { ChatExportFormat } from '$lib/api/client';

  // ... existing code ...

  // Export state
  let showExportDialog = $state(false);
  const exportMutation = useExportChatHistoryMutation();

  async function handleExport(format: ChatExportFormat) {
    if (!sessionId) return;

    try {
      const result = await $exportMutation.mutateAsync({
        sessionId,
        request: {
          format,
          include_metadata: true,
          include_timestamps: true,
        },
      });
      downloadBlob(result.blob, result.filename);
      showExportDialog = false;
    } catch (error) {
      console.error('Export failed:', error);
      // Error handling (could show toast notification)
    }
  }
</script>

<!-- In the bottom bar, add export button before clear button -->
<div class="input-actions">
  <!-- Export button -->
  <button
    type="button"
    class="action-btn export-btn"
    onclick={() => (showExportDialog = true)}
    disabled={!messages?.length}
    title="Export chat history"
  >
    <Download size={20} />
  </button>

  <!-- Existing clear button -->
  <button
    type="button"
    class="action-btn clear-btn"
    onclick={() => (showClearConfirm = true)}
    disabled={!messages?.length}
    title="Clear chat history"
  >
    <Trash2 size={20} />
  </button>

  <!-- ... send button ... -->
</div>

<!-- Export dialog -->
<ExportDialog
  bind:open={showExportDialog}
  title="Export Chat History"
  description="Export your entire conversation"
  isLoading={$exportMutation.isPending}
  onExport={handleExport}
  onCancel={() => (showExportDialog = false)}
/>
```

### ChatMessage.svelte Updates

Add export button to each assistant message:

```svelte
<!-- Add to script section -->
<script lang="ts">
  import { Download } from 'lucide-svelte';
  import ExportDialog from './ExportDialog.svelte';
  import { useExportSingleMessageMutation } from '$lib/api/hooks';
  import { downloadBlob } from '$lib/utils/download';
  import type { ChatExportFormat } from '$lib/api/client';

  interface Props {
    message: ChatMessage;
    sessionId: string;  // Add this prop
    // ... existing props
  }

  let { message, sessionId, ...rest } = $props();

  // Export state (only for assistant messages)
  let showExportDialog = $state(false);
  const exportMutation = useExportSingleMessageMutation();

  async function handleExport(format: ChatExportFormat) {
    try {
      const result = await $exportMutation.mutateAsync({
        sessionId,
        messageId: message.message_id,
        request: {
          format,
          include_metadata: true,
          include_timestamps: true,
        },
      });
      downloadBlob(result.blob, result.filename);
      showExportDialog = false;
    } catch (error) {
      console.error('Export failed:', error);
    }
  }
</script>

<!-- Add export button in message header/meta for assistant messages -->
{#if message.role === 'assistant'}
  <div class="message-actions">
    <button
      type="button"
      class="action-btn export-single-btn"
      onclick={() => (showExportDialog = true)}
      title="Export this Q&A"
    >
      <Download size={16} />
    </button>
  </div>

  <ExportDialog
    bind:open={showExportDialog}
    title="Export Q&A"
    description="Export this question and answer pair"
    isLoading={$exportMutation.isPending}
    onExport={handleExport}
    onCancel={() => (showExportDialog = false)}
  />
{/if}
```

---

## Test Requirements

### Backend Tests

#### Unit Tests (tests/services/export/)

```python
# tests/services/export/test_markdown_exporter.py
import pytest
from datetime import datetime
from app.services.export.markdown import MarkdownExporter
from app.services.export.base import ExportMetadata
from app.models.chat_message import ChatMessage, ChatRole


class TestMarkdownExporter:
    def test_export_basic_messages(self):
        """Test basic markdown export with user and assistant messages."""
        exporter = MarkdownExporter()
        messages = [
            _make_message("What is Python?", ChatRole.USER),
            _make_message("Python is a programming language.", ChatRole.ASSISTANT),
        ]
        metadata = _make_metadata(len(messages))

        result = exporter.export(messages, metadata)

        assert isinstance(result, bytes)
        content = result.decode("utf-8")
        assert "# Chat Export:" in content
        assert "**User**" in content
        assert "**Assistant**" in content
        assert "What is Python?" in content
        assert "Python is a programming language." in content

    def test_export_without_metadata(self):
        """Test export without metadata header."""
        exporter = MarkdownExporter()
        messages = [_make_message("Hello", ChatRole.USER)]

        result = exporter.export(messages, None)

        content = result.decode("utf-8")
        assert "# Chat Export:" not in content
        assert "**User**" in content

    def test_export_preserves_markdown(self):
        """Test that markdown in messages is preserved."""
        exporter = MarkdownExporter()
        messages = [
            _make_message("# Heading\n\n- List item\n- Another item", ChatRole.ASSISTANT),
        ]

        result = exporter.export(messages, None)

        content = result.decode("utf-8")
        assert "# Heading" in content
        assert "- List item" in content

    def test_content_type(self):
        """Test correct MIME type."""
        exporter = MarkdownExporter()
        assert exporter.content_type == "text/markdown; charset=utf-8"

    def test_file_extension(self):
        """Test correct file extension."""
        exporter = MarkdownExporter()
        assert exporter.file_extension == "md"


# tests/services/export/test_pdf_exporter.py
import pytest
from app.services.export.pdf import PDFExporter, WEASYPRINT_AVAILABLE


@pytest.mark.skipif(not WEASYPRINT_AVAILABLE, reason="weasyprint not installed")
class TestPDFExporter:
    def test_export_creates_valid_pdf(self):
        """Test that export creates valid PDF bytes."""
        exporter = PDFExporter()
        messages = [
            _make_message("Question?", ChatRole.USER),
            _make_message("Answer.", ChatRole.ASSISTANT),
        ]
        metadata = _make_metadata(len(messages))

        result = exporter.export(messages, metadata)

        assert isinstance(result, bytes)
        # PDF magic number
        assert result[:4] == b'%PDF'

    def test_content_type(self):
        """Test correct MIME type."""
        exporter = PDFExporter()
        assert exporter.content_type == "application/pdf"

    def test_file_extension(self):
        """Test correct file extension."""
        exporter = PDFExporter()
        assert exporter.file_extension == "pdf"
```

#### Integration Tests (tests/routes/test_chat_export.py)

```python
# tests/routes/test_chat_export.py
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
class TestExportChatHistory:
    async def test_export_markdown_success(
        self, client: AsyncClient, session_with_messages: str
    ):
        """Test successful markdown export."""
        response = await client.post(
            f"/api/v1/sessions/{session_with_messages}/chat/export",
            json={"format": "markdown"},
        )

        assert response.status_code == 200
        assert response.headers["content-type"] == "text/markdown; charset=utf-8"
        assert "attachment" in response.headers["content-disposition"]
        assert ".md" in response.headers["content-disposition"]

    @pytest.mark.skipif(not WEASYPRINT_AVAILABLE, reason="weasyprint not installed")
    async def test_export_pdf_success(
        self, client: AsyncClient, session_with_messages: str
    ):
        """Test successful PDF export."""
        response = await client.post(
            f"/api/v1/sessions/{session_with_messages}/chat/export",
            json={"format": "pdf"},
        )

        assert response.status_code == 200
        assert response.headers["content-type"] == "application/pdf"
        assert response.content[:4] == b'%PDF'

    async def test_export_session_not_found(self, client: AsyncClient):
        """Test export with non-existent session."""
        response = await client.post(
            "/api/v1/sessions/00000000-0000-0000-0000-000000000000/chat/export",
            json={"format": "markdown"},
        )

        assert response.status_code == 404
        assert response.json()["error_code"] == "SESSION_NOT_FOUND"

    async def test_export_no_messages(
        self, client: AsyncClient, empty_session: str
    ):
        """Test export with no chat messages."""
        response = await client.post(
            f"/api/v1/sessions/{empty_session}/chat/export",
            json={"format": "markdown"},
        )

        assert response.status_code == 404
        assert response.json()["error_code"] == "NO_CHAT_MESSAGES"

    async def test_export_invalid_format(
        self, client: AsyncClient, session_with_messages: str
    ):
        """Test export with invalid format."""
        response = await client.post(
            f"/api/v1/sessions/{session_with_messages}/chat/export",
            json={"format": "invalid"},
        )

        assert response.status_code == 422  # Pydantic validation error


@pytest.mark.asyncio
class TestExportSingleMessage:
    async def test_export_single_qa_success(
        self,
        client: AsyncClient,
        session_with_messages: str,
        assistant_message_id: str,
    ):
        """Test successful single Q/A export."""
        response = await client.post(
            f"/api/v1/sessions/{session_with_messages}/chat/{assistant_message_id}/export",
            json={"format": "markdown"},
        )

        assert response.status_code == 200
        content = response.content.decode("utf-8")
        assert "**User**" in content
        assert "**Assistant**" in content

    async def test_export_non_assistant_message(
        self,
        client: AsyncClient,
        session_with_messages: str,
        user_message_id: str,
    ):
        """Test export from user message fails."""
        response = await client.post(
            f"/api/v1/sessions/{session_with_messages}/chat/{user_message_id}/export",
            json={"format": "markdown"},
        )

        assert response.status_code == 400
        assert response.json()["error_code"] == "NOT_ASSISTANT_MESSAGE"

    async def test_export_message_not_found(
        self, client: AsyncClient, session_with_messages: str
    ):
        """Test export with non-existent message."""
        response = await client.post(
            f"/api/v1/sessions/{session_with_messages}/chat/00000000-0000-0000-0000-000000000000/export",
            json={"format": "markdown"},
        )

        assert response.status_code == 404
        assert response.json()["error_code"] == "CHAT_MESSAGE_NOT_FOUND"
```

### Frontend Tests

#### API Client Tests (tests/export.test.ts)

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { apiClient } from "../src/lib/api/client";

describe("Chat Export API", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  describe("exportChatHistory", () => {
    it("should export markdown successfully", async () => {
      const mockBlob = new Blob(["# Test"], { type: "text/markdown" });
      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: true,
          headers: new Headers({
            "Content-Type": "text/markdown; charset=utf-8",
            "Content-Disposition": 'attachment; filename="chat-export.md"',
          }),
          blob: () => Promise.resolve(mockBlob),
        } as Response),
      );

      const result = await apiClient.exportChatHistory("session-123", {
        format: "markdown",
      });

      expect(result.blob).toBeInstanceOf(Blob);
      expect(result.filename).toBe("chat-export.md");
    });

    it("should handle export errors", async () => {
      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: false,
          status: 404,
          json: () =>
            Promise.resolve({
              error_code: "NO_CHAT_MESSAGES",
              message: "No messages to export",
            }),
        } as Response),
      );

      await expect(
        apiClient.exportChatHistory("session-123", { format: "markdown" }),
      ).rejects.toThrow();
    });
  });

  describe("exportSingleMessage", () => {
    it("should export single Q/A successfully", async () => {
      const mockBlob = new Blob(["# Q&A"], { type: "text/markdown" });
      global.fetch = vi.fn(() =>
        Promise.resolve({
          ok: true,
          headers: new Headers({
            "Content-Type": "text/markdown; charset=utf-8",
            "Content-Disposition": 'attachment; filename="chat-qa.md"',
          }),
          blob: () => Promise.resolve(mockBlob),
        } as Response),
      );

      const result = await apiClient.exportSingleMessage(
        "session-123",
        "message-456",
        { format: "markdown" },
      );

      expect(result.blob).toBeInstanceOf(Blob);
      expect(result.filename).toBe("chat-qa.md");
    });
  });
});
```

#### Component Tests (tests/components/ExportDialog.test.ts)

```typescript
import { describe, it, expect, vi } from "vitest";
import { render, fireEvent } from "@testing-library/svelte";
import ExportDialog from "../src/lib/components/chat/ExportDialog.svelte";

describe("ExportDialog", () => {
  it("should render format options", () => {
    const { getByText } = render(ExportDialog, {
      props: {
        open: true,
        onExport: vi.fn(),
        onCancel: vi.fn(),
      },
    });

    expect(getByText("Markdown")).toBeInTheDocument();
    expect(getByText("PDF")).toBeInTheDocument();
  });

  it("should call onExport with selected format", async () => {
    const onExport = vi.fn();
    const { getByText } = render(ExportDialog, {
      props: {
        open: true,
        onExport,
        onCancel: vi.fn(),
      },
    });

    await fireEvent.click(getByText("PDF"));
    await fireEvent.click(getByText("Export"));

    expect(onExport).toHaveBeenCalledWith("pdf");
  });

  it("should disable buttons when loading", () => {
    const { getByText } = render(ExportDialog, {
      props: {
        open: true,
        isLoading: true,
        onExport: vi.fn(),
        onCancel: vi.fn(),
      },
    });

    expect(getByText("Exporting...")).toBeInTheDocument();
  });
});
```

---

## Implementation Phases

### Phase 1: Backend Foundation (3-4 days)

**Objective**: Implement backend export endpoints and services.

**Tasks**:

1. Add weasyprint dependency to pyproject.toml
2. Create app/schemas/chat.py schema additions (ChatExportFormat, ChatExportRequest)
3. Create app/core/exceptions.py exception classes
4. Create app/services/export/ directory and files:
   - base.py (abstract exporter interface)
   - markdown.py (markdown exporter)
   - pdf.py (PDF exporter)
   - **init**.py (factory function)
5. Add export endpoints to app/routes/chat.py
6. Write unit tests for exporters
7. Write integration tests for endpoints
8. Update api-contract.md with new endpoints

**Acceptance Criteria**:

- [ ] `POST /api/v1/sessions/{session_id}/chat/export` returns markdown file
- [ ] `POST /api/v1/sessions/{session_id}/chat/export` returns PDF file
- [ ] `POST /api/v1/sessions/{session_id}/chat/{message_id}/export` returns Q/A export
- [ ] All error cases return appropriate error codes
- [ ] All backend tests pass
- [ ] API contract updated to version 1.7.0

### Phase 2: Frontend Foundation (2-3 days)

**Objective**: Implement frontend API client and export dialog.

**Tasks**:

1. Copy updated api-contract.md to frontend
2. Run `npm run gen:api` to regenerate types
3. Add export types and methods to src/lib/api/client.ts
4. Add export mutation hooks to src/lib/api/hooks.ts
5. Create src/lib/utils/download.ts utility
6. Create src/lib/components/chat/ExportDialog.svelte
7. Write tests for API client export methods
8. Write tests for ExportDialog component

**Acceptance Criteria**:

- [ ] API client can call export endpoints
- [ ] TanStack Query mutations handle export requests
- [ ] ExportDialog displays format options
- [ ] Download utility triggers browser download
- [ ] All frontend tests pass

### Phase 3: UI Integration (2 days)

**Objective**: Integrate export functionality into existing components.

**Tasks**:

1. Add export button to SessionChat.svelte bottom bar
2. Add export button to ChatMessage.svelte for assistant messages
3. Wire up export dialog to mutations
4. Add loading states and error handling
5. Test full export flow end-to-end

**Acceptance Criteria**:

- [ ] Export button visible in chat bottom bar (left of clear button)
- [ ] Export button visible on each assistant message
- [ ] Clicking export opens format selection dialog
- [ ] Selecting format and clicking export triggers download
- [ ] Loading spinner shown during export
- [ ] Error messages displayed on failure

### Phase 4: Polish & Documentation (1 day)

**Objective**: Final polish and documentation updates.

**Tasks**:

1. Add tooltips and accessibility attributes
2. Test on different browsers
3. Update user documentation (if any)
4. Code review and cleanup
5. Final testing

**Acceptance Criteria**:

- [ ] Export works in Chrome, Firefox, Safari
- [ ] All accessibility requirements met
- [ ] No console errors
- [ ] Code passes linting

---

## Technical Decisions

### PDF Library Selection

**Decision**: Use `weasyprint` for PDF generation.

**Rationale**:

- Supports HTML/CSS rendering for styled documents
- Good markdown-to-HTML conversion support
- Active maintenance and community support
- Pure Python (no external binary dependencies except Cairo/Pango)
- BSD license

**Alternatives Considered**:

- `reportlab`: More control but much more complex API
- `fpdf2`: Lightweight but limited styling options
- `pdfkit`: Requires wkhtmltopdf binary, harder to deploy

**Trade-offs**:

- Requires system dependencies (pango, cairo)
- Adds ~50MB to Docker image
- Slower than simpler libraries for basic text

### Export as On-Demand vs Pre-Generated

**Decision**: Generate exports on-demand (no storage).

**Rationale**:

- Simpler architecture (no background jobs, no cleanup)
- Always reflects current chat state
- No storage costs
- Privacy-friendly (no exports stored)

**Trade-offs**:

- Slightly longer response time for large exports
- Cannot share export links (must download immediately)

### Single Q/A Export Target

**Decision**: Export targets assistant messages, automatically includes preceding user message.

**Rationale**:

- Users want to export "answers" not "questions"
- Logical unit is Q/A pair, not individual messages
- Simpler UX (one button per answer)

**Trade-offs**:

- Cannot export standalone user message
- Cannot export multiple Q/A pairs (use full export instead)

---

## Appendix

### File Locations Summary

**Backend**:
| File | Purpose |
|------|---------|
| `app/schemas/chat.py` | Add ChatExportFormat, ChatExportRequest |
| `app/core/exceptions.py` | Add export-related exception classes |
| `app/services/export/__init__.py` | Export factory function |
| `app/services/export/base.py` | Abstract exporter interface |
| `app/services/export/markdown.py` | Markdown exporter implementation |
| `app/services/export/pdf.py` | PDF exporter implementation |
| `app/routes/chat.py` | Add export endpoints |
| `pyproject.toml` | Add weasyprint dependency |
| `docs/api-contract.md` | Update to version 1.7.0 |

**Frontend**:
| File | Purpose |
|------|---------|
| `src/lib/api/client.ts` | Add export API methods |
| `src/lib/api/hooks.ts` | Add export mutation hooks |
| `src/lib/utils/download.ts` | Browser download utility |
| `src/lib/components/chat/ExportDialog.svelte` | Format selection dialog |
| `src/lib/components/chat/SessionChat.svelte` | Add full export button |
| `src/lib/components/chat/ChatMessage.svelte` | Add single export button |
| `docs/api-contract.md` | Copy from backend |

### Docker Dependencies

If using Docker, add to Dockerfile:

```dockerfile
# Install weasyprint system dependencies
RUN apt-get update && apt-get install -y \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf2.0-0 \
    libffi-dev \
    shared-mime-info \
    && rm -rf /var/lib/apt/lists/*
```

### Error Code Reference

| Code                      | Status | Description                              |
| ------------------------- | ------ | ---------------------------------------- |
| INVALID_FORMAT            | 400    | Export format not "pdf" or "markdown"    |
| NOT_ASSISTANT_MESSAGE     | 400    | Single export requires assistant message |
| SESSION_NOT_FOUND         | 404    | Session does not exist                   |
| CHAT_MESSAGE_NOT_FOUND    | 404    | Message does not exist                   |
| NO_CHAT_MESSAGES          | 404    | No messages to export                    |
| NO_PRECEDING_USER_MESSAGE | 404    | Assistant has no preceding question      |
| EXPORT_GENERATION_FAILED  | 500    | Failed to generate export file           |

---

## Changelog

| Version | Date       | Changes                     |
| ------- | ---------- | --------------------------- |
| 1.0.0   | 2026-02-04 | Initial implementation plan |
