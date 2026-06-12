#!/usr/bin/env bash
# Init git in the project directory (required by unity-builder)
set -euo pipefail

echo "::group::Init git"

cd project

echo "Initializing git repository..."
git init
git config user.email "ci@mod.builder"
git config user.name "mod.builder"
git add -A

if git commit -m "init" --no-verify 2>/dev/null; then
  echo "Git repository initialized"
else
  echo "Nothing to commit (already clean)"
fi

echo "::endgroup::"
