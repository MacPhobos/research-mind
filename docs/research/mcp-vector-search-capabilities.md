# MCP Vector Search: Capabilities & Architecture

**Document Version**: 1.1
**Date**: 2026-01-31
**Status**: Research Complete - No changes needed

## Executive Summary

MCP Vector Search is a production-ready semantic code search system built on ChromaDB vector database and Sentence Transformers embeddings. The architecture is **single-project focused** with limited multi-collection support, requiring significant extension for Research-Mind's multi-session isolation requirements.

Key strengths: CLI-first design, 8 language parsers, connection pooling, automatic reindexing strategies.
Key gaps: No session scoping, no REST API, no job-based async indexing, per-directory index isolation not implemented.

---

## 1. Current Architecture Overview

### 1.1 High-Level System Design

```
MCP Vector Search Architecture
┌─────────────────────────────────────────────────────────────┐
│                          CLI Interface                       │
│  (/src/mcp_vector_search/cli/main.py - typer + rich)       │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┬──────────────┐
        │              │              │              │
    [index]       [search]        [watch]        [status]
        │              │              │              │
└───────┴──────────────┴──────────────┴──────────────┘
         │
    ┌────▼─────────────────────────────────────────┐
    │         Project Manager                       │
    │ (/src/mcp_vector_search/core/project.py)    │
    └────┬─────────────────────────────────────────┘
         │
    ┌────▼─────────────────────────────────────────┐
    │  Semantic Indexer + Search Engine             │
    │  (core/indexer.py + core/search.py)          │
    │  - File Discovery                            │
    │  - Parser Registry (8 languages)             │
    │  - Chunk Processing                          │
    │  - Query Processing                          │
    └────┬─────────────────────────────────────────┘
         │
    ┌────▼──────────────────────────────────────────┐
    │  Vector Database (ChromaDB)                    │
    │  (core/database.py)                            │
    │  - Connection Pooling                         │
    │  - Collection Manager                         │
    │  - HNSW Search Index                          │
    └────┬──────────────────────────────────────────┘
         │
    ┌────▼──────────────────────────────────────────┐
    │  Persistent Storage                            │
    │  .mcp-vector-search/                          │
    │  ├── chroma.sqlite3 (vector DB)              │
    │  ├── config.json                             │
    │  ├── index_metadata.json                     │
    │  └── relationships.db                        │
    └───────────────────────────────────────────────┘
```

### 1.2 Project Layout

```
.mcp-vector-search/                    # Index storage (project root)
├── chroma.sqlite3                     # ChromaDB SQLite database
├── chroma.sqlite3-journal             # SQLite WAL files
├── chroma.sqlite3-wal
├── chroma.sqlite3-shm
├── config.json                        # Project configuration
├── index_metadata.json                # Indexing metadata
└── relationships.db                   # Semantic relationships (SQLite)
```

**Config format** (`config.json`):

```json
{
  "project_root": "/path/to/project",
  "file_extensions": [".py", ".js", ".ts"],
  "embedding_model": "sentence-transformers/all-MiniLM-L6-v2",
  "similarity_threshold": 0.75,
  "languages": ["python", "javascript", "typescript"],
  "watch_files": true,
  "cache_embeddings": true,
  "skip_dotfiles": true,
  "respect_gitignore": true
}
```

---

## 2. Indexing Architecture

### 2.1 Indexing Flow

**Entry Point**: `/src/mcp_vector_search/cli/commands/index.py`

