#!/usr/bin/env bash
# Log the mod.builder commit SHA
set -euo pipefail

cd .mod-builder
SHA=$(git rev-parse --short HEAD)
echo "::notice title=Mod Builder::mod.builder @ $SHA"
echo "mod_builder_sha=$SHA" >> "$GITHUB_OUTPUT"
