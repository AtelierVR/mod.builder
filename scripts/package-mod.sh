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
MOD_SOURCE=$(jq -r '.contact.source // ""' "$MF")

# ── Use GitHub metadata (fallback to nox.mod.json) ─────────────
NAME="${GH_NAME:-$MOD_NAME}"
DESC="${GH_DESC:-$MOD_DESC}"
LICENSE="${GH_LICENSE:-$(jq -r '.license // ""' "$MF")}"

# ── Zip ───────────────────────────────────────────────────────
ARCHIVE="$MOD_ID-$SAFE_VERSION-$PLATFORM.zip"
zip -qr "$OUTPUT_DIR/$ARCHIVE" .
echo "Packaged: $OUTPUT_DIR/$ARCHIVE"

# ── Hash & size ───────────────────────────────────────────────
HASH=$(sha256sum "$OUTPUT_DIR/$ARCHIVE" | cut -d' ' -f1)
SIZE=$(stat -c%s "$OUTPUT_DIR/$ARCHIVE" 2>/dev/null || wc -c < "$OUTPUT_DIR/$ARCHIVE")

# ── GitHub info ───────────────────────────────────────────────
REPO="${GITHUB_REPOSITORY:-unknown/unknown}"
REPO_OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
GIT_USER=$(echo "$MOD_SOURCE" | sed -n 's|.*github\.com/\([^/]*\)/.*|\1|p')
GIT_USER="${GIT_USER:-$REPO_OWNER}"

# ── Release tag (from GITHUB_REF or args) ─────────────────────
TAG="${GITHUB_REF##*/}"
[ "$TAG" = "main" ] && TAG="v$VERSION"
DOWNLOAD_BASE="https://github.com/$REPO/releases/download/$TAG"

# ── Fix contact URL (ensure https://) ─────────────────────────
CONTACT_URL=$(jq -r '.contact.website // ""' "$MF")
[ -z "$CONTACT_URL" ] && CONTACT_URL="$MOD_AUTHOR_URL"

# ── Generate manifest.json ────────────────────────────────────
cat > "$OUTPUT_DIR/manifest.json" << MANIFEST
{
  "id": "$MOD_ID",  
  "provides": $(jq '[.provides[]?] // []' "$MF"),
  "name": "$NAME",
  "description": "$DESC",
  "version": "$VERSION",
  "license": "$LICENSE",
  "icon": "$(jq -r '.icon // ""' "$MF")",
  "url": "$DOWNLOAD_BASE/manifest.json",
  "author": {
    "name": "$MOD_AUTHOR",
    "url": "$CONTACT_URL",
    "git": "$MOD_SOURCE",
    "github": "https://github.com/$GIT_USER"
  },
  "source": "$MOD_SOURCE",
  "contributors": $(jq '[.contributors[]? | {name, url: .website, git: (.website // "")}] | if length > 0 then . else [] end' "$MF"),
  "dependencies": $(jq '[.relations[]? | select(.type == "depends") | {(.id): .register}] | add // {}' "$MF"),
  "files": [
    {
      "file": "$ARCHIVE",
      "url": "$DOWNLOAD_BASE/$ARCHIVE",
      "platforms": ["$PLATFORM"],
      "hash": "sha256:$HASH",
      "size": $SIZE
    }
  ],
  "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
MANIFEST

echo "Manifest: $OUTPUT_DIR/manifest.json"
ls -lh "$OUTPUT_DIR/$ARCHIVE" "$OUTPUT_DIR/manifest.json"