```
User Command: mcp-vector-search index
│
├─→ ProjectManager.load_config()
│   └─→ Loads .mcp-vector-search/config.json
│
├─→ FileDiscovery.discover_files()
│   └─→ /src/mcp_vector_search/core/file_discovery.py
│       Walks directory tree respecting .gitignore, dotfiles rules
│       Returns: List[Path]
│
├─→ SemanticIndexer.index_directory()
│   ├─→ /src/mcp_vector_search/core/indexer.py (line 100+)
│   ├─→ Supports parallel indexing with multiprocessing
│   │
│   └─→ For each file:
│       ├─→ ParserRegistry.get_parser(file_extension)
│       │   └─→ /src/mcp_vector_search/parsers/registry.py
│       │       Returns language-specific parser
│       │
│       ├─→ Parser.parse(file_content)
│       │   ├─→ /src/mcp_vector_search/parsers/*.py
│       │   │   (python.py, javascript.py, typescript.py, etc.)
│       │   └─→ Returns: List[CodeChunk]
│       │
│       ├─→ ChunkProcessor.process_chunks()
│       │   └─→ /src/mcp_vector_search/core/chunk_processor.py
│       │       Adds metadata, handles relationships
│       │
│       └─→ EmbeddingFunction.embed(chunk_text)
│           └─→ /src/mcp_vector_search/core/embeddings.py
│               Uses SentenceTransformer model
│
├─→ VectorDatabase.add_chunks(chunks_with_embeddings)
│   └─→ /src/mcp_vector_search/core/database.py
│       ├─→ ChromaVectorDatabase
│       ├─→ CollectionManager.get_or_create_collection()
│       └─→ Insert into ChromaDB with metadata
│
└─→ IndexMetadata.update()
    └─→ /src/mcp_vector_search/core/index_metadata.py
        Records last indexed time, file hashes
```

### 2.2 Data Model (CodeChunk)

**Location**: `/src/mcp_vector_search/core/models.py`

```python
class CodeChunk(BaseModel):
    """Represents a parsed code segment for indexing."""
    id: str                    # Unique identifier (hash-based)
    content: str               # Code text (50-500 tokens typically)
    file_path: Path           # Source file
    start_line: int           # Source location
    end_line: int
    language: str             # Programming language
    chunk_type: str           # "function", "class", "method", etc.
    parent: str | None        # Parent container name
    docstring: str | None     # Documentation string
    metadata: dict[str, Any]  # Custom metadata
```

### 2.3 Parser Implementation

**Location**: `/src/mcp_vector_search/parsers/`

Supported languages (8 total):

- Python (AST + regex fallback)
- JavaScript/TypeScript (Tree-sitter + regex)
- Dart (AST + regex)
- PHP (Tree-sitter + regex)
- Ruby (Tree-sitter + regex)
- HTML (Semantic extraction)
- Markdown (Heading hierarchy)
- Text (Paragraph chunking)

**Python Parser Example** (`parsers/python.py`):

```python
class PythonParser(BaseParser):
    def parse(self, content: str, file_path: Path) -> List[CodeChunk]:
        # Uses AST parsing for functions, classes, methods
        # Extracts docstrings automatically
        # Falls back to regex for edge cases
        # Returns chunks with structural metadata
```

### 2.4 Chunking Strategy

Implemented in `/src/mcp_vector_search/core/chunk_processor.py`:

- **Function/Class Level**: One chunk per function/class definition
- **Size Limits**: Chunks 50-500 tokens (approximately 200-2000 chars)
- **Context Preservation**: Docstrings, type hints included
- **Hierarchy Tracking**: Parent class/module information stored
- **Deduplication**: Hash-based to prevent duplicates

**Metadata stored with chunks**:

```python
{
    "file_path": "/path/to/file.py",
    "language": "python",
    "chunk_type": "function",
    "parent": "ClassName",
    "start_line": 42,
    "end_line": 67,
    "docstring": "Function description",
    "complexity": 3,
    "has_tests": False
}
```

---

## 3. Search Architecture

### 3.1 Search Flow

**Entry Point**: `/src/mcp_vector_search/cli/commands/search.py`

