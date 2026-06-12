#!/usr/bin/env bash
# Validate that mod_id is not empty or null
set -euo pipefail

MOD_ID="${1:-}"
VERSION="${2:-}"
TAG="${3:-}"

echo "::group::Validate metadata"

VALID=true

# Check mod_id
if [ -z "$MOD_ID" ] || [ "$MOD_ID" = "null" ]; then
  echo "::error title=Validation::mod_id is empty or null"
  VALID=false
else
  echo "  mod_id : $MOD_ID ✓"
fi

# Check version
if [ -n "$VERSION" ] && [ "$VERSION" != "null" ]; then
  echo "  version: $VERSION ✓"
else
  echo "  version: missing or null"
fi

# Check tag
if [ -n "$TAG" ] && [ "$TAG" != "null" ]; then
  echo "  tag    : $TAG ✓"
fi

echo "valid=$VALID" >> "$GITHUB_OUTPUT"

if [ "$VALID" = "true" ]; then
  echo "::notice title=Validation::All checks passed for $MOD_ID"
else
  echo "::error title=Validation::One or more checks failed"
fi

echo "::endgroup::"
