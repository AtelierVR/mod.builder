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

echo "::group::Setup Unity project"
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
    "nox.game.builder": "https://github.com/AtelierVR/nox.game.builder.git",
    "nox.editor": "https://github.com/AtelierVR/nox.editor.git"
  }
}
MANIFEST

# ── 3. Resolve dependencies (fetch manifests via curl, no full clone) ──
echo "::group::Resolve dependencies"
DEPS=$(jq -r '[.relations[]? | select(.type == "depends" or .type == null) | .id] | .[]' \
  "$MANIFEST" 2>/dev/null || echo "")

for dep in $DEPS; do
  URL=$(jq -r --arg d "$dep" '.relations[]? | select(.id == $d) | .register // empty' "$MANIFEST")
  if [ -z "$URL" ]; then
    echo "::error::Missing register for dependency '$dep' in $MANIFEST"
    exit 1
  fi
  # Strip scheme, extract version for upm+
  case "$URL" in
    git+*)   URL="${URL#git+}" ;;
    upm+*)   URL="${URL##*@}" ;;
    upm:*)   URL="${URL#upm:}" ;;
    nuget:*) URL="${URL#nuget:}" ;;
  esac
  MANIFEST_URL="$URL"
  echo "  $dep → $MANIFEST_URL"
  jq --arg d "$dep" --arg u "$MANIFEST_URL" '.dependencies[$d] = $u' \
    "$PROJECT_DIR/Packages/manifest.json" > tmp.json && mv tmp.json "$PROJECT_DIR/Packages/manifest.json"
done

# ── 3b. Recursive: fetch manifests via curl, dedup by id+provides ──
BUILDER_DEPS="nox.loader nox.game.builder nox.editor"
BUILDER_REGISTERS='{"nox.loader":"git+https://github.com/AtelierVR/nox.loader.git","nox.game.builder":"git+https://github.com/AtelierVR/nox.game.builder.git","nox.editor":"git+https://github.com/AtelierVR/nox.editor.git"}'
RESOLVED_DEPS="$DEPS $BUILDER_DEPS"
# Skip the mod being built (already placed via file:) — include its id + all provides
MOD_PROVIDES=$(jq -r '[.provides[]?] | join(" ")' "$MANIFEST" 2>/dev/null || echo "")
RESOLVED_IDS="$MOD_ID $MOD_PROVIDES"

