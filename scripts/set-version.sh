#!/usr/bin/env bash
# Set mod version in the project manifest
set -euo pipefail

MOD_ID="$1"
VERSION="$2"

echo "::group::Set version"

MANIFEST="project/Packages/$MOD_ID/nox.mod.json"
if [ -f "$MANIFEST" ]; then
  echo "Using manifest: $MANIFEST"
else
  MANIFEST="project/Packages/$MOD_ID/nox.mod.jsonc"
  if [ -f "$MANIFEST" ]; then
    echo "Using manifest: $MANIFEST"
  else
    echo "::error title=Set version::No manifest found for $MOD_ID in project/Packages/$MOD_ID/"
    ls -la "project/Packages/$MOD_ID/" 2>/dev/null || echo "(directory not found)"
    exit 1
  fi
fi

OLD_VERSION=$(jq -r '.version' "$MANIFEST")
echo "$MOD_ID: $OLD_VERSION → $VERSION"

jq --arg v "$VERSION" '.version = $v' "$MANIFEST" > tmp.json && mv tmp.json "$MANIFEST"
echo "::notice title=Version::$MOD_ID set to $VERSION"
echo "::endgroup::"
