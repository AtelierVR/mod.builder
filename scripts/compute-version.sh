#!/bin/bash
# ────────────────────────────────────────────────────────────────
# compute-version.sh — semver from nox.mod.jsonc + branch
#
# Version field: "1.0.x" → auto-increment patch from git tags
#                 "1.0.0" → fixed, no increment
#
# Tag:  main        → v1.0.5
#       development → v1.0.5-dev
#       feature/x   → v1.0.5-feature-x
#
# VERSION_OVERRIDE env var skips auto-increment.
#
# Outputs: resolved, tag, prerelease
# ────────────────────────────────────────────────────────────────
set -euo pipefail

BRANCH="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}"
RAW=$(jq -r '.version' nox.mod.jsonc)

# Sanitize branch name for tag suffix
suffix() { echo "$1" | sed 's/[^a-zA-Z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'; }

if [ -n "${VERSION_OVERRIDE:-}" ]; then
  RESOLVED="$VERSION_OVERRIDE"
else
  if [[ "$RAW" == *"x"* ]]; then
    MAJOR_MINOR="${RAW%%.x}"
    PREFIX="v${MAJOR_MINOR}."

    # main counts only stable tags; others count all
    if [ "$BRANCH" = "main" ]; then
      LAST=$(git tag -l "${PREFIX}*" | grep -v '\-' | sort -V | tail -1)
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
echo "→ $TAG (resolved: $RESOLVED, prerelease: $PRERELEASE)"
