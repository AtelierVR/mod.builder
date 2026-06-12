# ────────────────────────────────────────────────────────────────
# build.ps1 — Launch Unity build, tail logs, exit with Unity
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

# ── 1. Load MOD_ID from unity/.env ─────────────────────────────
$MOD_ID = $null
if (Test-Path "unity\.env") {
    Get-Content "unity\.env" | ForEach-Object {
        if ($_ -match '^\s*MOD_ID\s*=\s*(.+)$') {
            $MOD_ID = $Matches[1].Trim()
        }
    }
}
if (-not $MOD_ID) {
    Write-Error "MOD_ID not found in unity/.env"
    exit 1
}

# ── 2. Paths ───────────────────────────────────────────────────
$unityEditor = "C:\Program Files\Unity\Hub\Editor\6000.4.4f1\Editor\Unity.exe"
$projectPath = Join-Path (Get-Location) "unity"
$logFile = Join-Path (Get-Location) "build.log"

# Remove previous log and build output
if (Test-Path $logFile) { Remove-Item $logFile -Force }
$buildDir = Join-Path (Get-Location) "build"
if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }

# ── 2b. Fix corrupted System.Formats.Asn1.dll ──────────────────
# The DLL in nox.cck/Plugins/ has a corrupted PE header (EF BF BD
# instead of 90 00 03). Download clean netstandard2.0 version from NuGet.
Write-Host "=== Fixing corrupted System.Formats.Asn1.dll ==="
$nugetUrl = "https://www.nuget.org/api/v2/package/System.Formats.Asn1/6.0.0"
$tmpZip = "$env:TEMP\nox_ci_sfasn1.zip"
$tmpDir = "$env:TEMP\nox_ci_sfasn1_pkg"
try {
    Invoke-WebRequest $nugetUrl -OutFile $tmpZip -ErrorAction Stop
    Expand-Archive $tmpZip -DestinationPath $tmpDir -Force
    $cleanDll = Get-ChildItem $tmpDir -Recurse -Filter "System.Formats.Asn1.dll" |
        Where-Object { $_.FullName -match "netstandard2\\.0" } |
        Select-Object -First 1
    if ($cleanDll) {
        # Find nox.cck Plugins/ in PackageCache
        $cckPlugins = Get-ChildItem $projectPath -Recurse -Directory -Filter "Plugins" -Depth 4 |
            Where-Object { $_.FullName -match "nox\\.cck" } |
            Select-Object -First 1
        if ($cckPlugins) {
            Copy-Item $cleanDll.FullName -Destination (Join-Path $cckPlugins.FullName "System.Formats.Asn1.dll") -Force
            Write-Host "  Replaced corrupted DLL with clean netstandard2.0 version"
        } else {
            Write-Warning "  nox.cck Plugins/ not found"
        }
    }
} catch {
    Write-Warning "  Could not download clean DLL: $_"
} finally {
    Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ── 3. Build arguments ─────────────────────────────────────────
$unityArgs = @(
    "-batchmode",
    "-projectPath", $projectPath,
    "-logFile", $logFile,
    "-buildTarget", "StandaloneWindows64",
    "-executeMethod", "Nox.GameBuilder.Pipeline.ExternalBuilder.BuildMod",
    "-noxModToBuild", $MOD_ID,
    "-noxOutputPath", $buildDir
)

Write-Host "MOD_ID      : $MOD_ID"
Write-Host "Unity       : $unityEditor"
Write-Host "Project     : $projectPath"
Write-Host "Log file    : $logFile"
Write-Host "Output      : $buildDir"
Write-Host ""

# ── 4. Start Unity process ─────────────────────────────────────
Write-Host "=== Starting Unity build ==="
$proc = Start-Process -FilePath $unityEditor -ArgumentList $unityArgs -PassThru -NoNewWindow

# ── 5. Tail log file in a background job ───────────────────────
$tailJob = Start-Job -ScriptBlock {
    param($logPath)
    # Wait for log file to appear
    while (-not (Test-Path $logPath)) { Start-Sleep -Milliseconds 500 }
    Get-Content $logPath -Wait -Tail 0
} -ArgumentList $logFile

# ── 6. Receive log output and wait for Unity ───────────────────
try {
    while (-not $proc.HasExited) {
        # Receive any pending log output
        $output = Receive-Job $tailJob 2>$null
        if ($output) {
            $output | ForEach-Object { Write-Host $_ }
        }
        Start-Sleep -Milliseconds 250
    }
    # Flush remaining logs after process exits
    Start-Sleep -Seconds 1
    $output = Receive-Job $tailJob 2>$null
    if ($output) {
        $output | ForEach-Object { Write-Host $_ }
    }
} finally {
    Stop-Job $tailJob -ErrorAction SilentlyContinue
    Remove-Job $tailJob -Force -ErrorAction SilentlyContinue
}

# ── 7. Report result ───────────────────────────────────────────
$exitCode = $proc.ExitCode
Write-Host ""
Write-Host "=== Unity build finished (exit code: $exitCode) ==="

# Also dump any remaining log content that might have been missed
if (Test-Path $logFile) {
    Write-Host "`n=== Last 20 lines of build.log ==="
    Get-Content $logFile -Tail 20 | ForEach-Object { Write-Host $_ }
}

# ── 8. Detect nox.mod.json in build output ─────────────────────
Write-Host "`n=== Checking build output for nox.mod.json ==="
if (-not (Test-Path $buildDir)) {
    Write-Error "Build output directory not found: $buildDir"
    exit 1
}

$noxModFiles = Get-ChildItem -Path $buildDir -Recurse -Filter "nox.mod.json" -ErrorAction SilentlyContinue
if (-not $noxModFiles) {
    Write-Error "nox.mod.json NOT FOUND in build output: $buildDir"
    Write-Host "Contents of build directory:"
    Get-ChildItem -Path $buildDir -Recurse -Depth 3 | ForEach-Object { Write-Host "  $($_.FullName)" }
    exit 1
}

Write-Host "Found $($noxModFiles.Count) nox.mod.json file(s):"
foreach ($f in $noxModFiles) {
    Write-Host "`n── $($f.FullName) ──"
    try {
        $content = Get-Content $f.FullName -Raw -Encoding utf8
        Write-Host $content
        # Validate JSON
        $json = $content | ConvertFrom-Json
        Write-Host "`n  id      : $($json.id)"
        Write-Host "  version : $($json.version)"
        if ($json.name)    { Write-Host "  name    : $($json.name)" }
        if ($json.provides) { Write-Host "  provides: $($json.provides -join ', ')" }
    } catch {
        Write-Error "Failed to parse $($f.FullName): $_"
        exit 1
    }
}

exit $exitCode
