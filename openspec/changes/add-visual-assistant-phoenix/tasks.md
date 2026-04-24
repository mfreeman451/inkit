## 1. Project Setup
- [x] 1.1 Scaffold Phoenix application with Ecto, SQLite, LiveView, Tailwind, and daisyUI.
- [x] 1.2 Add `.gitignore` rules for dependencies, build artifacts, SQLite databases, uploads, logs, and temporary files.
- [x] 1.3 Add `mix setup` support for dependency installation, database setup, and asset setup.
- [x] 1.4 Add Ash, AshSqlite, and Credo dependencies.
- [x] 1.5 Add Dockerfile and Docker Compose support for evaluator setup without local Elixir.
- [x] 1.6 Add bundled demo images and a seeded SQLite database for fresh Docker starts.

## 2. Persistence and Domain Model
- [x] 2.1 Add Ash resource and AshSqlite migration for uploaded image metadata.
- [x] 2.2 Add Ash resource and AshSqlite migration for per-image conversation messages.
- [x] 2.3 Add workflow functions for creating images, reading images, appending messages, and listing history.

## 3. Mock AI
- [x] 3.1 Implement mock image analysis responses with OpenAI-style IDs, timestamps, content, and usage metadata.
- [x] 3.2 Implement mock streaming chat responses that include conversation context and OpenAI-style chat completion chunk envelopes.
- [x] 3.3 Implement mock streaming chat chunks for LiveView rendering.

## 4. API
- [x] 4.1 Add multipart image upload endpoint with size limits, content validation, metadata persistence, and structured errors.
- [x] 4.2 Add non-streaming chat endpoint scoped to an uploaded image.
- [x] 4.3 Add SSE chat endpoint for API clients while retaining Phoenix LiveView streaming for the browser UI.
- [x] 4.4 Add consistent error JSON and status codes for validation, missing records, unsupported media, and internal failures.
- [x] 4.5 Add image render route for the LiveView demo.

## 5. Cache and Reliability
- [x] 5.1 Add an application cache boundary backed by ETS.
- [x] 5.2 Use cache only for non-authoritative data such as recent image metadata or rendered mock analysis.
- [x] 5.3 Add request logging and safe error handling that avoids leaking internal paths or stack traces.

## 6. LiveView Demo
- [x] 6.1 Add a minimal LiveView upload and chat interface using daisyUI components.
- [x] 6.2 Show upload state, image metadata, conversation history, and streamed assistant output.
- [x] 6.3 Add real conversations, upload management, settings cleanup, memory, activity, docs, and responsive mobile behavior.
- [x] 6.4 Add persisted API logs, paginated log view, and usage counters based on request logs.
- [x] 6.5 Keep the demo narrow enough that API behavior remains easy to review.

## 7. Tests and Documentation
- [x] 7.1 Add API tests for upload, chat, streaming, validation errors, and missing image IDs.
- [x] 7.2 Add workflow/storage tests for image metadata and conversation history.
- [x] 7.3 Add mock AI response shape tests.
- [x] 7.4 Add README instructions for fresh checkout setup, running tests, starting the server, API `curl` examples, trade-offs, and AI tool disclosure.
- [x] 7.5 Add Credo lint command and verify strict linting passes.
- [x] 7.6 Add Playwright E2E tests for upload preview, chat, saved conversations, tabs, API logs, settings cleanup, and mobile behavior.
- [x] 7.7 Add GitHub Actions CI and GHCR release workflows.
- [x] 7.8 Add a dependency-free Python API smoke script using the bundled kitchen and bathroom images.
- [x] 7.9 Add security regression tests for upload traversal, image content validation, XSS escaping, SQLi-shaped IDs, and defensive headers.
