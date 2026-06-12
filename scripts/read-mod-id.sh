#!/usr/bin/env bash
# Read mod id from nox.mod.json (or .jsonc) manifest
set -euo pipefail

echo "::group::Read mod id"

MANIFEST="nox.mod.json"
if [ -f "$MANIFEST" ]; then
  echo "Using manifest: $MANIFEST"
else
  MANIFEST="nox.mod.jsonc"
  echo "Using manifest: $MANIFEST"
fi

if [ ! -f "$MANIFEST" ]; then
  echo "::error title=Prepare::No manifest found (nox.mod.json or nox.mod.jsonc)"
  exit 1
fi

MOD_ID=$(jq -r '.id' "$MANIFEST")
echo "mod_id=$MOD_ID" >> "$GITHUB_OUTPUT"
echo "Mod ID: $MOD_ID"

# Also extract metadata for summary
MOD_NAME=$(jq -r '.name // .id' "$MANIFEST")
MOD_DESC=$(jq -r '.description // ""' "$MANIFEST")
MOD_VERSION=$(jq -r '.version' "$MANIFEST")

echo "name=$MOD_NAME" >> "$GITHUB_OUTPUT"
echo "description=$MOD_DESC" >> "$GITHUB_OUTPUT"
echo "manifest_version=$MOD_VERSION" >> "$GITHUB_OUTPUT"

echo "::notice title=Prepare::$MOD_NAME ($MOD_ID) detected"
echo "::endgroup::"
