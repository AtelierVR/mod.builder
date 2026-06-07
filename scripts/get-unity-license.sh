#!/bin/bash
# Print Unity license for CI secrets
# Usage: bash get-unity-license.sh

case "$(uname -s)" in
  Linux*)  cat ~/.local/share/unity3d/Unity/Unity_lic.ulf 2>/dev/null || echo "License not found at ~/.local/share/unity3d/Unity/Unity_lic.ulf" ;;
  Darwin*) cat ~/Library/Application\ Support/Unity/Unity_lic.ulf 2>/dev/null || cat /Library/Application\ Support/Unity/Unity_lic.ulf 2>/dev/null || echo "License not found" ;;
  CYGWIN*|MINGW*|MSYS*) cat "$PROGRAMDATA/Unity/Unity_lic.ulf" 2>/dev/null || echo "License not found at %PROGRAMDATA%/Unity/Unity_lic.ulf" ;;
esac
