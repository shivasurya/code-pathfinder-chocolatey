$ErrorActionPreference = 'Stop'

$packageName = 'code-pathfinder'
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$version = '1.2.1'  # VERSION_MARKER
$pythonSdkVersion = '1.2.1'  # PYTHON_SDK_VERSION_MARKER
$url = 'https://github.com/shivasurya/code-pathfinder/releases/download/v1.2.1/pathfinder-windows-amd64.exe'  # URL_MARKER
$checksum = '9d621c41fe6fb856bc98e14f99a24a3cc13e9a7a2d8f6d69353d7f451845fdf2'  # SHA256_MARKER
$checksumType = 'sha256'
$pypiChecksum = '18ca304256bd74a3d3028a448ff7175e617563fb7e158a68b6a18d3f74159a87 440c1d9bba4b4cb76cd0f7f36cb4a4442b9782047b240774b91587384508976f f60847e8d8ba60682a99451006fc5cb91e4f3b7b655fcaf20ba07dedbcfffd41 68bef8ccd80447bfd629aebb09fadb83e163c868f132df95826e2620b1881cae 2a165353ca23ddf52047c27a4737808d0fc77c83a43d9cc39e0f8602c8ce5022 831213c23413e7ab08eaaee602b7bcd9872ac55f2547cdbbfacfdb3dc4f00069'  # PYPI_SHA256_MARKER

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
