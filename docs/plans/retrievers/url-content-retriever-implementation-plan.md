# URL Content Retriever Implementation Plan

**Created**: 2026-02-03
**Status**: Draft
**Scope**: Backend (research-mind-service)

---

## Executive Summary

This plan implements intelligent URL content extraction for the research-mind project. Instead of storing raw HTML, the URL retriever will scrape and extract clean, readable content using industry-standard libraries with multi-tier fallback strategies.

### Design Decisions (User Confirmed)

| Decision          | Choice                           | Rationale                                                     |
| ----------------- | -------------------------------- | ------------------------------------------------------------- |
| **JS Rendering**  | Include Playwright               | Full capability for SPAs, React sites, lazy-loaded content    |
| **Failure Mode**  | Fail content item (ERROR status) | Prevent garbage data, user can retry with different URL       |
| **Output Format** | Markdown                         | Preserves headings, lists, links; optimal for LLM consumption |
| **Metadata**      | Essential only                   | Title, URL, word count, extraction method, timestamp          |

---

## Architecture Overview

### Extraction Pipeline

```
UrlRetriever.retrieve()
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                    ExtractionPipeline                        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ 1. Fetch URL content (httpx async)                      │ │
│  │ 2. Detect content type (HTML/PDF/Other)                 │ │
│  │ 3. Route to appropriate extractor                       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                           │                                   │
│           ┌───────────────┴───────────────┐                  │
│           ▼                               ▼                   │
│  ┌─────────────────┐             ┌─────────────────┐         │
│  │  HTMLExtractor  │             │  (Future: PDF)  │         │
│  │                 │             │                 │         │
│  │ 1. trafilatura  │             │  Not in scope   │         │
│  │    (primary)    │             │                 │         │
│  │                 │             └─────────────────┘         │
│  │ 2. newspaper4k  │                                         │
│  │    (fallback)   │                                         │
│  │                 │                                         │
│  │ 3. JSExtractor  │                                         │
│  │    (if static   │                                         │
│  │     fails)      │                                         │
│  └─────────────────┘                                         │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
ExtractionResult {
  content: str (markdown)
  title: str
  word_count: int
  extraction_method: str
  extraction_time_ms: float
  warnings: list[str]
}
       │
       ▼
Write to sandbox:
  - content.md (extracted content)
  - metadata.json (extraction metadata)
```

### Module Structure

```
research-mind-service/
└── app/
    └── services/
        └── extractors/                    # NEW: Content extraction module
            ├── __init__.py                # Public exports
            ├── base.py                    # BaseExtractor, ExtractionResult, ExtractionConfig
            ├── exceptions.py              # Exception hierarchy
            ├── html_extractor.py          # trafilatura + newspaper4k
            ├── js_extractor.py            # Playwright rendering
            └── pipeline.py                # ExtractionPipeline orchestrator
        └── retrievers/
            └── url_retriever.py           # MODIFY: Integrate extraction pipeline
```

---

## Dependencies

### New Dependencies (pyproject.toml)

| Library       | Version | Purpose                  | License    |
| ------------- | ------- | ------------------------ | ---------- |
| `trafilatura` | ^1.12.0 | Primary HTML extraction  | Apache 2.0 |
| `newspaper4k` | ^0.9.0  | Fallback HTML extraction | Apache 2.0 |
| `playwright`  | ^1.45.0 | JavaScript rendering     | Apache 2.0 |

### Installation Notes

```bash
# Add to pyproject.toml dependencies
uv add trafilatura newspaper4k playwright

# Install Playwright browsers (one-time setup)
uv run playwright install chromium
```

**Note**: Playwright requires browser binaries. Document this in README and setup instructions.

---

## Phase 1: Core Extraction Module

**Goal**: Create extraction infrastructure with static HTML extraction (trafilatura + newspaper4k)

### 1.1 Create Exception Hierarchy

**File**: `app/services/extractors/exceptions.py`

```python
"""Exception hierarchy for content extraction."""

class ExtractionError(Exception):
    """Base exception for all extraction errors."""
    pass

class NetworkError(ExtractionError):
    """Raised for network-related failures (timeout, connection, DNS)."""
    pass

class ContentTypeError(ExtractionError):
    """Raised when content type cannot be detected or is unsupported."""
    pass

class EmptyContentError(ExtractionError):
    """Raised when extraction produces insufficient content."""
    pass

class RateLimitError(ExtractionError):
    """Raised when HTTP 429 is received."""
    pass

class ContentTooLargeError(ExtractionError):
    """Raised when content exceeds size limits."""
    pass
```

