#!/bin/sh
set -eu

mkdir -p "$(dirname "$DATABASE_PATH")" "$UPLOAD_DIR"

cat <<EOF

Visual Assistant API is starting.

Open: http://localhost:${PORT}

API smoke test:
  curl -s -X POST http://localhost:${PORT}/upload -F "image=@/path/to/image.jpg"

EOF

exec "$@"
