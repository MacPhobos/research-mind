# Clear Chat History Feature - Implementation Plan

## Overview

Add a "Clear History" button to the SessionChat component that:

1. Displays a confirmation dialog (using existing ConfirmDialog)
2. Calls a new backend endpoint to delete all chat messages
3. Shows toast notification and reactively clears the chat view

## User Requirements

- **Modal**: Reusable ConfirmDialog (already exists)
- **Button placement**: Left of "Send" button
- **Feedback**: Toast notification + reactive update

---

## Implementation Sequence (Contract-First Workflow)

### Phase 1: Backend

#### Step 1.1: Update API Contract

**File**: `research-mind-service/docs/api-contract.md`

Add after "Delete Chat Message" section (~line 950):

````markdown
### Clear Chat History

#### `DELETE /api/v1/sessions/{session_id}/chat`

Delete all chat messages for a session.

**Path Parameters**

| Parameter    | Type   | Description  |
| ------------ | ------ | ------------ |
| `session_id` | string | Session UUID |

**Response** `204 No Content`

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
````

````

**Version bump**: `1.4.0` → `1.5.0`
**Add changelog entry**: "Added Clear Chat History endpoint"

#### Step 1.2: Add Service Function
**File**: `research-mind-service/app/services/chat_service.py`

Add after `delete_message()` function:

```python
def clear_chat_history(db: DbSession, session_id: str) -> int:
    """Delete all chat messages for a session.

    Returns the number of messages deleted.
    """
    count = (
        db.query(ChatMessage)
        .filter(ChatMessage.session_id == session_id)
        .delete(synchronize_session=False)
    )
    db.commit()
    logger.info("Cleared %d messages from session %s", count, session_id)
    return count
````

#### Step 1.3: Add Route Handler

**File**: `research-mind-service/app/routes/chat.py`

Add after `delete_chat_message` route:

```python
@router.delete(
    "/{session_id}/chat",
    status_code=204,
    response_model=None,
)
def clear_chat_history(
    session_id: str,
    db: Session = Depends(get_db),
) -> None:
    """Clear all chat messages for a session."""
    session = chat_service.get_session_by_id(db, session_id)
    if session is None:
        raise HTTPException(
            status_code=404,
            detail={
                "error": {
                    "code": "SESSION_NOT_FOUND",
                    "message": f"Session '{session_id}' not found",
                }
            },
        )
    chat_service.clear_chat_history(db, session_id)
```

#### Step 1.4: Add Backend Tests

**File**: `research-mind-service/tests/test_chat_clear.py` (new)

Test cases:

- Clear history with messages → 204, messages deleted
- Clear history with no messages → 204 (no-op)
- Clear history for non-existent session → 404

---

### Phase 2: Frontend

#### Step 2.1: Copy Contract & Regenerate Types

```bash
cp research-mind-service/docs/api-contract.md research-mind-ui/docs/api-contract.md
cd research-mind-ui && npm run gen:api
```

#### Step 2.2: Add API Client Method

**File**: `research-mind-ui/src/lib/api/client.ts`

Add after `deleteChatMessage()`:

```typescript
async clearChatHistory(sessionId: string): Promise<void> {
  const response = await fetch(
    `${apiBaseUrl}/api/v1/sessions/${sessionId}/chat`,
    { method: 'DELETE' }
  );
  if (!response.ok) {
    throw await ApiError.fromResponse('Failed to clear chat history', response);
  }
},
```

#### Step 2.3: Add TanStack Query Hook

**File**: `research-mind-ui/src/lib/api/hooks.ts`

Add after `useDeleteChatMessageMutation()`:

```typescript
export function useClearChatHistoryMutation() {
  const queryClient = useQueryClient();
  return createMutation<void, ApiError, string>({
    mutationFn: (sessionId) => apiClient.clearChatHistory(sessionId),
    onSuccess: (_data, sessionId) => {
      queryClient.removeQueries({ queryKey: queryKeys.chat.all(sessionId) });
      queryClient.invalidateQueries({
        queryKey: queryKeys.chat.all(sessionId),
      });
    },
  });
}
```

#### Step 2.4: Update SessionChat Component

**File**: `research-mind-ui/src/lib/components/chat/SessionChat.svelte`

**Imports** (add at top):

```typescript
import { Trash2 } from "lucide-svelte";
import { useClearChatHistoryMutation } from "$lib/api/hooks";
import { toastStore } from "$lib/stores/toast";
import ConfirmDialog from "$lib/components/shared/ConfirmDialog.svelte";
```

**State** (after line 28):

```typescript
const clearMutation = useClearChatHistoryMutation();
let showClearDialog = $state(false);
```

**Handlers** (after `refreshMessages` function):

```typescript
function openClearDialog() {
  showClearDialog = true;
}

