#!/bin/bash
# ────────────────────────────────────────────────────────────────
# package-mod.sh — zip the built mod into <id>-<version>.zip
#
# Inputs: MOD_ID, BUILD_DIR (path to build/<id>/)
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_ID="${1:-${MOD_ID:?MOD_ID required}}"
BUILD_DIR="${2:-build}"

OUTPUT_DIR="${GITHUB_WORKSPACE:-.}"

cd "${GITHUB_WORKSPACE:-.}"
cd "$BUILD_DIR"

# Read version from nox.mod.json (fallback to nox.mod.jsonc)
MANIFEST="nox.mod.json"
[ -f "$MANIFEST" ] || MANIFEST="nox.mod.jsonc"
VERSION=$(jq -r '.version' "$MANIFEST")
# Sanitize version for filename
VERSION="${VERSION//[^a-zA-Z0-9._-]/-}"

ARCHIVE="$MOD_ID-$VERSION.zip"
zip -r "$OUTPUT_DIR/$ARCHIVE" .
echo "Packaged: $OUTPUT_DIR/$ARCHIVE"
echo "$ARCHIVE"
ls -lh "$OUTPUT_DIR/$ARCHIVE"
