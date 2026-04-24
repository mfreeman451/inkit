# Visual Assistant API

Phoenix implementation of the Inkit take-home exercise. The app supports image upload, initial mock vision analysis, non-streaming API chat, Phoenix LiveView streaming chat, per-image conversation history, SQLite persistence, API request logs, and a small reviewer-facing UI.

## Quick Start

The intended evaluator path is Docker Compose — nothing else needs to be
installed locally:

```bash
SECRET_KEY_BASE="$(openssl rand -base64 48)" docker compose up --build
```

Open `http://localhost:4000`. SQLite data and uploads live in the
`inkit_data` Docker volume. The image ships with a demo SQLite database plus
two sample images (kitchen and bathroom), so the UI has content on first load.

Validate the REST API against a running instance:

```bash
python3 scripts/validate_api.py --base-url http://localhost:4000
```

### Local development (optional)

For iterating on the Elixir code without Docker:

- Elixir 1.15+ / Erlang/OTP
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
  -F "image=@priv/demo/uploads/kitchen.jpg"
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
- ETS-backed fixed-window rate limiter (60 req/min per IP per bucket by default)
- Periodic retention sweep GenServer (default 30-day messages/images, 7-day API logs)
- SSE chat with `Last-Event-ID` resume on `POST /chat/:id/stream`
- Credo, ExUnit, and Playwright
- Docker and GitHub Actions
- Kustomize and Argo CD manifests are included for Kubernetes deployment, but
  Docker Compose is the intended evaluator surface

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

## Operational knobs

These live under `config :inkit, ...` and can be overridden per environment.

| Key | Default | Purpose |
| --- | --- | --- |
| `:rate_limit` `enabled` | `true` | Turn per-IP rate limiting on/off (disabled in `test.exs`). |
| `:rate_limit` `window_ms` | `60_000` | Fixed window length. |
| `:rate_limit` `max_requests` | `60` | Per-IP, per-bucket cap per window. Buckets: `:upload`, `:chat`, `:chat_stream`. |
| `:retention` `enabled` | `true` | Whether the retention GenServer ticks. |
| `:retention` `messages_days` | `30` | Message rows older than this are purged. |
| `:retention` `api_logs_days` | `7` | API log rows older than this are purged. |
| `:retention` `images_days` | `30` | Images (and their messages) older than this are purged. |
| `:retention` `interval_ms` | `3_600_000` | Sweep interval. |
| `:async_api_logs` | `true` | Fire-and-forget API log writes via `Task.Supervisor`. |

Rate-limited responses carry `Retry-After` and `X-RateLimit-Remaining` /
`X-RateLimit-Reset-Ms` headers.

The SSE chat endpoint emits `id: N` before each `data:` frame. On reconnect
the client can send `Last-Event-ID: K` and the server skips the first `K + 1`
chunks. Mock completion IDs are derived deterministically from
`{image_id, prompt, prior_user_turns}` so resumes keep the same `chatcmpl-…`
ID across attempts.

## Trade-Offs

**Mock AI.** Responses are deterministic and tuned for the included
kitchen/bathroom demo images. The `Inkit.VisualAssistant.MockAI` boundary can
be swapped for a real provider (OpenAI, Anthropic, etc.) without touching the
persistence, streaming, or rate-limit paths.

**SQLite + local disk.** Keeps the whole app spin-up to a single
`docker compose up` with no external services. The data layer is Ash-backed so
a Postgres move is mostly a resource-layer swap, and image bytes would move
to object storage (S3/GCS). That work is deferred since the take-home
evaluator runs a single container.

**Horizontal scaling is bounded by the data layer, not the BEAM.** Even if
you back the Docker volume or the Kubernetes PVC with something like Longhorn
or Ceph (the manifests target a Longhorn StorageClass in practice), SQLite is
still a single-writer database and local-disk uploads are pod-local. So the
Kubernetes manifests intentionally pin `replicas: 1` with
`strategy: Recreate`. Stateless fan-out requires the Postgres + object
storage swap above; that’s the line this submission stops at.

**Production monitoring.** Phoenix telemetry events fire, and
`Phoenix.LiveDashboard` is mounted under `:dev_routes`. There is no
Prometheus/OTLP exporter wired — a real deployment would add one and put the
LiveDashboard behind auth.

**SSE resume.** Duplicate-persistence is possible if a client completes a full
stream and then reconnects with `Last-Event-ID`. A real provider integration
would gate persistence with an idempotency key; documented as a mock-mode
limitation.

## AI and Process Disclosure

This project was built with OpenAI Codex using GPT-5.5 at high reasoning effort as a coding assistant. I used OpenSpec for spec-driven development: the Phoenix/Ash implementation was planned in `openspec/changes/add-visual-assistant-phoenix`, validated with OpenSpec, then implemented and tested against that checklist.

AI was used to accelerate scaffolding, implementation, test writing, UI iteration, and documentation. I made the architecture and trade-off decisions, reviewed the generated code, ran the verification suite, and adjusted behavior where the implementation did not meet the take-home requirements.
