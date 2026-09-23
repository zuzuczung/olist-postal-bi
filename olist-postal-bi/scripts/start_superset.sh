#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$PROJECT_DIR/.env" ]]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
fi
export SUPERSET_CONFIG_PATH="$PROJECT_DIR/config/superset_config.py"
export FLASK_APP=superset

mkdir -p "$PROJECT_DIR/runtime/superset"
exec "$PROJECT_DIR/.superset-venv/bin/superset" run -p 8088 --with-threads
