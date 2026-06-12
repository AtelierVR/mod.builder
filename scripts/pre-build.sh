#!/usr/bin/env bash
# Pre-build notice
set -euo pipefail

MOD_ID="$1"
VERSION="$2"

echo "::group::Pre-build"
echo "┌──────────────────────────────────────────────┐"
echo "│  Mod     : $MOD_ID"
echo "│  Version : $VERSION"
echo "│  Unity   : ${UNITY_VERSION:-6000.4.4f1}"
echo "│  Target  : ${TARGET_PLATFORM:-StandaloneWindows64}"
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

echo "::endgroup::"