### 1.2 Create Base Classes

**File**: `app/services/extractors/base.py`

```python
"""Base classes for content extraction."""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol

@dataclass(frozen=True)
class ExtractionConfig:
    """Configuration for extraction pipeline."""
    timeout_seconds: int = 30
    max_retries: int = 3
    max_content_size_mb: int = 50
    min_content_length: int = 100  # Minimum chars for valid extraction
    retry_with_js: bool = True
    playwright_headless: bool = True
    user_agent: str = "research-mind/0.1 (content-extraction)"

@dataclass
class ExtractionResult:
    """Result of content extraction operation."""
    content: str                           # Extracted markdown content
    title: str                             # Document title
    word_count: int = 0                    # Auto-calculated
    extraction_method: str = ""            # Which extractor was used
    extraction_time_ms: float = 0.0        # Processing time
    warnings: list[str] = field(default_factory=list)

    def __post_init__(self):
        if self.word_count == 0:
            self.word_count = len(self.content.split())

class ContentExtractor(Protocol):
    """Protocol defining interface for content extractors."""

    def extract(self, html: str, url: str) -> ExtractionResult:
        """Extract content from HTML string.

        Args:
            html: Raw HTML content
            url: Source URL (for context, relative link resolution)

        Returns:
            ExtractionResult with extracted content

        Raises:
            EmptyContentError: If extraction produces insufficient content
        """
        ...
```

### 1.3 Implement HTML Extractor

**File**: `app/services/extractors/html_extractor.py`

```python
"""HTML content extractor using trafilatura with newspaper4k fallback."""

import logging
import time
from typing import Optional

import trafilatura
from newspaper import Article

from app.services.extractors.base import ExtractionConfig, ExtractionResult
from app.services.extractors.exceptions import EmptyContentError

logger = logging.getLogger(__name__)

class HTMLExtractor:
    """Extract readable content from HTML using multi-tier approach."""

    def __init__(self, config: ExtractionConfig | None = None):
        self.config = config or ExtractionConfig()

    def extract(self, html: str, url: str) -> ExtractionResult:
        """Extract content from HTML, trying trafilatura then newspaper4k."""
        start_time = time.perf_counter()
        warnings: list[str] = []

        # Try trafilatura first (primary)
        content = self._try_trafilatura(html, url)
        method = "trafilatura"

        # Fallback to newspaper4k if trafilatura fails or returns insufficient content
        if not content or len(content) < self.config.min_content_length:
            if content:
                warnings.append(f"trafilatura returned only {len(content)} chars, trying newspaper4k")
            content = self._try_newspaper4k(html, url)
            method = "newspaper4k"

        # Validate minimum content length
        if not content or len(content) < self.config.min_content_length:
            raise EmptyContentError(
                f"Extraction produced insufficient content: {len(content or '')} chars "
                f"(minimum: {self.config.min_content_length})"
            )

        # Extract title
        title = self._extract_title(html, url)

        elapsed_ms = (time.perf_counter() - start_time) * 1000

        return ExtractionResult(
            content=content,
            title=title,
            extraction_method=method,
            extraction_time_ms=elapsed_ms,
            warnings=warnings,
        )

    def _try_trafilatura(self, html: str, url: str) -> Optional[str]:
        """Extract using trafilatura with markdown output."""
        try:
            result = trafilatura.extract(
                html,
                url=url,
                output_format="markdown",
                include_links=True,
                include_images=False,
                include_tables=True,
                favor_precision=True,
            )
            return result
        except Exception as e:
            logger.warning(f"trafilatura extraction failed: {e}")
            return None

    def _try_newspaper4k(self, html: str, url: str) -> Optional[str]:
        """Extract using newspaper4k as fallback."""
        try:
            article = Article(url)
            article.set_html(html)
            article.parse()
            return article.text
        except Exception as e:
            logger.warning(f"newspaper4k extraction failed: {e}")
            return None

    def _extract_title(self, html: str, url: str) -> str:
        """Extract document title from HTML."""
        try:
            # Try trafilatura metadata
            metadata = trafilatura.extract_metadata(html)
            if metadata and metadata.title:
                return metadata.title
        except Exception:
            pass

        # Fallback: parse <title> tag
        import re
        match = re.search(r'<title[^>]*>([^<]+)</title>', html, re.IGNORECASE)
        if match:
            return match.group(1).strip()

        return url  # Last resort: use URL as title
```

