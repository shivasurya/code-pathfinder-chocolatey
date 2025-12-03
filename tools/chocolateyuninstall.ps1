$ErrorActionPreference = 'Stop'

Write-Host "Uninstalling code-pathfinder..." -ForegroundColor Yellow

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Remove shim
Uninstall-BinFile -Name 'pathfinder'

# Clean up virtualenv
$venvPath = Join-Path $toolsDir "venv"
if (Test-Path $venvPath) {
  Write-Host "Removing Python virtualenv..." -ForegroundColor Cyan
  Remove-Item -Path $venvPath -Recurse -Force
}

# Clean up wrapper script
$wrapperPath = Join-Path $toolsDir "pathfinder-wrapper.bat"
if (Test-Path $wrapperPath) {
  Remove-Item -Path $wrapperPath -Force
}

Write-Host "Uninstall complete" -ForegroundColor Green
