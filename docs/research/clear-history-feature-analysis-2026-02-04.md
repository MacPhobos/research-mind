# Clear History Feature - Research Analysis

**Date:** 2026-02-04
**Researcher:** Claude Code (Research Agent)
**Purpose:** Architecture analysis for implementing "Clear History" feature

---

## Executive Summary

This document provides a comprehensive analysis of the current chat session and message implementation in the research-mind codebase, with recommendations for implementing a "Clear History" feature.

**Key Findings:**

- Chat messages are stored in PostgreSQL with session-scoped isolation
- Individual message deletion endpoint exists but bulk clear does not
- Frontend has established patterns for destructive actions (ConfirmDialog component)
- Database uses CASCADE delete - clearing messages won't affect session

---

## 1. Architecture Overview

### How Sessions and Messages Are Related

```
Session (1) -----> (N) ChatMessage
   |                    |
   +-- session_id (PK)  +-- message_id (PK)
   +-- workspace_path   +-- session_id (FK, CASCADE)
   +-- is_indexed()     +-- role (user|assistant)
                        +-- content
                        +-- status
                        +-- created_at
```

**Key Relationship:** `ChatMessage.session_id` has `ForeignKey("sessions.session_id", ondelete="CASCADE")`, meaning:

- Messages belong to exactly one session
- Deleting a session automatically deletes all its messages
- Messages are scoped to sessions - no cross-session access

### Data Flow

1. User sends message via `POST /api/v1/sessions/{session_id}/chat`
2. Backend creates user message + placeholder assistant message
3. Frontend connects to SSE stream for assistant response
4. Messages persist to `chat_messages` table with timestamps and metadata
5. Frontend queries messages via `GET /api/v1/sessions/{session_id}/chat`

---

## 2. Backend Implementation Details

### Chat Message Model (`/research-mind-service/app/models/chat_message.py`)

```python
class ChatMessage(Base):
    __tablename__ = "chat_messages"

    message_id: str = Column(String(36), primary_key=True, default=lambda: str(uuid4()))
    session_id: str = Column(
        String(36),
        ForeignKey("sessions.session_id", ondelete="CASCADE"),
        nullable=False,
    )
    role: str = Column(String(20), nullable=False)  # "user" | "assistant"
    content: str = Column(Text, nullable=False)
    status: str = Column(String(20), nullable=False, default="pending")
    error_message: str | None = Column(Text, nullable=True)
    created_at: datetime = Column(DateTime(timezone=True), nullable=False)
    completed_at: datetime | None = Column(DateTime(timezone=True), nullable=True)
    token_count: int | None = Column(Integer, nullable=True)
    duration_ms: int | None = Column(Integer, nullable=True)
    metadata_json = Column(JSON, nullable=True, default=dict)
```

**Database Indexes:**

- `idx_chat_messages_session_id` - Fast session-scoped queries
- `idx_chat_messages_created_at` - Ordering
- `idx_chat_messages_status` - Filtering by status

### Session Model (`/research-mind-service/app/models/session.py`)

```python
class Session(Base):
    __tablename__ = "sessions"

    session_id: str = Column(String(36), primary_key=True)
    name: str = Column(String(255), nullable=False)
    workspace_path: str = Column(String(512), nullable=False, unique=True)
    status: str = Column(String(50), nullable=False, default="active")
    # ... other fields
```

### Current Chat Routes (`/research-mind-service/app/routes/chat.py`)

| Endpoint                                                 | Method | Description               |
| -------------------------------------------------------- | ------ | ------------------------- |
| `/api/v1/sessions/{session_id}/chat`                     | POST   | Send new message          |
| `/api/v1/sessions/{session_id}/chat`                     | GET    | List messages (paginated) |
| `/api/v1/sessions/{session_id}/chat/{message_id}`        | GET    | Get single message        |
| `/api/v1/sessions/{session_id}/chat/{message_id}`        | DELETE | Delete single message     |
| `/api/v1/sessions/{session_id}/chat/stream/{message_id}` | GET    | SSE stream                |

**Missing Endpoint:** No bulk delete/clear endpoint exists.

