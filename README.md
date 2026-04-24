# Visual Assistant API

Phoenix implementation of the Inkit take-home exercise. The app supports image upload, initial mock vision analysis, non-streaming API chat, Phoenix LiveView streaming chat, per-image conversation history, SQLite persistence, API request logs, and a small reviewer-facing UI.

## Quick Start

### Docker

The easiest evaluator path is Docker Compose:

```bash
SECRET_KEY_BASE="$(openssl rand -base64 48)" docker compose up --build
```

The container prints the URL at startup. Open `http://localhost:4000`.

SQLite data and uploads are stored in the `inkit_data` Docker volume.

### Local

Requirements:

- Elixir 1.15+
- Erlang/OTP
- SQLite
- Node 20+ for Playwright E2E tests

```bash
mix setup
mix phx.server
```

Open `http://localhost:4000`.

## API

Upload an image:

```bash
curl -s -X POST http://localhost:4000/upload \
  -F "image=@tmp/kitchen.jpg"
```

Ask a non-streaming question:

```bash
curl -s -X POST http://localhost:4000/chat/IMAGE_ID \
  -H "content-type: application/json" \
  -d '{"question":"What style is this image?"}'
```

Stream a chat answer with OpenAI-style SSE chunks:

```bash
curl -N -X POST http://localhost:4000/chat/IMAGE_ID/stream \
  -H "content-type: application/json" \
  -d '{"question":"What do you notice?"}'
```

Fetch an uploaded image:

```bash
curl -s http://localhost:4000/images/IMAGE_ID --output image.jpg
```

Browser chat streams through Phoenix LiveView. The REST API also includes
`POST /chat/:image_id/stream` for SSE clients that expect OpenAI-style
`chat.completion.chunk` frames ending with `data: [DONE]`.

## Stack

- Elixir, Phoenix, Phoenix LiveView
- Ash Framework resources/domains with AshSqlite
- SQLite through Ecto/AshSqlite
- Tailwind CSS and daisyUI
- ETS cache boundary for non-authoritative local caching
- Credo, ExUnit, and Playwright
- Docker and GitHub Actions
- Kustomize and Argo CD manifests for Kubernetes deployment

## Tests

```bash
mix format --check-formatted
mix test
mix credo --strict
npm ci
npx playwright install chromium
npm run test:e2e
```

Playwright runs on port `4003` with its own temporary SQLite database and upload directory, so it does not clear local development data on port `4000`.

## Requirement Coverage

- Upload endpoint validates supported image content and size.
- Non-streaming chat endpoint persists user and assistant messages.
- LiveView chat streams assistant chunks, and the REST API exposes an SSE chat
  stream compatible with OpenAI Chat Completions chunk framing.
- Conversations, labels, uploads, usage counters, and API logs are persisted in SQLite.
- The UI includes conversation selection, upload management, settings cleanup, docs, memory, and activity panels.
- Docker Compose starts the app without requiring a local Elixir toolchain.
- CI runs formatting, unit/API tests, Credo, and Playwright E2E tests.
- The release workflow builds and publishes a Docker image to GHCR for tagged releases.

## Trade-Offs

Mock responses are deterministic and tuned for the included kitchen/bathroom demo images. The app is structured so real model integration can replace `Inkit.VisualAssistant.MockAI`, but this submission does not require an API key or external AI service.

SQLite and local disk storage keep the project easy to run. That is appropriate for a take-home exercise, but production deployment would likely move image bytes to object storage and database storage to Postgres.

## AI and Process Disclosure

This project was built with OpenAI Codex using GPT-5.5 at high reasoning effort as a coding assistant. I used OpenSpec for spec-driven development: the Phoenix/Ash implementation was planned in `openspec/changes/add-visual-assistant-phoenix`, validated with OpenSpec, then implemented and tested against that checklist.

AI was used to accelerate scaffolding, implementation, test writing, UI iteration, and documentation. I made the architecture and trade-off decisions, reviewed the generated code, ran the verification suite, and adjusted behavior where the implementation did not meet the take-home requirements.
