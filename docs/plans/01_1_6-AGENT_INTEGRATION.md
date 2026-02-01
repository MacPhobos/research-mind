# Phase 1.6: Agent Integration

**Subphase**: 1.6 of 8 (Phase 1)
**Duration**: 5-7 business days
**Effort**: 40-56 hours
**Team Size**: 2 FTE engineers
**Prerequisite**: Phase 1.1 (FastAPI), Phase 1.3 (search results)
**Blocking**: 1.7, 1.8
**Status**: CRITICAL - Core agent analysis loop

---

## Subphase Objective

Create custom "research-analyst" agent for claude-ppm and implement agent invocation endpoint. Agents analyze search results in session-scoped sandboxes with network disabled and read-only file access.

**Success Definition**:

- Custom agent deployed to ~/.claude/agents/research-analyst/AGENT.md
- Agent invocation working via POST /api/sessions/{id}/analyze
- Agent returns answer with citations to code locations
- Session isolation enforced (agent can only see session files)
- Network disabled (no curl, wget, or external API calls)

---

## Timeline & Effort

### Day 1-2: Research-Analyst Agent Definition (12-16 hours)

- Create AGENT.md with agent personality and instructions
- Define capabilities (semantic search, file reading, synthesis)
- Define constraints (session scoping, read-only, no network)

### Day 3-4: Agent Runner Implementation (12-16 hours)

- Create AgentRunner for subprocess execution
- Pass SESSION_DIR environment variable
- Disable network via environment constraints
- Parse agent response for citations

### Day 5-7: Integration & Testing (12-16 hours)

- Analysis endpoint implementation
- Agent output parsing (extract citations)
- Error handling and timeout management
- Agent containment verification tests

---

## Deliverables

1. **~/.claude/agents/research-analyst/AGENT.md** (new)

   - Custom agent definition for research analysis
   - Capabilities, constraints, examples

2. **research-mind-service/app/services/agent_runner.py** (new)

   - AgentRunner for subprocess execution
   - Result parsing (citations, answer extraction)
   - Subprocess constraints (env vars, working directory, timeout)

3. **research-mind-service/app/routes/analyze.py** (new)

   - POST /api/sessions/{id}/analyze endpoint
   - Analysis request/response handling

4. **research-mind-service/app/schemas/analyze.py** (new)
   - Pydantic models for analysis requests/responses

---

## Detailed Implementation

### Task 1.6.1: Create research-analyst Agent (8-10 hours)

Create **~/.claude/agents/research-analyst/AGENT.md**:

```markdown
# Research Analyst Agent

You are a code analysis and research assistant specialized in understanding
complex codebases through semantic search and synthesis.

## Capabilities

You have access to:

1. **Semantic Search**: Search code with natural language queries
2. **File Reading**: Read source code files for detailed analysis
3. **Synthesis**: Combine findings into coherent analysis

## Constraints

You MUST follow these constraints:

1. **Session Isolation**: You can ONLY access files within SESSION_DIR

   - Environment variable: $SESSION_DIR points to session workspace
   - DO NOT attempt to access files outside SESSION_DIR
   - DO NOT use absolute paths like /etc, /root, etc.

2. **Read-Only**: You can only READ files, never WRITE or EXECUTE

   - No creating/modifying files
   - No running commands or scripts

3. **No Network**: Network access is DISABLED

   - DO NOT attempt: curl, wget, http requests, API calls
   - These will fail due to environment constraints

4. **Query Citations**: ALWAYS cite specific code locations
   - Include file paths (relative to session root)
   - Include line numbers when referencing code
   - Format: `[filename:line_number]` or `filename (lines X-Y)`

## Examples

### User Query

"How does authentication work in this codebase?"

### Your Response

Based on semantic search and file analysis:

The authentication system is implemented across three main files:

1. **auth/middleware.py** - Request authentication

   - `verify_token()` function (lines 15-30) validates JWT tokens
   - `require_auth` decorator (lines 45-60) enforces auth on routes

2. **auth/models.py** - User and token data structures

   - `User` model (lines 10-25) represents authenticated users
   - `Token` model (lines 30-40) stores JWT token data

3. **routes/auth.py** - Authentication endpoints
   - `POST /auth/login` (lines 20-40) validates credentials and issues token
   - `GET /auth/me` (lines 50-60) returns current user info

The flow is: Login → Token Issued → Token Validated on Each Request

## When You Get Stuck

If you encounter errors or limitations:

1. Explain what you tried to do
2. Explain why it failed
3. Propose an alternative approach
4. If you truly cannot proceed, ask clarifying questions

Remember: You are in a SANDBOXED environment by design.
This is not a limitation - it's a feature for security.
```

### Task 1.6.2: Create Agent Runner (12-16 hours)

Create **research-mind-service/app/services/agent_runner.py**:

