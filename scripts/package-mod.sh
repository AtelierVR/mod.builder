#!/bin/bash
# ────────────────────────────────────────────────────────────────
# package-mod.sh — zip the built mod into .noxmod
#
# Inputs: MOD_ID, BUILD_DIR (path to Packages/<id>/build/<id>/)
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_ID="${1:-${MOD_ID:?MOD_ID required}}"
BUILD_DIR="${2:-build}"

OUTPUT_DIR="${GITHUB_WORKSPACE:-.}"

cd "$BUILD_DIR"
zip -r "$OUTPUT_DIR/$MOD_ID.noxmod" .
echo "Packaged: $OUTPUT_DIR/$MOD_ID.noxmod"
ls -lh "$OUTPUT_DIR/$MOD_ID.noxmod"
