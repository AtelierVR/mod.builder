#!/bin/bash
# ────────────────────────────────────────────────────────────────
# Setup Unity secrets for a mod repo
# Usage: curl -sSL https://raw.githubusercontent.com/AtelierVR/mod.builder/main/scripts/setup-secrets.sh | bash
# ────────────────────────────────────────────────────────────────
set -euo pipefail

echo "🔧 mod.builder — Unity secrets setup"
echo ""

# Check gh CLI
if ! command -v gh &>/dev/null; then
  echo "❌ GitHub CLI (gh) not found. Install: https://cli.github.com"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "❌ Not logged in. Run: gh auth login"
  exit 1
fi

# UNITY_LICENSE
echo "── UNITY_LICENSE ──"
if gh secret list 2>/dev/null | grep -q UNITY_LICENSE; then
  echo "  Already set."
else
  case "$(uname -s)" in
    Linux*)  LICENSE=$(cat ~/.local/share/unity3d/Unity/Unity_lic.ulf 2>/dev/null || echo "") ;;
    Darwin*) LICENSE=$(cat ~/Library/Application\ Support/Unity/Unity_lic.ulf 2>/dev/null || echo "") ;;
    CYGWIN*|MINGW*|MSYS*) LICENSE=$(cat "$PROGRAMDATA/Unity/Unity_lic.ulf" 2>/dev/null || echo "") ;;
  esac
  if [ -n "$LICENSE" ]; then
    echo "$LICENSE" | gh secret set UNITY_LICENSE
    echo "  ✅ Set from local Unity install."
  else
    read -rp "  Paste Unity license (.ulf file content): " LICENSE
    echo "$LICENSE" | gh secret set UNITY_LICENSE
    echo "  ✅ Set."
  fi
fi

# UNITY_EMAIL
echo "── UNITY_EMAIL ──"
if gh secret list 2>/dev/null | grep -q UNITY_EMAIL; then
  echo "  Already set."
else
  read -rp "  Unity account email: " EMAIL
  gh secret set UNITY_EMAIL --body "$EMAIL"
  echo "  ✅ Set."
fi

# UNITY_PASSWORD
echo "── UNITY_PASSWORD ──"
if gh secret list 2>/dev/null | grep -q UNITY_PASSWORD; then
  echo "  Already set."
else
  read -rsp "  Unity account password: " PASSWORD
  echo ""
  gh secret set UNITY_PASSWORD --body "$PASSWORD"
  echo "  ✅ Set."
fi

echo ""
echo "✅ All secrets configured."
