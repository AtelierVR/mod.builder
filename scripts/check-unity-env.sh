#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# check-unity-env.sh — validate Unity CI environment secrets
#
# Checks:
#   1. UNITY_LICENSE is present and contains valid .ulf structure
#   2. UNITY_EMAIL is present and looks like an email
#   3. UNITY_PASSWORD is present
#
# Exits 0 on success, 1 if any check fails.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

ERRORS=0

check() {
  local status="$1"
  shift
  local msg="$*"
  if [ "$status" -ne 0 ]; then
    echo "  [FAIL] $msg" >&2
    ERRORS=$((ERRORS + 1))
  else
    echo "  [OK]   $msg"
  fi
}

echo "::group::Validate Unity CI environment secrets"

# ── 1. UNITY_LICENSE ────────────────────────────────────────────
echo "Checking UNITY_LICENSE..."
if [ -z "${UNITY_LICENSE:-}" ]; then
  echo "  [FAIL] UNITY_LICENSE is not set" >&2
  ERRORS=$((ERRORS + 1))
else
  # Check for .ulf structure (use double quotes — secret may contain single quotes)
  echo "$UNITY_LICENSE" | grep -q "<License id="
  check $? "<License id= element present"

  echo "$UNITY_LICENSE" | grep -q "<SerialHash"
  check $? "<SerialHash element present"

  echo "$UNITY_LICENSE" | grep -q "<MachineBindings"
  check $? "<MachineBindings element present"

  # Validate as XML
  if command -v xmllint &>/dev/null; then
    if ! echo "$UNITY_LICENSE" | xmllint --noout - 2>/dev/null; then
      echo "  [FAIL] UNITY_LICENSE is not valid XML" >&2
      ERRORS=$((ERRORS + 1))
    else
      echo "  [OK]   valid XML structure"
    fi
  else
    echo "  [SKIP] xmllint not available — XML structure check skipped"
  fi

  # Reject if it looks like a file path
  if echo "$UNITY_LICENSE" | grep -qE "^/[A-Za-z]:|\.ulf\$|Unity_lic"; then
    echo "  [FAIL] UNITY_LICENSE looks like a file PATH, not file content" >&2
    echo "         The secret must contain the .ulf XML content, not 'C:\\...'" >&2
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── 2. UNITY_EMAIL ──────────────────────────────────────────────
echo ""
echo "Checking UNITY_EMAIL..."
if [ -z "${UNITY_EMAIL:-}" ]; then
  echo "  [FAIL] UNITY_EMAIL is not set" >&2
  ERRORS=$((ERRORS + 1))
else
  echo "$UNITY_EMAIL" | grep -q '@'
  check $? 'valid email format'
fi

# ── 3. UNITY_PASSWORD ───────────────────────────────────────────
echo ""
echo "Checking UNITY_PASSWORD..."
if [ -z "${UNITY_PASSWORD:-}" ]; then
  echo "  [FAIL] UNITY_PASSWORD is not set" >&2
  ERRORS=$((ERRORS + 1))
else
  echo "  [OK]   set"
fi

echo "::endgroup::"
echo ""

if [ "$ERRORS" -ne 0 ]; then
  echo "::error::$ERRORS secret(s) invalid — fix before running builds"
  exit 1
fi

echo "::notice::All Unity environment secrets are valid"
exit 0