```
User Command: mcp-vector-search search "authentication logic"
│
├─→ SemanticSearchEngine.search()
│   └─→ /src/mcp_vector_search/core/search.py
│
├─→ QueryProcessor.process_query(query)
│   ├─→ /src/mcp_vector_search/core/query_processor.py
│   ├─→ Text normalization
│   └─→ Threshold calculation
│
├─→ EmbeddingFunction.embed(query)
│   └─→ /src/mcp_vector_search/core/embeddings.py
│       Uses same model as indexing (typically all-MiniLM-L6-v2)
│
├─→ VectorDatabase.search()
│   ├─→ /src/mcp_vector_search/core/database.py
│   └─→ ChromaDB HNSW search
│       query_vector (384-dim for all-MiniLM)
│       limit: top-k results
│       similarity_threshold: 0.7 (default, configurable)
│
├─→ ResultEnhancer.enhance_results()
│   ├─→ /src/mcp_vector_search/core/result_enhancer.py
│   ├─→ Loads context from source files
│   ├─→ Caches results
│   └─→ Adds surrounding code for context
│
├─→ ResultRanker.rank_results()
│   ├─→ /src/mcp_vector_search/core/result_ranker.py
│   ├─→ Reranking by relevance score
│   └─→ Deduplication of similar results
│
└─→ Return SearchResult list
    └─→ /src/mcp_vector_search/core/models.py
        Each result includes:
        - File path + location
        - Similarity score
        - Code snippet
        - Context lines
```

### 3.2 Search Parameters

Available filters: None currently implemented in production code
Similarity threshold: Configurable (default 0.7)
Limit: Top-k results (default 10)

**IMPORTANT**: Filters are mentioned in abstract interface (`database.py` line 61-77) but not currently used by search handlers.

### 3.3 Similarity Search Mechanism

**Location**: ChromaDB HNSW (Hierarchical Navigable Small World)

```
Configuration (CollectionManager, core/collection_manager.py):
┌────────────────────────────────────────────────┐
│ HNSW Parameters (Tuned for Code Search)        │
├────────────────────────────────────────────────┤
│ Space:              cosine (semantic distance) │
│ M:                  32 (connections/node)      │
│ ef_construction:    400 (build quality)        │
│ ef_search:          75 (search quality)        │
│ distance_metric:    cosine                     │
└────────────────────────────────────────────────┘

Embedding Model: sentence-transformers/all-MiniLM-L6-v2
- Output dimension: 384
- Training: MSMarco dataset (semantic search optimized)
- Inference: ~50ms for typical query
```

---

## 4. Vector Database Implementation

### 4.1 ChromaDB Integration

**Location**: `/src/mcp_vector_search/core/database.py`

```python
class ChromaVectorDatabase(VectorDatabase):
    """ChromaDB implementation with connection pooling & corruption recovery."""

    def __init__(self, persist_directory: Path, embedding_function):
        self.persist_directory = persist_directory
        self.embedding_function = embedding_function
        self.connection_pool = ChromaConnectionPool(...)  # Line 150+
        self.collection_manager = CollectionManager(...)
        self.corruption_recovery = CorruptionRecovery(...)
```

**Key Components**:

1. **Connection Pooling** (`core/connection_pool.py`):

   - Min connections: 2
   - Max connections: 10
   - Max idle time: 300s
   - Performance gain: 13.6% for high-throughput scenarios

2. **Collection Manager** (`core/collection_manager.py`):

   - Single collection per project: `"code_search"`
   - Lazily created on first use
   - HNSW parameters tuned for code search

3. **Corruption Recovery** (`core/corruption_recovery.py`):

   - Automatic SQLite lock cleanup on startup
   - Detects stale journal files (-journal, -wal, -shm)
   - Rebuilds corrupted indices

4. **Statistics Collector** (`core/statistics_collector.py`):
   - Tracks index size (document count, chunk count)
   - Last indexed time
   - Embedding model used
   - Collection health metrics

### 4.2 Data Storage

**Location on disk**: `.mcp-vector-search/chroma.sqlite3`

```sql
-- ChromaDB uses SQLite with custom schema
-- Stores:
-- - Embeddings (384-dim vectors for all-MiniLM)
-- - Document metadata
-- - Collection structure
-- - HNSW graph for similarity search
```

