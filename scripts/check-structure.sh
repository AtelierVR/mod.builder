#!/bin/bash
# ────────────────────────────────────────────────────────────────
# check-structure.sh — validate mod structure
#
# Checks:
#   1. package.json exists
#   2. nox.mod.json[c] exists
#   3. Root .asmdef exists (in repo root or SDK/)
#   4. Entrypoints reference existing assemblies
#
# Exits 1 if any check fails.
# ────────────────────────────────────────────────────────────────
set -euo pipefail

MOD_DIR="${1:-.}"
ERRORS=0

check() {
  if [ "$1" -ne 0 ]; then
    echo "  [FAIL] $2"
    ERRORS=$((ERRORS + 1))
  else
    echo "  [OK]   $2"
  fi
}

echo "=== Checking mod structure: $MOD_DIR ==="

# 1. package.json
test -f "$MOD_DIR/package.json"
check $? "package.json"

# 2. nox.mod.jsonc or nox.mod.json
MANIFEST=""
if [ -f "$MOD_DIR/nox.mod.jsonc" ]; then
  MANIFEST="$MOD_DIR/nox.mod.jsonc"
elif [ -f "$MOD_DIR/nox.mod.json" ]; then
  MANIFEST="$MOD_DIR/nox.mod.json"
fi
check $([ -n "$MANIFEST" ]; echo $?) "nox.mod.json[c]"

if [ -z "$MANIFEST" ]; then
  echo ""
  echo "$ERRORS error(s) — cannot continue without manifest"
  exit 1
fi

# 3. Root .asmdef (repo root or SDK/)
ASMDEF_COUNT=$(find "$MOD_DIR" -maxdepth 2 -name "*.asmdef" | wc -l)
check $([ "$ASMDEF_COUNT" -gt 0 ]; echo $?) ".asmdef ($ASMDEF_COUNT found)"

# 4. Entrypoints reference existing asmdef names
ALL_ASMDEFS=$(find "$MOD_DIR" -name "*.asmdef" -exec jq -r '.name' {} \; | sort -u)

if [ -z "$ALL_ASMDEFS" ]; then
  echo "  [SKIP] entrypoints check (no asmdefs)"
else
  echo "  Assemblies: $ALL_ASMDEFS" | tr '\n' ' '
  echo ""

  # Read entrypoints
  ENTRYPOINTS=$(jq -r '.entrypoints // {} | to_entries[] | .value[]' "$MANIFEST" 2>/dev/null || echo "")

  if [ -z "$ENTRYPOINTS" ]; then
    echo "  [OK]   entrypoints (none declared)"
  else
    echo "$ENTRYPOINTS" | while read -r ep; do
      # Extract assembly name: "Nox.Network.Runtime.Main" → "Nox.Network.Runtime"
      ASM="${ep%%.*}"
      if echo "$ALL_ASMDEFS" | grep -qFx "$ASM"; then
        echo "  [OK]   $ep → $ASM"
      else
        echo "  [FAIL] $ep → $ASM (assembly not found)"
        ERRORS=$((ERRORS + 1))
      fi
    done
  fi
fi

# Summary
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "All checks passed!"
else
  echo "$ERRORS error(s) found"
  exit 1
fi
