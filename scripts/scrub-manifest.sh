#!/bin/bash
# ────────────────────────────────────────────────────────────────
# scrub-manifest.sh — strip embedded credentials from build metadata
#
# setup-unity-project.sh injects the GH_PAT into the github dependency URLs of
# the generated Packages/manifest.json so the (containerised) Unity build can
# clone private packages. This removes those credentials again so they never
# end up in uploaded artifacts or caches.
# ────────────────────────────────────────────────────────────────
set -euo pipefail

for f in project/Packages/manifest.json project/Packages/packages-lock.json; do
  [ -f "$f" ] || continue
  sed -i -E 's#(https://)x-access-token:[^@]*@#\1#g' "$f"
  echo "scrubbed: $f"
done