### 4.3 Metadata Representation

**For chunking queries**: Metadata columns in ChromaDB

```python
metadata_dict = {
    "file_path": str(chunk.file_path),
    "language": chunk.language,
    "chunk_type": chunk.chunk_type,
    "start_line": chunk.start_line,
    "end_line": chunk.end_line,
    "parent": chunk.parent or "",
    "docstring_present": bool(chunk.docstring),
    "complexity": chunk.complexity_score,
}
```

**Metadata limitations**:

- No hierarchical filtering (can't query "functions inside ClassA")
- No range queries on line numbers
- Text search in metadata is limited

---

## 5. Key Modules & File Paths

### 5.1 Core Module Map

| Module               | Path                         | Lines   | Purpose                                           |
| -------------------- | ---------------------------- | ------- | ------------------------------------------------- |
| SemanticIndexer      | `core/indexer.py`            | 61-400+ | Parse files, generate chunks, coordinate indexing |
| SemanticSearchEngine | `core/search.py`             | 22-200+ | Query processing, search coordination             |
| FileDiscovery        | `core/file_discovery.py`     | -       | Walk directory, respect .gitignore                |
| ParserRegistry       | `parsers/registry.py`        | -       | Dispatch to language-specific parsers             |
| ChromaVectorDatabase | `core/database.py`           | 35+     | ChromaDB wrapper, pooling, recovery               |
| CollectionManager    | `core/collection_manager.py` | 9+      | Collection lifecycle, HNSW config                 |
| ChunkProcessor       | `core/chunk_processor.py`    | -       | Metadata handling, relationships                  |
| EmbeddingFunction    | `core/embeddings.py`         | -       | SentenceTransformer wrapper                       |
| ResultEnhancer       | `core/result_enhancer.py`    | -       | Add context, caching                              |
| ResultRanker         | `core/result_ranker.py`      | -       | Reranking, deduplication                          |

### 5.2 MCP Integration Points

**Location**: `/src/mcp_vector_search/mcp/`

- `server.py` (MCPVectorSearchServer): Main MCP server class
- `tool_schemas.py`: Pydantic schemas for MCP tools
- `search_handlers.py`: Search-specific tool implementations
- `project_handlers.py`: Project management tools
- `analysis_handlers.py`: Code analysis tools

**Current Tools** (MCP interface):

```
Available tools (from tool_schemas.py):
- search_code: Semantic search
- index_project: Trigger indexing
- get_project_status: Stats
- [other tools as defined]
```

---

## 6. Extension Points for REST API

### 6.1 Entry Points for Integration

**Ideal Integration Architecture**: Wrapper service that imports mcp-vector-search as a library

```
┌─────────────────────────────────────────┐
│   FastAPI REST Service (NEW)            │
│   (research-mind-service)               │
├─────────────────────────────────────────┤
│   - Session routing                     │
│   - Job queue management                │
│   - Audit logging                       │
└─────────────┬───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│  MCP Vector Search Library              │
│  (imported as mcp_vector_search)        │
├─────────────────────────────────────────┤
│  - SemanticIndexer                      │
│  - SemanticSearchEngine                 │
│  - ChromaVectorDatabase                 │
└─────────────────────────────────────────┘
```

### 6.2 Recommended Extension Points

1. **Indexing Entry Point** (`SemanticIndexer`):

   - Currently: Single project, single collection
   - **For REST**: Create session-scoped indexer instance per session
   - Needed: Session parameter in **init**, collection_name parameterization

2. **Search Entry Point** (`SemanticSearchEngine`):

   - Currently: Auto-reindexing triggered from search
   - **For REST**: Disable auto-reindex, make explicit job-based
   - Needed: SearchEngine without auto-indexing mode

3. **Project Manager** (`ProjectManager`):

   - Currently: Loads from `.mcp-vector-search/config.json`
   - **For REST**: Load from session-specific config directory
   - Needed: Config path parameterization

4. **Collection Management**:

   - **PROBLEM**: Single collection per project hardcoded
   - **Solution**: Parameterize collection_name in CollectionManager
   - **Code change required**:
     ```python
     # core/collection_manager.py line 16-22
     def __init__(self, collection_name: str = "code_search") -> None:  # ✓ Already parameterized!
     ```
   - ✓ **Good news**: Already supports multiple collection names

5. **Connection Pool**:
   - ✓ **Already abstracted**: `ChromaConnectionPool`
   - Can create separate pool per session if needed

### 6.3 Multi-Session / Multi-Collection Strategy

**Recommended approach**: Per-session collections in shared ChromaDB

```
Single ChromaDB instance:
.mcp-vector-search/chroma.sqlite3
├── Collection: "session_abc123"
├── Collection: "session_def456"
├── Collection: "session_ghi789"
└── [Shared embeddings model]
```

**Implementation path**:

1. Parameterize collection_name throughout system ✓ (already done in CollectionManager)
2. Create wrapper that manages session→collection mapping
3. Store session metadata separately (in research-mind-service DB)

---

## 7. Operational Characteristics

### 7.1 Indexing Performance

**Typical benchmarks** (from README):

- Speed: ~1000 files/minute on typical Python project
- Depends on: file count, average chunk count per file, embedding model
- Parallelization: Multiprocessing enabled by default (line 74 in indexer.py)

**Embedding Generation**:

- Model: all-MiniLM-L6-v2 (lightweight)
- Latency: ~50ms per chunk
- Batch processing: Supported in ChunkProcessor
- Memory: ~1MB baseline + ~1MB per 1000 chunks

### 7.2 Search Performance

**Typical latency**: <100ms for most queries (from README)

**Latency components**:

1. Query embedding: ~50ms (same model as indexed)
2. Vector search (HNSW): ~10-30ms (depends on db size, ef_search parameter)
3. Result enhancement: ~20-50ms (reading source files, caching helps)
4. Ranking/dedup: <5ms

### 7.3 Storage Footprint

**Typical sizes** (from README):

- SQLite DB: ~1KB per chunk (compressed embeddings)
- Relationships DB: Negligible
- Config files: <1KB

**Example**:

- 5000 chunks (~50K LOC codebase)
- Storage: ~5MB + source file refs
- Memory: ~50MB during search

### 7.4 Caching & Optimization

**Implemented** (`core/result_enhancer.py`):

- Result context caching (avoids re-reading files)
- Hash-based deduplication in ranking
- Connection pooling (13.6% improvement)

**Not implemented**:

- Query result caching (no TTL concept)
- Incremental indexing (full reindex on changes)

### 7.5 Auto-Reindexing Strategies

**Location**: `/src/mcp_vector_search/core/auto_indexer.py`

Available strategies:

1. **Search-Triggered**: Check for stale files during search
2. **Git Hooks**: Post-commit, post-merge hooks
3. **Scheduled Tasks**: Cron/Windows tasks
4. **Manual Check**: Via CLI command

**For Research-Mind**: Disable auto-reindex, use explicit job model

---

## 8. Risks & Unknowns

### 8.1 Critical Gaps for Research-Mind

| Gap                      | Impact                          | Mitigation                         |
| ------------------------ | ------------------------------- | ---------------------------------- |
| No session scoping       | Multi-tenant mixing             | Create per-session collections     |
| No job queuing           | Blocking indexing               | Add async job model in wrapper     |
| No request isolation     | Shared embedding model          | Thread-safe, but consider batching |
| Single collection        | Per-project only                | Already parameterizable            |
| Limited metadata filters | Can't filter by type/complexity | Implement post-search filtering    |
| No audit logging         | No search query history         | Add logging in wrapper             |

### 8.2 Architecture Unknowns

**Q1**: How does ChromaDB handle concurrent writes to same collection?

- **Risk**: Potential lock contention with multiple indexing jobs
- **Investigation needed**: ChromaDB SQLite lock behavior

**Q2**: Can we safely share embedding model across sessions?

- **Risk**: Model loading overhead if per-session
- **Investigation needed**: Sentence Transformer memory/latency characteristics

**Q3**: How to handle index corruption in multi-session environment?

- **Risk**: One session's index corruption affects others
- **Current mitigation**: Corruption recovery per collection (good)
- **Recommended**: Separate SQLite files per session (not shared)

### 8.3 Known Limitations

1. **No REST API**: All access currently through CLI or MCP tools
2. **Single embedding model**: Can't mix models per session
3. **No hybrid search**: Vector-only, no BM25 fallback
4. **Limited reranking**: Basic similarity-only ranking
5. **No TTL/pruning**: No automatic cleanup of old chunks
6. **No deduplication across sessions**: Identical code indexed multiple times

---

## 9. Recommended Architecture for Research-Mind Integration

### 9.1 Session-Scoped Indexing

```python
# Pseudo-code for wrapper
class SessionIndexer:
    def __init__(self, session_id: str, session_root: Path):
        self.session_id = session_id
        self.collection_name = f"session_{session_id}"

        # Create session-scoped config
        config = ProjectConfig.for_session(session_root)

        # Create indexer with session collection
        self.database = ChromaVectorDatabase(
            persist_directory=config.index_path,
            embedding_function=embedding_fn
        )
        self.indexer = SemanticIndexer(
            database=self.database,
            project_root=session_root,
            config=config
        )
```

### 9.2 Job-Based Indexing

```python
# Async job model
class IndexingJob:
    job_id: str
    session_id: str
    status: Literal["pending", "running", "completed", "failed"]
    progress: float  # 0.0-1.0
    indexed_files: int
    total_files: int
    error: str | None
    started_at: datetime
    completed_at: datetime | None
```

### 9.3 Multi-Session Collection Strategy

Use per-session collections, shared embedding model:

```
.mcp-vector-search/
├── chroma.sqlite3
│   ├── Collection: "session_abc123"
│   ├── Collection: "session_def456"
│   ├── Collection: "session_ghi789"
│   └── [embeddings shared]
└── sessions/
    ├── abc123/.mcp-vector-search/
    │   ├── config.json
    │   └── index_metadata.json
    ├── def456/.mcp-vector-search/
    └── ghi789/.mcp-vector-search/
```

---

## 10. Summary Table

| Aspect               | Current State       | For Research-Mind        |
| -------------------- | ------------------- | ------------------------ |
| **Entry Points**     | CLI + MCP           | REST API (wrapper)       |
| **Scoping**          | Single project      | Per-session collections  |
| **Indexing**         | Synchronous CLI     | Async job model          |
| **Multi-tenancy**    | Not supported       | Session-scoped isolation |
| **API**              | MCP tools only      | FastAPI endpoints        |
| **Job model**        | None                | Queue + job tracking     |
| **Audit logging**    | Limited             | Required (in wrapper)    |
| **Metadata filters** | Incomplete          | Enhanced via wrapper     |
| **Storage**          | .mcp-vector-search/ | Session directories      |

---

## References

### Code Locations

- Main indexer: `/Users/mac/workspace/research-mind/mcp-vector-search/src/mcp_vector_search/core/indexer.py`
- Search engine: `/Users/mac/workspace/research-mind/mcp-vector-search/src/mcp_vector_search/core/search.py`
- Database: `/Users/mac/workspace/research-mind/mcp-vector-search/src/mcp_vector_search/core/database.py`
- Parsers: `/Users/mac/workspace/research-mind/mcp-vector-search/src/mcp_vector_search/parsers/`
- MCP server: `/Users/mac/workspace/research-mind/mcp-vector-search/src/mcp_vector_search/mcp/server.py`

### Documentation

- Architecture doc: `/Users/mac/workspace/research-mind/mcp-vector-search/docs/reference/architecture.md`
- README: `/Users/mac/workspace/research-mind/mcp-vector-search/README.md`
