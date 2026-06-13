#!/bin/bash
# ────────────────────────────────────────────────────────────────
# package-all-platforms.sh — loop through all platforms and
#   call package-mod.sh for each.
#
# Inputs: MOD_ID, MOD_VERSION, PLATFORMS, GH_NAME, GH_DESC, GH_LICENSE
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_ID="${MOD_ID:?MOD_ID required}"
MOD_VERSION="${MOD_VERSION:-}"
PLATFORMS="${PLATFORMS:?PLATFORMS required}"

for plat in $PLATFORMS; do
    echo "::group::Package: $MOD_ID ($plat)"
    bash .mod-builder/scripts/package-mod.sh \
        "$MOD_ID" \
        "project/build/$plat/$MOD_ID" \
        "$MOD_VERSION" \
        "$plat"
    echo "::endgroup::"
done
