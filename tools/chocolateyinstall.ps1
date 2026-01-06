$ErrorActionPreference = 'Stop'

$packageName = 'code-pathfinder'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$version = '1.1.5'  # VERSION_MARKER
$pythonDslVersion = '1.1.5'  # PYTHON_DSL_VERSION_MARKER
$url = 'https://github.com/shivasurya/code-pathfinder/releases/download/v1.1.5/pathfinder-windows-amd64.exe'  # URL_MARKER
$checksum = 'a7742fd60442eb153ca6f7d9fb3a589032e448639320fdf80bcc5af147ac06c2'  # SHA256_MARKER
$checksumType = 'sha256'
$pypiChecksum = 'b80facc948d9177051d68fbf024b5934857974bed6aee2e484a412dc6cc5e537 6f0b624287067a387522a1966fe89be019514b9ff51537c5a66951c3ec0bc275 000900c409c766dfa34777ddbfc0c0c3ae45a3d2b6c635dddb3280092967ef8a 93c1972bdf69b53eb1134c445fd586da6e12f8ccaff2acbb6400d3afae93534d d9dd69ca7aaffa6e719b87b4896a117f4ce27b3f15853c459fceb6e1db10320b'  # PYPI_SHA256_MARKER

$finalExeName = 'pathfinder.exe'
$downloadedFileName = 'pathfinder-windows-amd64.exe'

# --- Installation Logic ---

Write-Host "Installing pathfinder binary from $url..." -ForegroundColor Cyan

# Download the EXE and verify the hash
$downloadArgs = @{
    PackageName   = $packageName
    FileFullPath  = Join-Path $toolsDir $downloadedFileName
    Url           = $url
    Checksum      = $checksum
    ChecksumType  = $checksumType
}
Get-ChocolateyWebFile @downloadArgs

# Rename the downloaded EXE to the desired name
Rename-Item -Path (Join-Path $toolsDir $downloadedFileName) -NewName $finalExeName -Force

# --- Python Environment Setup ---

Write-Host "Setting up Python environment for DSL support..." -ForegroundColor Cyan
$venvPath = Join-Path $toolsDir "venv"

# Clean up old venv if it exists (ensures fresh install on upgrades)
if (Test-Path $venvPath) {
  Write-Host "Removing old Python virtualenv for fresh installation..." -ForegroundColor Yellow
  Remove-Item -Path $venvPath -Recurse -Force
}

# Find Python 3.12 (installed via dependency)
try {
  $pythonExe = (Get-Command python -ErrorAction Stop).Source
  Write-Host "Found Python at: $pythonExe" -ForegroundColor Gray
} catch {
  Write-Host ""
  Write-Host "ERROR: Python 3.12 is required but not found!" -ForegroundColor Red
  Write-Host ""
  Write-Host "code-pathfinder requires Python 3.12 for DSL support." -ForegroundColor Yellow
  Write-Host "Python should have been installed automatically as a dependency." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "To install Python manually:" -ForegroundColor Cyan
  Write-Host "  choco install python312 -y" -ForegroundColor White
  Write-Host ""
  Write-Host "After installing Python, restart your terminal and reinstall code-pathfinder." -ForegroundColor Cyan
  throw "Installation failed: Python 3.12 not found"
}

# Create fresh virtualenv
& $pythonExe -m venv $venvPath
if ($LASTEXITCODE -ne 0) {
  throw "Failed to create Python virtualenv"
}

# Install codepathfinder package with checksum verification
$venvPip = Join-Path $venvPath "Scripts\pip.exe"

Write-Host "Installing codepathfinder Python package (version $pythonDslVersion)..." -ForegroundColor Cyan

# Download the wheel file first for verification
# Temporarily allow errors to not stop execution for pip commands
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

$pipDownloadOutput = & $venvPip download --no-deps --dest $env:TEMP "codepathfinder==$pythonDslVersion" 2>&1
$pipDownloadExitCode = $LASTEXITCODE

$ErrorActionPreference = $previousErrorAction

if ($pipDownloadExitCode -ne 0) {
  Write-Host "Pip download output:" -ForegroundColor Red
  Write-Host $pipDownloadOutput -ForegroundColor Red
  throw "Failed to download codepathfinder package from PyPI"
}

$wheelFile = Get-ChildItem "$env:TEMP\codepathfinder-$pythonDslVersion*.whl" | Select-Object -First 1
if (-not $wheelFile) {
  throw "Could not find downloaded wheel file"
}

# Verify checksum using certutil (more universally available than Get-FileHash)
$certutilOutput = certutil -hashfile $wheelFile.FullName SHA256
$actualHash = ($certutilOutput | Select-Object -Index 1).Trim().ToLower()

if ($actualHash -ne $pypiChecksum) {
  Remove-Item $wheelFile.FullName -Force
  throw "PyPI package checksum mismatch! Expected: $pypiChecksum, Got: $actualHash"
}

Write-Host "PyPI checksum verified: $actualHash" -ForegroundColor Gray

# Install from verified wheel
$ErrorActionPreference = 'Continue'
$pipInstallOutput = & $venvPip install $wheelFile.FullName 2>&1
$pipInstallExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction

if ($pipInstallExitCode -ne 0) {
  Write-Host "Pip install output:" -ForegroundColor Red
  Write-Host $pipInstallOutput -ForegroundColor Red
  Remove-Item $wheelFile.FullName -Force
  throw "Failed to install codepathfinder Python package"
}

# Cleanup
Remove-Item $wheelFile.FullName -Force

# --- Wrapper and Shim Setup ---

# Create wrapper script that adds venv to PATH
$wrapperPath = Join-Path $toolsDir "pathfinder-wrapper.bat"
@"
@echo off
set PATH=%~dp0venv\Scripts;%PATH%
"%~dp0pathfinder.exe" %*
"@ | Out-File -FilePath $wrapperPath -Encoding ASCII

# Install shim for wrapper (makes 'pathfinder' available globally)
Install-BinFile -Name 'pathfinder' -Path $wrapperPath

Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "  Binary: $toolsDir\$finalExeName" -ForegroundColor Gray
Write-Host "  Python venv: $venvPath" -ForegroundColor Gray
Write-Host "Run 'pathfinder version' to verify installation" -ForegroundColor Cyan
