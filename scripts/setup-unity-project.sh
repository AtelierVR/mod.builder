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

# ── 1. Create Unity project structure ──────────────────────────
mkdir -p "$PROJECT_DIR/ProjectSettings" "$PROJECT_DIR/Packages" "$PROJECT_DIR/Assets"
echo "m_EditorVersion: $UNITY_VER" > "$PROJECT_DIR/ProjectSettings/ProjectVersion.txt"

# ── 2. Generate Packages/manifest.json (core Unity deps) ────────
cat > "$PROJECT_DIR/Packages/manifest.json" << 'MANIFEST'
{
  "dependencies": {
    "com.cysharp.unitask": "https://github.com/Cysharp/UniTask.git?path=src/UniTask/Assets/Plugins/UniTask",
    "com.unity.nuget.newtonsoft-json": "3.2.2",
    "com.unity.2d.sprite": "1.0.0",
    "com.unity.animation.rigging": "1.4.1",
    "com.unity.inputsystem": "1.19.0",
    "com.unity.render-pipelines.universal": "17.5.0",
    "com.unity.scriptablebuildpipeline": "2.6.1",
    "com.unity.ugui": "2.0.0",
    "com.unity.xr.openxr": "1.17.0-pre.1"
  }
}
MANIFEST

# ── 3. Resolve dependencies from registers ─────────────────────
DEPS=$(jq -r '[.relations[]? | select(.type == "depends" or .type == null) | .id] | .[]' \
  "$MOD_DIR/nox.mod.jsonc" 2>/dev/null || echo "")

for dep in $DEPS; do
  URL=$(jq -r --arg d "$dep" '.registers[$d] // empty' "$MOD_DIR/nox.mod.jsonc")
  if [ -z "$URL" ]; then
    echo "  $dep → NOT FOUND in registers — skipping"
    continue
  fi

  # Strip scheme prefix
  URL="${URL#git+}"
  URL="${URL#upm:}"
  URL="${URL#nuget:}"
  echo "  $dep → $URL"

  jq --arg d "$dep" --arg u "$URL" '.dependencies[$d] = $u' \
    "$PROJECT_DIR/Packages/manifest.json" > tmp.json \
    && mv tmp.json "$PROJECT_DIR/Packages/manifest.json"
done

echo ""
echo "=== Final manifest ==="
jq '.dependencies' "$PROJECT_DIR/Packages/manifest.json"

# ── 4. Place mod in Packages/ ──────────────────────────────────
mkdir -p "$PROJECT_DIR/Packages/$MOD_ID"
cp -r "$MOD_DIR"/* "$PROJECT_DIR/Packages/$MOD_ID/"
echo "Mod placed: Packages/$MOD_ID"