### 1.4 Create Extraction Pipeline

**File**: `app/services/extractors/pipeline.py`

```python
"""Extraction pipeline orchestrating multiple extractors."""

import logging
import time
from typing import Optional

import httpx

from app.services.extractors.base import ExtractionConfig, ExtractionResult
from app.services.extractors.exceptions import (
    ContentTooLargeError,
    ContentTypeError,
    EmptyContentError,
    ExtractionError,
    NetworkError,
    RateLimitError,
)
from app.services.extractors.html_extractor import HTMLExtractor

logger = logging.getLogger(__name__)

class ExtractionPipeline:
    """Orchestrates content extraction from URLs."""

    def __init__(self, config: ExtractionConfig | None = None):
        self.config = config or ExtractionConfig()
        self.html_extractor = HTMLExtractor(self.config)
        self._js_extractor = None  # Lazy-loaded

    @property
    def js_extractor(self):
        """Lazy-load JS extractor to avoid Playwright import overhead."""
        if self._js_extractor is None:
            from app.services.extractors.js_extractor import JSExtractor
            self._js_extractor = JSExtractor(self.config)
        return self._js_extractor

    async def extract(self, url: str) -> ExtractionResult:
        """Extract content from URL with automatic fallback strategies."""
        # Fetch content
        html, content_type = await self._fetch_url(url)

        # Validate content type
        if not self._is_html(content_type):
            raise ContentTypeError(f"Unsupported content type: {content_type}")

        # Try static extraction first
        try:
            return self.html_extractor.extract(html, url)
        except EmptyContentError as e:
            if not self.config.retry_with_js:
                raise
            logger.info(f"Static extraction failed, trying JS rendering: {e}")

        # Fallback to JavaScript rendering
        return await self._extract_with_js(url)

    async def _fetch_url(self, url: str) -> tuple[str, str]:
        """Fetch URL content with error handling."""
        try:
            async with httpx.AsyncClient(
                timeout=self.config.timeout_seconds,
                follow_redirects=True,
            ) as client:
                response = await client.get(
                    url,
                    headers={"User-Agent": self.config.user_agent},
                )

                # Handle rate limiting
                if response.status_code == 429:
                    raise RateLimitError(f"Rate limited by {url}")

                response.raise_for_status()

                # Check content size
                content_length = len(response.content)
                max_bytes = self.config.max_content_size_mb * 1024 * 1024
                if content_length > max_bytes:
                    raise ContentTooLargeError(
                        f"Content size {content_length} exceeds maximum {max_bytes}"
                    )

                content_type = response.headers.get("content-type", "")
                return response.text, content_type

        except httpx.TimeoutException as e:
            raise NetworkError(f"Timeout fetching {url}: {e}") from e
        except httpx.RequestError as e:
            raise NetworkError(f"Network error fetching {url}: {e}") from e
        except httpx.HTTPStatusError as e:
            raise NetworkError(
                f"HTTP {e.response.status_code} from {url}: {e.response.reason_phrase}"
            ) from e

    async def _extract_with_js(self, url: str) -> ExtractionResult:
        """Extract content using JavaScript rendering."""
        html = await self.js_extractor.render(url)
        result = self.html_extractor.extract(html, url)
        result.extraction_method = f"playwright+{result.extraction_method}"
        return result

    def _is_html(self, content_type: str) -> bool:
        """Check if content type is HTML."""
        ct_lower = content_type.lower()
        return "text/html" in ct_lower or "application/xhtml" in ct_lower
```

### 1.5 Module Exports

**File**: `app/services/extractors/__init__.py`

```python
"""Content extraction module for URL content retrieval."""

from app.services.extractors.base import (
    ContentExtractor,
    ExtractionConfig,
    ExtractionResult,
)
from app.services.extractors.exceptions import (
    ContentTooLargeError,
    ContentTypeError,
    EmptyContentError,
    ExtractionError,
    NetworkError,
    RateLimitError,
)
from app.services.extractors.html_extractor import HTMLExtractor
from app.services.extractors.pipeline import ExtractionPipeline

__all__ = [
    # Base classes
    "ContentExtractor",
    "ExtractionConfig",
    "ExtractionResult",
    # Extractors
    "HTMLExtractor",
    "ExtractionPipeline",
    # Exceptions
    "ExtractionError",
    "NetworkError",
    "ContentTypeError",
    "EmptyContentError",
    "RateLimitError",
    "ContentTooLargeError",
]
```

