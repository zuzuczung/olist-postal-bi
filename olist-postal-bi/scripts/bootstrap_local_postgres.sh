#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_BIN="$PROJECT_DIR/runtime/Postgres.app/Contents/Versions/16/bin"
PG_DATA="$PROJECT_DIR/runtime/postgres/data"
PG_LOG="$PROJECT_DIR/runtime/postgres/postgres.log"
PG_PORT="55432"

if [[ ! -f "$PROJECT_DIR/.env" ]]; then
  printf 'Missing %s. Copy .env.example to .env and configure credentials.\n' "$PROJECT_DIR/.env" >&2
  exit 1
fi
set -a
source "$PROJECT_DIR/.env"
set +a
if [[ -z "${PGPASSWORD:-}" ]]; then
  printf 'PGPASSWORD is required in %s/.env.\n' "$PROJECT_DIR" >&2
  exit 1
fi

mkdir -p "$PROJECT_DIR/runtime/postgres"
if [[ ! -x "$PG_BIN/postgres" ]]; then
  printf 'Postgres.app runtime is missing: %s\n' "$PG_BIN" >&2
  exit 1
fi
if [[ ! -s "$PG_DATA/PG_VERSION" ]]; then
  "$PG_BIN/initdb" --pgdata="$PG_DATA" --encoding=UTF8 --locale=C --auth-local=trust --auth-host=scram-sha-256
  {
    printf "\nlisten_addresses = '*'\n"
    printf "port = %s\n" "$PG_PORT"
    printf "timezone = 'UTC'\n"
  } >> "$PG_DATA/postgresql.conf"
  printf "host all all 192.168.0.0/16 scram-sha-256\n" >> "$PG_DATA/pg_hba.conf"
fi

if ! "$PG_BIN/pg_isready" -h 127.0.0.1 -p "$PG_PORT" >/dev/null 2>&1; then
  "$PG_BIN/pg_ctl" -D "$PG_DATA" -l "$PG_LOG" start
fi

ADMIN_USER="$(id -un)"
if ! "$PG_BIN/psql" -h /tmp -p "$PG_PORT" -d postgres -U "$ADMIN_USER" -tAc "SELECT 1 FROM pg_roles WHERE rolname='olist_bi'" | grep -q 1; then
  "$PG_BIN/psql" -h /tmp -p "$PG_PORT" -d postgres -U "$ADMIN_USER" -v ON_ERROR_STOP=1 -v role_password="$PGPASSWORD" -c "CREATE ROLE olist_bi LOGIN PASSWORD :'role_password'"
fi
if ! "$PG_BIN/psql" -h /tmp -p "$PG_PORT" -d postgres -U "$ADMIN_USER" -tAc "SELECT 1 FROM pg_database WHERE datname='olist_postal_bi'" | grep -q 1; then
  "$PG_BIN/createdb" -h /tmp -p "$PG_PORT" -U "$ADMIN_USER" -O olist_bi olist_postal_bi
fi
"$PG_BIN/psql" -h /tmp -p "$PG_PORT" -d olist_postal_bi -U "$ADMIN_USER" -v ON_ERROR_STOP=1 -c "GRANT ALL ON DATABASE olist_postal_bi TO olist_bi"
"$PG_BIN/pg_isready" -h 127.0.0.1 -p "$PG_PORT" -d olist_postal_bi
