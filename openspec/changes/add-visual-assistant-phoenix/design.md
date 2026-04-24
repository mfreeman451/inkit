## Context
The take-home asks for a staged Visual Assistant: image upload, mock image analysis, streaming chat, per-image history, and persistent storage. The implementation should show production-oriented thinking while staying straightforward for reviewers to run locally.

## Goals / Non-Goals
- Goals: implement the upload API in Phoenix, model metadata/history as Ash resources, persist through AshSqlite/SQLite, stream chat through LiveView, provide a strong LiveView demo, and document a clean evaluator setup.
- Goals: keep dependencies limited and defensible.
- Non-Goals: integrate with real OpenAI services, build a polished product UI, require an external cache service, require Docker, or optimize for multi-node production deployment.

## Decisions
- Decision: Use Phoenix controllers for upload, image retrieval, and non-streaming chat; use Phoenix LiveView for browser streaming chat.
- Rationale: The question-answering endpoint stays easy to exercise through HTTP, while LiveView gives us streaming chat without carrying a separate SSE implementation.
- Decision: Use SQLite through Ecto.
- Rationale: SQLite keeps evaluator setup simple while still allowing migrations, schemas, constraints, and transaction boundaries.
- Decision: Use Ash Framework domains/resources with AshSqlite for image metadata and conversation history.
- Rationale: Ash gives the app a conventional resource layer and can generate SQLite migrations/snapshots from the resource definitions.
- Decision: Use daisyUI on Tailwind CSS for LiveView UI components.
- Rationale: daisyUI provides adequate form, button, alert, card, loading, and chat primitives without spending exercise time on custom CSS.
- Decision: Use ETS or Cachex behind an application cache module.
- Rationale: The exercise asks for a caching layer, but an external cache service would make local setup heavier. A local cache demonstrates the boundary and trade-off clearly.
- Decision: Keep mock AI response construction isolated.
- Rationale: OpenAI-compatible response shapes are part of the exercise; isolating this code makes it easier to test response structure and streaming chunk order.

## Risks / Trade-offs
- SQLite has different concurrency characteristics than PostgreSQL. Mitigation: keep write transactions short, document the choice, and design storage functions so a future adapter could move to another database.
- ETS/Cachex is single-node. Mitigation: document the limitation and keep cache usage non-authoritative so persistence remains the source of truth.
- LiveView streaming is Phoenix-specific. Mitigation: document that chat streaming is part of the browser workflow and keep workflow logic separated from the UI.
- Multipart upload security is easy to underdo. Mitigation: enforce size limits, validate content type from file contents, restrict accepted formats, and keep uploaded bytes outside Git.

## Migration Plan
1. Scaffold the Phoenix project.
2. Add Ash/AshSqlite configuration, resources, domains, and generated migrations.
3. Implement upload and chat workflow modules.
4. Add API endpoints and tests.
5. Add LiveView streaming and tests.
6. Add LiveView demo using daisyUI.
7. Update README and local setup documentation.

## Open Questions
- Should uploaded image bytes be stored on local disk only, or should the first implementation persist them as database blobs? Local disk is simpler and avoids bloating SQLite, but it requires cleanup and path management.
- Should the cache use raw ETS or Cachex? ETS keeps dependencies lower and is sufficient for the first implementation.
