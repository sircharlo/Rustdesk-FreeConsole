# Development Modules

This directory contains development and testing utilities for BetterDesk Console.

## Contents

### Testing Scripts
- **test_ban_api.sh** - Test script for ban/unban API endpoints
- **test_change_id.py** - Test ID change API endpoint (requires HBBS_API_KEY environment variable)
- **test_id_change.sh** - Test ID change via Web Console API (requires ADMIN_PASS environment variable)
- **test_generator.py** - Test script for RustDesk Client Generator

### Diagnostic Tools
- **check_database.py** - Database inspection and validation tool
- **check_and_fix_database.sh** - **Database Schema Checker & Fixer** ⭐
  - Use this if you have login problems!
- **diagnose_offline_status.sh** - **Diagnose offline status issues** ⭐
  - Use this if devices show as offline incorrectly!
- **fix_peer_columns.sh** - **Quick Fix for Device Errors** ⭐
  - Use this if you get 500 errors when editing devices!
- **fix_systemd_services.sh** - **Fix Systemd Services for API Binaries** ⭐
  - Use this if RustDesk services still use original binaries!
- **fix_database.py** - Fix database.rs imports and change_id function

### Patching Tools
- **patch_rendezvous.py** - Patch rendezvous_server.rs to call touch_peer on RegisterPeer
- **patch_id_change.py** - Patch rendezvous_server.rs for ID change via old_id field
- **patch_peer_remove.py** - Patch peer.rs to add remove function
- **patch_database_simple.py** - Add change_id function to database.rs

### Development Scripts
- **update.ps1** - PowerShell update script (Windows development environment)

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
