# ────────────────────────────────────────────────────────────────
# build-mod.ps1 — Launch Unity build, tail logs, exit with Unity
# Usage: build-mod.ps1 <projectPath> <modId> "windows=path,linux=path"
# Example: build-mod.ps1 "D:\proj" "nox.network" "windows=D:\out\win,linux=D:\out\linux"
# ────────────────────────────────────────────────────────────────
param(
    [Parameter(Mandatory=$true)] [string] $ProjectPath,
    [Parameter(Mandatory=$true)] [string] $ModId,
    [Parameter(Mandatory=$true)] [string] $Platform,
    [switch] $ShowStackTraces,
    [switch] $GitHubAction
)

$ErrorActionPreference = "Stop"

# ── Helpers ────────────────────────────────────────────────────
$StackTracePattern = '^\s*(at |Rethrow |--- End of |\(at |\[0x)'

# ── 1. Paths ───────────────────────────────────────────────────
$unityEditor = "C:\Program Files\Unity\Hub\Editor\6000.4.4f1\Editor\Unity.exe"
$logFile = Join-Path $ProjectPath "Logs\ModBuilder_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

# Remove previous output (log file is timestamped, no need to remove)
# Build paths come from Platform parameter, no single OutputPath to clean

# ── 2. Build arguments ─────────────────────────────────────────
$unityArgs = @(
    "-batchmode",
    "-projectPath", $ProjectPath,
    "-logFile", $logFile,
    "-executeMethod", "Nox.GameBuilder.Pipeline.ExternalBuilder.BuildMod",
    "--noxMod", $ModId,
    "--noxOutput", $Platform,
    "-accept-apiupdate"
)

if ($GitHubAction) { $unityArgs += "--githubAction" }

$displayPlatforms = ($Platform -split ',' | ForEach-Object { $_.Trim() }) -join "`n               "

Write-Host "=== Unity Build ==="
Write-Host "Unity       : $unityEditor"
Write-Host "Project     : $ProjectPath"
Write-Host "Mod         : $ModId"
Write-Host "Platform(s) : $displayPlatforms"
if ($GitHubAction) { Write-Host "GH Actions  : enabled" }
Write-Host "Log file    : $logFile"
Write-Host ""

# ── 3. Start Unity process ─────────────────────────────────────
Write-Host "Starting Unity..."
$proc = Start-Process -FilePath $unityEditor -ArgumentList $unityArgs -PassThru -NoNewWindow

# ── 4. Tail log file in background ─────────────────────────────
$tailJob = Start-Job -ScriptBlock {
    param($logPath, $filterTraces)
    while (-not (Test-Path $logPath)) { Start-Sleep -Milliseconds 500 }
    Get-Content $logPath -Wait -Tail 0 | ForEach-Object {
        if ($filterTraces -and $_ -match '^\s*(at |Rethrow |--- End of |\(at |\[0x)') { return }
        $_
    }
} -ArgumentList $logFile, (-not $ShowStackTraces)

# ── 5. Wait for Unity to finish ────────────────────────────────
try {
    while (-not $proc.HasExited) {
        Receive-Job $tailJob | ForEach-Object { Write-Host $_ }
        Start-Sleep -Milliseconds 500
    }
} finally {
    Receive-Job $tailJob | ForEach-Object { Write-Host $_ }
    Stop-Job $tailJob -ErrorAction SilentlyContinue
    Remove-Job $tailJob -ErrorAction SilentlyContinue
}

# ── 6. Final log dump ──────────────────────────────────────────
Write-Host ""
Write-Host "=== Build finished (exit code: $($proc.ExitCode)) ==="
if (Test-Path $logFile) {
    Write-Host "--- Last 40 lines of $logFile ---"
    $lines = Get-Content $logFile -Tail 40
    if (-not $ShowStackTraces) {
        $lines = $lines | Where-Object { $_ -notmatch $StackTracePattern }
    }
    $lines | ForEach-Object { Write-Host $_ }
}

# ── 7. Show build output ───────────────────────────────────────
Write-Host ""
$platforms = $Platform -split ',' | ForEach-Object { $_.Split('=')[1].Trim() }
foreach ($outDir in $platforms) {
    Write-Host "=== Build output: $outDir ==="
    Get-ChildItem $outDir -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ }
    if (-not (Get-ChildItem $outDir -ErrorAction SilentlyContinue)) { Write-Host "(empty or not found)" }
    Write-Host ""
}

exit $proc.ExitCode
