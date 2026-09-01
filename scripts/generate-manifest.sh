#!/bin/bash
# ────────────────────────────────────────────────────────────────
# generate-manifest.sh — one-shot manifest.json for all platforms
#
# Collects .files-{plat}.json (from package-mod.sh), reads
# nox.mod.json for metadata, outputs manifest.json.
#
# Inputs: MOD_ID, MOD_VERSION, PLATFORMS, GH_NAME, GH_DESC, GH_LICENSE
# Output: manifest.json
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_ID="${MOD_ID:?MOD_ID required}"
MOD_VERSION="${MOD_VERSION:-}"
PLATFORMS="${PLATFORMS:?PLATFORMS required}"

# ── Find nox.mod.json ────────────────────────────────────────
MF=""
for plat in $PLATFORMS; do
    candidate="project/build/$plat/$MOD_ID/nox.mod.json"
    if [ -f "$candidate" ]; then MF="$candidate"; break; fi
done
if [ -z "$MF" ]; then echo "::error::No nox.mod.json found for $MOD_ID"; exit 1; fi

# ── GitHub info ───────────────────────────────────────────────
REPO="${GITHUB_REPOSITORY:-unknown/unknown}"
REPO_OWNER="${REPO%%/*}"
TAG="${GITHUB_REF##*/}"; [ "$TAG" = "main" ] && TAG="v$MOD_VERSION"
DOWNLOAD_BASE="https://github.com/$REPO/releases/download/$TAG"

# ── Metadata from nox.mod.json ────────────────────────────────
MOD_NAME=$(jq -r '.name // .id' "$MF")
MOD_DESC=$(jq -r '.description // ""' "$MF")
MOD_SOURCE=$(jq -r '.contact.source // ""' "$MF")

NAME="${GH_NAME:-$MOD_NAME}"
DESC="${GH_DESC:-$MOD_DESC}"
LICENSE="${GH_LICENSE:-$(jq -r '.license // ""' "$MF")}"
ICON=$(jq -r '.icon // empty' "$MF")
[ -z "$ICON" ] && ICON="null" || ICON="\"$ICON\""

# ── Collect .files-*.json ─────────────────────────────────────
FILES="["; first=true
for plat in $PLATFORMS; do
    ff=".files-$plat.json"
    if [ -f "$ff" ]; then
        [ "$first" = true ] && first=false || FILES="$FILES,"
        FILES="$FILES$(cat "$ff")"; rm "$ff"
    fi
done
FILES="$FILES]"

# ── Fetch GitHub contributors (actual committers) ─────────────
GH_CONTRIBUTORS="[]"
if [ "$REPO" != "unknown/unknown" ]; then
  GH_CONTRIBUTORS="$(curl -sL --max-time 15 "https://api.github.com/repos/$REPO/contributors?per_page=100" 2>/dev/null \
    | jq -c '[.[]? | select(.login != null) | select(.login | test("\\[bot\\]$") | not) | {name: .login, url: ("https://github.com/" + .login), github: .login}] // []' 2>/dev/null)"
  [ -z "$GH_CONTRIBUTORS" ] && GH_CONTRIBUTORS="[]"
fi

# Contributors = declared contributors + actual GitHub committers (deduped),
# minus the author (REPO_OWNER). Authors are NOT merged into contributors.
CONTRIBUTORS_JSON="$(jq '[.contributors[]? | {name, url: .website, github: (.website // "" | capture("github\\.com/(?<u>[^/]+)") | .u // "")}] + $gh | unique_by(.github) | map(select(.github != $author))' "$MF" \
  --argjson gh "$GH_CONTRIBUTORS" \
  --arg author "$REPO_OWNER")"

# ── Generate manifest.json ────────────────────────────────────
jq -n \
  --arg id "$MOD_ID" \
  --argjson provides "$(jq '[.provides[]?] // []' "$MF")" \
  --arg name "$NAME" \
  --arg description "$DESC" \
  --arg version "$MOD_VERSION" \
  --arg license "$LICENSE" \
  --argjson icon "$ICON" \
  --arg url "$DOWNLOAD_BASE/manifest.json" \
  --arg repo_owner "$REPO_OWNER" \
  --arg mod_source "$MOD_SOURCE" \
  --argjson dependencies "$(jq '[.relations[]? | select(.type == "depends") | {(.id): .register}] | add // {}' "$MF")" \
  --argjson contributors "$CONTRIBUTORS_JSON" \
  --argjson files "$FILES" \
  --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    id: $id,
    provides: $provides,
    name: $name,
    description: $description,
    version: $version,
    license: $license,
    icon: $icon,
    url: $url,
    author: { name: $repo_owner, url: "https://github.com/\($repo_owner)", github: $repo_owner },
    source: { type: "git", url: $mod_source },
    contributors: $contributors,
    dependencies: $dependencies,
    files: $files,
    generated: $generated
  }' > manifest.json

echo "Generated manifest.json:"
cat manifest.json
