#!/bin/bash
# ────────────────────────────────────────────────────────────────
# setup-unity-project.sh — create project, resolve deps, place mod
#
# Expected inputs (env vars or args):
#   MOD_ID      — mod identifier (e.g. nox.network)
#   MOD_DIR     — path to the checked-out mod source
#   PROJECT_DIR — path to create the Unity project
#   UNITY_VER   — Unity version (default: 6000.4.4f1)
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_ID="${1:-${MOD_ID:?MOD_ID required}}"
MOD_DIR="${2:-${MOD_DIR:?MOD_DIR required}}"
PROJECT_DIR="${3:-project}"
UNITY_VER="${UNITY_VERSION:-6000.4.4f1}"

echo "Mod    : $MOD_ID"
echo "Source : $MOD_DIR"
echo "Project: $PROJECT_DIR"
echo "Unity  : $UNITY_VER"

# ── 0. Pick the mod manifest (nox.mod.json or nox.mod.jsonc) ──
MANIFEST="$MOD_DIR/nox.mod.json"
[ -f "$MANIFEST" ] || MANIFEST="$MOD_DIR/nox.mod.jsonc"
echo "Manifest: $MANIFEST"

# ── 1. Create Unity project structure ──────────────────────────
mkdir -p "$PROJECT_DIR/ProjectSettings" "$PROJECT_DIR/Packages" "$PROJECT_DIR/Assets"
echo "m_EditorVersion: $UNITY_VER" > "$PROJECT_DIR/ProjectSettings/ProjectVersion.txt"

# ── 2. Generate Packages/manifest.json (core Unity deps) ────────
cat > "$PROJECT_DIR/Packages/manifest.json" << 'MANIFEST'
{
  "dependencies": {
    "nox.loader": "https://github.com/AtelierVR/nox.loader.git",
    "nox.game.builder": "https://github.com/AtelierVR/nox.game.builder.git"
  }
}
MANIFEST

# ── 3. Resolve dependencies (fetch manifests via curl, no full clone) ──
DEPS=$(jq -r '[.relations[]? | select(.type == "depends" or .type == null) | .id] | .[]' \
  "$MANIFEST" 2>/dev/null || echo "")

for dep in $DEPS; do
  URL=$(jq -r --arg d "$dep" '.relations[]? | select(.id == $d) | .register // empty' "$MANIFEST")
  if [ -z "$URL" ]; then
    echo "::error::Missing register for dependency '$dep' in $MANIFEST"
    exit 1
  fi
  URL="${URL#git+}"; URL="${URL#upm:}"; URL="${URL#nuget:}"
  echo "  $dep → $URL"
  jq --arg d "$dep" --arg u "$URL" '.dependencies[$d] = $u' \
    "$PROJECT_DIR/Packages/manifest.json" > tmp.json && mv tmp.json "$PROJECT_DIR/Packages/manifest.json"
done

# ── 3b. Recursive: fetch manifests via curl, dedup by id+provides ──
BUILDER_DEPS="nox.loader nox.game.builder"
BUILDER_REGISTERS='{"nox.loader":"git+https://github.com/AtelierVR/nox.loader.git","nox.game.builder":"git+https://github.com/AtelierVR/nox.game.builder.git"}'
RESOLVED_DEPS="$DEPS $BUILDER_DEPS"
RESOLVED_IDS=""  # space-separated: id + all provides

# Helper: fetch manifest from raw.githubusercontent.com, try main then master,
# fallback to git ls-remote --symref for non-GitHub repos
fetch_manifest() {
  local repo="$1" mf id provides relations branch raw content branches
  repo="${repo#git+}"
  repo="${repo%%.git}"
  repo="${repo%%\?*}"
  local repo_path="${repo#https://github.com/}"

  # Try main/master for GitHub repos
  if [ "$repo_path" != "$repo" ]; then
    # It's a GitHub URL
    for branch in main master; do
      for mf in nox.mod.json nox.mod.jsonc package.json; do
        raw="https://raw.githubusercontent.com/$repo_path/refs/heads/$branch/$mf"
        content=$(curl -sL "$raw" 2>/dev/null)
        if echo "$content" | jq -e '.id or .name' > /dev/null 2>&1; then
          id=$(echo "$content" | jq -r '.id // .name // empty')
          provides=$(echo "$content" | jq -r '[.provides[]?] | join(" ")' 2>/dev/null)
          relations=$(echo "$content" | jq -c '[.relations[]? | {id,type,register}]' 2>/dev/null)
          echo "$id|$provides|$relations"
          return 0
        fi
      done
    done
  fi

  # Non-GitHub or both branches failed: detect default branch via git ls-remote
  local head_ref=$(git ls-remote --symref "$repo" HEAD 2>/dev/null | head -1 | sed 's|ref: refs/heads/||; s|[\t ]*HEAD||')
  if [ -n "$head_ref" ] && [ "$repo_path" != "$repo" ]; then
    for mf in nox.mod.json nox.mod.jsonc package.json; do
      raw="https://raw.githubusercontent.com/$repo_path/refs/heads/$head_ref/$mf"
      content=$(curl -sL "$raw" 2>/dev/null)
      if echo "$content" | jq -e '.id or .name' > /dev/null 2>&1; then
        id=$(echo "$content" | jq -r '.id // .name // empty')
        provides=$(echo "$content" | jq -r '[.provides[]?] | join(" ")' 2>/dev/null)
        relations=$(echo "$content" | jq -c '[.relations[]? | {id,type,register}]' 2>/dev/null)
        echo "$id|$provides|$relations"
        return 0
      fi
    done
  fi

  return 1
}

