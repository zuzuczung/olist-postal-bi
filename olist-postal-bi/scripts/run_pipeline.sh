#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PSQL="$PROJECT_DIR/runtime/Postgres.app/Contents/Versions/16/bin/psql"
set -a
source "$PROJECT_DIR/.env"
set +a

"$PROJECT_DIR/.venv/bin/python" "$PROJECT_DIR/scripts/load_staging.py"
"$PSQL" -v ON_ERROR_STOP=1 -f "$PROJECT_DIR/sql/03_analytics.sql"
"$PSQL" -v ON_ERROR_STOP=1 -f "$PROJECT_DIR/sql/02_quality_checks.sql" | tee "$PROJECT_DIR/artifacts/quality_checks.txt"
"$PSQL" -v ON_ERROR_STOP=1 -f "$PROJECT_DIR/sql/04_kpi_validation.sql" | tee "$PROJECT_DIR/artifacts/kpi_validation.txt"
"$PSQL" -v ON_ERROR_STOP=1 -f "$PROJECT_DIR/sql/05_page_validation.sql" | tee "$PROJECT_DIR/artifacts/page_validation.txt"
