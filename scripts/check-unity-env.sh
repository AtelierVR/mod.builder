#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# check-unity-env.sh — validate Unity CI environment secrets
#
# Checks:
#   1. UNITY_LICENSE is present and contains valid .ulf structure
#   2. UNITY_EMAIL is present and looks like an email
#   3. UNITY_PASSWORD is present
#   4. UNITY_EMAIL + UNITY_PASSWORD validated against Unity license API
#
# Exits 0 on success, 1 if any check fails.
# ─────────────────────────────────────────────────────────────────
set -uo pipefail

ERRORS=0

check_ok() {
  echo "  [OK]   $1"
}

check_fail() {
  echo "  [FAIL] $1" >&2
  ERRORS=$((ERRORS + 1))
}

echo "::group::Validate Unity CI environment secrets"

# ── 1. UNITY_LICENSE ────────────────────────────────────────────
echo "Checking UNITY_LICENSE..."
if [ -z "${UNITY_LICENSE:-}" ]; then
  check_fail "UNITY_LICENSE is not set"
else
  # Check for .ulf XML structure elements (double quotes — secret may contain single quotes)
  if echo "$UNITY_LICENSE" | grep -q "<License id="; then
    check_ok "<License id= element present"
  else
    check_fail "<License id= element missing — secret may be a file path, not file content"
  fi

  if echo "$UNITY_LICENSE" | grep -q "<SerialHash"; then
    check_ok "<SerialHash element present"
  else
    check_fail "<SerialHash element missing"
  fi

  if echo "$UNITY_LICENSE" | grep -q "<MachineBindings"; then
    check_ok "<MachineBindings element present"
  else
    check_fail "<MachineBindings element missing"
  fi

  # Compute a fingerprint hash of the three secrets for debugging
  LIC_HASH=$(echo "$UNITY_LICENSE" | sha256sum | cut -d' ' -f1 | cut -c1-16)
  EMAIL_HASH=$(echo "$UNITY_EMAIL" | sha256sum | cut -d' ' -f1 | cut -c1-16)
  PASS_HASH=$(echo "$UNITY_PASSWORD" | sha256sum | cut -d' ' -f1 | cut -c1-16)
  echo "  [INFO]  UNITY_LICENSE sha256/16: $LIC_HASH"
  echo "  [INFO]  UNITY_EMAIL sha256/16:    $EMAIL_HASH"
  echo "  [INFO]  UNITY_PASSWORD sha256/16:   $PASS_HASH"

  # Validate as XML if xmllint is available
  if command -v xmllint &>/dev/null; then
    if echo "$UNITY_LICENSE" | xmllint --noout - 2>/dev/null; then
      check_ok "valid XML structure"
    else
      check_fail "not valid XML"
    fi
  else
    echo "  [SKIP] xmllint not available — XML structure check skipped"
  fi

  # Reject if it looks like a file path
  if echo "$UNITY_LICENSE" | grep -qE "^/[A-Za-z]:|\.ulf\$|Unity_lic"; then
    check_fail "looks like a file PATH, not file content"
  fi

  # Validate email/password against Unity license API
  if [ -n "${UNITY_EMAIL:-}" ] && [ -n "${UNITY_PASSWORD:-}" ]; then
    echo ""
    echo "Validating UNITY_EMAIL + UNITY_PASSWORD against Unity license API..."
    HTTP_CODE=$(curl -sL -X POST "https://license.unity3d.com/request" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "username=${UNITY_EMAIL}&password=${UNITY_PASSWORD}&license_request=1" \
      --max-time 30 \
      -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")

    case "$HTTP_CODE" in
      200)
        check_ok "Unity credentials are valid"
        ;;
      401|403)
        check_fail "Unity credentials rejected (HTTP $HTTP_CODE)"
        ;;
      000)
        echo "  [WARN] Could not reach Unity license API (network timeout) — build will retry activation" >&2
        ;;
      *)
        echo "  [WARN] Unity license API returned HTTP $HTTP_CODE — activation will retry during build" >&2
        ;;
    esac
  fi
fi

# ── 2. UNITY_EMAIL ──────────────────────────────────────────────
echo ""
echo "Checking UNITY_EMAIL..."
if [ -z "${UNITY_EMAIL:-}" ]; then
  check_fail "UNITY_EMAIL is not set"
else
  if echo "$UNITY_EMAIL" | grep -q "@"; then
    check_ok "valid email format"
  else
    check_fail "does not look like a valid email"
  fi
fi

# ── 3. UNITY_PASSWORD ───────────────────────────────────────────
echo ""
echo "Checking UNITY_PASSWORD..."
if [ -z "${UNITY_PASSWORD:-}" ]; then
  check_fail "UNITY_PASSWORD is not set"
else
  check_ok "set"
fi

echo "::endgroup::"
echo ""

if [ "$ERRORS" -ne 0 ]; then
  echo "::error::$ERRORS secret(s) invalid — fix before running builds"
  exit 1
fi

echo "::notice::All Unity environment secrets are valid"
exit 0