# Helper: fetch manifest via git clone --depth 1 (single strategy, all hosts)
fetch_manifest() {
  local repo="$1" mf id provides relations subpath
  repo="${repo#git+}"

  # UPM: fetch from package registry. Format: upm+<url>[@<version>]
  # Default server: https://packages.unity.com/
  case "$repo" in
    upm:*|upm+*)
      local upm_url="$repo"
      upm_url="${upm_url#upm+}"
      upm_url="${upm_url#upm:}"
      local upm_version=""
      case "$upm_url" in
        *@*)
          upm_version="${upm_url##*@}"
          upm_url="${upm_url%@*}"
          ;;
      esac
      case "$upm_url" in
        http*) ;;
        *) upm_url="https://packages.unity.com/$upm_url" ;;
      esac
      local content=$(curl -sL "$upm_url" 2>/dev/null)
      if echo "$content" | jq -e '.name or .id' > /dev/null 2>&1; then
        id=$(echo "$content" | jq -r '.name // .id // empty')
        # Resolve version: use provided, or "@latest", or latest from server
        if [ -z "$upm_version" ] || [ "$upm_version" = "latest" ]; then
          upm_version=$(echo "$content" | jq -r '.["dist-tags"].latest // .version // empty')
        fi
        provides=""
        relations=$(echo "$content" | jq -c '[.dependencies | to_entries[]? | {id: .key, type: "depends", register: ("upm+" + .value)}]' 2>/dev/null)
        echo "$id|$provides|$relations|$upm_version"
        return 0
      fi
      return 1
      ;;
  esac

  # Git: clone --depth 1, extract subpath from ?path=...
  subpath=""
  case "$repo" in
    *\?path=*)
      subpath="/${repo#*\?path=}"
      subpath="${subpath%%\?*}"
      ;;
  esac
  repo="${repo%%\?*}"
  repo="${repo%%.git}"

  local TMPDIR=$(mktemp -d)
  local attempt=0
  local clone_url="$repo"
  # Authenticated clone avoids GitHub anonymous-clone throttling on runners
  if [ -n "${GITHUB_TOKEN:-}" ] && [ "${clone_url#https://github.com/}" != "$clone_url" ]; then
    clone_url="https://x-access-token:${GITHUB_TOKEN}@${clone_url#https://}"
  fi
  # GIT_LFS_SKIP_SMUDGE: runners may lack git-lfs; we only need nox.mod.json (not LFS)
  while ! GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 "$clone_url" "$TMPDIR" 2>/dev/null; do
    attempt=$((attempt+1))
    [ "$attempt" -ge 5 ] && break
    sleep $((attempt * 2))
  done
  for mf in "$TMPDIR$subpath/nox.mod.json" "$TMPDIR$subpath/nox.mod.jsonc" "$TMPDIR$subpath/package.json" "$TMPDIR/nox.mod.json" "$TMPDIR/nox.mod.jsonc" "$TMPDIR/package.json"; do
    if [ -f "$mf" ]; then
      id=$(jq -r '.id // .name // empty' "$mf" 2>/dev/null)
      if [ -n "$id" ] && [ "$id" != "null" ]; then
        provides=$(jq -r '[.provides[]?] | join(" ")' "$mf" 2>/dev/null)
        relations=$(jq -c '[.relations[]? | {id,type,register}]' "$mf" 2>/dev/null)
        echo "$id|$provides|$relations"
        rm -rf "$TMPDIR"
        return 0
      fi
    fi
  done
  rm -rf "$TMPDIR"

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
        MANIFEST_DATA=$(fetch_manifest "$URL") || true
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

        # Process sub-deps (avoid pipe subshell with for loop)
        if [ "$MRELS" != "null" ] && [ -n "$MRELS" ]; then
          for rel in $(echo "$MRELS" | jq -c '.[]' 2>/dev/null); do
            sd=$(echo "$rel" | jq -r '.id // empty')
            sdt=$(echo "$rel" | jq -r '.type // "depends"')
            sdr=$(echo "$rel" | jq -r '.register // empty')
            [ -z "$sd" ] && continue
            [ -z "$sdr" ] && continue

            # Skip if sub-dep or any of its known IDs already in manifest
            if jq -e --arg d "$sd" '.dependencies[$d]' "$PROJECT_DIR/Packages/manifest.json" > /dev/null 2>&1; then
              continue
            fi

            case "$sdr" in
              git+*)   sdr="${sdr#git+}" ;;
              upm+*)   sdr="${sdr##*@}" ;;
              upm:*)   sdr="${sdr#upm:}" ;;
              nuget:*) sdr="${sdr#nuget:}" ;;
            esac
            MURL="$sdr"
            echo "    $sd → $MURL"
            jq --arg d "$sd" --arg u "$MURL" '.dependencies[$d] = $u' \
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
      MANIFEST_DATA=$(fetch_manifest "$URL") || true
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
cat "$PROJECT_DIR/Packages/manifest.json"

# ── Annotate: list all deps with registers ──
DEPS_COUNT=$(jq '.dependencies | length' "$PROJECT_DIR/Packages/manifest.json")
echo "::notice title=Dependencies::$DEPS_COUNT dependencies resolved"
jq -r '.dependencies | to_entries[] | "::group::\(.key)\n  register: \(.value)\n::endgroup::"' "$PROJECT_DIR/Packages/manifest.json"

# ── 4. Place mod in Packages/ and add file: entry to manifest ──
mkdir -p "$PROJECT_DIR/Packages/$MOD_ID"
cp -r "$MOD_DIR"/* "$PROJECT_DIR/Packages/$MOD_ID/"
echo "Mod placed: Packages/$MOD_ID"

# Register the mod as a file: dependency so Unity resolves it locally
jq --arg id "$MOD_ID" --arg path "file:Packages/$MOD_ID" \
  '.dependencies[$id] = $path' \
  "$PROJECT_DIR/Packages/manifest.json" > tmp.json && mv tmp.json "$PROJECT_DIR/Packages/manifest.json"
echo "Manifest: added file:Packages/$MOD_ID for $MOD_ID"
