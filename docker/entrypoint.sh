#!/bin/sh
set -eu

mkdir -p "$(dirname "$DATABASE_PATH")" "$UPLOAD_DIR"

if [ ! -s "$DATABASE_PATH" ] && [ -f /app/demo/inkit_demo.db ]; then
  cp /app/demo/inkit_demo.db "$DATABASE_PATH"
  echo "Seeded demo SQLite database at $DATABASE_PATH"
fi

cat <<EOF

Visual Assistant API is starting.

Open: http://localhost:${PORT}

API smoke test from the repo checkout:
  python3 scripts/validate_api.py --base-url http://localhost:${PORT}

EOF

exec "$@"
