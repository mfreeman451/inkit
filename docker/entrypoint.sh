#!/bin/sh
set -eu

mkdir -p "$(dirname "$DATABASE_PATH")" "$UPLOAD_DIR"

if [ ! -s "$DATABASE_PATH" ] && [ -f /app/demo/inkit_demo.db ]; then
  cp /app/demo/inkit_demo.db "$DATABASE_PATH"
  echo "Seeded demo SQLite database at $DATABASE_PATH"
fi

public_scheme="${PHX_SCHEME:-http}"
public_host="${PHX_HOST:-localhost}"
public_port="${PHX_URL_PORT:-${PORT:-4000}}"
public_url="${public_scheme}://${public_host}"

if [ "$public_port" != "80" ] && [ "$public_port" != "443" ]; then
  public_url="${public_url}:${public_port}"
fi

cat <<EOF

Visual Assistant API is starting.

Open: ${public_url}

Remote Docker host:
  PHX_HOST=<server-hostname-or-ip> docker compose up --build

Local-only bind:
  INKIT_BIND=127.0.0.1 docker compose up --build

API smoke test from the repo checkout:
  python3 scripts/validate_api.py --base-url ${public_url}

EOF

exec "$@"
