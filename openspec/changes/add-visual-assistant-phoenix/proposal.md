# Change: Build the Phoenix Visual Assistant

## Why
The project needs an initial implementation plan for the Inkit take-home exercise that is easy for evaluators to clone, run, test, and review. The stack is now Elixir/Phoenix with Ash Framework resources, SQLite persistence through AshSqlite, Phoenix LiveView for a lightweight demo UI, and daisyUI for browser-facing components.

## What Changes
- Scaffold a Phoenix application for the Visual Assistant API and optional LiveView demo.
- Add SQLite persistence through Ash resources/domains and AshSqlite migrations for image metadata and per-image chat history.
- Add upload and non-streaming chat API endpoints plus a LiveView streaming chat workflow.
- Add mock OpenAI-compatible response builders for image analysis, non-streaming chat, and streaming chat chunks.
- Add a LiveView demo UI using daisyUI components for upload, image context, chat, and streamed responses.
- Add a small cache boundary backed by ETS or Cachex without requiring an external cache service.
- Add Credo linting and README quality commands so the code can be checked for idiomatic Elixir style.
- Add Dockerfile and Docker Compose support so evaluators can run the app without installing Elixir locally.
- Add README setup, test, API examples, trade-offs, and AI usage disclosure so evaluators can run the project from a fresh checkout.

## Impact
- Affected specs: visual-assistant
- Affected code: Phoenix app scaffold, router/controllers, LiveViews, Ash domain/resources, AshSqlite migrations/snapshots, workflow modules, mock AI modules, cache module, tests, README, `.gitignore`
