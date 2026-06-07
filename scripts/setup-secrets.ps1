# ────────────────────────────────────────────────────────────────
# Setup Unity secrets for a mod repo
# Usage: iwr https://raw.githubusercontent.com/AtelierVR/mod.builder/main/scripts/setup-secrets.ps1 | iex
# ────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"

Write-Host "🔧 mod.builder — Unity secrets setup" -ForegroundColor Cyan
Write-Host ""

# Check gh CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Host "❌ GitHub CLI (gh) not found. Install: winget install GitHub.cli" -ForegroundColor Red
  exit 1
}

# UNITY_LICENSE
Write-Host "── UNITY_LICENSE ──"
$existing = gh secret list 2>$null | Select-String UNITY_LICENSE
if ($existing) {
  Write-Host "  Already set."
} else {
  $licensePath = "$env:PROGRAMDATA\Unity\Unity_lic.ulf"
  if (Test-Path $licensePath) {
    $license = Get-Content $licensePath -Raw
    $license | gh secret set UNITY_LICENSE
    Write-Host "  ✅ Set from local Unity install." -ForegroundColor Green
  } else {
    $license = Read-Host "  Paste Unity license (.ulf file content)"
    $license | gh secret set UNITY_LICENSE
    Write-Host "  ✅ Set." -ForegroundColor Green
  }
}

# UNITY_EMAIL
Write-Host "── UNITY_EMAIL ──"
$existing = gh secret list 2>$null | Select-String UNITY_EMAIL
if ($existing) {
  Write-Host "  Already set."
} else {
  $email = Read-Host "  Unity account email"
  gh secret set UNITY_EMAIL --body "$email"
  Write-Host "  ✅ Set." -ForegroundColor Green
}

# UNITY_PASSWORD
Write-Host "── UNITY_PASSWORD ──"
$existing = gh secret list 2>$null | Select-String UNITY_PASSWORD
if ($existing) {
  Write-Host "  Already set."
} else {
  $password = Read-Host "  Unity account password" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  gh secret set UNITY_PASSWORD --body "$plain"
  Write-Host "  ✅ Set." -ForegroundColor Green
}

Write-Host ""
Write-Host "✅ All secrets configured." -ForegroundColor Green
