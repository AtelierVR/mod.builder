<div align="center">
  <img src="https://media.githubusercontent.com/media/AtelierVR/.github/refs/heads/main/profile/logo.png" width="320" alt="NoxVR" />
  <h1>mod.builder</h1>
  <p>Reusable CI/CD workflows for Nox mods — build, version, and publish.</p>

  [![License](https://img.shields.io/badge/License-AGPL--3.0-22c55e?style=flat-square)](LICENSE)
  ![Unity](https://img.shields.io/badge/Runtime-Unity%206000-000000?style=flat-square&logo=unity&logoColor=white)
  ![Shell](https://img.shields.io/badge/Scripts-bash%20%7C%20pwsh-4EAA25?style=flat-square)

  <p>Part of the <a href="https://github.com/AtelierVR"><strong>NoxVR</strong></a> ecosystem</p>
</div>

---

## Workflows

| Workflow | Description |
|:---|:---|
| [`check.yml`](.github/workflows/check.yml) | Validate mod structure — `package.json`, `nox.mod.jsonc`, `.asmdef`, entrypoints |
| [`version.yml`](.github/workflows/version.yml) | Compute next semver from git tags + bump `nox.mod.jsonc` + commit |
| [`build.yml`](.github/workflows/build.yml) | Create Unity project, resolve dependencies, BuildMod, package `.noxmod` |
| [`release.yml`](.github/workflows/release.yml) | Publish `.noxmod` to GitHub Releases |

## Quick start

```yaml
# .github/workflows/build.yml
name: Build & Release
on:
  push:
    branches: ["**"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:
    inputs:
      version_override:
        description: "Override version (empty = auto)"
        required: false

jobs:
  check:
    uses: AtelierVR/mod.builder/.github/workflows/check.yml@main

  version:
    needs: check
    if: github.event_name != 'pull_request'
    uses: AtelierVR/mod.builder/.github/workflows/version.yml@main
    with:
      override: ${{ inputs.version_override }}
    secrets: inherit

  build:
    needs: version
    if: always() && (needs.version.result == 'success' || needs.version.result == 'skipped')
    uses: AtelierVR/mod.builder/.github/workflows/build.yml@main
    with:
      version: ${{ needs.version.outputs.resolved }}
    secrets: inherit

  release:
    needs: [ version, build ]
    if: github.event_name != 'pull_request'
    uses: AtelierVR/mod.builder/.github/workflows/release.yml@main
    with:
      tag: ${{ needs.version.outputs.tag }}
      prerelease: ${{ needs.version.outputs.prerelease }}
```

## Secrets

```bash
# Windows
iwr https://raw.githubusercontent.com/AtelierVR/mod.builder/main/scripts/setup-secrets.ps1 | iex

# Linux / Mac
curl -sSL https://raw.githubusercontent.com/AtelierVR/mod.builder/main/scripts/setup-secrets.sh | bash
```

| Secret | Description |
|:---|:---|
| `UNITY_LICENSE` | Auto-detected from local Unity install |
| `UNITY_EMAIL` | Your Unity account email |
| `UNITY_PASSWORD` | Your Unity account password |

## Versioning

`nox.mod.jsonc` → `"version": "1.0.x"`

| Branch | Tag |
|:---|:---|
| `main` | `v1.0.0`, `v1.0.1`... |
| `development` | `v1.0.0-dev`, `v1.0.1-dev`... |
| `feature/xyz` | `v1.0.0-feature-xyz`... |

---

<div align="center">
  <p>Made with ♥ by <a href="https://github.com/AtelierVR">AtelierVR</a> &nbsp;·&nbsp; <a href="https://www.gnu.org/licenses/agpl-3.0">AGPL-3.0</a></p>
  <p>Part of the <strong>NoxVR</strong> project — a federated social VR platform</p>
</div>
