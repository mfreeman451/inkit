## ADDED Requirements

### Requirement: Fresh Checkout Setup
The system SHALL provide documented setup commands that allow an evaluator to install dependencies, initialize the SQLite database, run tests, and start the Phoenix server from a fresh repository checkout without external services.

#### Scenario: Evaluator starts the application locally
- **GIVEN** an evaluator has cloned the repository and installed the documented Elixir/Erlang prerequisites
- **WHEN** they follow the README setup commands
- **THEN** dependencies are installed, the SQLite database is prepared, tests can run, and the Phoenix server can start locally

#### Scenario: Evaluator starts the application with Docker
- **GIVEN** an evaluator has cloned the repository and has Docker installed
- **WHEN** they run the documented Docker Compose command
- **THEN** the application builds, starts, prints the local URL, and serves the LiveView UI on port 4000

#### Scenario: Evaluator starts with bundled demo data
- **GIVEN** an evaluator starts the Docker image with a fresh data volume
- **WHEN** the application starts
- **THEN** a seeded SQLite database and bundled kitchen and bathroom images are available for immediate UI review

### Requirement: Image Upload API
The system SHALL expose a REST-style endpoint that accepts image uploads, validates image content and size, persists image metadata, generates a unique image identifier, and returns initial mock analysis.

#### Scenario: User uploads a valid image
- **GIVEN** the API is running
- **WHEN** a client uploads a supported image file using multipart form data
- **THEN** the system returns a success status with an image identifier, persisted metadata, and mock image analysis

#### Scenario: User uploads an invalid file
- **GIVEN** the API is running
- **WHEN** a client uploads a missing, oversized, or unsupported file
- **THEN** the system returns a structured error response with an appropriate 4xx status code

#### Scenario: User uploads a suspicious filename
- **GIVEN** the API is running
- **WHEN** a client uploads an image with a path traversal or control-character filename
- **THEN** the system stores the image under a server-generated path and persists only a safe basename for display

#### Scenario: User uploads disguised content
- **GIVEN** the API is running
- **WHEN** a client uploads non-image bytes with an allowed image extension
- **THEN** the system rejects the upload based on detected content rather than trusting the client filename or content type

### Requirement: LiveView Streaming Chat
The system SHALL provide Phoenix LiveView streaming chat for a previously uploaded image, stream mock assistant response chunks through LiveView updates, and persist the completed exchange in the image's history.

#### Scenario: User streams a chat response in the browser
- **GIVEN** an image has been uploaded
- **WHEN** a user submits a valid question in the LiveView interface
- **THEN** the system streams ordered assistant updates and records the completed user and assistant messages

#### Scenario: Streaming question fails validation
- **GIVEN** an image has been uploaded
- **WHEN** a user submits an empty question in the LiveView interface
- **THEN** the system shows a safe validation error and does not append a conversation message

### Requirement: SSE Streaming Chat API
The system SHALL expose a REST-style SSE endpoint for a previously uploaded image that emits OpenAI-style `chat.completion.chunk` data frames and terminates the event stream with `data: [DONE]`.

#### Scenario: API client streams a chat response
- **GIVEN** an image has been uploaded
- **WHEN** a client submits a valid streaming chat request for that image
- **THEN** the system returns `text/event-stream`, emits ordered JSON chunks using the OpenAI chat completion chunk envelope, sends `data: [DONE]`, and persists the completed user and assistant messages

#### Scenario: Streaming chat request fails validation
- **GIVEN** the API is running
- **WHEN** a client submits an invalid streaming chat request
- **THEN** the system returns a structured JSON error before opening the SSE stream

### Requirement: Non-Streaming Chat API
The system SHALL expose a REST-style chat endpoint that accepts a question for a previously uploaded image, appends user and assistant messages to that image's history, and returns a mock OpenAI-compatible non-streaming chat response.

#### Scenario: User asks a question about an uploaded image
- **GIVEN** an image has been uploaded
- **WHEN** a client submits a valid question for that image
- **THEN** the system returns a mock assistant response and persists both the user message and assistant message in the image's conversation history

#### Scenario: User asks about a missing image
- **GIVEN** the API is running
- **WHEN** a client submits a chat request for an unknown image identifier
- **THEN** the system returns a structured not-found error

### Requirement: Per-Image Conversation History
The system SHALL persist conversation history separately for each uploaded image and include relevant prior messages when generating mock chat responses.

#### Scenario: User asks a follow-up question
- **GIVEN** an image has prior conversation messages
- **WHEN** a client asks a follow-up question for that image
- **THEN** the mock assistant response is generated with access to that image's previous conversation messages

### Requirement: Local Persistence
The system SHALL use SQLite through AshSqlite-generated migrations for durable local storage of Ash resource-backed image metadata and conversation history.