### Phase 1 Deliverables

- [ ] `app/services/extractors/__init__.py`
- [ ] `app/services/extractors/base.py`
- [ ] `app/services/extractors/exceptions.py`
- [ ] `app/services/extractors/html_extractor.py`
- [ ] `app/services/extractors/pipeline.py`
- [ ] Dependencies added to `pyproject.toml`
- [ ] Unit tests for HTMLExtractor

---

## Phase 2: Playwright Integration

**Goal**: Add JavaScript rendering capability for SPAs and dynamic content

### 2.1 Implement JS Extractor

**File**: `app/services/extractors/js_extractor.py`

```python
"""JavaScript rendering extractor using Playwright."""

import asyncio
import logging
from typing import Optional

from playwright.async_api import async_playwright, Browser, Page

from app.services.extractors.base import ExtractionConfig
from app.services.extractors.exceptions import NetworkError

logger = logging.getLogger(__name__)

class JSExtractor:
    """Extract content by rendering JavaScript with Playwright."""

    def __init__(self, config: ExtractionConfig | None = None):
        self.config = config or ExtractionConfig()
        self._browser: Optional[Browser] = None
        self._playwright = None

    async def _ensure_browser(self) -> Browser:
        """Ensure browser is initialized (lazy initialization)."""
        if self._browser is None:
            self._playwright = await async_playwright().start()
            self._browser = await self._playwright.chromium.launch(
                headless=self.config.playwright_headless,
            )
        return self._browser

    async def render(self, url: str, wait_time_ms: int = 2000) -> str:
        """Render URL with JavaScript and return HTML.

        Args:
            url: URL to render
            wait_time_ms: Time to wait for JS execution (default: 2000ms)

        Returns:
            Rendered HTML content

        Raises:
            NetworkError: If page fails to load
        """
        browser = await self._ensure_browser()
        page: Optional[Page] = None

        try:
            page = await browser.new_page()

            # Set reasonable timeout
            page.set_default_timeout(self.config.timeout_seconds * 1000)

            # Navigate and wait for network idle
            response = await page.goto(url, wait_until="networkidle")

            if response is None or response.status >= 400:
                status = response.status if response else "unknown"
                raise NetworkError(f"Failed to load {url}: HTTP {status}")

            # Wait for additional JS execution
            await asyncio.sleep(wait_time_ms / 1000)

            # Get rendered HTML
            html = await page.content()
            return html

        except Exception as e:
            if isinstance(e, NetworkError):
                raise
            raise NetworkError(f"Playwright rendering failed for {url}: {e}") from e

        finally:
            if page:
                await page.close()

    async def close(self):
        """Close browser and cleanup resources."""
        if self._browser:
            await self._browser.close()
            self._browser = None
        if self._playwright:
            await self._playwright.stop()
            self._playwright = None
```

### 2.2 Add Browser Lifecycle Management

For production use, consider adding a context manager or singleton pattern for browser reuse:

```python
# Usage pattern in content_service.py or as application lifecycle
from contextlib import asynccontextmanager

@asynccontextmanager
async def extraction_context():
    """Managed extraction context with cleanup."""
    pipeline = ExtractionPipeline()
    try:
        yield pipeline
    finally:
        if pipeline._js_extractor:
            await pipeline.js_extractor.close()
```

### Phase 2 Deliverables

- [ ] `app/services/extractors/js_extractor.py`
- [ ] Playwright browser installation documented
- [ ] Integration tests with JS-heavy sites

---

## Phase 3: Update UrlRetriever

**Goal**: Integrate extraction pipeline into existing UrlRetriever

### 3.1 Update UrlRetriever Implementation

**File**: `app/services/retrievers/url_retriever.py` (MODIFY)

