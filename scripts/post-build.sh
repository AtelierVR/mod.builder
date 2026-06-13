#!/usr/bin/env bash
# Post-build: list build output per platform and write step summary
set -euo pipefail

MOD_ID="$1"
PLATFORMS="${PLATFORMS:-windows linux}"

echo "::group::Post-build"

total_dlls=0
total_bundles=0
found_any=false

for plat in $PLATFORMS; do
  OUTPUT="project/build/$plat/$MOD_ID"
  echo "--- [$plat] Expected: $(realpath "$OUTPUT" 2>/dev/null || echo "$OUTPUT") ---"

  if [ -d "$OUTPUT" ]; then
    found_any=true
    echo "Contents:"
    ls -laR "$OUTPUT"
    DLLS=$(find "$OUTPUT" -name "*.dll" | wc -l)
    BUNDLES=$(find "$OUTPUT" -name "*.assets" -o -name "*.scenes" -o -name "*.scriptables" | wc -l)
    total_dlls=$((total_dlls + DLLS))
    total_bundles=$((total_bundles + BUNDLES))
    echo "[$plat] DLLs: $DLLS  AssetBundles: $BUNDLES"
  else
    echo "::warning title=Post-build::$MOD_ID [$plat] output not found: $OUTPUT"
  fi
done

if [ "$found_any" = true ]; then
  echo "::notice title=Post-build::$MOD_ID built ($total_dlls DLLs, $total_bundles bundles)"

  echo "## 📦 Build Output" >> "$GITHUB_STEP_SUMMARY"
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "| Platform | DLLs | Bundles |" >> "$GITHUB_STEP_SUMMARY"
  echo "|----------|------|---------|" >> "$GITHUB_STEP_SUMMARY"
  for plat in $PLATFORMS; do
    OUTPUT="project/build/$plat/$MOD_ID"
    if [ -d "$OUTPUT" ]; then
      DLLS=$(find "$OUTPUT" -name "*.dll" | wc -l)
      BUNDLES=$(find "$OUTPUT" -name "*.assets" -o -name "*.scenes" -o -name "*.scriptables" | wc -l)
      echo "| $plat | $DLLS | $BUNDLES |" >> "$GITHUB_STEP_SUMMARY"
    fi
  done
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "### Files" >> "$GITHUB_STEP_SUMMARY"
  echo '```' >> "$GITHUB_STEP_SUMMARY"
  for plat in $PLATFORMS; do
    OUTPUT="project/build/$plat/$MOD_ID"
    [ -d "$OUTPUT" ] && find "$OUTPUT" -type f -exec ls -lh {} \; | awk '{print $5, $NF}' >> "$GITHUB_STEP_SUMMARY"
  done
  echo '```' >> "$GITHUB_STEP_SUMMARY"
else
  echo "::warning title=Post-build::No build output found for $MOD_ID"
  echo "--- Contents of project/build/ ---"
  ls -laR project/build/ 2>/dev/null || echo "(build folder does not exist)"

  echo "## ⚠️ Build Failed" >> "$GITHUB_STEP_SUMMARY"
  echo "" >> "$GITHUB_STEP_SUMMARY"
  echo "No output found for \`$MOD_ID\`" >> "$GITHUB_STEP_SUMMARY"
fi

echo "::endgroup::"
