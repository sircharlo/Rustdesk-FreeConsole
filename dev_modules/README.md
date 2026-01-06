# Development Modules

This directory contains development and testing utilities for BetterDesk Console.

## Contents

### Testing Scripts
- **test_ban_api.sh** - Test script for ban/unban API endpoints
  - Tests device banning functionality
  - Validates API responses
  - Usage: `./test_ban_api.sh`

### Diagnostic Tools
- **check_database.py** - Database inspection and validation tool
  - Checks database schema
  - Verifies migrations applied
  - Lists devices and their status
  - Usage: `python3 check_database.py`

### Development Scripts
- **update.ps1** - PowerShell update script (Windows development environment)
  - Alternative to update.sh for Windows
  - Updates web console components

## Usage

These tools are for **development and testing only**. They are not required for production deployment.

### Requirements
- Python 3.8+ (for check_database.py)
- Bash (for test_ban_api.sh)
- curl (for API testing)

### Notes
- These scripts assume a local or test RustDesk server installation
- Always test on non-production systems first
- See main [README.md](../README.md) for production deployment

## Contributing

When adding new development tools:
1. Document usage in this README
2. Add appropriate shebang and error handling
3. Include comments explaining functionality
4. Test on clean environment before committing
