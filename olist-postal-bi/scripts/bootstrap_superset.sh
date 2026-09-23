#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPERSET_BIN="$PROJECT_DIR/.superset-venv/bin/superset"
SUPERSET_DB="$PROJECT_DIR/runtime/superset/superset.db"

if [[ ! -f "$PROJECT_DIR/.env" ]]; then
  printf 'Missing %s. Copy .env.example to .env and configure credentials.\n' "$PROJECT_DIR/.env" >&2
  exit 1
fi
set -a
source "$PROJECT_DIR/.env"
set +a
: "${SUPERSET_USERNAME:?SUPERSET_USERNAME is required in .env}"
: "${SUPERSET_PASSWORD:?SUPERSET_PASSWORD is required in .env}"

if [[ ! -x "$SUPERSET_BIN" ]]; then
  python3 -m venv "$PROJECT_DIR/.superset-venv"
  "$PROJECT_DIR/.superset-venv/bin/pip" install -r "$PROJECT_DIR/requirements-superset.txt"
fi

export SUPERSET_CONFIG_PATH="$PROJECT_DIR/config/superset_config.py"
export FLASK_APP=superset
mkdir -p "$PROJECT_DIR/runtime/superset"
"$SUPERSET_BIN" db upgrade

ADMIN_COUNT="0"
if [[ -f "$SUPERSET_DB" ]]; then
  ADMIN_COUNT="$(sqlite3 "$SUPERSET_DB" "SELECT count(*) FROM ab_user WHERE username='admin';" 2>/dev/null || printf '0')"
fi
if [[ "$ADMIN_COUNT" == "0" ]]; then
  "$SUPERSET_BIN" fab create-admin \
    --username "$SUPERSET_USERNAME" \
    --firstname Olist \
    --lastname Admin \
    --email admin@olist.local \
    --password "$SUPERSET_PASSWORD"
fi
"$SUPERSET_BIN" init
