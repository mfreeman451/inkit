# Project Context

## Purpose
This repository is for the Inkit take-home exercise: a Visual Assistant API that lets users upload images, receive mock AI image analysis, and ask follow-up questions about uploaded images.

The project is intended to demonstrate backend engineering judgment under ambiguity. The implementation should be complete enough for peer review and discussion, with clear trade-offs documented where the exercise leaves choices open.

Primary goals:
- Provide a REST API for secure image upload and metadata tracking.
- Provide streaming chat through Phoenix LiveView for questions about an uploaded image.
- Preserve conversation history per image.
- Add production-oriented persistence, migrations, caching, validation, logging, and error handling as time allows.
- Match OpenAI-style response shapes for mock vision, chat, and streaming chat responses closely enough that clients can consume them predictably.

## Tech Stack
- Backend language: Elixir.
- Application framework: Phoenix.
- Frontend/demo layer: Phoenix LiveView may be used for a lightweight interactive demo of upload and chat flows.
- UI/CSS components: daisyUI on top of Tailwind CSS for any browser-facing Phoenix LiveView interface.
- API layer: Phoenix controllers expose upload, image retrieval, and non-streaming question-answering routes. Browser streaming chat is handled by Phoenix LiveView rather than a separate SSE endpoint.
- Domain/data layer: Ash Framework resources and domains with AshSqlite.
- Database: SQLite through Ecto/AshSqlite, with AshSqlite-generated migrations and resource snapshots.
- Cache: prefer a small cache boundary in the application code backed by ETS or Cachex. Keep the implementation single-node and document that limitation.
- Code quality: `mix format`, `mix credo --strict`, and `mix test` should pass before submission.
- AI integration: mock services only. No real OpenAI calls are required for the exercise unless explicitly proposed later.
- Provided Python/Flask starter code may be used as reference material, but the implementation is not required to keep Flask or Python.

## Project Conventions

### Code Style
- Prefer small, explicit Elixir modules with clear structs or maps for request/response shapes.
- Keep Phoenix controllers and LiveViews thin: validate input, call context modules, and serialize or render responses.
- Use structured error responses consistently across endpoints.
- Use standard formatters (`mix format` for Elixir, `prettier` if TypeScript or JavaScript is introduced).
- Prefer descriptive names over abbreviations, especially for domain objects such as images, conversations, messages, and stream events.
- Keep comments sparse and useful; document non-obvious trade-offs, concurrency decisions, and compatibility choices.
- Do not add dependencies casually. Prefer standard library or well-known, actively maintained packages.

### Architecture Patterns
- Use OpenSpec for feature planning before implementing new capabilities or architecture changes.
- Organize the backend around clear boundaries:
  - HTTP transport: Phoenix router, controllers, plugs, validation, status codes, and serialization.
  - LiveView transport: optional browser workflow for upload, chat, and streamed updates.
  - Ash domain/resources: image metadata and conversation messages.
  - Workflow modules: upload workflow, chat workflow, mock AI behavior, history handling, and cache access.
  - Storage: AshSqlite resources over SQLite for image metadata, conversation messages, persistence, and cleanup.
  - Infrastructure: logging, configuration, migrations, cache, rate limiting.
- Treat uploaded image bytes separately from image metadata. Metadata must be queryable without loading image contents into memory.
- Use generated unique identifiers for uploaded images and conversations/messages where needed.
- Make concurrent access explicit. Use Ecto transactions for persistent changes and OTP-managed processes, ETS, or Cachex for shared in-memory state.
- Keep LiveView streaming chat and history persistence backed by shared workflow logic.
- Keep mock AI response construction isolated so response-shape compatibility can be tested independently.

### Testing Strategy
- Add focused automated tests for request validation, error responses, upload metadata, chat history, and mock AI response shapes.
- Test upload API behavior and LiveView/workflow streaming behavior.
- Test LiveView interactions if a browser demo is implemented, but do not let UI tests replace API coverage.
- Include concurrency tests where shared state, history, or storage writes are involved.
- Add storage-layer tests when persistence is introduced, including migration setup and cleanup behavior.
- Prefer table-driven tests for API validation and response cases.
- Manual smoke tests should cover upload, LiveView streaming chat, missing/invalid image IDs, invalid files, and repeated conversation turns.

### Local Setup and Evaluator Experience
- Optimize for a fresh checkout experience. An evaluator should be able to clone the repository, follow the README, and run the app without reverse-engineering project internals.
- Keep required services minimal. SQLite should work out of the box without Docker, and no external cache service should be required.
- Provide explicit setup commands in the README, including dependency installation, database creation/migration, test execution, and starting the Phoenix server.
- Prefer standard Phoenix commands such as `mix setup`, `mix test`, and `mix phx.server` where possible.
- Include `mix credo --strict` as the lint gate so reviewers can quickly verify idiomatic Elixir style.
- Provide a Docker Compose path so evaluators without local Elixir can run `docker compose up --build` and open `http://localhost:4000`.
- Include sample API requests for upload and browser instructions for LiveView streaming chat.
- Include any required Elixir, Erlang/OTP, Node, or package manager versions.
- Do not require secrets for the default mock-only implementation.
- Keep generated local files out of Git, including SQLite database files, uploads, temporary images, logs, and dependency/build caches.
- If a Docker or Compose workflow is added, it should be optional and should not replace the simple local path.

### Git Workflow
- Use short-lived feature branches for implementation work.
- Keep commits scoped and reviewable.
- Use imperative commit messages, for example `add image upload endpoint` or `implement chat history storage`.
- Do not commit generated artifacts, local databases, uploaded test files, secrets, or dependency caches.
- Before submitting, include a README update describing how to run the project, how to run tests, what trade-offs were made, and whether AI tools were used.

## Domain Context
- The core domain is an image-backed visual assistant.
- Users upload an image and receive an image identifier plus initial mock analysis.
- Users ask questions against a specific uploaded image.
- Chat history is scoped to the image so later questions can refer to earlier turns.
- Streaming chat should use Phoenix LiveView updates and may reuse OpenAI-style mock chunks internally.
- Mock AI responses should include realistic IDs, timestamps, roles, content, finish reasons, and usage/token fields where applicable.
- The exercise is intentionally staged:
  - Question 1: foundational upload API and LiveView chat workflow.
  - Question 2: streaming chat through Phoenix LiveView.
  - Question 3: per-image conversation history.
  - Question 4: persistent storage, migrations, caching, and production-readiness concerns.

## Important Constraints
- This is a take-home interview project, so the solution should prioritize clarity, maintainability, and defensible trade-offs over feature breadth.
- The submitted repository must be easy for evaluators to clone, run, test, and inspect.
- The UI does not need to be polished and may be omitted unless it helps demonstrate the API.
- If LiveView is included, keep it narrow and functional; the API remains the primary deliverable.
- No real AI provider integration is required; use mock responses that follow expected external API shapes.
- Uploaded files must be validated by content and type, not only by filename.
- Upload handling must avoid unnecessary memory pressure and must have clear size limits.
- Error responses must not leak internal details, file paths, stack traces, or sensitive configuration.
- The service should be safe to run locally and should not require secrets for the mock-only implementation.
- If a starter app or third-party dependency is adopted, review it first and document why it is needed.
- Any use of AI assistance must be disclosed in the project README before submission.

## External Dependencies
- OpenAI API shape is an external compatibility reference for mock responses only.
- SQLite is the chosen local persistence layer.
- A caching layer is expected for the final production-readiness stage. ETS or Cachex is the preferred take-home implementation.
- No external AI, storage, queue, or monitoring services are currently required.