while [ -n "$RESOLVED_DEPS" ]; do
  NEW_DEPS=""
  for dep in $RESOLVED_DEPS; do
    # Dedup: skip if dep or any of its known provides already resolved
    case " $RESOLVED_IDS " in
      *" $dep "*) continue ;;
    esac

    # Get URL for this dep (from mod manifest, builder registers, or manifest.json)
    URL=$(jq -r --arg d "$dep" '.relations[]? | select(.id == $d) | .register // empty' "$MANIFEST")
    [ -z "$URL" ] && URL=$(echo "$BUILDER_REGISTERS" | jq -r --arg d "$dep" '.[$d] // empty')
    [ -z "$URL" ] && URL=$(jq -r --arg d "$dep" '.dependencies[$d] // empty' "$PROJECT_DIR/Packages/manifest.json")
    [ -z "$URL" ] && continue  # upm/nuget, can't recurse

    case "$URL" in
      git+*|http*)
        MANIFEST_DATA=$(fetch_manifest "$URL")
        if [ -z "$MANIFEST_DATA" ]; then
          echo "::error::Failed to fetch manifest for '$dep' from $URL"
          exit 1
        fi

        MID=$(echo "$MANIFEST_DATA" | cut -d'|' -f1)
        MPROV=$(echo "$MANIFEST_DATA" | cut -d'|' -f2)
        MRELS=$(echo "$MANIFEST_DATA" | cut -d'|' -f3)

        echo "  → resolving: $MID"
        # Mark id + all provides as resolved
        RESOLVED_IDS="$RESOLVED_IDS $MID $MPROV"

        # Process sub-deps
        if [ "$MRELS" != "null" ] && [ -n "$MRELS" ]; then
          echo "$MRELS" | jq -c '.[]' 2>/dev/null | while read -r rel; do
            sd=$(echo "$rel" | jq -r '.id // empty')
            sdt=$(echo "$rel" | jq -r '.type // "depends"')
            sdr=$(echo "$rel" | jq -r '.register // empty')
            [ -z "$sd" ] && continue
            [ -z "$sdr" ] && continue

            # Skip if sub-dep or any of its known IDs already in manifest
            if jq -e --arg d "$sd" '.dependencies[$d]' "$PROJECT_DIR/Packages/manifest.json" > /dev/null 2>&1; then
              continue
            fi

            sdr="${sdr#git+}"; sdr="${sdr#upm:}"; sdr="${sdr#nuget:}"
            echo "    $sd → $sdr"
            jq --arg d "$sd" --arg u "$sdr" '.dependencies[$d] = $u' \
              "$PROJECT_DIR/Packages/manifest.json" > tmp.json && mv tmp.json "$PROJECT_DIR/Packages/manifest.json"
            NEW_DEPS="$NEW_DEPS $sd"
          done
        fi
        ;;
    esac
  done
  RESOLVED_DEPS="$NEW_DEPS"
done

# ── Final pass: normalize keys to each package's own id ──
echo ""
echo "=== Normalizing manifest keys ==="
for key in $(jq -r '.dependencies | keys[]' "$PROJECT_DIR/Packages/manifest.json"); do
  URL=$(jq -r --arg k "$key" '.dependencies[$k]' "$PROJECT_DIR/Packages/manifest.json")
  case "$URL" in
    http*)
      MANIFEST_DATA=$(fetch_manifest "$URL")
      if [ -n "$MANIFEST_DATA" ]; then
        REAL_ID=$(echo "$MANIFEST_DATA" | cut -d'|' -f1)
        if [ -n "$REAL_ID" ] && [ "$REAL_ID" != "null" ] && [ "$REAL_ID" != "$key" ]; then
          echo "  $key → $REAL_ID"
          jq --arg old "$key" --arg new "$REAL_ID" --arg u "$URL" \
            'del(.dependencies[$old]) | .dependencies[$new] = $u' \
            "$PROJECT_DIR/Packages/manifest.json" > tmp.json && mv tmp.json "$PROJECT_DIR/Packages/manifest.json"
        fi
      fi
      ;;
  esac
done

echo ""
echo "=== Final manifest ==="
jq '.dependencies' "$PROJECT_DIR/Packages/manifest.json"

# ── 4. Place mod in Packages/ ──────────────────────────────────
mkdir -p "$PROJECT_DIR/Packages/$MOD_ID"
cp -r "$MOD_DIR"/* "$PROJECT_DIR/Packages/$MOD_ID/"
echo "Mod placed: Packages/$MOD_ID"
