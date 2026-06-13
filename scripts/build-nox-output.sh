#!/bin/bash
# ────────────────────────────────────────────────────────────────
# build-nox-output.sh — convert space-separated platforms to
#   --noxOutput format: "windows=build/windows,linux=build/linux"
#
# Input:  PLATFORMS (space-separated, e.g. "windows linux")
# Output: GITHUB_OUTPUT key "args"
# ────────────────────────────────────────────────────────────────
set -euo pipefail

PLATFORMS="${PLATFORMS:-$1}"

args=""
for plat in $PLATFORMS; do
    [ -n "$args" ] && args="$args,"
    args="${args}${plat}=build/${plat}"
done

echo "args=$args" >> "${GITHUB_OUTPUT:-/dev/stdout}"
echo "noxOutput=$args"
