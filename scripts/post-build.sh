#!/usr/bin/env bash
# Post-build: list build output and write step summary
set -euo pipefail

MOD_ID="$1"
OUTPUT="project/build/$MOD_ID"

echo "::group::Post-build"

echo "Expected output: $(realpath "$OUTPUT" 2>/dev/null || echo "$OUTPUT")"

if [ -d "$OUTPUT" ]; then
  echo "--- Contents of $OUTPUT ---"
  ls -laR "$OUTPUT"
  echo "--- Summary ---"
  DLLS=$(find "$OUTPUT" -name "*.dll" | wc -l)
  BUNDLES=$(find "$OUTPUT" -name "*.assets" -o -name "*.scenes" -o -name "*.scriptables" | wc -l)
  echo "DLLs: $DLLS  AssetBundles: $BUNDLES"
  echo "::notice title=Post-build::$MOD_ID built ($DLLS DLLs, $BUNDLES bundles)"

  # Append to step summary
  echo "## 📦 Build Output" >> "$GITHUB_STEP_SUMMARY"
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "| Artifact | Count |" >> "$GITHUB_STEP_SUMMARY"
  echo "|----------|-------|" >> "$GITHUB_STEP_SUMMARY"
  echo "| DLLs | $DLLS |" >> "$GITHUB_STEP_SUMMARY"
  echo "| AssetBundles | $BUNDLES |" >> "$GITHUB_STEP_SUMMARY"
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "### Files" >> "$GITHUB_STEP_SUMMARY"
  echo '```' >> "$GITHUB_STEP_SUMMARY"
  find "$OUTPUT" -type f -exec ls -lh {} \; | awk '{print $5, $NF}' >> "$GITHUB_STEP_SUMMARY"
  echo '```' >> "$GITHUB_STEP_SUMMARY"
else
  echo "::warning title=Post-build::Build output folder not found: $OUTPUT"
  echo "--- Contents of project/build/ (if any) ---"
  ls -laR project/build/ 2>/dev/null || echo "(build folder does not exist)"

  echo "## ⚠️ Build Failed" >> "$GITHUB_STEP_SUMMARY"
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "Output folder not found: \`$OUTPUT\`" >> "$GITHUB_STEP_SUMMARY"
fi

echo "::endgroup::"