```python
"""
Agent runner for executing research-analyst agent in subprocess.

Handles:
- Subprocess execution with environment constraints
- Result parsing (citations, answer extraction)
- Timeout and error handling
- Session isolation enforcement
"""

import subprocess
import logging
import asyncio
import json
from pathlib import Path
from typing import Dict, List, Tuple
import re

logger = logging.getLogger(__name__)


class AgentRunner:
    """Execute research-analyst agent in isolated subprocess."""

    @staticmethod
    async def run_analysis(
        session_id: str,
        workspace_path: Path,
        question: str,
        search_context: str,
        timeout_seconds: int = 300,
    ) -> Dict:
        """
        Run agent analysis with session isolation.

        Args:
            session_id: Session identifier
            workspace_path: Session workspace directory
            question: User's research question
            search_context: Search results context for agent
            timeout_seconds: Max execution time (5 min default)

        Returns:
            Dict with answer and citations
        """
        # Build environment with constraints
        env = {
            "SESSION_DIR": str(workspace_path),  # Agent can only access this
            "DISABLE_NETWORK": "1",  # Network disabled
            "PATH": "/usr/local/bin:/usr/bin:/bin",  # Limited PATH
        }

        # Build agent invocation
        prompt = f"""
        User Question: {question}

        Search Context:
        {search_context}

        Please analyze the provided context and answer the user's question.
        Always cite specific code locations (file:line_number).
        """

        try:
            # Run agent in subprocess (cannot escape SESSION_DIR)
            result = await asyncio.to_thread(
                subprocess.run,
                ["claude", "agent", "research-analyst", "--prompt", prompt],
                cwd=str(workspace_path),
                env=env,
                timeout=timeout_seconds,
                capture_output=True,
                text=True,
            )

            if result.returncode != 0:
                logger.error(f"Agent failed: {result.stderr}")
                return {
                    "error": "Agent execution failed",
                    "answer": "",
                    "citations": [],
                }

            # Parse response and extract citations
            answer = result.stdout
            citations = AgentRunner._extract_citations(answer)

            return {
                "answer": answer,
                "citations": citations,
                "session_id": session_id,
            }

        except subprocess.TimeoutExpired:
            logger.error(f"Agent timeout after {timeout_seconds}s")
            return {
                "error": "Agent analysis timeout",
                "answer": "",
                "citations": [],
            }
        except Exception as e:
            logger.error(f"Agent execution failed: {e}")
            return {
                "error": str(e),
                "answer": "",
                "citations": [],
            }

    @staticmethod
    def _extract_citations(text: str) -> List[Dict]:
        """
        Extract code citations from agent response.

        Looks for patterns like:
        - [filename:line_number]
        - filename (lines X-Y)
        - path/to/file.py:42
        """
        citations = []

        # Pattern 1: [filename:line_number]
        pattern1 = r"\[([^:\]]+):(\d+)\]"
        for match in re.finditer(pattern1, text):
            citations.append({
                "file": match.group(1),
                "line": int(match.group(2)),
                "format": "bracket",
            })

        # Pattern 2: filename (lines X-Y)
        pattern2 = r"([^\s]+\.py)\s*\(lines?\s+(\d+)(?:-(\d+))?\)"
        for match in re.finditer(pattern2, text):
            citations.append({
                "file": match.group(1),
                "start_line": int(match.group(2)),
                "end_line": int(match.group(3)) if match.group(3) else int(match.group(2)),
                "format": "parentheses",
            })

        return citations
```

### Task 1.6.3: Create Analysis Endpoint (10-12 hours)

Create **research-mind-service/app/routes/analyze.py**:

```python
"""
Agent analysis endpoints.
"""

import logging
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session as DBSession

from app.services.agent_runner import AgentRunner
from app.services.session_service import SessionService
from app.schemas.analyze import AnalysisRequest, AnalysisResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/sessions", tags=["analysis"])


@router.post("/{session_id}/analyze", response_model=AnalysisResponse)
async def analyze(
    session_id: str,
    request: AnalysisRequest,
    db: DBSession = Depends(get_db),
):
    """
    Invoke agent to analyze search results.

    **Path Parameters**:
    - `session_id`: Session to analyze

    **Request Body**:
    - `question`: Research question
    - `agent`: Agent to use (default: research-analyst)

    **Returns**: Answer with citations

    **Status Codes**:
    - 200: Analysis complete
    - 404: Session not found
    - 503: Agent execution failed
    """
    # Verify session exists
    session = SessionService.get_session(db, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    try:
        # Get search context (for future integration)
        search_context = "Search results context here"  # Phase 2: get from cache

        # Run analysis
        result = await AgentRunner.run_analysis(
            session_id=session_id,
            workspace_path=session.workspace_path,
            question=request.question,
            search_context=search_context,
            timeout_seconds=300,  # 5 minutes
        )

        if "error" in result:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=result["error"],
            )

        return AnalysisResponse(**result)

    except Exception as e:
        logger.error(f"Analysis failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Analysis failed",
        )
```

---

## Research References

**docs/research/claude-ppm-capabilities.md** (Sections 3-5)

- Agent session management
- Custom agent definition format
- MCP integration patterns

**docs/research/claude-ppm-sandbox-containment-plan.md** (Section 1)

- Subprocess isolation constraints
- Environment variable approach to session scoping
- Network disabling strategy

---

## Acceptance Criteria

- [ ] research-analyst agent defined in ~/.claude/agents/
- [ ] Agent follows SESSION_DIR constraint
- [ ] POST /api/sessions/{id}/analyze endpoint working
- [ ] Agent returns answer with citations
- [ ] Session isolation enforced
- [ ] Network disabled (no external calls possible)
- [ ] Timeout handling working (5 min max)
- [ ] Citation extraction working

---

## Summary

**Phase 1.6** delivers:

- Custom research-analyst agent for code analysis
- Agent runner with subprocess isolation
- Analysis endpoint providing end-to-end research loop
- Foundation for Phase 1.7 integration testing

Complete the core research loop: Index → Search → Analyze

---

**Document Version**: 1.0
**Last Updated**: 2026-01-31
**Parent**: 01-PHASE_1_FOUNDATION.md
