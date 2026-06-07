# Setup Unity secrets for a mod repo
# Usage: irm https://raw.githubusercontent.com/AtelierVR/mod.builder/refs/heads/main/scripts/setup-secrets.ps1 | iex

$ErrorActionPreference = "Stop"

function Ok  ($msg) { Write-Host "   OK   " -ForegroundColor White -BackgroundColor Green -NoNewline; Write-Host " $msg" -ForegroundColor White }
function Fail($msg) { Write-Host " FAILED " -ForegroundColor White -BackgroundColor Red   -NoNewline; Write-Host " $msg" -ForegroundColor White }
function Info($msg) { Write-Host "  INFO  " -ForegroundColor White -BackgroundColor Blue  -NoNewline; Write-Host " $msg" -ForegroundColor White }
function Sep ($msg) { Write-Host ""; Write-Host "--- $msg ---" }

Write-Host ""
Write-Host "  mod.builder -- Unity secrets setup" -ForegroundColor Cyan
Write-Host ""

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Fail "GitHub CLI not found. Install: winget install GitHub.cli"
  return
}

$ErrorActionPreference = "Continue"
gh auth status *>$null
if ($LASTEXITCODE -ne 0) {
  Fail "Not logged in. Run: gh auth login"
  return
}
$ErrorActionPreference = "Stop"

function Test-SecretExists($name) {
  gh secret list 2>&1 | Select-String $name | Out-Null
  return $?
}

Sep "UNITY_LICENSE"
if (Test-SecretExists "UNITY_LICENSE") {
  Info "Already set."
} else {
  $p = "$env:PROGRAMDATA\Unity\Unity_lic.ulf"
  if (Test-Path $p) {
    Get-Content $p -Raw | gh secret set UNITY_LICENSE
    Ok "Set from local Unity install."
  } else {
    $license = Read-Host "  Paste Unity license (.ulf content)"
    $license | gh secret set UNITY_LICENSE
    Ok "Set."
  }
}

Sep "UNITY_EMAIL"
if (Test-SecretExists "UNITY_EMAIL") {
  Info "Already set."
} else {
  $email = Read-Host "  Unity account email"
  gh secret set UNITY_EMAIL --body "$email"
  Ok "Set."
}

Sep "UNITY_PASSWORD"
if (Test-SecretExists "UNITY_PASSWORD") {
  Info "Already set."
} else {
  $pw = Read-Host "  Unity account password" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw)
  gh secret set UNITY_PASSWORD --body ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr))
  Ok "Set."
}

Write-Host ""
Sep "Result"
Ok "All secrets configured."
