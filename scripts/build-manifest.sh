#!/bin/bash
# ────────────────────────────────────────────────────────────────
# build-manifest.sh — generate a single manifest.json that
#   references all platforms' nox.mod.json files.
#
# Inputs: MOD_ID, MOD_VERSION, PLATFORMS
# Output: manifest.json
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_ID="${MOD_ID:?MOD_ID required}"
MOD_VERSION="${MOD_VERSION:-}"
PLATFORMS="${PLATFORMS:?PLATFORMS required}"

echo '{' > manifest.json
echo "  \"id\": \"$MOD_ID\"," >> manifest.json
echo "  \"version\": \"$MOD_VERSION\"," >> manifest.json
echo '  "platforms": {' >> manifest.json

first=true
for plat in $PLATFORMS; do
    mf="project/build/$plat/$MOD_ID/nox.mod.json"
    if [ -f "$mf" ]; then
        [ "$first" = true ] && first=false || echo "," >> manifest.json
        echo -n "    \"$plat\": $(jq -c '.' "$mf")" >> manifest.json
    fi
done

echo '' >> manifest.json
echo '  }' >> manifest.json
echo '}' >> manifest.json

echo "Generated manifest.json:"
cat manifest.json
