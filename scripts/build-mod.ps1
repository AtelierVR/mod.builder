# ────────────────────────────────────────────────────────────────
# build-mod.ps1 — CI orchestration: pull, setup, build
# All git & bash commands run through WSL for consistency.
# Run from workspace root or builder/scripts/ — auto-detects.
# ────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"

# Resolve workspace root (parent of builder/)
$workspaceRoot = if (Test-Path (Join-Path $PSScriptRoot "..\..\.env")) {
    Join-Path $PSScriptRoot "..\.."
} elseif (Test-Path (Join-Path $PSScriptRoot ".env")) {
    $PSScriptRoot
} else {
    Write-Error "Cannot find workspace root (no .env found)"
    exit 1
}
Set-Location $workspaceRoot

# ── Helpers ────────────────────────────────────────────────────
function ConvertTo-WslPath {
    param([string]$winPath)
    $p = (Resolve-Path $winPath).Path -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)') {
        return '/mnt/' + $Matches[1].ToLower() + $Matches[2]
    }
    return $p
}

function Invoke-Wsl {
    param([string]$command, [string]$description)
    if ($description) { Write-Host "  $description" }
    $wslCmd = "cd '$rootWsl' ; $command"
    wsl -e bash -c $wslCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "WSL command failed (exit=$LASTEXITCODE): $command"
        exit $LASTEXITCODE
    }
}

# ── Detect WSL ─────────────────────────────────────────────────
if (-not (Get-Command "wsl" -ErrorAction SilentlyContinue)) {
    Write-Error "WSL is required but not found."
    exit 1
}

$rootWsl = ConvertTo-WslPath "."
Write-Host "Workspace (WSL): $rootWsl"

# ── 1. Load MOD_ID from .env ───────────────────────────────────
if (-not (Test-Path ".env")) {
    Write-Error ".env file not found at root"
    exit 1
}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*MOD_ID\s*=\s*(.+)$') {
        $MOD_ID = $Matches[1].Trim()
    }
}
if (-not $MOD_ID) {
    Write-Error "MOD_ID not found in .env"
    exit 1
}
Write-Host "MOD_ID: $MOD_ID"

# ── 2. Git pull mod/ via WSL ───────────────────────────────────
Write-Host "`n=== git pull mod/ ==="
Invoke-Wsl "cd mod ; git pull"

# ── 3. Git pull builder/ via WSL ───────────────────────────────
Write-Host "`n=== git pull builder/ ==="
Invoke-Wsl "cd builder ; git pull"

# ── 4. Remove unity/ if it exists ──────────────────────────────
if (Test-Path "unity") {
    Write-Host "`n=== Removing existing unity/ ==="
    Remove-Item -Recurse -Force "unity"
}

# ── 5. Create unity/ and write .env inside it ──────────────────
Write-Host "`n=== Creating unity/ with .env ==="
New-Item -ItemType Directory -Force -Path "unity" | Out-Null
"MOD_ID=$MOD_ID" | Out-File -FilePath "unity\.env" -Encoding utf8

# ── 6. Fix line-endings (CRLF→LF) for shell scripts ────────────
Write-Host "`n=== Fixing shell script line endings (CRLF -> LF) ==="
Invoke-Wsl "sed -i 's/\r$//' '$rootWsl/builder/scripts/'*.sh"

# ── 7. Run setup-unity-project.sh via WSL ──────────────────────
Write-Host "`n=== Running setup-unity-project.sh ==="
$unityWsl = "$rootWsl/unity"
$builderScriptWsl = "$rootWsl/builder/scripts/setup-unity-project.sh"
$modWsl = "$rootWsl/mod"
Invoke-Wsl "bash '$builderScriptWsl' '$MOD_ID' '$modWsl' '$unityWsl'"

# ── 8. Run build.ps1 ───────────────────────────────────────────
Write-Host "`n=== Running build.ps1 ==="
& (Join-Path $PSScriptRoot "build.ps1")