```python
"""Retriever for URL content with intelligent content extraction."""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from pathlib import Path

from app.core.config import settings
from app.services.extractors import (
    ExtractionConfig,
    ExtractionError,
    ExtractionPipeline,
)
from app.services.retrievers.base import RetrievalResult

logger = logging.getLogger(__name__)


class UrlRetriever:
    """Fetch URL content, extract readable content, store as markdown."""

    def __init__(
        self,
        timeout: int | None = None,
        retry_with_js: bool = True,
    ) -> None:
        self._config = ExtractionConfig(
            timeout_seconds=timeout if timeout is not None else settings.url_fetch_timeout,
            max_content_size_mb=settings.max_url_response_bytes // (1024 * 1024),
            retry_with_js=retry_with_js,
            min_content_length=100,
        )
        self._pipeline = ExtractionPipeline(self._config)

    def retrieve(
        self,
        *,
        source: str,
        target_dir: Path,
        title: str | None = None,
        metadata: dict | None = None,
    ) -> RetrievalResult:
        """Retrieve and extract content from URL.

        Args:
            source: URL to fetch
            target_dir: Directory to store extracted content
            title: Optional title override
            metadata: Optional additional metadata

        Returns:
            RetrievalResult with extraction details
        """
        url = source

        try:
            # Run async extraction in sync context
            result = asyncio.run(self._pipeline.extract(url))

            # Use provided title or extracted title
            resolved_title = title or result.title

            # Write extracted content as markdown
            content_file = target_dir / "content.md"
            content_file.write_text(result.content, encoding="utf-8")

            # Build metadata
            meta = {
                "url": url,
                "title": resolved_title,
                "word_count": result.word_count,
                "extraction_method": result.extraction_method,
                "extraction_time_ms": result.extraction_time_ms,
                "retrieved_at": datetime.now(timezone.utc).isoformat(),
                **(metadata or {}),
            }

            # Add warnings if any
            if result.warnings:
                meta["extraction_warnings"] = result.warnings

            # Write metadata
            meta_file = target_dir / "metadata.json"
            meta_file.write_text(json.dumps(meta, indent=2), encoding="utf-8")

            return RetrievalResult(
                success=True,
                storage_path=str(target_dir.name),
                size_bytes=len(result.content.encode("utf-8")),
                mime_type="text/markdown",
                title=resolved_title,
                metadata=meta,
            )

        except ExtractionError as e:
            logger.error(f"Content extraction failed for {url}: {e}")
            return RetrievalResult(
                success=False,
                storage_path=str(target_dir.name),
                size_bytes=0,
                mime_type=None,
                title=title or url,
                metadata={"url": url, "error_type": type(e).__name__},
                error_message=str(e),
            )

        except Exception as e:
            logger.exception(f"Unexpected error extracting {url}")
            return RetrievalResult(
                success=False,
                storage_path=str(target_dir.name),
                size_bytes=0,
                mime_type=None,
                title=title or url,
                metadata={"url": url, "error_type": "UnexpectedError"},
                error_message=f"Unexpected error: {e}",
            )
```

### 3.2 Update Configuration Settings

**File**: `app/core/config.py` (ADD)

```python
# Add to Settings class
class Settings(BaseSettings):
    # ... existing settings ...

    # URL Extraction settings
    url_extraction_retry_with_js: bool = True
    url_extraction_min_content_length: int = 100
    playwright_headless: bool = True
```

### Phase 3 Deliverables

- [ ] Updated `url_retriever.py` with extraction pipeline integration
- [ ] Updated `app/core/config.py` with extraction settings
- [ ] Integration tests for UrlRetriever with extraction

---

## Phase 4: Testing

**Goal**: Comprehensive test coverage for extraction and retrieval

### 4.1 Unit Tests for HTMLExtractor

**File**: `tests/services/extractors/test_html_extractor.py`

