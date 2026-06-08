#!/bin/bash
# ────────────────────────────────────────────────────────────────
# package-mod.sh — zip the built mod + generate manifest.json
#
# Inputs: MOD_ID, BUILD_DIR, MOD_VERSION, PLATFORM
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_ID="${1:-${MOD_ID:?MOD_ID required}}"
BUILD_DIR="${2:-build}"
MOD_VERSION="${3:-}"
PLATFORM="${4:-full}"

OUTPUT_DIR="${GITHUB_WORKSPACE:-.}"

cd "${GITHUB_WORKSPACE:-.}"
cd "$BUILD_DIR"

# ── Read mod manifest ─────────────────────────────────────────
MF="nox.mod.json"
[ -f "$MF" ] || MF="nox.mod.jsonc"

# Read version (arg > manifest)
if [ -n "$MOD_VERSION" ]; then
    VERSION="$MOD_VERSION"
else
    VERSION=$(jq -r '.version' "$MF")
fi
SAFE_VERSION="${VERSION//[^a-zA-Z0-9._-]/-}"

MOD_NAME=$(jq -r '.name // .id' "$MF")
MOD_DESC=$(jq -r '.description // ""' "$MF")
MOD_AUTHOR=$(jq -r '.authors[0].name // ""' "$MF")
MOD_AUTHOR_URL=$(jq -r '.authors[0].website // ""' "$MF")

# ── Zip ───────────────────────────────────────────────────────
ARCHIVE="$MOD_ID-$SAFE_VERSION-$PLATFORM.zip"
zip -qr "$OUTPUT_DIR/$ARCHIVE" .
echo "Packaged: $OUTPUT_DIR/$ARCHIVE"

# ── Hash & size ───────────────────────────────────────────────
HASH=$(sha256sum "$OUTPUT_DIR/$ARCHIVE" | cut -d' ' -f1)
SIZE=$(stat -c%s "$OUTPUT_DIR/$ARCHIVE" 2>/dev/null || wc -c < "$OUTPUT_DIR/$ARCHIVE")

# ── GitHub repo info ──────────────────────────────────────────
REPO="${GITHUB_REPOSITORY:-unknown}"
REPO_OWNER="${REPO%%/*}"

# ── Generate manifest.json ────────────────────────────────────
cat > "$OUTPUT_DIR/manifest.json" << MANIFEST
{
  "id": "$MOD_ID",
  "name": "$MOD_NAME",
  "description": "$MOD_DESC",
  "version": "$VERSION",
  "author": {
    "name": "$MOD_AUTHOR",
    "url": "$MOD_AUTHOR_URL",
    "github": "$REPO_OWNER"
  },
  "contributors": $(jq '[.contributors[]? | {name, url: .website, github: (.website | capture("github\\.com/(?<u>[^/]+)") | .u // "")}] | if length > 0 then . else [] end' "$MF"),
  "dependencies": $(jq '[.relations[]? | select(.type == "depends") | {(.id): .version // "*"}] | add // {}' "$MF"),
  "files": [
    {
      "file": "$ARCHIVE",
      "platform": "full",
      "hash": "sha256:$HASH",
      "size": $SIZE
    }
  ],
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
MANIFEST

echo "Manifest: $OUTPUT_DIR/manifest.json"
ls -lh "$OUTPUT_DIR/$ARCHIVE" "$OUTPUT_DIR/manifest.json"
