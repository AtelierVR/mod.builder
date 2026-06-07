#!/bin/bash
# ────────────────────────────────────────────────────────────────
# Setup Unity secrets for a mod repo
# Usage: curl -sSL https://raw.githubusercontent.com/AtelierVR/mod.builder/main/scripts/setup-secrets.sh | bash
# ────────────────────────────────────────────────────────────────
set -euo pipefail

ok()   { printf '\033[42m\033[30m   OK   \033[0m %s\n' "$*"; }
fail() { printf '\033[41m\033[30m FAILED \033[0m %s\n' "$*"; }
info() { printf '\033[44m\033[30m  INFO  \033[0m %s\n' "$*"; }

echo ""
echo "  mod.builder — Unity secrets setup"
echo ""

if ! command -v gh &>/dev/null; then
  fail "GitHub CLI not found. Install: https://cli.github.com"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  fail "Not logged in. Run: gh auth login"
  exit 1
fi

secret_exists() {
  gh secret list 2>/dev/null | grep -q "$1"
}

# UNITY_LICENSE
echo "── UNITY_LICENSE ──"
if secret_exists "UNITY_LICENSE"; then
  info "Already set."
else
  case "$(uname -s)" in
    Linux*)  LICENSE=$(cat ~/.local/share/unity3d/Unity/Unity_lic.ulf 2>/dev/null || echo "") ;;
    Darwin*) LICENSE=$(cat ~/Library/Application\ Support/Unity/Unity_lic.ulf 2>/dev/null || echo "") ;;
    CYGWIN*|MINGW*|MSYS*) LICENSE=$(cat "$PROGRAMDATA/Unity/Unity_lic.ulf" 2>/dev/null || echo "") ;;
  esac
  if [ -n "$LICENSE" ]; then
    echo "$LICENSE" | gh secret set UNITY_LICENSE
    ok "Set from local Unity install."
  else
    read -rp "  Paste Unity license (.ulf content): " LICENSE
    echo "$LICENSE" | gh secret set UNITY_LICENSE
    ok "Set."
  fi
fi

# UNITY_EMAIL
echo "── UNITY_EMAIL ──"
if secret_exists "UNITY_EMAIL"; then
  info "Already set."
else
  read -rp "  Unity account email: " EMAIL
  gh secret set UNITY_EMAIL --body "$EMAIL"
  ok "Set."
fi

# UNITY_PASSWORD
echo "── UNITY_PASSWORD ──"
if secret_exists "UNITY_PASSWORD"; then
  info "Already set."
else
  read -rsp "  Unity account password: " PASSWORD
  echo ""
  gh secret set UNITY_PASSWORD --body "$PASSWORD"
  ok "Set."
fi

echo ""
echo "── Result ──"
ok "All secrets configured."
