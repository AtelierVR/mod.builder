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

# ── 3. Resolve dependencies from registers ─────────────────────
DEPS=$(jq -r '[.relations[]? | select(.type == "depends" or .type == null) | .id] | .[]' \
  "$MANIFEST" 2>/dev/null || echo "")

for dep in $DEPS; do
  URL=$(jq -r --arg d "$dep" '.relations[]? | select(.id == $d) | .register // empty' "$MANIFEST")
  if [ -z "$URL" ]; then
    echo "::error::Missing register for dependency '$dep' in $MANIFEST"
    exit 1
  fi

  # Strip scheme prefix
  URL="${URL#git+}"
  URL="${URL#upm:}"
  URL="${URL#nuget:}"
  echo "  $dep → $URL"

  # Verify git repos exist before adding to manifest
  case "$URL" in
    http*)
      # Strip UPM query params (?path=...) for git ls-remote
      VERIFY_URL="${URL%%\?*}"
      if ! git ls-remote --heads "$VERIFY_URL" &>/dev/null; then
        echo "::error::Git repository unreachable for '$dep': $VERIFY_URL"
        echo "::error::Check the register URL in $MANIFEST"
        exit 1
      fi
      ;;
  esac

  jq --arg d "$dep" --arg u "$URL" '.dependencies[$d] = $u' \
    "$PROJECT_DIR/Packages/manifest.json" > tmp.json \
    && mv tmp.json "$PROJECT_DIR/Packages/manifest.json"
done

# ── 3b. Recursive: resolve transitive deps from library manifests ──
# Include hardcoded builder deps in recursive resolution
BUILDER_DEPS="nox.loader nox.game.builder"
BUILDER_REGISTERS='{"nox.loader":"git+https://github.com/AtelierVR/nox.loader.git","nox.game.builder":"git+https://github.com/AtelierVR/nox.game.builder.git"}'
RESOLVED_DEPS="$DEPS $BUILDER_DEPS"
RESOLVED_IDS=""
while [ -n "$RESOLVED_DEPS" ]; do
  NEW_DEPS=""
  for dep in $RESOLVED_DEPS; do
    # Skip already-resolved deps (dedup: multiple manifests in same repo)
    case " $RESOLVED_IDS " in
      *" $dep "*) continue ;;
    esac
    RESOLVED_IDS="$RESOLVED_IDS $dep"

    # Only recurse into git dependencies (not upm/nuget)
    URL=$(jq -r --arg d "$dep" '.relations[]? | select(.id == $d) | .register // empty' "$MANIFEST")
    [ -z "$URL" ] && URL=$(echo "$BUILDER_REGISTERS" | jq -r --arg d "$dep" '.[$d] // empty')
    [ -z "$URL" ] && URL=$(jq -r --arg d "$dep" '.dependencies[$d] // empty' "$PROJECT_DIR/Packages/manifest.json")
    if [ -z "$URL" ]; then
      continue  # not a Nox library, no register to recurse into
    fi
    case "$URL" in
      git+*|http*)
        REPO_URL="${URL#git+}"
        # Strip UPM query params (?path=...) — git doesn't understand them
        CLONE_URL="${REPO_URL%%\?*}"
        # Use a unique temp dir
        TMPDIR=$(mktemp -d)
        if ! git clone --depth 1 "$CLONE_URL" "$TMPDIR" 2>/dev/null; then
          echo "::error::Failed to clone '$dep' from $CLONE_URL"
          echo "::error::Check that the repository exists and is accessible"
          rm -rf "$TMPDIR"
          exit 1
        fi
        for manifest in "$TMPDIR/nox.mod.json" "$TMPDIR/nox.mod.jsonc"; do
          [ -f "$manifest" ] || continue
          TYPE=$(jq -r '.type // "mod"' "$manifest")
          if [ "$TYPE" = "library" ] || [ "$TYPE" = "mod" ]; then
            echo "  → resolving library: $dep"
            SUB_DEPS=$(jq -r '[.relations[]? | .id] | .[]' "$manifest" 2>/dev/null || echo "")
            for sd in $SUB_DEPS; do
              SD_URL=$(jq -r --arg d "$sd" '.relations[]? | select(.id == $d) | .register // empty' "$manifest" 2>/dev/null)
              # Fallback: old-style top-level "registers" object
              [ -z "$SD_URL" ] && SD_URL=$(jq -r --arg d "$sd" '.registers[$d] // empty' "$manifest" 2>/dev/null)
              if [ -z "$SD_URL" ]; then
                echo "::error::Missing register for transitive dependency '$sd' of '$dep' in $manifest"
                exit 1
              fi
              # Already in manifest?
              if jq -e --arg d "$sd" '.dependencies[$d]' "$PROJECT_DIR/Packages/manifest.json" > /dev/null 2>&1; then
                continue
              fi
              SD_URL="${SD_URL#git+}"
              SD_URL="${SD_URL#upm:}"
              echo "    $sd → $SD_URL"
              jq --arg d "$sd" --arg u "$SD_URL" '.dependencies[$d] = $u' \
                "$PROJECT_DIR/Packages/manifest.json" > tmp.json && mv tmp.json "$PROJECT_DIR/Packages/manifest.json"
              NEW_DEPS="$NEW_DEPS $sd"
            done
          fi
        done
        rm -rf "$TMPDIR"
        ;;
    esac
  done
  RESOLVED_DEPS="$NEW_DEPS"
done

echo ""
echo "=== Final manifest ==="
jq '.dependencies' "$PROJECT_DIR/Packages/manifest.json"

# ── 4. Place mod in Packages/ ──────────────────────────────────
mkdir -p "$PROJECT_DIR/Packages/$MOD_ID"
cp -r "$MOD_DIR"/* "$PROJECT_DIR/Packages/$MOD_ID/"
echo "Mod placed: Packages/$MOD_ID"
