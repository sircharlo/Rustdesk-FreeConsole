# Legacy Scripts

This folder contains the older installation scripts (v1.x) that have been superseded by the new ALL-IN-ONE scripts.

> **💡 Recommendation**: Use the new unified scripts instead:
> - `betterdesk.sh` (Linux)
> - `betterdesk.ps1` (Windows)
> - `betterdesk-docker.sh` (Docker)

## Available Legacy Scripts

| Script | Version | Platform | Description |
|--------|---------|----------|-------------|
| `install-improved.sh` | v1.5.5 | Linux | Full installation with migrations |
| `install-improved.ps1` | v1.5.2 | Windows | Full installation with migrations |
| `install-docker.sh` | v1.0 | Docker | Docker Compose deployment |
| `docker-quickstart.sh` | v1.0 | Docker | Quick Docker setup |
| `fix-admin.sh` | v1.0 | Docker (Linux) | Fix admin account |
| `fix-admin.bat` | v1.0 | Docker (Windows) | Fix admin account |

## Usage

These scripts still work but lack the interactive menu and some newer features:

```bash
# Linux
sudo ./scripts/legacy/install-improved.sh

# Windows (PowerShell as Admin)
.\scripts\legacy\install-improved.ps1

# Diagnostics (Linux)
sudo ./scripts/legacy/install-improved.sh --diagnose

# Fix offline status (Linux)
sudo ./scripts/legacy/install-improved.sh --fix
```

## Why Use New Scripts?

The new ALL-IN-ONE scripts (`betterdesk.*`) offer:
- Interactive menu with all operations in one place
- Backup functionality
- Admin password reset
- Binary building from source
- Comprehensive diagnostics
- Uninstall option

## Migration

To migrate from legacy to new scripts, simply run the new script - it will detect your existing installation and offer appropriate options.