#### Scenario: Application restarts
- **GIVEN** an image and conversation history were stored in SQLite
- **WHEN** the Phoenix application restarts using the same local database
- **THEN** the image metadata and conversation history remain available

### Requirement: Local Cache Boundary
The system SHALL provide an application cache boundary backed by ETS or Cachex and SHALL NOT require an external cache service.

#### Scenario: Cached data is unavailable
- **GIVEN** cached data has expired or is absent
- **WHEN** the application handles a request
- **THEN** it falls back to persisted data or recomputes non-authoritative data without failing the request solely because of a cache miss

### Requirement: LiveView Demo UI
The system SHALL provide a minimal Phoenix LiveView demo using daisyUI components for uploading an image, viewing image metadata, asking questions, and observing streamed assistant output.

#### Scenario: User interacts with the browser demo
- **GIVEN** the Phoenix server is running
- **WHEN** a user opens the demo UI
- **THEN** they can upload an image, ask questions, see conversation history, and observe assistant responses without using a separate frontend application

### Requirement: Upload and Conversation Management
The system SHALL provide browser UI controls for listing saved conversations, selecting previous conversations, labeling uploaded images, deleting uploaded images with their conversation history, and clearing local image/conversation data.

#### Scenario: User selects a saved conversation
- **GIVEN** one or more image conversations are stored
- **WHEN** the user opens the conversations view and selects a conversation
- **THEN** the system shows that conversation's image context, messages, memory, activity, and focused chat input

#### Scenario: User returns from a selected conversation
- **GIVEN** the user is viewing a saved conversation
- **WHEN** they click the back control in the conversation header
- **THEN** the system returns to the conversations list without mixing messages from another active or recently streamed conversation

#### Scenario: User manages uploads
- **GIVEN** one or more images are stored
- **WHEN** the user opens the uploads view
- **THEN** they can label or delete each image without affecting unrelated conversations

### Requirement: API Logs and Usage Metrics
The system SHALL persist request logs for API and LiveView assistant operations and SHALL expose them in a paginated browser view with usage counters derived from persisted data.

#### Scenario: User reviews API logs
- **GIVEN** upload or chat activity has occurred
- **WHEN** the user opens the API Logs view
- **THEN** the system shows persisted request rows with method, path, status, duration, image identifier, and pagination controls

#### Scenario: User deletes images
- **GIVEN** usage data and uploaded images exist
- **WHEN** the user deletes images or clears conversations
- **THEN** usage counters remain based on persisted request logs rather than resetting because image rows were removed

### Requirement: Safe Error Handling
The system SHALL return consistent, structured errors and SHALL avoid exposing internal file paths, stack traces, secrets, or sensitive configuration in client responses.

#### Scenario: Unexpected server error occurs
- **GIVEN** an unexpected error occurs during request handling
- **WHEN** the system responds to the client
- **THEN** the response contains a safe generic error shape and the sensitive details are limited to server-side logs

#### Scenario: Browser renders user-controlled text
- **GIVEN** uploaded filenames, labels, and prompts may contain HTML-like text
- **WHEN** the browser renders conversations, labels, or assistant context
- **THEN** the system escapes user-controlled text and does not render it as executable HTML

#### Scenario: API receives SQLi-shaped identifiers
- **GIVEN** a client submits an image identifier containing SQL-like characters
- **WHEN** the system queries persisted data
- **THEN** the identifier is treated as opaque data and returns either the matching record or a safe not-found response

### Requirement: API Smoke Validation
The system SHALL provide a dependency-free validation script that exercises the public REST API using bundled kitchen and bathroom sample images.

#### Scenario: Evaluator validates the API manually
- **GIVEN** the application is running locally
- **WHEN** an evaluator runs the documented Python validation script
- **THEN** it verifies upload, image download, non-streaming chat, SSE streaming chat, OpenAI-style response shapes, and persisted history for both sample images

### Requirement: Elixir Quality Gate
The system SHALL provide automated formatting, linting, and test commands that can be run locally by an evaluator.

#### Scenario: Evaluator checks code quality
- **GIVEN** an evaluator has completed project setup
- **WHEN** they run the documented quality commands
- **THEN** formatting, Credo linting, and tests complete successfully

### Requirement: Browser E2E Coverage
The system SHALL provide Playwright E2E tests that validate the primary desktop and mobile UI workflows using an isolated test database.

#### Scenario: CI runs browser tests
- **GIVEN** CI or an evaluator runs the documented E2E command
- **WHEN** Playwright starts the application
- **THEN** it uses an isolated SQLite database and validates upload, preview, chat, conversation selection, tabs, API logs, settings cleanup, and mobile behavior