```python
"""Tests for HTML content extraction."""

import pytest
from app.services.extractors.html_extractor import HTMLExtractor
from app.services.extractors.exceptions import EmptyContentError

# Sample HTML fixtures
ARTICLE_HTML = """
<!DOCTYPE html>
<html>
<head><title>Test Article</title></head>
<body>
<article>
<h1>Main Heading</h1>
<p>This is a substantial article with enough content to pass the minimum length requirement.
It contains multiple sentences and paragraphs to ensure proper extraction testing.</p>
<p>Second paragraph with more content for thorough testing of the extraction pipeline.</p>
</article>
<nav>Navigation menu that should be ignored</nav>
</body>
</html>
"""

MINIMAL_HTML = """
<!DOCTYPE html>
<html><body><p>Short</p></body></html>
"""

class TestHTMLExtractor:
    def test_extract_article_content(self):
        extractor = HTMLExtractor()
        result = extractor.extract(ARTICLE_HTML, "https://example.com/article")

        assert result.content
        assert len(result.content) >= 100
        assert result.title == "Test Article"
        assert result.extraction_method in ("trafilatura", "newspaper4k")
        assert result.word_count > 0

    def test_extract_raises_on_minimal_content(self):
        extractor = HTMLExtractor()

        with pytest.raises(EmptyContentError):
            extractor.extract(MINIMAL_HTML, "https://example.com")

    def test_title_extraction(self):
        extractor = HTMLExtractor()
        result = extractor.extract(ARTICLE_HTML, "https://example.com/article")

        assert result.title == "Test Article"

    def test_fallback_to_newspaper4k(self):
        # Create HTML that trafilatura struggles with but newspaper4k handles
        complex_html = """
        <!DOCTYPE html>
        <html><head><title>Complex Page</title></head>
        <body><div class="content">{}</div></body>
        </html>
        """.format("Lorem ipsum dolor sit amet. " * 50)

        extractor = HTMLExtractor()
        result = extractor.extract(complex_html, "https://example.com")

        assert result.content
        # May use either extractor depending on content structure
```

### 4.2 Integration Tests for UrlRetriever

**File**: `tests/services/retrievers/test_url_retriever_integration.py`

```python
"""Integration tests for URL retriever with content extraction."""

import pytest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from app.services.retrievers.url_retriever import UrlRetriever

@pytest.fixture
def temp_dir(tmp_path):
    """Create temporary directory for content storage."""
    content_dir = tmp_path / "content"
    content_dir.mkdir()
    return content_dir

class TestUrlRetrieverIntegration:
    @pytest.mark.asyncio
    async def test_retrieve_real_url(self, temp_dir):
        """Test retrieval from a real, stable URL."""
        retriever = UrlRetriever(retry_with_js=False)

        result = retriever.retrieve(
            source="https://httpbin.org/html",
            target_dir=temp_dir,
        )

        assert result.success
        assert result.size_bytes > 0
        assert result.mime_type == "text/markdown"

        # Verify files created
        content_file = temp_dir / "content.md"
        assert content_file.exists()

        metadata_file = temp_dir / "metadata.json"
        assert metadata_file.exists()

    def test_retrieve_handles_network_error(self, temp_dir):
        """Test graceful handling of network errors."""
        retriever = UrlRetriever()

        result = retriever.retrieve(
            source="https://nonexistent.invalid/page",
            target_dir=temp_dir,
        )

        assert not result.success
        assert result.error_message
        assert "error_type" in result.metadata

    def test_retrieve_handles_empty_content(self, temp_dir):
        """Test handling of pages with insufficient content."""
        retriever = UrlRetriever(retry_with_js=False)

        # Mock a page that returns minimal content
        with patch.object(
            retriever._pipeline,
            'extract',
            side_effect=Exception("Empty content")
        ):
            result = retriever.retrieve(
                source="https://example.com/empty",
                target_dir=temp_dir,
            )

        assert not result.success
```

### 4.3 Test URLs for Manual Verification

Document test URLs for different scenarios:

| Scenario        | Test URL                 | Expected Behavior                    |
| --------------- | ------------------------ | ------------------------------------ |
| Simple article  | https://httpbin.org/html | Extract with trafilatura             |
| News article    | https://www.bbc.com/news | Extract with trafilatura/newspaper4k |
| SPA (React)     | (find stable example)    | Require Playwright                   |
| Minimal content | https://example.com      | May fail content length check        |
| Rate limited    | (simulate 429)           | Raise RateLimitError                 |

### Phase 4 Deliverables

- [ ] `tests/services/extractors/test_html_extractor.py`
- [ ] `tests/services/extractors/test_pipeline.py`
- [ ] `tests/services/extractors/test_js_extractor.py`
- [ ] `tests/services/retrievers/test_url_retriever_integration.py`
- [ ] All tests passing

---

## Phase 5: Documentation & Cleanup

**Goal**: Update documentation and finalize implementation

### 5.1 Update README

Add to `research-mind-service/README.md`:

````markdown
## URL Content Extraction

The service extracts readable content from URLs using a multi-tier approach:

1. **trafilatura** (primary) - Fast, accurate article extraction
2. **newspaper4k** (fallback) - Alternative extraction for complex pages
3. **Playwright** (JS rendering) - For SPAs and JavaScript-heavy sites