### Chat Service (`/research-mind-service/app/services/chat_service.py`)

Current `delete_message` function:

```python
def delete_message(db: DbSession, session_id: str, message_id: str) -> bool:
    """Delete a chat message by ID.
    Returns True if the message was found and deleted, False otherwise.
    """
    message = get_message_by_id(db, session_id, message_id)
    if message is None:
        return False
    db.delete(message)
    db.commit()
    return True
```

---

## 3. Frontend Implementation Details

### Chat Components

**Component Hierarchy:**

```
routes/sessions/[id]/chat/+page.svelte
    |
    +-- SessionChat.svelte
            |
            +-- ChatMessage.svelte
            |       +-- MarkdownContent.svelte
            |
            +-- useChatStream.svelte (hook)
```

### Key Files

| File                                                               | Purpose                                                 |
| ------------------------------------------------------------------ | ------------------------------------------------------- |
| `/research-mind-ui/src/lib/components/chat/SessionChat.svelte`     | Main chat container with message list, input, streaming |
| `/research-mind-ui/src/lib/components/chat/ChatMessage.svelte`     | Individual message display with two-stage rendering     |
| `/research-mind-ui/src/lib/api/hooks.ts`                           | TanStack Query hooks for chat operations                |
| `/research-mind-ui/src/lib/api/client.ts`                          | API client with Zod validation                          |
| `/research-mind-ui/src/lib/components/shared/ConfirmDialog.svelte` | Reusable confirmation dialog                            |

### State Management (TanStack Query)

**Query Keys Structure:**

```typescript
queryKeys.chat.all(sessionId); // All chat queries for session
queryKeys.chat.list(sessionId, {}); // Message list query
queryKeys.chat.detail(sessionId, msgId); // Single message query
```

**Current Hooks:**

```typescript
useChatMessagesQuery(sessionId); // List messages
useSendChatMessageMutation(); // Send message
useDeleteChatMessageMutation(); // Delete single message
```

### Existing Destructive Action Pattern

**ConfirmDialog Component (`/research-mind-ui/src/lib/components/shared/ConfirmDialog.svelte`):**

```svelte
<ConfirmDialog
  open={showConfirm}
  title="Delete Session"
  message="Are you sure you want to delete this session?"
  confirmLabel="Delete"
  cancelLabel="Cancel"
  variant="danger"
  onConfirm={handleDelete}
  onCancel={() => showConfirm = false}
/>
```

Features:

- Modal overlay with escape key support
- Danger variant with red button styling
- Accessible with ARIA attributes
- Consistent cancel/confirm action pattern

---

## 4. API Contract Analysis

### Current Contract Version: 1.4.0

**Chat Endpoints Defined:**

| Method | Endpoint                                          | Status      |
| ------ | ------------------------------------------------- | ----------- |
| POST   | `/sessions/{session_id}/chat`                     | Implemented |
| GET    | `/sessions/{session_id}/chat`                     | Implemented |
| GET    | `/sessions/{session_id}/chat/{message_id}`        | Implemented |
| DELETE | `/sessions/{session_id}/chat/{message_id}`        | Implemented |
| GET    | `/sessions/{session_id}/chat/stream/{message_id}` | Implemented |

**Missing from Contract:**

- `DELETE /sessions/{session_id}/chat` - Clear all messages

### Error Codes Defined

| Code                     | HTTP Status | Description                         |
| ------------------------ | ----------- | ----------------------------------- |
| `SESSION_NOT_FOUND`      | 404         | Session UUID not found              |
| `CHAT_MESSAGE_NOT_FOUND` | 404         | Chat message UUID not found         |
| `SESSION_NOT_INDEXED`    | 400         | Session must be indexed before chat |

---

## 5. Implementation Recommendations

### Recommended Approach: New Bulk Delete Endpoint

**API Contract Addition:**

````markdown
### Clear Chat History

#### `DELETE /api/v1/sessions/{session_id}/chat`

Delete all chat messages for a session. This is a destructive operation.

**Path Parameters**

