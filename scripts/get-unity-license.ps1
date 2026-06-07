# Print Unity license for CI secrets
# Usage: .\get-unity-license.ps1
# One-liner: gc "$env:PROGRAMDATA\Unity\Unity_lic.ulf"

$path = "$env:PROGRAMDATA\Unity\Unity_lic.ulf"
if (Test-Path $path) { Get-Content $path -Raw } else { Write-Error "License not found at $path" }
