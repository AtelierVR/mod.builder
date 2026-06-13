#!/usr/bin/env bash
# Pre-build notice + generate --noxOutput args
set -euo pipefail

MOD_ID="$1"
VERSION="$2"
PLATFORMS="${PLATFORMS:-windows linux}"

echo "::group::Pre-build"
echo "┌──────────────────────────────────────────────┐"
echo "│  Mod       : $MOD_ID"
echo "│  Version   : $VERSION"
echo "│  Unity     : ${UNITY_VERSION:-6000.4.4f1}"
echo "│  Target    : ${TARGET_PLATFORM:-StandaloneWindows64}"
echo "│  Platforms : $PLATFORMS"
echo "└──────────────────────────────────────────────┘"
echo "::notice title=Build::$MOD_ID v$VERSION"

# Write summary header
echo "# 🔨 Build: $MOD_ID v$VERSION" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "| Key | Value |" >> "$GITHUB_STEP_SUMMARY"
echo "|-----|-------|" >> "$GITHUB_STEP_SUMMARY"
echo "| Mod | $MOD_ID |" >> "$GITHUB_STEP_SUMMARY"
echo "| Version | $VERSION |" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

# Build --noxOutput args
args=""
for plat in $PLATFORMS; do
    [ -n "$args" ] && args="$args,"
    args="${args}${plat}=build/${plat}"
done
echo "noxOutput=$args"
echo "args=$args" >> "${GITHUB_OUTPUT:-/dev/stdout}"

echo "::endgroup::"