| Parameter    | Type   | Description  |
| ------------ | ------ | ------------ |
| `session_id` | string | Session UUID |

**Response** `200 OK`

```json
{
  "deleted_count": 42
}
```
````

**Response** `404 Not Found` - Session not found

```json
{
  "detail": {
    "error": {
      "code": "SESSION_NOT_FOUND",
      "message": "Session 'nonexistent-id' not found"
    }
  }
}
```

**curl**:

```bash
curl -X DELETE http://localhost:15010/api/v1/sessions/{session_id}/chat
```

````

### Implementation Steps

#### Backend (research-mind-service)

1. **Update API Contract** (`docs/api-contract.md`)
   - Add `DELETE /sessions/{session_id}/chat` endpoint
   - Version bump: 1.4.0 -> 1.5.0
   - Add changelog entry

2. **Add Schema** (`app/schemas/chat.py`)
   ```python
   class ClearChatHistoryResponse(BaseModel):
       deleted_count: int
````

3. **Add Service Function** (`app/services/chat_service.py`)

   ```python
   def clear_chat_history(db: DbSession, session_id: str) -> int:
       """Delete all chat messages for a session.
       Returns the number of messages deleted.
       """
       result = db.query(ChatMessage).filter(
           ChatMessage.session_id == session_id
       ).delete(synchronize_session='fetch')
       db.commit()
       return result
   ```

4. **Add Route** (`app/routes/chat.py`)

   ```python
   @router.delete("/{session_id}/chat", response_model=ClearChatHistoryResponse)
   def clear_chat_history(
       session_id: str,
       db: Session = Depends(get_db),
   ) -> ClearChatHistoryResponse:
       """Clear all chat messages for a session."""
       # Verify session exists
       session = chat_service.get_session_by_id(db, session_id)
       if session is None:
           raise HTTPException(status_code=404, detail={...})

       deleted_count = chat_service.clear_chat_history(db, session_id)
       return ClearChatHistoryResponse(deleted_count=deleted_count)
   ```

5. **Add Tests** (`tests/test_chat.py`)
   - Test successful clear returns count
   - Test clear on non-existent session returns 404
   - Test clear on empty session returns 0

#### Frontend (research-mind-ui)

1. **Copy Updated Contract**

   ```bash
   cp research-mind-service/docs/api-contract.md research-mind-ui/docs/api-contract.md
   ```

2. **Regenerate Types**

   ```bash
   npm run gen:api
   ```

3. **Add API Client Method** (`src/lib/api/client.ts`)

   ```typescript
   async clearChatHistory(sessionId: string): Promise<{ deleted_count: number }> {
     const response = await fetch(
       `${apiBaseUrl}/api/v1/sessions/${sessionId}/chat`,
       { method: 'DELETE' }
     );
     if (!response.ok) {
       throw await ApiError.fromResponse('Failed to clear chat history', response);
     }
     return response.json();
   }
   ```

4. **Add TanStack Mutation Hook** (`src/lib/api/hooks.ts`)

   ```typescript
   export function useClearChatHistoryMutation() {
     const queryClient = useQueryClient();

     return createMutation<{ deleted_count: number }, ApiError, string>({
       mutationFn: (sessionId) => apiClient.clearChatHistory(sessionId),
       onSuccess: (_data, sessionId) => {
         // Clear all cached messages for this session
         queryClient.removeQueries({
           queryKey: queryKeys.chat.all(sessionId),
         });
       },
     });
   }
   ```

5. **Add UI Button to SessionChat.svelte**

   ```svelte
   <script lang="ts">
     import { useClearChatHistoryMutation } from '$lib/api/hooks';
     import ConfirmDialog from '$lib/components/shared/ConfirmDialog.svelte';
     import { Trash2 } from 'lucide-svelte';

     let showClearConfirm = $state(false);
     const clearMutation = useClearChatHistoryMutation();

     async function handleClearHistory() {
       await $clearMutation.mutateAsync(sessionId);
       showClearConfirm = false;
     }
   </script>

   <!-- In header or actions area -->
   <button
     type="button"
     class="clear-btn"
     onclick={() => showClearConfirm = true}
     disabled={displayMessages().length === 0}
   >
     <Trash2 size={16} />
     Clear History
   </button>

   <ConfirmDialog
     bind:open={showClearConfirm}
     title="Clear Chat History"
     message="Are you sure you want to delete all messages? This cannot be undone."
     confirmLabel="Clear All"
     cancelLabel="Cancel"
     variant="danger"
     onConfirm={handleClearHistory}
     onCancel={() => showClearConfirm = false}
   />
   ```

---

## 6. Alternative Approaches Considered

### Option A: Client-side Loop Delete (NOT RECOMMENDED)

- Call `DELETE /chat/{message_id}` for each message
- Pros: No backend changes
- Cons: N+1 requests, poor performance, race conditions, partial failure states

### Option B: Reuse Session Delete (NOT RECOMMENDED)

- Delete and recreate the session
- Pros: No new endpoint needed
- Cons: Loses session metadata, workspace, content, audit logs

### Option C: Soft Delete / Archive (FUTURE ENHANCEMENT)

- Mark messages as "cleared" without deletion
- Pros: Recoverable, audit trail
- Cons: More complex, requires UI for recovery, database growth

**Recommendation:** Option B1 (New Bulk Delete Endpoint) provides the best balance of simplicity, performance, and user experience.

---

## 7. File Paths Reference

### Frontend (research-mind-ui)

| Purpose               | Path                                              |
| --------------------- | ------------------------------------------------- |
| Chat page             | `/src/routes/sessions/[id]/chat/+page.svelte`     |
| SessionChat component | `/src/lib/components/chat/SessionChat.svelte`     |
| ChatMessage component | `/src/lib/components/chat/ChatMessage.svelte`     |
| API hooks             | `/src/lib/api/hooks.ts`                           |
| API client            | `/src/lib/api/client.ts`                          |
| ConfirmDialog         | `/src/lib/components/shared/ConfirmDialog.svelte` |
| Query keys            | `/src/lib/api/queryKeys.ts`                       |

### Backend (research-mind-service)

| Purpose           | Path                            |
| ----------------- | ------------------------------- |
| Chat routes       | `/app/routes/chat.py`           |
| Chat service      | `/app/services/chat_service.py` |
| Chat schemas      | `/app/schemas/chat.py`          |
| ChatMessage model | `/app/models/chat_message.py`   |
| Session model     | `/app/models/session.py`        |
| API contract      | `/docs/api-contract.md`         |

---

## 8. Checklist for Implementation

### Backend Tasks

- [ ] Update `docs/api-contract.md` with new endpoint
- [ ] Bump version to 1.5.0
- [ ] Add `ClearChatHistoryResponse` schema
- [ ] Add `clear_chat_history()` service function
- [ ] Add `DELETE /{session_id}/chat` route
- [ ] Add unit tests for clear endpoint
- [ ] Run `make test` to verify

### Frontend Tasks

- [ ] Copy updated contract to UI
- [ ] Run `npm run gen:api` to regenerate types
- [ ] Add `clearChatHistory()` to API client
- [ ] Add `useClearChatHistoryMutation()` hook
- [ ] Add Clear History button to SessionChat
- [ ] Add ConfirmDialog for clear action
- [ ] Run `npm test` to verify
- [ ] Test end-to-end flow manually

---

## 9. Appendix: Existing Patterns

### Destructive Action Pattern (Session Delete)

From `/research-mind-ui/src/lib/api/hooks.ts`:

```typescript
export function useDeleteSessionMutation() {
  const queryClient = useQueryClient();

  return createMutation<void, ApiError, string>({
    mutationFn: (sessionId) => apiClient.deleteSession(sessionId),
    onSuccess: (_data, sessionId) => {
      queryClient.removeQueries({
        queryKey: queryKeys.sessions.detail(sessionId),
      });
      queryClient.invalidateQueries({ queryKey: queryKeys.sessions.all });
    },
  });
}
```

### Content Delete Pattern

From `/research-mind-ui/src/lib/api/hooks.ts`:

```typescript
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

---

**End of Research Document**
