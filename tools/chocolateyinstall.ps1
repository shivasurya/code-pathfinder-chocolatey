$ErrorActionPreference = 'Stop'

$packageName = 'code-pathfinder'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$version = '2.1.0'  # VERSION_MARKER
$pythonSdkVersion = '2.1.0'  # PYTHON_SDK_VERSION_MARKER
$url = 'https://github.com/shivasurya/code-pathfinder/releases/download/v2.1.0/pathfinder-windows-amd64.exe'  # URL_MARKER
$checksum = 'ddc82d6b06ad150ae35bdefa0530df0a2b8958a6a8d270c8c47652c8da4b397f'  # SHA256_MARKER
$checksumType = 'sha256'
$pypiChecksum = '08e0ab941f8b97273acddcb69ae307c7ddbb6da97b411e58a9a153421d137bdb a87c47be25224213d06453c7fa25d2dbcaa7a626385cdc96ddd8799ccd80feaa dde250a8bbb7045a9b963b7f721be30f81caed4a32947aeba64c99021ecdde39 bca0961400bf0deee203426b4d4b2e4ec7af51b6a2c25cdbde9a49ec521c6d73 f03ad834bc935962a464afe7ad8a4e37299872680b0da85f50a45082c8d7ec2d 9b62817a8f6797d7a669b02daf314a5e9a2aea98c83146fb4d7437405a021137'  # PYPI_SHA256_MARKER

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

Write-Host "Setting up Python environment for SDK support..." -ForegroundColor Cyan
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
  Write-Host "code-pathfinder requires Python 3.12 for SDK support." -ForegroundColor Yellow
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

Write-Host "Installing codepathfinder Python package (version $pythonSdkVersion)..." -ForegroundColor Cyan

# Download the wheel file first for verification
# Temporarily allow errors to not stop execution for pip commands
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

$pipDownloadOutput = & $venvPip download --no-deps --dest $env:TEMP "codepathfinder==$pythonSdkVersion" 2>&1
$pipDownloadExitCode = $LASTEXITCODE

$ErrorActionPreference = $previousErrorAction

if ($pipDownloadExitCode -ne 0) {
  Write-Host "Pip download output:" -ForegroundColor Red
  Write-Host $pipDownloadOutput -ForegroundColor Red
  throw "Failed to download codepathfinder package from PyPI"
}

$wheelFile = Get-ChildItem "$env:TEMP\codepathfinder-$pythonSdkVersion*.whl" | Select-Object -First 1
if (-not $wheelFile) {
  throw "Could not find downloaded wheel file"
}

# Verify checksum using certutil (more universally available than Get-FileHash)
$certutilOutput = certutil -hashfile $wheelFile.FullName SHA256
$actualHash = ($certutilOutput | Select-Object -Index 1).Trim().ToLower()

# Split the checksum string (may contain multiple checksums for different packages)
$validChecksums = $pypiChecksum -split '\s+'

if ($validChecksums -notcontains $actualHash) {
  Remove-Item $wheelFile.FullName -Force
  throw "PyPI package checksum mismatch! Expected one of: $pypiChecksum, Got: $actualHash"
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
