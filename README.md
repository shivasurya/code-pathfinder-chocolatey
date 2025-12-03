# code-pathfinder Chocolatey Package

Official Chocolatey package for [Code Pathfinder](https://codepathfinder.dev/).

## Installation

```powershell
choco install code-pathfinder
```

## Usage

After installation:
```powershell
pathfinder version
pathfinder scan --project /path/to/code --rules /path/to/rules
```

## Requirements

- Windows 10 or later
- Python 3.12 (automatically installed as a dependency)

## What Gets Installed

- **pathfinder.exe** - The main Code Pathfinder binary
- **Python virtualenv** - Isolated Python environment with `codepathfinder` package for DSL support
- **Wrapper script** - Ensures Python environment is available when running pathfinder

## Package Maintenance

This package is automatically updated when new releases are published.

**Repository**: https://github.com/shivasurya/code-pathfinder-chocolatey
**Main Project**: https://github.com/shivasurya/code-pathfinder
**Documentation**: https://codepathfinder.dev/docs/quickstart

## License

AGPL-3.0 - See [LICENSE](LICENSE) file for details
