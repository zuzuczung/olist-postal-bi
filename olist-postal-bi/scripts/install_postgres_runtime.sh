#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="$PROJECT_DIR/runtime/downloads/Postgres-2.9.6-16.dmg"
APP="$PROJECT_DIR/runtime/Postgres.app"
DOWNLOAD_URL="https://github.com/PostgresApp/PostgresApp/releases/download/v2.9.6/Postgres-2.9.6-16.dmg"
EXPECTED_SHA256="2689dc64d6a02e0a66e4585616919060d8fbf5bb06886fccc05b7f87638bf081"
VOLUME="/Volumes/Postgres-2.9.6-16"

if [[ -x "$APP/Contents/Versions/16/bin/postgres" ]]; then
  "$APP/Contents/Versions/16/bin/postgres" --version
  exit 0
fi

mkdir -p "$PROJECT_DIR/runtime/downloads"
if [[ ! -f "$DMG" ]]; then
  curl --fail --location --progress-bar "$DOWNLOAD_URL" --output "$DMG"
fi
printf '%s  %s\n' "$EXPECTED_SHA256" "$DMG" | shasum -a 256 -c -

hdiutil attach -nobrowse -readonly "$DMG"
detach_volume() {
  hdiutil detach "$VOLUME" >/dev/null 2>&1 || true
}
trap detach_volume EXIT
ditto "$VOLUME/Postgres.app" "$APP"
detach_volume
trap - EXIT
"$APP/Contents/Versions/16/bin/postgres" --version

