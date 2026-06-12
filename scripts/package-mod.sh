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
MF=""
if [ -f "nox.mod.json" ]; then
    MF="nox.mod.json"
else
    echo "::error::No manifest found (nox.mod.json or nox.mod.jsonc) in $(pwd)"
    echo "Contents of $(pwd):"
    ls -la
    exit 1
fi
echo "::group::Package: $MOD_ID"
echo "Using manifest: $MF"

# Read version (arg > manifest)
if [ -n "$MOD_VERSION" ]; then
    VERSION="$MOD_VERSION"
else
    VERSION=$(jq -r '.version' "$MF")
fi
SAFE_VERSION="${VERSION//[^a-zA-Z0-9._-]/-}"
echo "Version: $VERSION (safe: $SAFE_VERSION)"
echo "Platform: $PLATFORM"

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
echo "Creating archive: $ARCHIVE"
zip -qr "$OUTPUT_DIR/$ARCHIVE" .
echo "Packaged: $OUTPUT_DIR/$ARCHIVE"
ls -lh "$OUTPUT_DIR/$ARCHIVE"

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

# ── Icon (null if empty) ──────────────────────────────────────
ICON=$(jq -r '.icon // empty' "$MF")
[ -z "$ICON" ] && ICON="null" || ICON="\"$ICON\""

# ── Build manifest.json step by step ──────────────────────────
jq -n '{}' \
  > "$OUTPUT_DIR/manifest.json"

# Helper: set a field
set_field() { jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$OUTPUT_DIR/manifest.json" > "$OUTPUT_DIR/manifest.tmp" && mv "$OUTPUT_DIR/manifest.tmp" "$OUTPUT_DIR/manifest.json"; }
set_json()  { jq --arg k "$1" --argjson v "$2" '.[$k] = $v' "$OUTPUT_DIR/manifest.json" > "$OUTPUT_DIR/manifest.tmp" && mv "$OUTPUT_DIR/manifest.tmp" "$OUTPUT_DIR/manifest.json"; }

set_field id "$MOD_ID"
set_json  provides "$(jq '[.provides[]?] // []' "$MF")"
set_field name "$NAME"
set_field description "$DESC"
set_field version "$VERSION"
set_field license "$LICENSE"
set_json  icon "$ICON"
set_field url "$DOWNLOAD_BASE/manifest.json"

# Author = repo owner
set_json author "$(jq -n \
  --arg name "$REPO_OWNER" \
  --arg url "https://github.com/$REPO_OWNER" \
  --arg github "$REPO_OWNER" \
  '{name: $name, url: $url, github: $github}')"

# Source
set_json source "$(jq -n --arg url "$MOD_SOURCE" '{type: "git", url: $url}')"

# Contributors = mod authors + contributors from nox.mod.json
set_json contributors "$(jq -s '.[0] + .[1]' \
  <(jq '[.authors[]? | {name, url: .website // "", github: (.website // "" | capture("github\\.com/(?<u>[^/]+)") | .u // "")}]' "$MF") \
  <(jq '[.contributors[]? | {name, url: .website, github: (.website // "" | capture("github\\.com/(?<u>[^/]+)") | .u // "")}] | if length > 0 then . else [] end' "$MF"))"

# Dependencies
set_json dependencies "$(jq '[.relations[]? | select(.type == "depends") | {(.id): .register}] | add // {}' "$MF")"

# Files: iterate over all zips found (future-proof)
set_json files "$(jq -n \
  --arg url "$DOWNLOAD_BASE/$ARCHIVE" \
  --arg platform "$PLATFORM" \
  --arg hash "sha256:$HASH" \
  --argjson size "$SIZE" \
  '[{url: $url, platforms: [$platform], hash: $hash, size: $size}]')"

# Generated timestamp
set_field generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Manifest: $OUTPUT_DIR/manifest.json"
ls -lh "$OUTPUT_DIR/$ARCHIVE" "$OUTPUT_DIR/manifest.json"

echo "::notice title=Package::$MOD_ID v$VERSION packaged ($(du -h "$OUTPUT_DIR/$ARCHIVE" | cut -f1))"

# Write to step summary
echo "## 📦 Package: $MOD_ID v$VERSION" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "| File | Size | SHA256 |" >> "$GITHUB_STEP_SUMMARY"
echo "|------|------|--------|" >> "$GITHUB_STEP_SUMMARY"
echo "| $ARCHIVE | $(du -h "$OUTPUT_DIR/$ARCHIVE" | cut -f1) | \`$HASH\` |" >> "$GITHUB_STEP_SUMMARY"
echo "| manifest.json | $(du -h "$OUTPUT_DIR/manifest.json" | cut -f1) | |" >> "$GITHUB_STEP_SUMMARY"

echo "::endgroup::"
