# Purpose

Understanding of new topic areas related to internal products and systems is time consuming. It usually involves finding and reading through a lot of material present in different sources of truth. This wastes a lot of time while perhaps not providing a cohesive and summarized picture.

# Usecase

“I want to know what Project X or Team Y does, by asking specific questions related to available material.”

Available material (content entities) might be:
Wiki articles (scraped)
Wiki articles (mcp)
Google docs
PDF/Word/etc docs
GIT repos
Meeting transcripts

# Problem

Finding context related to a research “activity” (session) typically requires asking stakeholders to supply some links to documentation, git repos etc. This by itself is OK, it provides a useful starting point and also a good idea of how well a topic area is structured in terms of documentation.

The shotgun approach of indexing, MCP’ing and LLM collating through ALL material is not ideal. It often results in diluted or sometimes outright incorrect results due to context that is too broad, semantically related but not relevant.

# Approach

A concept of a “research session” allows the user to create a content sandbox composed of a number of content entities. These are pulled in into the sandbox directory (named using research session id) using various methods:
Web page scraping
MCP
Plaintext pastes
PDF/etc doc uploads
GIT clones
These are handled by the Research-Mind and stored in the session sandbox directory (think in terms of content entity per subdirectory).

Use a combination of:
“Research-Mind” UI/Service that provides and keeps track of a concept of a research session.
mcp-vector-search + REST API
claude-mpm + specific set of agents and skills + use of mcp-vector-search

## research-mind

A monorepo consisting of discrete research-mind-ui and research-mind-service git projects.

### research-mind-ui

The UI provides:
Session CRUD
Ability to add in content entities related to a session
Chat interface to ask questions
Ability to have admin like actions
Trigger reindexing
Model choices
etc

### research-mind-service

This is a backend service used by the research-mind-ui which provides:
Session, Admin, etc CRUD
Content retrieval mechanisms for each type of content entities
Storage of retrieved content into session sandbox directory
Usage of mcp-vector-search to trigger indexing of sandbox directory contents, using a mcp-vector-search REST API (tbd)

## mcp-vector-search

mcp-vector-search provides an indexing layer. The vast majority of functionality is already in place. Some could be enhanced further and would benefit the common MCP use case path as well.

The main idea here is to run mcp-vector-search on the sandbox directory. This will cause indexing of all the sandboxes content.

Required additions would be:
A REST API that exposes some basic functionality like:
Trigger indexing / re-indexing
Code complexity hints

## claude-mpm

This is where all the gold is buried. It’s a combination of:
mcp-vector-search indexed on sandboxed content
User has provided relevant content scope (sandbox data) resulting in an indexed data set that is relevant to session queries.
claude-mpm acting on available data
uses mcp-vector-search MCP → narrow down search query
uses sandbox content (raw files) → expand on search query
uses a specific set of agents and skills customized for “research-mind” use case.

The main idea here is to have the chat interface provided by research-mind UI (for a session) to:
Use claude-mpm to answer questions, leveraging a combo of vector search mcp and filesystem content.

# Concept Problems

The whole “stack” takes time to spin up in multi-user scenarios
mcp-vector-search indexing wait time
claude-mpm launch wait time
Storage aspects → cost → pruning maintenance
Anthropic cost

# Approach Comparisons

## Approach A: Indexing + Embedding + RAG + LLM

This is a typical Index/Embed/RAG → feed to LLM to answer a question type of a scenario. It works pretty well when the LLM is provided the right context. Context quality is what makes the critical difference. This approach is deficient in capability compared to Approach B.

## Approach B: Indexing + Embedding → mcp-vector-search + file sandbox ← → claude-mpm

This approach merges the benefits of:
index search via mcp-vector-search + sandbox file content
use of claude-mpm + specific agents/skills using mcp-vector-search AND sandbox content
Using claude-mpm allows for search context expansion based on 1) and 2) to provide additional information using “agentic” means.

# Research Topics

Constraints:
You are executing research from the monorepo root which contains several projects to be used for reference:
mcp-vector-search
claude-mpm
**CRITICAL** The reference projects should be used to provide context information and are read-only, and must never be modified during the research phase.

Architecture:

research-mind-ui provides the UI and interacts only with research-mind-service
research-mind-service communicates with:
mcp-vector-search using REST API to trigger indexing actions
claude-mpm to answer questions and which implicitly uses mcp-vector-search indexed on sandbox data
mcp-vector-search will require REST API implementation to support indexing and reindexing calls issued by research-mind-service
Research-mind-service will use claude-mpm launched within the context of the sandboxed directory to resolve user queries.

Research Goals:

Perform in-depth research to understand capabilities of mcp-vector-search present in mcp-vector-search/ git clone of the monorepo. Write results to docs/research directory in the monorepo. We need to understand:
how to introduce FastAPI functionality that leverages current functionality with respect to triggering indexing and re-indexing.
How to introduce compartmentalization of indexing/search using sets of sandboxed directories, where each sandboxed directory has subdirectories containing content.
Perform in-depth research to understand capabilities of claude-mpm present in claude-mpm/ git clone of the monorepo. Write results to docs/research directory in the monorepo. We need to understand:
How to launch and use claude-mpm using a sandbox and mcp-vector-search mcp which is indexing and searching within a specific sandbox context.
How to ensure claude-mpm is using only the knowledge scope contained within the sandbox.
