#!/bin/bash
# compute-version.sh — semver from nox.mod.jsonc + branch
set -euo pipefail

BRANCH="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}"
MANIFEST="nox.mod.jsonc"
[ -f "$MANIFEST" ] || MANIFEST="nox.mod.json"
[ -f "$MANIFEST" ] || { echo "FAIL: nox.mod.json[c] not found"; exit 1; }

RAW=$(jq -r '.version' "$MANIFEST")
echo "version: $RAW  branch: $BRANCH"

suffix() { echo "$1" | sed 's/[^a-zA-Z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'; }

if [ -n "${VERSION_OVERRIDE:-}" ]; then
  RESOLVED="$VERSION_OVERRIDE"
else
  if [[ "$RAW" == *"x"* ]]; then
    MAJOR_MINOR="${RAW%%.x}"
    PREFIX="v${MAJOR_MINOR}."

    if [ "$BRANCH" = "main" ]; then
      LAST=$(git tag -l "${PREFIX}*" | { grep -v '\-' || true; } | sort -V | tail -1)
    else
      LAST=$(git tag -l "${PREFIX}*" | sort -V | tail -1)
    fi

    if [ -z "$LAST" ]; then NEXT_PATCH=0
    else
      PATCH=$(echo "$LAST" | sed "s/${PREFIX//./\\.}//; s/-.*//")
      NEXT_PATCH=$((PATCH + 1))
    fi
    RESOLVED="${MAJOR_MINOR}.${NEXT_PATCH}"
  else
    RESOLVED="$RAW"
  fi
fi

TAG="v${RESOLVED}"
PRERELEASE="false"

if [ "$BRANCH" != "main" ]; then
  TAG="${TAG}-$(suffix "$BRANCH")"
  PRERELEASE="true"
fi

echo "resolved=$RESOLVED" >> "$GITHUB_OUTPUT"
echo "tag=$TAG" >> "$GITHUB_OUTPUT"
echo "prerelease=$PRERELEASE" >> "$GITHUB_OUTPUT"
echo ">> $TAG (resolved: $RESOLVED, prerelease: $PRERELEASE)"
