#!/bin/bash
# ────────────────────────────────────────────────────────────────
# generate-packages.sh — zip all platform builds and emit
#   .files-{plat}.json entries for the merged manifest.
#
# Inputs: MOD_ID, MOD_VERSION, PLATFORMS
# Output: {mod_id}-{version}-{plat}.zip + .files-{plat}.json
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_ID="${MOD_ID:?MOD_ID required}"
MOD_VERSION="${MOD_VERSION:-}"
PLATFORMS="${PLATFORMS:?PLATFORMS required}"
OUTPUT_DIR="${GITHUB_WORKSPACE:-.}"

# GitHub info
REPO="${GITHUB_REPOSITORY:-unknown/unknown}"
TAG="${GITHUB_REF##*/}"; [ "$TAG" = "main" ] && TAG="v$MOD_VERSION"
DOWNLOAD_BASE="https://github.com/$REPO/releases/download/$TAG"

SAFE_VERSION="${MOD_VERSION//[^a-zA-Z0-9._-]/-}"

for plat in $PLATFORMS; do
    BUILD_DIR="project/build/$plat/$MOD_ID"
    ARCHIVE="$MOD_ID-$SAFE_VERSION-$plat.zip"

    echo "::group::Package: $MOD_ID ($plat)"

    cd "$BUILD_DIR"
    zip -qr "$OUTPUT_DIR/$ARCHIVE" .
    cd "$OUTPUT_DIR"

    HASH=$(sha256sum "$ARCHIVE" | cut -d' ' -f1)
    SIZE=$(stat -c%s "$ARCHIVE" 2>/dev/null || wc -c < "$ARCHIVE")

    # Write .files entry for manifest
    jq -n \
      --arg url "$DOWNLOAD_BASE/$ARCHIVE" \
      --arg platform "$plat" \
      --arg hash "sha256:$HASH" \
      --argjson size "$SIZE" \
      '{url: $url, platforms: [$platform], hash: $hash, size: $size}' \
      > ".files-$plat.json"

    echo "Packaged: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
    echo "::notice title=Package::$MOD_ID [$plat] packaged"
    echo "| $ARCHIVE | $(du -h "$ARCHIVE" | cut -f1) | \`$HASH\` |" >> "$GITHUB_STEP_SUMMARY"

    echo "::endgroup::"
done
