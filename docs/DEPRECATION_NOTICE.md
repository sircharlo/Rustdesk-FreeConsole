# ⚠️ Deprecation Notice

## Ban Enforcer (Python Daemon) - DEPRECATED

**Effective Date**: January 5, 2026  
**Version**: 1.2.0

---

### Status: OBSOLETE

The Python-based `ban_enforcer.py` daemon has been **replaced** by native HBBS ban checking as of version 1.2.0.

### What Changed?

**Old System (v1.1.0):**
- External Python daemon running every 2 seconds
- Cleared UUID/PK of banned devices
- ~95% effectiveness due to race conditions
- Required systemd service management
- Additional process overhead

**New System (v1.2.0):**
- Native ban check integrated into HBBS server
- Checks `is_banned` during device registration
- **100% effectiveness** - no race conditions
- No external processes needed
- Minimal performance impact (~1ms per check)

### Migration Guide

If you're using Ban Enforcer from v1.1.0:

1. **Install Patched HBBS Binary**
   ```bash
   cd hbbs-patch
   ./build.sh
   sudo ./install.sh
   ```

2. **Stop Ban Enforcer Service**
   ```bash
   sudo systemctl stop rustdesk-ban-enforcer
   sudo systemctl disable rustdesk-ban-enforcer
   ```

3. **Verify Ban Functionality**
   - Ban a test device through web console
   - Try to connect from that device
   - Connection should be rejected with "UUID mismatch" error

4. **Remove Service (Optional)**
   ```bash
   sudo rm /etc/systemd/system/rustdesk-ban-enforcer.service
   sudo systemctl daemon-reload
   ```

### Why Keep the Files?

The Ban Enforcer code remains in the repository for:
- **Reference**: Understanding the evolution of the ban system
- **Rollback**: Emergency fallback if needed
- **Educational**: Learning how external enforcement worked
- **Historical**: Documenting the project's development

### Recommendation

**Do NOT use Ban Enforcer for new installations.** Always use the native HBBS ban check (v1.2.0+).

For existing users: Migrate to the native system at your earliest convenience for improved reliability and performance.

---

### Files Affected

These files are now **deprecated** but kept for reference:
- `ban_enforcer.py` - Python daemon script
- `install_ban_enforcer.sh` - Installation script
- `rustdesk-ban-enforcer.service` - Systemd service file
- `BAN_ENFORCER.md` - Documentation
- `BAN_ENFORCER_TEST.md` - Testing guide

### Support

Ban Enforcer will **NOT** receive:
- Bug fixes
- Security updates
- Feature enhancements
- Compatibility updates

All future development focuses on the native HBBS ban check system.

---

**For questions or issues**, please refer to:
- Native ban system: [hbbs-patch/BAN_CHECK_PATCH.md](hbbs-patch/BAN_CHECK_PATCH.md)
- Quick setup: [hbbs-patch/QUICKSTART.md](hbbs-patch/QUICKSTART.md)
- General issues: [GitHub Issues](https://github.com/UNITRONIX/Rustdesk-FreeConsole/issues)