async function handleClearConfirm() {
  showClearDialog = false;
  try {
    await $clearMutation.mutateAsync(sessionId);
    toastStore.success("Chat history cleared");
    stream.reset();
  } catch (err) {
    console.error("Failed to clear chat history:", err);
    toastStore.error("Failed to clear chat history");
  }
}

function handleClearCancel() {
  showClearDialog = false;
}
```

**Update `isSendDisabled`** (line 136):

```typescript
const isSendDisabled = $derived(
  !inputContent.trim() ||
    $sendMutation.isPending ||
    $clearMutation.isPending ||
    stream.isStreaming ||
    !isIndexed,
);
```

**Update input-actions** (replace lines 224-245):

```svelte
<div class="input-actions">
  <span class="input-hint">
    {#if stream.isStreaming}
      <Loader2 size={14} class="spinner" />
      Generating response...
    {:else if $clearMutation.isPending}
      <Loader2 size={14} class="spinner" />
      Clearing history...
    {:else}
      Press Ctrl+Enter to send
    {/if}
  </span>
  <div class="action-buttons">
    <button
      type="button"
      onclick={openClearDialog}
      disabled={!isIndexed || stream.isStreaming || $clearMutation.isPending || displayMessages().length === 0}
      class="clear-btn"
      title="Clear chat history"
    >
      <Trash2 size={18} />
    </button>
    <button type="submit" disabled={isSendDisabled} class="send-btn">
      {#if $sendMutation.isPending}
        <Loader2 size={18} class="spinner" />
      {:else}
        <Send size={18} />
      {/if}
      Send
    </button>
  </div>
</div>
```

**Add ConfirmDialog** (before closing `</div>` of session-chat, around line 247):

```svelte
<ConfirmDialog
  bind:open={showClearDialog}
  title="Clear Chat History"
  message="Are you sure you want to clear all chat messages? This action cannot be undone."
  confirmLabel="Clear"
  cancelLabel="Cancel"
  variant="danger"
  onConfirm={handleClearConfirm}
  onCancel={handleClearCancel}
/>
```

**Add styles**:

```css
.action-buttons {
  display: flex;
  align-items: center;
  gap: var(--space-2);
}

.clear-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--space-2);
  background: transparent;
  border: 1px solid var(--border-color);
  border-radius: var(--border-radius-md);
  color: var(--text-secondary);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.clear-btn:hover:not(:disabled) {
  background: var(--error-bg, rgba(239, 68, 68, 0.1));
  border-color: var(--error-color);
  color: var(--error-color);
}

.clear-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
```

**Update mobile media query** (add to existing @media block):

```css
.action-buttons {
  justify-content: flex-end;
}
```

#### Step 2.5: Add Frontend Tests

**File**: `research-mind-ui/tests/clearChatHistory.test.ts` (new)

Test cases:

- API client method exists and calls correct endpoint
- 204 response handled correctly
- 404 error thrown correctly

---

## Critical Files Summary

| File                                                          | Action                              |
| ------------------------------------------------------------- | ----------------------------------- |
| `research-mind-service/docs/api-contract.md`                  | Add endpoint, bump version          |
| `research-mind-service/app/services/chat_service.py`          | Add `clear_chat_history()`          |
| `research-mind-service/app/routes/chat.py`                    | Add route handler                   |
| `research-mind-service/tests/test_chat_clear.py`              | New test file                       |
| `research-mind-ui/docs/api-contract.md`                       | Copy from service                   |
| `research-mind-ui/src/lib/api/client.ts`                      | Add `clearChatHistory()`            |
| `research-mind-ui/src/lib/api/hooks.ts`                       | Add `useClearChatHistoryMutation()` |
| `research-mind-ui/src/lib/components/chat/SessionChat.svelte` | Add button, dialog, handlers        |
| `research-mind-ui/tests/clearChatHistory.test.ts`             | New test file                       |

---

## Verification

### Backend

```bash
cd research-mind-service
uv run pytest tests/test_chat_clear.py -v  # New tests
make test                                   # All tests
```

### Frontend

```bash
cd research-mind-ui
npm run typecheck  # Type check
npm run test       # All tests
```

### Manual Testing

1. Navigate to a session with chat messages
2. Click trash icon (left of Send)
3. Verify confirmation dialog appears with danger styling
4. Click "Clear" to confirm
5. Verify toast shows "Chat history cleared"
6. Verify chat view is empty
7. Refresh page - messages should remain deleted
