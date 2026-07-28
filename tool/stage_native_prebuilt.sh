#!/usr/bin/env bash
# Stage a built library into native/prebuilt/<triple>/ and emit a release zip.
# Usage: stage_native_prebuilt.sh <triple> <path-to-lib> [out-dir]
set -euo pipefail

TRIPLE="${1:?triple required}"
LIB="${2:?library path required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${3:-$ROOT/native/prebuilt-dist}"

if [[ ! -f "$LIB" ]]; then
  echo "Library not found: $LIB" >&2
  exit 1
fi

STAGE="$ROOT/native/prebuilt/$TRIPLE"
mkdir -p "$STAGE" "$OUT_DIR"
cp -f "$LIB" "$STAGE/"
BASENAME="$(basename "$LIB")"
echo "Staged $LIB -> $STAGE/$BASENAME"

ZIP="$OUT_DIR/datachannel-${TRIPLE}.zip"
rm -f "$ZIP"
# zip paths relative so extract yields <triple>/<file>
(
  cd "$ROOT/native/prebuilt"
  zip -qr "$ZIP" "$TRIPLE"
)
echo "Wrote $ZIP"
