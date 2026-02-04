# Session Chat Interface Implementation Plan

> **Version**: 1.1.0
> **Created**: 2026-02-03
> **Updated**: 2026-02-03
> **Status**: Draft (claude-mpm Exclusive Integration)
> **Authors**: Claude Code (Research Agent)

**CRITICAL REQUIREMENT**: This implementation MUST use `claude-mpm` executable exclusively. Never the native `claude` CLI.

This document provides a comprehensive implementation plan for adding a chat interface to research-mind that allows users to query session content using claude-mpm.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [API Contract Changes](#3-api-contract-changes)
4. [Data Models](#4-data-models)
5. [Backend Implementation](#5-backend-implementation)
6. [Frontend Implementation](#6-frontend-implementation)
7. [claude-mpm Integration](#7-claude-mpm-integration)
8. [Real-time Updates](#8-real-time-updates)
9. [Testing Strategy](#9-testing-strategy)
10. [Implementation Phases](#10-implementation-phases)

---

## 1. Overview

### 1.1 Feature Summary

The Session Chat Interface enables users to ask natural language questions about the content indexed in a research session. The system will:

1. Accept user questions via a chat UI within each session
2. Invoke `claude-mpm` CLI with the session's sandbox directory as context
3. Stream the AI response back to the user in real-time via Server-Sent Events (SSE)
4. Persist chat history per session for continuity

### 1.2 Goals

- **Natural Language Querying**: Users can ask questions like "What authentication patterns are used in this codebase?"
- **Real-time Streaming**: Responses appear token-by-token for a responsive experience
- **Session Isolation**: Each session has its own chat history and context
- **Persistence**: Chat messages are stored for session continuity across page refreshes

### 1.3 Non-Goals (Phase 1)

- Multi-turn conversation with explicit memory management (future)
- Agent selection/switching (always uses default research agent)
- File editing or code generation within the session sandbox
- WebSocket-based bidirectional communication (SSE is sufficient)

---

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Frontend (SvelteKit)                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     Session Chat Component                        │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐  │  │
│  │  │ Chat Input  │  │ Message List │  │  Streaming Display      │  │  │
│  │  │ (textarea)  │  │ (history)    │  │  (EventSource)          │  │  │
│  │  └─────────────┘  └──────────────┘  └─────────────────────────┘  │  │
│  └───────────────────────────┬──────────────────────────────────────┘  │
└──────────────────────────────┼──────────────────────────────────────────┘
                               │
                               │ HTTP POST (send message)
                               │ SSE (stream response)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Backend (FastAPI)                               │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      Chat Router                                  │  │
│  │  POST /api/v1/sessions/{id}/chat       - Send message            │  │
│  │  GET  /api/v1/sessions/{id}/chat       - List messages           │  │
│  │  GET  /api/v1/sessions/{id}/chat/stream/{msg_id} - SSE stream    │  │
│  │  DELETE /api/v1/sessions/{id}/chat/{msg_id} - Delete message     │  │
│  └───────────────────────────┬──────────────────────────────────────┘  │
│                              │                                          │
│  ┌───────────────────────────▼──────────────────────────────────────┐  │
│  │                      Chat Service                                 │  │
│  │  - Create message records                                         │  │
│  │  - Invoke claude-mpm CLI subprocess                                │  │
│  │  - Stream output via async generator                              │  │
│  │  - Update message with final response                             │  │
│  └───────────────────────────┬──────────────────────────────────────┘  │
└──────────────────────────────┼──────────────────────────────────────────┘
                               │
                               │ subprocess (async)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            claude-mpm CLI                               │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  claude-mpm --print --output-format stream-json                   │  │
│  │  --project-dir {session_workspace_path}                          │  │
│  │  --include-partial-messages                                       │  │
│  │  "User's question here"                                           │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  Output: JSON chunks with partial content → Backend parses and streams │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Interactions

```
User types question
        │
        ▼
[Frontend] POST /api/v1/sessions/{id}/chat
        │  { "content": "What patterns are used?" }
        │
        ▼
[Backend] Creates ChatMessage record (status: "pending")
        │  Returns { message_id, stream_url }
        │
        ▼
[Frontend] Connects to SSE: GET /api/v1/sessions/{id}/chat/stream/{msg_id}
        │
        ▼
[Backend] Spawns subprocess: claude-mpm --print --output-format stream-json ...
        │
        ▼
[Subprocess] Outputs JSON chunks with partial content
        │
        ▼
[Backend] Parses chunks → Yields SSE events → Updates message record
        │
        ▼
[Frontend] EventSource receives chunks → Appends to display
        │
        ▼
[Backend] Subprocess completes → Final SSE event → Close connection
```

### 2.3 Technology Choices

| Component                | Technology                     | Rationale                                                                                       |
| ------------------------ | ------------------------------ | ----------------------------------------------------------------------------------------------- |
| Streaming Protocol       | SSE (Server-Sent Events)       | Simpler than WebSockets for one-way streaming, automatic reconnection, works over standard HTTP |
| Subprocess Communication | asyncio.create_subprocess_exec | Native Python async, stream stdout line-by-line                                                 |
| Frontend Streaming       | Native EventSource API         | Built into browsers, no additional libraries needed                                             |
| Message Storage          | PostgreSQL (existing)          | Consistent with existing data layer                                                             |

---

## 3. API Contract Changes

### 3.1 New Endpoints

Add the following to `docs/api-contract.md`:

````markdown
## Chat

Chat messages allow users to query session content using AI.

### Chat Message Schema

```typescript
interface ChatMessage {
  message_id: string; // UUID
  session_id: string; // Parent session UUID
  role: "user" | "assistant"; // Message author
  content: string; // Message content
  status: "pending" | "streaming" | "completed" | "error";
  error_message?: string; // Error details if status is "error"
  created_at: string; // ISO 8601 timestamp
  completed_at?: string; // ISO 8601 timestamp (when response finished)
  token_count?: number; // Approximate token count
  duration_ms?: number; // Response generation time
  metadata_json?: object; // Additional metadata (model, etc.)
}
```
````

### Send Chat Message

#### `POST /api/v1/sessions/{session_id}/chat`

Send a new chat message and get a stream URL for the response.

**Path Parameters**

| Parameter    | Type   | Description  |
| ------------ | ------ | ------------ |
| `session_id` | string | Session UUID |

**Request Body**

```json
{
  "content": "What authentication patterns are used in this codebase?"
}
```

| Field     | Type   | Required | Constraints        |
| --------- | ------ | -------- | ------------------ |
| `content` | string | yes      | 1-10000 characters |

**Response** `201 Created`

```json
{
  "message_id": "c1d2e3f4-g5h6-7890-ijkl-mn1234567890",
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "role": "user",
  "content": "What authentication patterns are used in this codebase?",
  "status": "pending",
  "created_at": "2026-02-03T10:30:00Z",
  "stream_url": "/api/v1/sessions/a1b2c3d4.../chat/stream/c1d2e3f4..."
}
```

**Response** `404 Not Found` - Session not found
**Response** `400 Bad Request` - Session not indexed

```json
{
  "detail": {
    "error": {
      "code": "SESSION_NOT_INDEXED",
      "message": "Session must be indexed before chat is available"
    }
  }
}
```

---

### Stream Chat Response

#### `GET /api/v1/sessions/{session_id}/chat/stream/{message_id}`

Stream the AI response for a chat message using Server-Sent Events.

**Path Parameters**

| Parameter    | Type   | Description  |
| ------------ | ------ | ------------ |
| `session_id` | string | Session UUID |
| `message_id` | string | Message UUID |

**Response** `200 OK` (text/event-stream)

SSE events in the stream:

```
event: start
data: {"message_id": "c1d2e3f4...", "status": "streaming"}

event: chunk
data: {"content": "Based on my analysis"}

event: chunk
data: {"content": " of the codebase..."}

event: complete
data: {"message_id": "c1d2e3f4...", "status": "completed", "token_count": 542, "duration_ms": 3200}

event: error
data: {"message_id": "c1d2e3f4...", "status": "error", "error": "Subprocess timed out"}
```

**Response** `404 Not Found` - Message not found

---

### List Chat Messages

#### `GET /api/v1/sessions/{session_id}/chat`

List all chat messages for a session with pagination.

**Path Parameters**

| Parameter    | Type   | Description  |
| ------------ | ------ | ------------ |
| `session_id` | string | Session UUID |

**Query Parameters**

| Parameter | Type    | Default | Description       |
| --------- | ------- | ------- | ----------------- |
| `limit`   | integer | 50      | Items per page    |
| `offset`  | integer | 0       | Starting position |

**Response** `200 OK`

```json
{
  "messages": [
    {
      "message_id": "...",
      "session_id": "...",
      "role": "user",
      "content": "What patterns are used?",
      "status": "completed",
      "created_at": "2026-02-03T10:30:00Z"
    },
    {
      "message_id": "...",
      "session_id": "...",
      "role": "assistant",
      "content": "Based on my analysis, the codebase uses...",
      "status": "completed",
      "created_at": "2026-02-03T10:30:05Z",
      "completed_at": "2026-02-03T10:30:12Z",
      "token_count": 542,
      "duration_ms": 7000
    }
  ],
  "count": 2
}
```

---

### Delete Chat Message

#### `DELETE /api/v1/sessions/{session_id}/chat/{message_id}`

Delete a chat message.

**Response** `204 No Content`
**Response** `404 Not Found` - Message not found

````

### 3.2 New Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `SESSION_NOT_INDEXED` | 400 | Session must be indexed before chat |
| `CHAT_MESSAGE_NOT_FOUND` | 404 | Chat message UUID not found |
| `CHAT_STREAM_EXPIRED` | 410 | Stream has already completed |
| `CLAUDE_MPM_NOT_AVAILABLE` | 500 | claude-mpm CLI not found on PATH |
| `CLAUDE_MPM_TIMEOUT` | 500 | claude-mpm response timed out |
| `CLAUDE_MPM_FAILED` | 500 | claude-mpm process returned non-zero exit |
| `CLAUDE_API_KEY_NOT_SET` | 500 | ANTHROPIC_API_KEY not in environment |
| `SESSION_WORKSPACE_NOT_FOUND` | 500 | Session workspace directory not found |

### 3.3 Version Bump

Bump contract version from `1.2.0` to `1.3.0` (minor - new feature).

---

## 4. Data Models

### 4.1 Database Schema

**New Table: `chat_messages`**

```sql
CREATE TABLE chat_messages (
    message_id VARCHAR(36) PRIMARY KEY,
    session_id VARCHAR(36) NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'streaming', 'completed', 'error')),
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    token_count INTEGER,
    duration_ms INTEGER,
    metadata_json JSONB,

    -- Indexes
    CONSTRAINT fk_session FOREIGN KEY (session_id)
        REFERENCES sessions(session_id) ON DELETE CASCADE
);

CREATE INDEX idx_chat_messages_session_id ON chat_messages(session_id);
CREATE INDEX idx_chat_messages_created_at ON chat_messages(created_at DESC);
CREATE INDEX idx_chat_messages_status ON chat_messages(status);
````

### 4.2 SQLAlchemy Model

**File: `app/models/chat_message.py`**

```python
"""SQLAlchemy ORM model for chat messages within sessions."""

from __future__ import annotations

import enum
from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.types import JSON

from app.db.base import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ChatRole(str, enum.Enum):
    """Message author role."""
    USER = "user"
    ASSISTANT = "assistant"


class ChatStatus(str, enum.Enum):
    """Message lifecycle status."""
    PENDING = "pending"
    STREAMING = "streaming"
    COMPLETED = "completed"
    ERROR = "error"


class ChatMessage(Base):
    """A chat message within a research session."""

    __tablename__ = "chat_messages"

    message_id: str = Column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    session_id: str = Column(
        String(36),
        ForeignKey("sessions.session_id", ondelete="CASCADE"),
        nullable=False,
    )

    role: str = Column(String(20), nullable=False)
    content: str = Column(Text, nullable=False)
    status: str = Column(
        String(20), nullable=False, default=ChatStatus.PENDING.value
    )
    error_message: str | None = Column(Text, nullable=True)

    created_at: datetime = Column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
    completed_at: datetime | None = Column(DateTime(timezone=True), nullable=True)

    token_count: int | None = Column(Integer, nullable=True)
    duration_ms: int | None = Column(Integer, nullable=True)
    metadata_json = Column(JSON, nullable=True, default=dict)

    __table_args__ = (
        Index("idx_chat_messages_session_id", "session_id"),
        Index("idx_chat_messages_created_at", "created_at"),
        Index("idx_chat_messages_status", "status"),
    )

    def __repr__(self) -> str:
        return f"<ChatMessage {self.message_id}: role={self.role} status={self.status}>"
```

### 4.3 Pydantic Schemas

**File: `app/schemas/chat.py`**

```python
"""Pydantic v2 schemas for chat endpoints."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class SendChatMessageRequest(BaseModel):
    """Body for POST /api/v1/sessions/{session_id}/chat."""
    content: str = Field(..., min_length=1, max_length=10000)


class ChatMessageResponse(BaseModel):
    """Single chat message returned by the API."""
    model_config = ConfigDict(from_attributes=True)

    message_id: str
    session_id: str
    role: Literal["user", "assistant"]
    content: str
    status: Literal["pending", "streaming", "completed", "error"]
    error_message: str | None = None
    created_at: datetime
    completed_at: datetime | None = None
    token_count: int | None = None
    duration_ms: int | None = None
    metadata_json: dict | None = None
    stream_url: str | None = None  # Only set for pending messages


class ChatMessageListResponse(BaseModel):
    """Paginated list of chat messages."""
    messages: list[ChatMessageResponse]
    count: int


# SSE Event Types
class ChatStreamStartEvent(BaseModel):
    """Event sent when streaming starts."""
    message_id: str
    status: Literal["streaming"] = "streaming"


class ChatStreamChunkEvent(BaseModel):
    """Event sent for each content chunk."""
    content: str


class ChatStreamCompleteEvent(BaseModel):
    """Event sent when streaming completes."""
    message_id: str
    status: Literal["completed"] = "completed"
    token_count: int | None = None
    duration_ms: int | None = None


class ChatStreamErrorEvent(BaseModel):
    """Event sent when an error occurs."""
    message_id: str
    status: Literal["error"] = "error"
    error: str
```

---

## 5. Backend Implementation

### 5.1 Chat Service

**File: `app/services/chat_service.py`**

```python
"""Chat service for managing chat messages and AI interactions."""

from __future__ import annotations

import asyncio
import json
import logging
import shutil
import time
from datetime import datetime, timezone
from typing import AsyncGenerator
from uuid import uuid4

from sqlalchemy.orm import Session

from app.models.chat_message import ChatMessage, ChatRole, ChatStatus
from app.models.session import Session as SessionModel
from app.schemas.chat import (
    ChatMessageResponse,
    ChatStreamChunkEvent,
    ChatStreamCompleteEvent,
    ChatStreamErrorEvent,
    ChatStreamStartEvent,
)

logger = logging.getLogger(__name__)

# Configuration
# NOTE: Updated 2026-02-03 - using claude-mpm exclusively
CLAUDE_MPM_TIMEOUT_SECONDS = 300  # 5 minutes max


class ChatServiceError(Exception):
    """Base exception for chat service errors."""
    pass


class ClaudeMpmNotAvailableError(ChatServiceError):
    """Raised when claude-mpm CLI is not available."""
    pass


class SessionNotIndexedError(ChatServiceError):
    """Raised when session is not indexed."""
    pass


def create_user_message(
    db: Session,
    session_id: str,
    content: str,
) -> ChatMessage:
    """Create a user chat message."""
    # Verify session exists and is indexed
    session = db.query(SessionModel).filter_by(session_id=session_id).first()
    if not session:
        raise ValueError(f"Session '{session_id}' not found")
    if not session.is_indexed():
        raise SessionNotIndexedError(
            "Session must be indexed before chat is available"
        )

    message = ChatMessage(
        message_id=str(uuid4()),
        session_id=session_id,
        role=ChatRole.USER.value,
        content=content,
        status=ChatStatus.PENDING.value,
    )
    db.add(message)
    db.commit()
    db.refresh(message)
    return message


def create_assistant_message(
    db: Session,
    session_id: str,
    user_message_id: str,
) -> ChatMessage:
    """Create a placeholder assistant message for streaming."""
    message = ChatMessage(
        message_id=str(uuid4()),
        session_id=session_id,
        role=ChatRole.ASSISTANT.value,
        content="",  # Will be populated during streaming
        status=ChatStatus.PENDING.value,
        metadata_json={"user_message_id": user_message_id},
    )
    db.add(message)
    db.commit()
    db.refresh(message)
    return message


def update_message_status(
    db: Session,
    message_id: str,
    status: ChatStatus,
    content: str | None = None,
    error_message: str | None = None,
    token_count: int | None = None,
    duration_ms: int | None = None,
) -> ChatMessage | None:
    """Update a chat message's status and content."""
    message = db.query(ChatMessage).filter_by(message_id=message_id).first()
    if not message:
        return None

    message.status = status.value
    if content is not None:
        message.content = content
    if error_message is not None:
        message.error_message = error_message
    if token_count is not None:
        message.token_count = token_count
    if duration_ms is not None:
        message.duration_ms = duration_ms
    if status == ChatStatus.COMPLETED:
        message.completed_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(message)
    return message


def list_messages(
    db: Session,
    session_id: str,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[ChatMessage], int]:
    """List chat messages for a session."""
    query = (
        db.query(ChatMessage)
        .filter_by(session_id=session_id)
        .order_by(ChatMessage.created_at.asc())
    )
    total = query.count()
    messages = query.offset(offset).limit(limit).all()
    return messages, total


def get_message(
    db: Session,
    session_id: str,
    message_id: str,
) -> ChatMessage | None:
    """Get a single chat message."""
    return (
        db.query(ChatMessage)
        .filter_by(session_id=session_id, message_id=message_id)
        .first()
    )


def delete_message(
    db: Session,
    session_id: str,
    message_id: str,
) -> bool:
    """Delete a chat message."""
    message = get_message(db, session_id, message_id)
    if not message:
        return False
    db.delete(message)
    db.commit()
    return True


async def stream_claude_response(
    session: SessionModel,
    user_content: str,
    assistant_message_id: str,
) -> AsyncGenerator[str, None]:
    """
    Stream response from claude-mpm using subprocess.

    Uses line-buffered streaming since claude-mpm outputs plain text.
    Yields SSE-formatted events.

    NOTE: Updated 2026-02-03 based on CLI research findings.
    See /docs/research/claude-mpm-cli-research.md for details.
    CRITICAL: Uses claude-mpm exclusively, NOT native claude CLI.
    """
    start_time = time.time()
    accumulated_content = ""
    token_count = 0

    try:
        # Verify claude-mpm is available
        claude_mpm_path = shutil.which("claude-mpm")
        if not claude_mpm_path:
            raise ClaudeMpmNotAvailableError(
                "claude-mpm CLI is not available on PATH"
            )

        workspace_path = session.workspace_path

        # Build command using claude-mpm exclusively
        # NOTE: --non-interactive is the oneshot mode flag
        # Working directory is set via CLAUDE_MPM_USER_PWD env var AND cwd
        cmd = [
            claude_mpm_path,
            "run",
            "--non-interactive",               # Oneshot mode
            "--no-hooks",                      # Skip hooks for speed
            "--no-tickets",                    # Skip ticket creation
            "--launch-method", "subprocess",   # Required for output capture
            "-i", user_content,                # Input prompt
        ]

        # Set environment variables
        env = os.environ.copy()
        env["CLAUDE_MPM_USER_PWD"] = workspace_path
        env["DISABLE_TELEMETRY"] = "1"

        logger.info(f"Spawning claude-mpm subprocess in {workspace_path}...")

        # Yield start event
        start_event = ChatStreamStartEvent(message_id=assistant_message_id)
        yield f"event: start\ndata: {start_event.model_dump_json()}\n\n"

        # Start subprocess with working directory set
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
            cwd=workspace_path,  # Also set cwd for safety
        )

        # Stream stdout line by line
        # NOTE: claude-mpm outputs plain text, not JSON
        try:
            while True:
                try:
                    line = await asyncio.wait_for(
                        process.stdout.readline(),
                        timeout=CLAUDE_MPM_TIMEOUT_SECONDS
                    )
                except asyncio.TimeoutError:
                    process.kill()
                    raise TimeoutError("claude-mpm response timed out")

                if not line:
                    break

                line_str = line.decode("utf-8")
                if not line_str:
                    continue

                # Accumulate content
                accumulated_content += line_str
                token_count += len(line_str.split())  # Rough estimate

                # Yield chunk event with the line
                chunk_event = ChatStreamChunkEvent(content=line_str)
                yield f"event: chunk\ndata: {chunk_event.model_dump_json()}\n\n"

            # Wait for process to complete
            await process.wait()

            if process.returncode != 0:
                stderr = await process.stderr.read()
                error_msg = stderr.decode("utf-8") if stderr else "Unknown error"
                raise RuntimeError(f"claude-mpm process failed: {error_msg}")

        except asyncio.CancelledError:
            process.kill()
            raise

        # Calculate duration
        duration_ms = int((time.time() - start_time) * 1000)

        # Yield complete event
        complete_event = ChatStreamCompleteEvent(
            message_id=assistant_message_id,
            token_count=token_count,
            duration_ms=duration_ms,
        )
        yield f"event: complete\ndata: {complete_event.model_dump_json()}\n\n"

        # Return final content and metadata for database update
        yield f"__FINAL__:{json.dumps({'content': accumulated_content, 'token_count': token_count, 'duration_ms': duration_ms})}"

    except Exception as e:
        logger.exception(f"Error streaming Claude response: {e}")
        error_event = ChatStreamErrorEvent(
            message_id=assistant_message_id,
            error=str(e),
        )
        yield f"event: error\ndata: {error_event.model_dump_json()}\n\n"
        yield f"__ERROR__:{str(e)}"
```

### 5.2 Chat Router

**File: `app/routes/chat.py`**

```python
"""Chat REST endpoints for session-scoped AI conversations."""

from __future__ import annotations

import json
import logging
from typing import AsyncGenerator

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.session import Session as SessionModel
from app.schemas.chat import (
    ChatMessageListResponse,
    ChatMessageResponse,
    SendChatMessageRequest,
)
from app.services import chat_service
from app.services.chat_service import (
    ChatServiceError,
    ClaudeCliNotAvailableError,
    SessionNotIndexedError,
)

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/v1/sessions/{session_id}/chat",
    tags=["chat"],
)


@router.post("/", response_model=ChatMessageResponse, status_code=201)
def send_message(
    session_id: str,
    request: SendChatMessageRequest,
    db: Session = Depends(get_db),
) -> ChatMessageResponse:
    """Send a chat message and get a stream URL for the response."""
    try:
        # Create user message
        user_message = chat_service.create_user_message(
            db, session_id, request.content
        )

        # Create placeholder assistant message
        assistant_message = chat_service.create_assistant_message(
            db, session_id, user_message.message_id
        )

        # Build stream URL
        stream_url = f"/api/v1/sessions/{session_id}/chat/stream/{assistant_message.message_id}"

        return ChatMessageResponse(
            message_id=user_message.message_id,
            session_id=user_message.session_id,
            role=user_message.role,
            content=user_message.content,
            status=user_message.status,
            created_at=user_message.created_at,
            stream_url=stream_url,
        )

    except ValueError as e:
        raise HTTPException(
            status_code=404,
            detail={"error": {"code": "SESSION_NOT_FOUND", "message": str(e)}},
        )
    except SessionNotIndexedError as e:
        raise HTTPException(
            status_code=400,
            detail={"error": {"code": "SESSION_NOT_INDEXED", "message": str(e)}},
        )


@router.get("/stream/{message_id}")
async def stream_response(
    session_id: str,
    message_id: str,
    db: Session = Depends(get_db),
) -> StreamingResponse:
    """Stream the AI response for a chat message using SSE."""
    # Get session
    session = db.query(SessionModel).filter_by(session_id=session_id).first()
    if not session:
        raise HTTPException(
            status_code=404,
            detail={"error": {"code": "SESSION_NOT_FOUND", "message": f"Session '{session_id}' not found"}},
        )

    # Get assistant message
    message = chat_service.get_message(db, session_id, message_id)
    if not message:
        raise HTTPException(
            status_code=404,
            detail={"error": {"code": "CHAT_MESSAGE_NOT_FOUND", "message": f"Message '{message_id}' not found"}},
        )

    if message.status not in ("pending", "streaming"):
        raise HTTPException(
            status_code=410,
            detail={"error": {"code": "CHAT_STREAM_EXPIRED", "message": "Stream has already completed"}},
        )

    # Get associated user message content
    user_message_id = message.metadata_json.get("user_message_id") if message.metadata_json else None
    user_message = None
    if user_message_id:
        user_message = chat_service.get_message(db, session_id, user_message_id)

    if not user_message:
        raise HTTPException(
            status_code=404,
            detail={"error": {"code": "CHAT_MESSAGE_NOT_FOUND", "message": "Associated user message not found"}},
        )

    # Update status to streaming
    chat_service.update_message_status(db, message_id, chat_service.ChatStatus.STREAMING)

    async def event_generator() -> AsyncGenerator[str, None]:
        """Generate SSE events from claude-mpm subprocess."""
        final_content = ""
        final_token_count = None
        final_duration_ms = None
        error_occurred = False
        error_message = None

        try:
            async for event in chat_service.stream_claude_response(
                session, user_message.content, message_id
            ):
                if event.startswith("__FINAL__:"):
                    # Extract final metadata
                    final_data = json.loads(event[10:])
                    final_content = final_data.get("content", "")
                    final_token_count = final_data.get("token_count")
                    final_duration_ms = final_data.get("duration_ms")
                elif event.startswith("__ERROR__:"):
                    error_occurred = True
                    error_message = event[10:]
                else:
                    yield event

        except ClaudeCliNotAvailableError as e:
            error_occurred = True
            error_message = str(e)
            yield f"event: error\ndata: {{\"message_id\": \"{message_id}\", \"status\": \"error\", \"error\": \"{str(e)}\"}}\n\n"

        except Exception as e:
            logger.exception(f"Streaming error: {e}")
            error_occurred = True
            error_message = str(e)
            yield f"event: error\ndata: {{\"message_id\": \"{message_id}\", \"status\": \"error\", \"error\": \"{str(e)}\"}}\n\n"

        finally:
            # Update message in database
            # Note: Need a new db session since this is async
            from app.db.session import get_session_local
            with get_session_local()() as final_db:
                if error_occurred:
                    chat_service.update_message_status(
                        final_db,
                        message_id,
                        chat_service.ChatStatus.ERROR,
                        error_message=error_message,
                    )
                else:
                    chat_service.update_message_status(
                        final_db,
                        message_id,
                        chat_service.ChatStatus.COMPLETED,
                        content=final_content,
                        token_count=final_token_count,
                        duration_ms=final_duration_ms,
                    )

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  # Disable nginx buffering
        },
    )


@router.get("/", response_model=ChatMessageListResponse)
def list_messages(
    session_id: str,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
) -> ChatMessageListResponse:
    """List all chat messages for a session with pagination."""
    # Verify session exists
    session = db.query(SessionModel).filter_by(session_id=session_id).first()
    if not session:
        raise HTTPException(
            status_code=404,
            detail={"error": {"code": "SESSION_NOT_FOUND", "message": f"Session '{session_id}' not found"}},
        )

    messages, total = chat_service.list_messages(db, session_id, limit, offset)
    return ChatMessageListResponse(
        messages=[ChatMessageResponse.model_validate(m) for m in messages],
        count=total,
    )


@router.delete("/{message_id}", status_code=204, response_model=None)
def delete_message(
    session_id: str,
    message_id: str,
    db: Session = Depends(get_db),
) -> None:
    """Delete a chat message."""
    deleted = chat_service.delete_message(db, session_id, message_id)
    if not deleted:
        raise HTTPException(
            status_code=404,
            detail={"error": {"code": "CHAT_MESSAGE_NOT_FOUND", "message": f"Message '{message_id}' not found"}},
        )
```

### 5.3 Router Registration

**Update: `app/main.py`**

```python
from app.routes import chat

# ... existing router registrations ...
app.include_router(chat.router)
```

---

## 6. Frontend Implementation

### 6.1 API Client Updates

**Update: `src/lib/api/client.ts`**

```typescript
// Add to existing type aliases
export type ChatMessageResponse = components["schemas"]["ChatMessageResponse"];
export type ChatMessageListResponse =
  components["schemas"]["ChatMessageListResponse"];

// Add Zod schemas
const ChatMessageResponseSchema = z.object({
  message_id: z.string(),
  session_id: z.string(),
  role: z.enum(["user", "assistant"]),
  content: z.string(),
  status: z.enum(["pending", "streaming", "completed", "error"]),
  error_message: z.string().nullable().optional(),
  created_at: z.string(),
  completed_at: z.string().nullable().optional(),
  token_count: z.number().nullable().optional(),
  duration_ms: z.number().nullable().optional(),
  metadata_json: z.record(z.unknown()).nullable().optional(),
  stream_url: z.string().nullable().optional(),
});

const ChatMessageListResponseSchema = z.object({
  messages: z.array(ChatMessageResponseSchema),
  count: z.number(),
});

// Add to apiClient
export const apiClient = {
  // ... existing methods ...

  // ---------------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------------

  /**
   * Send a chat message and get stream URL.
   */
  async sendChatMessage(
    sessionId: string,
    content: string,
  ): Promise<ChatMessageResponse> {
    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/chat/`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content }),
      },
    );
    if (!response.ok) {
      throw await ApiError.fromResponse(
        "Failed to send chat message",
        response,
      );
    }
    const data = await response.json();
    return ChatMessageResponseSchema.parse(data);
  },

  /**
   * List chat messages for a session.
   */
  async listChatMessages(
    sessionId: string,
    limit = 50,
    offset = 0,
  ): Promise<ChatMessageListResponse> {
    const params = new URLSearchParams({
      limit: String(limit),
      offset: String(offset),
    });
    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/chat/?${params}`,
    );
    if (!response.ok) {
      throw await ApiError.fromResponse(
        "Failed to list chat messages",
        response,
      );
    }
    const data = await response.json();
    return ChatMessageListResponseSchema.parse(data);
  },

  /**
   * Delete a chat message.
   */
  async deleteChatMessage(sessionId: string, messageId: string): Promise<void> {
    const response = await fetch(
      `${apiBaseUrl}/api/v1/sessions/${sessionId}/chat/${messageId}`,
      { method: "DELETE" },
    );
    if (!response.ok) {
      throw await ApiError.fromResponse(
        "Failed to delete chat message",
        response,
      );
    }
  },

  /**
   * Get the SSE stream URL for a chat message.
   */
  getChatStreamUrl(sessionId: string, messageId: string): string {
    return `${apiBaseUrl}/api/v1/sessions/${sessionId}/chat/stream/${messageId}`;
  },
};
```

### 6.2 TanStack Query Hooks

**Update: `src/lib/api/hooks.ts`**

```typescript
import {
  createQuery,
  createMutation,
  useQueryClient,
} from "@tanstack/svelte-query";

// Chat message query
export function useChatMessagesQuery(sessionId: string) {
  return createQuery({
    queryKey: ["chatMessages", sessionId],
    queryFn: () => apiClient.listChatMessages(sessionId),
    staleTime: 0, // Always refetch to show latest
    enabled: !!sessionId,
  });
}

// Send chat message mutation
export function useSendChatMessageMutation() {
  const queryClient = useQueryClient();

  return createMutation({
    mutationFn: ({
      sessionId,
      content,
    }: {
      sessionId: string;
      content: string;
    }) => apiClient.sendChatMessage(sessionId, content),
    onSuccess: (_data, variables) => {
      // Invalidate chat messages query to refetch
      queryClient.invalidateQueries({
        queryKey: ["chatMessages", variables.sessionId],
      });
    },
  });
}

// Delete chat message mutation
export function useDeleteChatMessageMutation() {
  const queryClient = useQueryClient();

  return createMutation({
    mutationFn: ({
      sessionId,
      messageId,
    }: {
      sessionId: string;
      messageId: string;
    }) => apiClient.deleteChatMessage(sessionId, messageId),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({
        queryKey: ["chatMessages", variables.sessionId],
      });
    },
  });
}
```

### 6.3 Chat Component

**File: `src/lib/components/chat/SessionChat.svelte`**

```svelte
<script lang="ts">
  import { Send, Loader, AlertCircle, Trash2 } from 'lucide-svelte';
  import { useChatMessagesQuery, useSendChatMessageMutation } from '$lib/api/hooks';
  import { apiClient, type ChatMessageResponse } from '$lib/api/client';
  import { formatRelativeTime } from '$lib/utils/format';
  import LoadingSpinner from '$lib/components/shared/LoadingSpinner.svelte';
  import ChatMessage from './ChatMessage.svelte';

  interface Props {
    sessionId: string;
    isIndexed: boolean;
  }

  let { sessionId, isIndexed }: Props = $props();

  // State
  let inputValue = $state('');
  let isStreaming = $state(false);
  let streamingContent = $state('');
  let streamError = $state<string | null>(null);

  // Queries and mutations
  const messagesQuery = useChatMessagesQuery(sessionId);
  const sendMutation = useSendChatMessageMutation();

  // Reactive messages list with streaming message appended
  const displayMessages = $derived(() => {
    const messages = $messagesQuery.data?.messages ?? [];
    if (isStreaming && streamingContent) {
      return [
        ...messages,
        {
          message_id: 'streaming',
          session_id: sessionId,
          role: 'assistant' as const,
          content: streamingContent,
          status: 'streaming' as const,
          created_at: new Date().toISOString(),
        },
      ];
    }
    return messages;
  });

  async function handleSubmit() {
    if (!inputValue.trim() || isStreaming || !isIndexed) return;

    const content = inputValue.trim();
    inputValue = '';
    streamError = null;

    try {
      // Send message and get stream URL
      const response = await $sendMutation.mutateAsync({ sessionId, content });

      if (!response.stream_url) {
        throw new Error('No stream URL returned');
      }

      // Start streaming
      isStreaming = true;
      streamingContent = '';

      await streamResponse(response.stream_url);

    } catch (error) {
      console.error('Chat error:', error);
      streamError = error instanceof Error ? error.message : 'Unknown error';
    } finally {
      isStreaming = false;
      // Refetch messages to get final state
      $messagesQuery.refetch();
    }
  }

  async function streamResponse(streamUrl: string) {
    const fullUrl = `${import.meta.env.VITE_API_BASE_URL || 'http://localhost:15010'}${streamUrl}`;

    const eventSource = new EventSource(fullUrl);

    return new Promise<void>((resolve, reject) => {
      eventSource.addEventListener('start', (event) => {
        console.log('Stream started:', event.data);
      });

      eventSource.addEventListener('chunk', (event) => {
        const data = JSON.parse(event.data);
        streamingContent += data.content;
      });

      eventSource.addEventListener('complete', (event) => {
        console.log('Stream complete:', event.data);
        eventSource.close();
        resolve();
      });

      eventSource.addEventListener('error', (event) => {
        // Check if this is an SSE error event with data
        try {
          const data = JSON.parse((event as MessageEvent).data);
          streamError = data.error || 'Stream error';
        } catch {
          streamError = 'Connection error';
        }
        eventSource.close();
        reject(new Error(streamError));
      });

      eventSource.onerror = () => {
        eventSource.close();
        reject(new Error('Connection lost'));
      };
    });
  }

  function handleKeyDown(event: KeyboardEvent) {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      handleSubmit();
    }
  }
</script>

<div class="chat-container">
  <!-- Messages Area -->
  <div class="messages-area">
    {#if $messagesQuery.isPending}
      <div class="loading-state">
        <LoadingSpinner size="md" />
        <span>Loading chat history...</span>
      </div>
    {:else if $messagesQuery.isError}
      <div class="error-state">
        <AlertCircle size={24} />
        <span>Failed to load chat history</span>
      </div>
    {:else if displayMessages().length === 0}
      <div class="empty-state">
        <p>No messages yet. Ask a question about your session content!</p>
        {#if !isIndexed}
          <p class="warning">Session must be indexed before chat is available.</p>
        {/if}
      </div>
    {:else}
      {#each displayMessages() as message (message.message_id)}
        <ChatMessage {message} />
      {/each}
    {/if}

    {#if streamError}
      <div class="error-message">
        <AlertCircle size={16} />
        <span>{streamError}</span>
      </div>
    {/if}
  </div>

  <!-- Input Area -->
  <div class="input-area">
    <textarea
      bind:value={inputValue}
      onkeydown={handleKeyDown}
      placeholder={isIndexed ? "Ask a question about your session content..." : "Index session to enable chat"}
      disabled={!isIndexed || isStreaming}
      rows="2"
    />
    <button
      type="button"
      onclick={handleSubmit}
      disabled={!inputValue.trim() || isStreaming || !isIndexed}
      class="send-button"
    >
      {#if isStreaming}
        <Loader size={20} class="animate-spin" />
      {:else}
        <Send size={20} />
      {/if}
    </button>
  </div>
</div>

<style>
  .chat-container {
    display: flex;
    flex-direction: column;
    height: 100%;
    max-height: 600px;
    border: 1px solid var(--border-color);
    border-radius: var(--border-radius-lg);
    overflow: hidden;
  }

  .messages-area {
    flex: 1;
    overflow-y: auto;
    padding: var(--space-4);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .loading-state,
  .error-state,
  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    padding: var(--space-6);
    color: var(--text-secondary);
    text-align: center;
  }

  .empty-state .warning {
    color: var(--warning-color);
    font-size: var(--font-size-sm);
  }

  .error-message {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-3);
    background: var(--error-bg);
    color: var(--error-color);
    border-radius: var(--border-radius-md);
    font-size: var(--font-size-sm);
  }

  .input-area {
    display: flex;
    gap: var(--space-2);
    padding: var(--space-3);
    border-top: 1px solid var(--border-color);
    background: var(--bg-secondary);
  }

  .input-area textarea {
    flex: 1;
    padding: var(--space-3);
    border: 1px solid var(--border-color);
    border-radius: var(--border-radius-md);
    font-size: var(--font-size-base);
    resize: none;
    font-family: inherit;
  }

  .input-area textarea:focus {
    outline: none;
    border-color: var(--primary-color);
  }

  .input-area textarea:disabled {
    background: var(--bg-muted);
    cursor: not-allowed;
  }

  .send-button {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    padding: 0;
    background: var(--primary-color);
    color: white;
    border: none;
    border-radius: var(--border-radius-md);
    cursor: pointer;
    transition: opacity var(--transition-fast);
  }

  .send-button:hover:not(:disabled) {
    opacity: 0.9;
  }

  .send-button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  :global(.animate-spin) {
    animation: spin 1s linear infinite;
  }

  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }
</style>
```

### 6.4 Chat Message Component

**File: `src/lib/components/chat/ChatMessage.svelte`**

```svelte
<script lang="ts">
  import { User, Bot, Loader } from 'lucide-svelte';
  import { formatRelativeTime } from '$lib/utils/format';
  import type { ChatMessageResponse } from '$lib/api/client';

  interface Props {
    message: ChatMessageResponse;
  }

  let { message }: Props = $props();

  const isUser = $derived(message.role === 'user');
  const isStreaming = $derived(message.status === 'streaming');
</script>

<div class="message" class:user={isUser} class:assistant={!isUser}>
  <div class="avatar">
    {#if isUser}
      <User size={18} />
    {:else}
      <Bot size={18} />
    {/if}
  </div>

  <div class="content-wrapper">
    <div class="header">
      <span class="role">{isUser ? 'You' : 'Assistant'}</span>
      <span class="time">{formatRelativeTime(message.created_at)}</span>
      {#if isStreaming}
        <Loader size={14} class="animate-spin" />
      {/if}
    </div>

    <div class="content">
      {message.content || '...'}
    </div>

    {#if message.status === 'error' && message.error_message}
      <div class="error">
        Error: {message.error_message}
      </div>
    {/if}

    {#if message.token_count && message.duration_ms}
      <div class="metadata">
        {message.token_count} tokens, {(message.duration_ms / 1000).toFixed(1)}s
      </div>
    {/if}
  </div>
</div>

<style>
  .message {
    display: flex;
    gap: var(--space-3);
    padding: var(--space-3);
    border-radius: var(--border-radius-md);
  }

  .message.user {
    background: var(--bg-hover);
  }

  .message.assistant {
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
  }

  .avatar {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: var(--bg-muted);
    color: var(--text-secondary);
    flex-shrink: 0;
  }

  .message.user .avatar {
    background: var(--primary-color);
    color: white;
  }

  .content-wrapper {
    flex: 1;
    min-width: 0;
  }

  .header {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-bottom: var(--space-1);
  }

  .role {
    font-weight: 600;
    font-size: var(--font-size-sm);
    color: var(--text-primary);
  }

  .time {
    font-size: var(--font-size-xs);
    color: var(--text-muted);
  }

  .content {
    font-size: var(--font-size-base);
    color: var(--text-primary);
    white-space: pre-wrap;
    word-break: break-word;
  }

  .error {
    margin-top: var(--space-2);
    padding: var(--space-2);
    background: var(--error-bg);
    color: var(--error-color);
    border-radius: var(--border-radius-sm);
    font-size: var(--font-size-sm);
  }

  .metadata {
    margin-top: var(--space-2);
    font-size: var(--font-size-xs);
    color: var(--text-muted);
  }
</style>
```

### 6.5 Session Page Integration

**Update: `src/routes/sessions/[id]/+page.svelte`**

Add a Chat section to the session overview page:

```svelte
<!-- Add import -->
<script lang="ts">
  // ... existing imports ...
  import SessionChat from '$lib/components/chat/SessionChat.svelte';
</script>

<!-- Add Chat section after Indexing Status section -->
<section class="card chat-section">
  <h2 class="card-title">
    <MessageSquare size={20} />
    Chat with Session
  </h2>
  <SessionChat
    sessionId={currentSessionId}
    isIndexed={$indexQuery.data?.is_indexed ?? false}
  />
</section>

<style>
  /* ... existing styles ... */

  .chat-section {
    min-height: 400px;
  }
</style>
```

---

## 7. claude-mpm Integration

> **IMPORTANT**: This section was updated 2026-02-03 based on CLI research findings.
> See `/docs/research/claude-mpm-cli-research.md` for full details.
>
> **CRITICAL REQUIREMENT**: We MUST use `claude-mpm` executable exclusively. Never the native `claude` CLI.

### 7.1 Architecture Overview

`claude-mpm` is a **wrapper/orchestration layer** around the native Claude CLI that provides:

- **47+ Specialized Agents**: Research, engineering, QA, security, etc.
- **Session Management**: Context preservation across interactions
- **Hook System**: Custom processing hooks
- **Monitoring**: WebSocket-based real-time updates

For the session chat feature, we use claude-mpm's oneshot mode exclusively.

### 7.2 CLI Invocation Strategy (claude-mpm Exclusive)

Use claude-mpm's oneshot capability with subprocess mode:

```bash
claude-mpm run \
  --non-interactive \
  --no-hooks \
  --no-tickets \
  --launch-method subprocess \
  -i "User's question here"
```

**Key flags:**

- `--non-interactive`: Oneshot mode, output response and exit
- `--no-hooks`: Disable hook service (faster for automation)
- `--no-tickets`: Disable automatic ticket creation
- `--launch-method subprocess`: Use subprocess for output capture (required for streaming)
- `-i <prompt>`: Input prompt for the question

**Working directory**: Set via `CLAUDE_MPM_USER_PWD` environment variable AND subprocess `cwd` parameter.

```python
# CORRECT: claude-mpm exclusive implementation
claude_mpm_path = shutil.which("claude-mpm")
if not claude_mpm_path:
    raise ClaudeMpmNotAvailableError(
        "claude-mpm CLI is not available on PATH"
    )

cmd = [
    claude_mpm_path,
    "run",
    "--non-interactive",
    "--no-hooks",
    "--no-tickets",
    "--launch-method", "subprocess",
    "-i", user_question,
]

env = os.environ.copy()
env["CLAUDE_MPM_USER_PWD"] = session_workspace_path
env["DISABLE_TELEMETRY"] = "1"

process = await asyncio.create_subprocess_exec(
    *cmd,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
    env=env,
    cwd=session_workspace_path,  # Also set cwd for safety
)
```

**NOTE**: The native `claude` CLI must NOT be used directly. claude-mpm internally invokes `claude --dangerously-skip-permissions --print` with proper agent configuration.

### 7.3 Streaming Considerations

**Current Limitation**: claude-mpm does not provide built-in JSONL streaming output format via command-line flags. Output is plain text.

**Workarounds for real-time updates**:

| Approach              | Description                                       | Complexity | Recommended |
| --------------------- | ------------------------------------------------- | ---------- | ----------- |
| **Line buffering**    | Stream stdout line-by-line as it arrives          | Medium     | YES         |
| **WebSocket monitor** | Use claude-mpm's `--monitor` WebSocket            | Medium     | Future      |
| **Polling**           | Poll backend for completion, return full response | Low        | Fallback    |

**Recommended for Phase 1**: Use line-buffered streaming on stdout with claude-mpm:

```python
async def stream_claude_response(
    workspace_path: str,
    user_content: str,
) -> AsyncGenerator[str, None]:
    """Stream response from claude-mpm line-by-line."""
    claude_mpm_path = shutil.which("claude-mpm")
    if not claude_mpm_path:
        raise ClaudeMpmNotAvailableError(
            "claude-mpm CLI is not available on PATH"
        )

    cmd = [
        claude_mpm_path,
        "run",
        "--non-interactive",
        "--no-hooks",
        "--no-tickets",
        "--launch-method", "subprocess",
        "-i", user_content,
    ]

    env = os.environ.copy()
    env["CLAUDE_MPM_USER_PWD"] = workspace_path
    env["DISABLE_TELEMETRY"] = "1"

    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env,
        cwd=workspace_path,
    )

    # Stream stdout line-by-line
    TIMEOUT_SECONDS = 300  # 5 minutes
    while True:
        try:
            line = await asyncio.wait_for(
                process.stdout.readline(),
                timeout=TIMEOUT_SECONDS
            )
        except asyncio.TimeoutError:
            process.kill()
            raise TimeoutError("claude-mpm response timed out")

        if not line:
            break
        yield line.decode("utf-8")

    await process.wait()
    if process.returncode != 0:
        stderr = await process.stderr.read()
        raise RuntimeError(f"claude-mpm failed: {stderr.decode('utf-8')}")
```

### 7.4 Output Format

claude-mpm with `--non-interactive` outputs plain text response via stdout:

```
Based on my analysis of the codebase, the authentication patterns used include:

1. JWT-based authentication for API endpoints
2. Session cookies for web interface
3. OAuth2 integration for third-party services

The main authentication flow is implemented in...
```

**Note**: Output is always plain text. JSONL streaming is not available in claude-mpm. Parse line-by-line for SSE streaming.

### 7.5 Error Handling

Common errors to handle:

| Error                | Detection                      | Resolution                               | Error Code                    |
| -------------------- | ------------------------------ | ---------------------------------------- | ----------------------------- |
| claude-mpm not found | `shutil.which()` returns None  | Check PATH, provide install instructions | `CLAUDE_MPM_NOT_AVAILABLE`    |
| Process timeout      | `asyncio.TimeoutError`         | Kill process, return timeout error       | `CLAUDE_MPM_TIMEOUT`          |
| Non-zero exit        | `process.returncode != 0`      | Parse stderr, return error message       | `CLAUDE_MPM_FAILED`           |
| API key not set      | `ANTHROPIC_API_KEY` not in env | Verify environment configuration         | `CLAUDE_API_KEY_NOT_SET`      |
| Workspace not found  | `NotADirectoryError`           | Verify session workspace exists          | `SESSION_WORKSPACE_NOT_FOUND` |

### 7.6 Environment Setup

The subprocess inherits environment from the parent process. Key variables:

| Variable              | Purpose                              | Required        |
| --------------------- | ------------------------------------ | --------------- |
| `ANTHROPIC_API_KEY`   | Claude API authentication            | Yes (inherited) |
| `HOME`                | User home directory for config files | Yes (inherited) |
| `PATH`                | Must include `claude-mpm` location   | Yes             |
| `CLAUDE_MPM_USER_PWD` | Working directory for session        | Yes             |
| `DISABLE_TELEMETRY`   | Disable analytics                    | Recommended     |

```python
def prepare_claude_mpm_environment(session_workspace: str) -> dict:
    """Prepare environment for claude-mpm subprocess."""
    env = os.environ.copy()

    # Ensure API key is available (inherited from parent)
    if "ANTHROPIC_API_KEY" not in env:
        raise ClaudeApiKeyNotSetError(
            "ANTHROPIC_API_KEY environment variable not set"
        )

    # Set working directory via env var (claude-mpm specific)
    env["CLAUDE_MPM_USER_PWD"] = session_workspace

    # Disable telemetry for privacy
    env["DISABLE_TELEMETRY"] = "1"

    return env
```

**Installation Requirement** (add to deployment docs):

```bash
# claude-mpm must be installed and on PATH
pipx install "claude-mpm[monitor]"

# Verify installation
claude-mpm --version
claude-mpm doctor  # Run diagnostics
```

### 7.7 claude-mpm Run Command Reference

**Available Flags for Session Chat**:

| Flag                         | Type   | Description                           |
| ---------------------------- | ------ | ------------------------------------- |
| `--non-interactive`          | flag   | Oneshot mode, required for automation |
| `--no-hooks`                 | flag   | Disable hooks for faster execution    |
| `--no-tickets`               | flag   | Disable ticket creation               |
| `--launch-method subprocess` | choice | Required for output capture           |
| `-i <prompt>`                | string | Input question                        |

**Flags NOT Needed**:

| Flag              | Reason                                       |
| ----------------- | -------------------------------------------- |
| `--monitor`       | WebSocket overhead not needed for basic chat |
| `--resume`        | Each chat is independent                     |
| `--chrome`        | No browser integration needed                |
| `--reload-agents` | Agents persist across invocations            |

**Invalid Flags (Do Not Use)**:

| Flag                          | Status         | Notes                                         |
| ----------------------------- | -------------- | --------------------------------------------- |
| `--output-format stream-json` | Does not exist | Use line-buffered streaming                   |
| `--include-partial-messages`  | Does not exist | Not available                                 |
| `--project-dir`               | Does not exist | Use `CLAUDE_MPM_USER_PWD` env var             |
| `claude-mpm --print`          | Invalid        | `--print` is handled internally by claude-mpm |

---

## 8. Real-time Updates

### 8.1 SSE Implementation (Backend)

FastAPI's `StreamingResponse` with async generators:

```python
from fastapi.responses import StreamingResponse

async def event_generator():
    yield "event: start\ndata: {\"status\": \"streaming\"}\n\n"

    async for chunk in stream_data():
        yield f"event: chunk\ndata: {json.dumps({'content': chunk})}\n\n"

    yield "event: complete\ndata: {\"status\": \"completed\"}\n\n"

return StreamingResponse(
    event_generator(),
    media_type="text/event-stream",
    headers={
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",
    },
)
```

### 8.2 EventSource (Frontend)

Native browser API for SSE consumption:

```typescript
const eventSource = new EventSource(streamUrl);

eventSource.addEventListener("chunk", (event) => {
  const data = JSON.parse(event.data);
  appendContent(data.content);
});

eventSource.addEventListener("complete", () => {
  eventSource.close();
});

eventSource.onerror = () => {
  eventSource.close();
  handleError();
};
```

### 8.3 SSE Event Format

```
event: <event-type>
data: <json-payload>

```

**Event types:**

- `start`: Streaming has begun
- `chunk`: Content chunk received
- `complete`: Streaming finished successfully
- `error`: An error occurred

### 8.4 Heartbeat Implementation

To prevent proxy timeouts on idle connections:

```python
async def event_generator_with_heartbeat():
    heartbeat_interval = 15  # seconds
    last_event_time = time.time()

    async for event in generate_events():
        yield event
        last_event_time = time.time()

        # Send heartbeat if too quiet
        if time.time() - last_event_time > heartbeat_interval:
            yield ": heartbeat\n\n"  # SSE comment
            last_event_time = time.time()
```

---

## 9. Testing Strategy

### 9.1 Backend Unit Tests

**File: `tests/test_chat_service.py`**

```python
import pytest
from unittest.mock import Mock, patch, AsyncMock
from app.services import chat_service
from app.models.chat_message import ChatMessage, ChatRole, ChatStatus


class TestChatService:
    def test_create_user_message(self, db_session, indexed_session):
        """Test creating a user message."""
        message = chat_service.create_user_message(
            db_session,
            indexed_session.session_id,
            "What patterns are used?"
        )

        assert message.message_id is not None
        assert message.role == ChatRole.USER.value
        assert message.content == "What patterns are used?"
        assert message.status == ChatStatus.PENDING.value

    def test_create_user_message_not_indexed(self, db_session, session):
        """Test error when session not indexed."""
        with pytest.raises(chat_service.SessionNotIndexedError):
            chat_service.create_user_message(
                db_session,
                session.session_id,
                "Question"
            )

    def test_list_messages(self, db_session, indexed_session_with_messages):
        """Test listing chat messages."""
        messages, total = chat_service.list_messages(
            db_session,
            indexed_session_with_messages.session_id
        )

        assert len(messages) == 2
        assert total == 2

    @pytest.mark.asyncio
    async def test_stream_claude_response(self, indexed_session):
        """Test streaming response from claude-mpm."""
        with patch('app.services.chat_service.asyncio.create_subprocess_exec') as mock_exec:
            # Mock subprocess
            mock_process = AsyncMock()
            mock_process.stdout.readline = AsyncMock(side_effect=[
                b'{"delta": {"text": "Hello"}}\n',
                b'{"delta": {"text": " world"}}\n',
                b'',
            ])
            mock_process.returncode = 0
            mock_process.stderr.read = AsyncMock(return_value=b'')
            mock_exec.return_value = mock_process

            events = []
            async for event in chat_service.stream_claude_response(
                indexed_session,
                "Test question",
                "msg_123"
            ):
                events.append(event)

            assert any('chunk' in e for e in events)
            assert any('complete' in e for e in events)
```

### 9.2 Backend Integration Tests

**File: `tests/test_chat_routes.py`**

```python
import pytest
from fastapi.testclient import TestClient


class TestChatRoutes:
    def test_send_message_success(self, client, indexed_session):
        """Test sending a chat message."""
        response = client.post(
            f"/api/v1/sessions/{indexed_session.session_id}/chat/",
            json={"content": "What patterns are used?"}
        )

        assert response.status_code == 201
        data = response.json()
        assert data["role"] == "user"
        assert data["content"] == "What patterns are used?"
        assert "stream_url" in data

    def test_send_message_not_indexed(self, client, session):
        """Test error when session not indexed."""
        response = client.post(
            f"/api/v1/sessions/{session.session_id}/chat/",
            json={"content": "Question"}
        )

        assert response.status_code == 400
        assert response.json()["detail"]["error"]["code"] == "SESSION_NOT_INDEXED"

    def test_list_messages(self, client, session_with_messages):
        """Test listing chat messages."""
        response = client.get(
            f"/api/v1/sessions/{session_with_messages.session_id}/chat/"
        )

        assert response.status_code == 200
        data = response.json()
        assert "messages" in data
        assert "count" in data
```

### 9.3 Frontend Component Tests

**File: `tests/chat.test.ts`**

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/svelte";
import SessionChat from "../src/lib/components/chat/SessionChat.svelte";

describe("SessionChat", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("renders chat interface when indexed", async () => {
    render(SessionChat, { props: { sessionId: "test-123", isIndexed: true } });

    expect(screen.getByPlaceholderText(/Ask a question/)).toBeInTheDocument();
    expect(screen.getByRole("button")).toBeEnabled();
  });

  it("disables input when not indexed", async () => {
    render(SessionChat, { props: { sessionId: "test-123", isIndexed: false } });

    expect(screen.getByPlaceholderText(/Index session/)).toBeDisabled();
    expect(screen.getByRole("button")).toBeDisabled();
  });

  it("sends message on submit", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({
          message_id: "msg-1",
          stream_url: "/api/v1/sessions/test-123/chat/stream/msg-1",
        }),
    });
    global.fetch = mockFetch;

    render(SessionChat, { props: { sessionId: "test-123", isIndexed: true } });

    const input = screen.getByRole("textbox");
    await fireEvent.input(input, { target: { value: "Test question" } });
    await fireEvent.click(screen.getByRole("button"));

    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/sessions/test-123/chat/"),
      expect.objectContaining({ method: "POST" }),
    );
  });
});
```

### 9.4 E2E Tests

**File: `tests/e2e/chat.spec.ts`** (Playwright)

```typescript
import { test, expect } from "@playwright/test";

test.describe("Session Chat", () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to a session with indexed content
    await page.goto("/sessions/test-session-123");
  });

  test("can send chat message and see response", async ({ page }) => {
    // Type message
    await page.fill("textarea", "What patterns are used?");

    // Send
    await page.click('button[type="submit"]');

    // Wait for response to start streaming
    await expect(page.locator(".message.assistant")).toBeVisible();

    // Wait for streaming to complete
    await expect(page.locator(".message.assistant .metadata")).toBeVisible({
      timeout: 30000,
    });
  });
});
```

---

## 10. Implementation Phases

### Phase 1: Foundation (Week 1)

**Tasks:**

1. [ ] Create database migration for `chat_messages` table
2. [ ] Implement `ChatMessage` SQLAlchemy model
3. [ ] Implement Pydantic schemas for chat
4. [ ] Implement chat service with basic CRUD
5. [ ] Implement chat router endpoints (without streaming)
6. [ ] Write backend unit tests

**Deliverables:**

- Database schema for chat messages
- REST API for creating/listing chat messages
- Backend tests passing

### Phase 2: Streaming Backend (Week 2)

**Tasks:**

1. [ ] Implement native Claude CLI subprocess invocation
2. [ ] Implement SSE streaming in FastAPI
3. [ ] Add stream endpoint to chat router
4. [ ] Implement heartbeat for long-running streams
5. [ ] Add timeout handling
6. [ ] Write streaming integration tests

**Deliverables:**

- Working SSE endpoint that streams Claude CLI responses
- Proper error handling and timeouts
- Integration tests for streaming

### Phase 3: Frontend Implementation (Week 3)

**Tasks:**

1. [ ] Add chat types to API client
2. [ ] Add TanStack Query hooks for chat
3. [ ] Create SessionChat component
4. [ ] Create ChatMessage component
5. [ ] Implement EventSource handling
6. [ ] Integrate into session page
7. [ ] Write frontend tests

**Deliverables:**

- Complete chat UI in session page
- Real-time streaming display
- Chat history persistence

### Phase 4: Polish and Testing (Week 4)

**Tasks:**

1. [ ] Add error states and recovery
2. [ ] Add loading states and animations
3. [ ] Implement message deletion
4. [ ] Add keyboard shortcuts
5. [ ] E2E testing
6. [ ] Performance optimization
7. [ ] Documentation updates

**Deliverables:**

- Production-ready chat feature
- Complete test coverage
- Updated API contract documentation

### Dependency Graph

```
Phase 1: Foundation
    |
    ├── chat_messages migration
    ├── ChatMessage model
    ├── Pydantic schemas
    └── Chat service + router
            |
            v
Phase 2: Streaming Backend
    |
    ├── claude-mpm subprocess
    ├── SSE implementation
    └── Stream endpoint
            |
            v
Phase 3: Frontend Implementation
    |
    ├── API client updates
    ├── TanStack Query hooks
    ├── SessionChat component
    └── EventSource handling
            |
            v
Phase 4: Polish and Testing
    |
    ├── Error handling
    ├── E2E tests
    └── Documentation
```

---

## Appendix

### A. References

**FastAPI SSE:**

- [FastAPI Server-Sent Events for LLM Streaming](https://medium.com/@2nick2patel2/fastapi-server-sent-events-for-llm-streaming-smooth-tokens-low-latency-1b211c94cff5)
- [Implementing SSE with FastAPI](https://mahdijafaridev.medium.com/implementing-server-sent-events-sse-with-fastapi-real-time-updates-made-simple-6492f8bfc154)
- [Building Streamable MCP Servers with FastAPI and SSE](https://www.aubergine.co/insights/a-guide-to-building-streamable-mcp-servers-with-fastapi-and-sse)

**SvelteKit SSE:**

- [sveltekit-sse Library](https://github.com/razshare/sveltekit-sse)
- [Building Real-time SvelteKit Apps with SSE](https://sveltetalk.com/posts/building-real-time-sveltekit-apps-with-server-sent-events)
- [SSE in SvelteKit](https://medium.com/version-1/sse-in-sveltekit-5c085b3b61d1)

**Claude CLI:**

- `claude --help` (native Claude CLI flags)
- See Section 7 for corrected CLI invocation strategy

**Research Findings:**

- `/docs/research/claude-mpm-cli-research.md` (CLI architecture and flag analysis)

### B. Glossary

| Term            | Definition                                                                                 |
| --------------- | ------------------------------------------------------------------------------------------ |
| **SSE**         | Server-Sent Events - HTTP-based protocol for server-to-client streaming                    |
| **EventSource** | Browser API for consuming SSE streams                                                      |
| **Claude CLI**  | Native Claude command-line interface (the `claude` command)                                |
| **claude-mpm**  | Claude Multi-Agent Project Manager - wrapper around Claude CLI with orchestration features |
| **JSONL**       | JSON Lines - newline-delimited JSON objects                                                |

### C. API Contract Checklist

- [ ] Update `research-mind-service/docs/api-contract.md`
- [ ] Version bump to 1.3.0
- [ ] Add Chat section with all endpoints
- [ ] Add new error codes
- [ ] Add changelog entry
- [ ] Copy to `research-mind-ui/docs/api-contract.md`
- [ ] Regenerate TypeScript types (`npm run gen:api`)

### D. Revision History

| Version | Date       | Author         | Changes                                                                                                                                                                                                                                                                                                                                                                                   |
| ------- | ---------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1.0.0   | 2026-02-03 | Claude Code    | Initial draft                                                                                                                                                                                                                                                                                                                                                                             |
| 1.0.1   | 2026-02-03 | Research Agent | **CLI corrections**: Updated Section 7 based on claude-mpm research. Removed invalid flags (`--output-format stream-json`, `--include-partial-messages`, `--project-dir`). Changed to use native Claude CLI with `--print` flag. Updated streaming approach to line-buffered stdout.                                                                                                      |
| 1.1.0   | 2026-02-03 | Research Agent | **claude-mpm Exclusive Integration**: Per project requirement, changed from native Claude CLI to claude-mpm exclusively. Updated all code examples to use `claude-mpm run --non-interactive --no-hooks --no-tickets --launch-method subprocess -i`. Added `CLAUDE_MPM_USER_PWD` env var. Updated error codes. See `/docs/research/claude-mpm-cli-research.md` for complete CLI reference. |

---

_End of Implementation Plan_