### Setup

```bash
# Install dependencies
uv sync

# Install Playwright browsers (required for JS rendering)
uv run playwright install chromium
```
````

### Configuration

| Setting                             | Default | Description                                 |
| ----------------------------------- | ------- | ------------------------------------------- |
| `url_fetch_timeout`                 | 30      | HTTP request timeout in seconds             |
| `url_extraction_retry_with_js`      | true    | Retry with Playwright on extraction failure |
| `url_extraction_min_content_length` | 100     | Minimum characters for valid extraction     |
| `playwright_headless`               | true    | Run browser in headless mode                |

````

### 5.2 Update CLAUDE.md

Document the extraction module in service CLAUDE.md for future development reference.

### 5.3 Verify TextRetriever

The TextRetriever should continue to work as-is (stores raw text). Verify no changes needed:

```python
# app/services/retrievers/text_retriever.py
# Should remain unchanged - stores raw text content as content.txt
````

### Phase 5 Deliverables

- [ ] README updated with extraction documentation
- [ ] CLAUDE.md updated with module structure
- [ ] TextRetriever verified (no changes needed)
- [ ] Final code review

---

## Implementation Checklist

### Phase 1: Core Extraction Module

- [ ] Create `app/services/extractors/` directory
- [ ] Implement `exceptions.py`
- [ ] Implement `base.py` with ExtractionConfig and ExtractionResult
- [ ] Implement `html_extractor.py` with trafilatura + newspaper4k
- [ ] Implement `pipeline.py` (static extraction only)
- [ ] Create `__init__.py` exports
- [ ] Add trafilatura and newspaper4k to pyproject.toml
- [ ] Write unit tests for HTMLExtractor

### Phase 2: Playwright Integration

- [ ] Implement `js_extractor.py`
- [ ] Add playwright to pyproject.toml
- [ ] Document browser installation steps
- [ ] Update pipeline.py to use JSExtractor
- [ ] Write tests for JS extraction

### Phase 3: Update UrlRetriever

- [ ] Refactor `url_retriever.py` to use ExtractionPipeline
- [ ] Update `app/core/config.py` with extraction settings
- [ ] Write integration tests
- [ ] Verify backward compatibility (same RetrievalResult interface)

### Phase 4: Testing

- [ ] Unit tests for all extractors
- [ ] Integration tests for UrlRetriever
- [ ] Manual testing with various URL types
- [ ] CI/CD pipeline updates (Playwright browser install)

### Phase 5: Documentation

- [ ] Update README with extraction documentation
- [ ] Update CLAUDE.md with new module structure
- [ ] Verify TextRetriever unchanged
- [ ] Final code review and cleanup

---

## Risk Assessment

| Risk                                     | Mitigation                                      |
| ---------------------------------------- | ----------------------------------------------- |
| Playwright browser installation in CI/CD | Document installation steps, add to CI config   |
| Some sites block automated requests      | Use realistic User-Agent, implement retry logic |
| Rate limiting from aggressive scraping   | Implement backoff, respect robots.txt (future)  |
| Memory usage with Playwright             | Lazy-load browser, close pages after use        |
| Content quality varies by site           | Multi-tier extraction, fail gracefully          |

---

## Future Enhancements (Out of Scope)

1. **PDF Extraction** - Add pymupdf4llm for PDF content
2. **Robots.txt Compliance** - Respect crawl rules
3. **Caching** - Cache extracted content for repeated URLs
4. **Async Retriever** - Make retriever fully async
5. **Content Deduplication** - Detect duplicate content across URLs
6. **Rate Limiting** - Implement per-domain rate limits

---

## Timeline Estimate

| Phase                        | Effort    | Dependencies  |
| ---------------------------- | --------- | ------------- |
| Phase 1: Core Extraction     | 3-4 hours | None          |
| Phase 2: Playwright          | 2-3 hours | Phase 1       |
| Phase 3: UrlRetriever Update | 2-3 hours | Phase 1, 2    |
| Phase 4: Testing             | 2-3 hours | Phase 1, 2, 3 |
| Phase 5: Documentation       | 1 hour    | All phases    |

**Total Estimated Effort**: 10-14 hours

---

_Plan created by Claude Code PM Agent_
_Based on research-mind architecture analysis and user requirements_
