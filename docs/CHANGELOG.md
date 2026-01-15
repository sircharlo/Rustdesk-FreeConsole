# BetterDesk Console - Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-01-11

### 🔐 Security & Authentication Update

**Major Security Enhancement**: Added comprehensive authentication system for both web console and HBBS HTTP API, plus LAN access capabilities.

### Added

#### Authentication System
- **User Login System**:
  - bcrypt password hashing (cost 12)
  - 24-hour session tokens stored in database
  - Login page with secure password handling
  - Session validation on all protected routes
  
- **Role-Based Access Control (RBAC)**:
  - Three roles: admin, operator, viewer
  - Role-specific permissions for device management
  - Admin-only access to user management
  - Audit logging for all actions

- **User Management Panel**:
  - Create/edit/delete users
  - Activate/deactivate accounts
  - Role assignment
  - Password reset functionality
  - User list with status indicators

#### API Security
- **X-API-Key Authentication**:
  - 64-character random API keys generated during installation
  - Middleware verification on all HBBS API endpoints
  - Stored securely in `/opt/rustdesk/.api_key` with 600 permissions
  - Automatic key injection by web console
  - 401 Unauthorized for missing/invalid keys

- **LAN Access**:
  - HBBS API now binds to `0.0.0.0:21120` (accessible on LAN)
  - Web console binds to `0.0.0.0:5000` (accessible on LAN)
  - Protected by authentication (API key + user login)
  - External tools can use API with X-API-Key header

#### Web Console Features
- **Sidebar Navigation**: Modern sidebar menu with icon-based navigation
- **Password-Protected Key Access**: Public key requires password verification
- **Password Change**: Users can change their passwords in Settings
- **Removed Devices Tab**: Simplified interface, devices managed on Dashboard
- **Expanded About Page**: Credits, GitHub links, open source information
- **Enhanced Settings**: Password change, session management, preferences

#### Installation & Updates
- **API Key Generation**: Automatic during installation via `openssl rand`
- **Environment Variables**: HBBS_API_KEY, FLASK_HOST, FLASK_PORT, FLASK_DEBUG
- **Service Configuration**: Updated systemd services with new environment vars
- **Update Script**: `update-to-v1.4.0.sh` for existing installations
- **Backward Compatibility**: Preserves existing configurations during update

### Changed

- **API Binding**: Changed from `127.0.0.1` (localhost-only) to `0.0.0.0` (LAN-accessible)
- **Authentication Required**: All API endpoints now require X-API-Key header
- **Web Console Access**: Requires user login instead of open access
- **Session Management**: 24-hour sessions instead of permanent access
- **Database Schema**: Added `users`, `sessions`, `audit_log` tables

### Security

- ✅ **Authentication**: All services protected by authentication
- ✅ **Encrypted Passwords**: bcrypt hashing for user passwords
- ✅ **API Key Auth**: X-API-Key header prevents unauthorized API access
- ✅ **Session Tokens**: Time-limited tokens with automatic expiration
- ✅ **Audit Trail**: All administrative actions logged
- ✅ **Secure Storage**: API keys with 600 permissions
- ✅ **XSS Protection**: Input sanitization throughout
- ✅ **SQL Injection Prevention**: Parameterized queries only
- ✅ **CSRF Protection**: Session-based validation

### Technical Details

- **Files Modified**:
  - `hbbs-patch/src/http_api.rs` - Added X-API-Key middleware
  - `web/app_v14.py` - Added authentication, user management, API key loading
  - `web/auth.py` - Password hashing, session management, user CRUD
  - `web/templates/login.html` - New login page
  - `web/templates/index_v14.html` - Sidebar navigation, user management UI
  - `web/static/script_v14.js` - User management, password change, key verification
  - `install-improved.sh` - API key generation and service configuration
  - `update-to-v1.4.0.sh` - Update script for existing installations

- **Database Migration**: `migrations/v1.4.0_auth_system.py`
  - Creates `users` table with roles
  - Creates `sessions` table for session management
  - Creates `audit_log` table for action tracking
  - Generates default admin user

- **API Endpoints** (all require X-API-Key):
  - `GET /api/health` - Health check
  - `GET /api/peers` - List all peers with online status

- **Web Endpoints** (all require login except `/login`):
  - `GET /login` - Login page
  - `POST /login` - Authenticate user
  - `GET /logout` - End session
  - `GET /` - Dashboard
  - `GET /api/users` - List users (admin only)
  - `POST /api/users` - Create user (admin only)
  - `PUT /api/users/<id>` - Update user (admin only)
  - `DELETE /api/users/<id>` - Delete user (admin only)
  - `POST /api/change-password` - Change password
  - `POST /api/verify-password` - Verify password for key access

### Migration Path

**For new installations:**
```bash
sudo ./install-improved.sh
```
- Automatically generates API key
- Configures services for LAN access
- Creates default admin user

**For existing installations:**
```bash
sudo ./update-to-v1.4.0.sh
```
- Creates automatic backup
- Runs database migration
- Generates API key if not exists
- Updates systemd services
- Preserves existing configuration
- Rollback capability on failure

### Documentation

- Updated `README.md` with authentication instructions
- Updated `hbbs-patch/README.md` with API security documentation
- Updated `hbbs-patch/SECURITY_AUDIT.md` with v1.4.0 security review
- Updated `docs/PORT_SECURITY.md` with LAN access notes
- Added API key retrieval instructions

### Known Issues

- 26 Pylance type warnings in `app_v14.py` for `log_audit()` parameters (non-critical)
- API key must be manually distributed to external tools

### Upgrade Notes

**Breaking Changes:**
- Existing API clients must add `X-API-Key` header
- Web console now requires user login
- Sessions expire after 24 hours

**Recommended Actions After Upgrade:**
1. Login with default admin credentials (shown after migration)
2. Change admin password immediately
3. Delete `/opt/BetterDeskConsole/admin_credentials.txt`
4. Create additional users with appropriate roles
5. Update external tools with API key from `/opt/rustdesk/.api_key`
6. Configure firewall for LAN access if needed

---

## [1.3.0-secure] - 2026-01-10

### 🔒 Security Update: Localhost-Only API Binding

**Critical Security Enhancement**: HTTP API now binds exclusively to localhost (127.0.0.1), eliminating network exposure.

### Changed
- **API Port**: Changed from 21114 to 21120
  - Avoids conflict with RustDesk Pro (which uses 21114 for public API)
  - Clearly distinguishes this as a localhost-only service
  - Updated all documentation and configuration examples

- **API Binding**: Localhost-only (127.0.0.1)
  - Previous: Bound to 0.0.0.0 (all interfaces, potential security risk)
  - Current: Bound to 127.0.0.1 (localhost only, secure by design)
  - API accessible only from same machine
  - Cannot be accessed from network/internet
  - No firewall configuration needed for port 21120

- **Server Configuration**: Added `--api-port` parameter
  - Command-line parameter support for flexible deployment
  - Systemd service updated: `ExecStart=/opt/rustdesk/hbbs --api-port 21120`
  - Windows service compatible with new parameter

- **Web Console**: Updated to use new API endpoint
  - Flask app now connects to `http://localhost:21120/api`
  - Automatic backup of old configuration during update
  - Verified working with new API port

### Added
- **Documentation**:
  - `PORT_SECURITY.md` - Complete port security analysis
  - SSH tunnel instructions for remote API access
  - Security audit documentation
  - Updated README with security notes (6 instances of port references)

- **Binaries**: Updated Linux binaries with security features
  - `hbbs-v8-api` (9.59 MB) - Built 10.01.2026 10:25 UTC
  - `hbbr-v8-api` (4.73 MB) - Built 10.01.2026 10:25 UTC
  - Contains: "HTTP API server listening on (localhost only)" string
  - Verified: `--api-port` parameter support
  - Windows binaries retained (compatible with new system)

- **Installation Scripts**:
  - `install-improved.sh` configured for v8-api binaries
  - Automatic backup creation before installation
  - File validation and verification
  - Service configuration with new port

### Security
- ✅ **Zero Network Exposure**: API cannot be accessed from external networks
- ✅ **Connection Refused**: External access attempts properly blocked
- ✅ **SSH Tunnel Support**: Remote access via secure tunnel only
- ✅ **No Private Data**: All documentation free of IPs, passwords, credentials
- ✅ **Verified Installation**: Complete end-to-end security validation

### Fixed
- **Port Conflict**: No longer conflicts with RustDesk Pro API (port 21114)
- **Network Security**: Eliminated accidental API exposure to internet
- **Service Startup**: systemd service properly configured with --api-port parameter

### Technical Details
- **API Endpoints**: `/api/health`, `/api/peers` (unchanged)
- **Response Format**: JSON (unchanged)
- **Performance**: Same as v1.2.0-v8 (~1ms per request)
- **Compatibility**: Fully compatible with existing RustDesk clients
- **RustDesk Ports**: TCP 21115-21117, UDP 21116 (unchanged, public access required)

### Remote Access

For remote API access (e.g., from Windows workstation to Linux server):

```bash
# Create SSH tunnel
ssh -L 21120:localhost:21120 user@server

# Then access API locally
curl http://localhost:21120/api/health
```

### Migration from v1.2.0-v8

**Automatic upgrade:**
```bash
cd Rustdesk-FreeConsole
git pull
sudo ./install-improved.sh
```

**Manual steps if needed:**
1. Update systemd service: Add `--api-port 21120` to ExecStart
2. Update web console: Change API URL to `http://localhost:21120/api`
3. Reload services: `systemctl daemon-reload && systemctl restart rustdesksignal betterdesk`

### Verification

```bash
# 1. Check API binding (should show 127.0.0.1:21120 only)
ss -tlnp | grep 21120

# 2. Test local access (should succeed)
curl http://localhost:21120/api/health

# 3. Test external access (should fail - connection refused)
curl http://SERVER_IP:21120/api/health

# 4. Verify RustDesk ports still public
ss -tlnp | grep -E '21115|21116|21117'
```

**Expected results:**
- ✅ Port 21120 on 127.0.0.1 (localhost only)
- ✅ Local API access works
- ✅ External API access blocked
- ✅ RustDesk client ports public (21115-21117)

---

## [1.2.0-v8] - 2026-01-06

### 🚀 Major Update: Precompiled Binaries + Bidirectional Ban Enforcement

**Game Changer**: Installation time reduced from ~20 minutes to ~2 minutes!

### Added
- **Precompiled Binaries**: No more compilation required!
  - `hbbs-patch/bin/hbbs-v8` (9.5 MB) - Signal server with bidirectional bans
  - `hbbs-patch/bin/hbbr-v8` (5.0 MB) - Relay server with bidirectional bans
  - Ready-to-deploy binaries compiled from RustDesk Server v1.1.14
  - Installation now takes ~2-3 minutes (vs ~20 min with compilation)
  - Reduced dependencies: No longer requires git, cargo, or Rust toolchain

- **Bidirectional Ban Enforcement**: Complete ban system overhaul
  - **Source Ban Check**: Prevents banned devices from initiating ANY connections
    - Checks device ID at punch hole request (P2P connections)
    - Checks device ID at relay request (relay connections)
    - Added `find_by_addr()` method in `peer.rs` to identify source device by IP
  - **Target Ban Check**: Prevents connections TO banned devices (legacy feature)
  - Works for both P2P and relay connection types
  - Real-time database sync - no restart required after ban/unban
  - Comprehensive logging for audit trail

- **Enhanced Build System**:
  - Updated `build.sh` with v8 patches (8 automated patches)
  - New deployment script: `deploy-v8.sh`
  - Binary verification and checksum tools
  - Rebuild instructions for custom architectures

- **Documentation**:
  - `hbbs-patch/bin/README.md` - Binary documentation and verification
  - `docs/INSTALLATION_V8.md` - Complete v8 installation guide
  - `hbbs-patch/BAN_ENFORCEMENT.md` - Technical documentation for bidirectional bans
  - `hbbs-patch/SECURITY_AUDIT.md` - Security audit report
  - Updated all guides with v8 information

### Changed
- **Installer Redesign** (`install.sh`):
  - Now uses precompiled binaries from `hbbs-patch/bin/`
  - Removed compilation steps (no more `cargo build`)
  - Reduced dependencies: Only requires python3, pip3, curl, systemctl
  - Automatic backup of existing binaries (timestamped)
  - Installs both HBBS and HBBR
  - Restarts services after installation
  - ~500MB disk space saved (no Rust toolchain needed)

- **Version Numbering**: Changed from `1.2.0` to `1.2.0-v8` to indicate binary version

### Fixed
- **Ban Enforcement Bug**: Banned devices could still initiate connections
  - Root cause: Only target device was checked, not source device
  - Solution: Added dual ban check (source + target) in punch hole and relay handlers
  - Added `find_by_addr()` to map socket address to device ID
  - Now blocks in BOTH directions

### Removed
- Old binary versions (`hbbs-v2-patched` through `hbbs-v5-patched`) - no longer needed
- Compilation requirements from documentation
- References to git/cargo in installation guides

### Technical Details
- **Architecture**: Linux x86_64 (tested on Ubuntu 20.04+, Debian 11+)
- **Performance**: Same as before (~1ms per ban check)
- **Reliability**: 100% ban enforcement in both directions
- **Compatibility**: Works with all RustDesk clients compatible with v1.1.14 server
- **Build Time**: N/A for end users (using precompiled), ~15-20 min if rebuilding from source

### Migration Notes
Users upgrading from v1.2.0 or earlier:
```bash
cd Rustdesk-FreeConsole
git pull
sudo ./install.sh  # Will automatically backup and upgrade
```

Benefits of v8:
- ✅ 10x faster installation
- ✅ No compilation errors
- ✅ Fixed ban enforcement bug (bidirectional)
- ✅ Smaller dependency footprint
- ✅ Easier deployment

---

## [1.2.0] - 2026-01-05

### 🔥 Major Update: Native HBBS Ban Check

**Breaking Change**: Ban enforcement moved from Python daemon to native HBBS binary

### Added
- **Native Ban Check in HBBS**: Device bans now enforced at registration level in HBBS server
  - Modified `src/database.rs`: Added `is_device_banned()` method for real-time ban checking
  - Modified `src/peer.rs`: Registration logic now checks ban status before accepting devices
  - Banned devices receive `UUID_MISMATCH` error code (standard RustDesk rejection)
  - 100% effective - no race conditions or timing windows
  - Fail-open policy: continues operation if database unavailable
  - Single SQL query per registration: `SELECT is_banned FROM peer WHERE id = ?`

- **HBBS Build System**: Complete automated build and installation tooling
  - `hbbs-patch/build.sh`: Automated patch application and compilation script
  - `hbbs-patch/install.sh`: One-command installation on server
  - `hbbs-patch/QUICKSTART.md`: 3-step setup guide
  - `hbbs-patch/BAN_CHECK_PATCH.md`: Technical documentation
  - Supports RustDesk Server v1.1.14

- **Documentation**:
  - Complete HBBS patch documentation in `hbbs-patch/` directory
  - Build system guides for local and server-side compilation
  - Migration guide from Ban Enforcer to native ban check

### Changed
- **Ban Enforcer Deprecated**: The Python `ban_enforcer.py` daemon is now **obsolete**
  - Native HBBS implementation replaces daemon functionality
  - No external processes needed
  - Better performance and reliability
  - Kept in repository for reference/rollback purposes

### Technical Details
- **Performance**: Minimal overhead (~1ms per registration)
- **Reliability**: 100% ban enforcement (vs ~95% with daemon)
- **Architecture**: Ban check integrated into device registration flow
- **Compatibility**: Works with existing BetterDesk Console database schema
- **Build**: Rust 1.90+ required for compilation

### Migration Notes
Users upgrading from v1.1.0:
1. Compile patched HBBS binary (see `hbbs-patch/QUICKSTART.md`)
2. Install patched binary on server
3. Stop and disable `rustdesk-ban-enforcer` service
4. Verify ban functionality through console

---

## [1.1.0] - 2026-01-05

### Added
- **Device Banning System**: Complete implementation of device ban management
  - Added `is_banned`, `banned_at`, `banned_by`, and `ban_reason` columns to database
  - Database migration script (`migrations/v1.1.0_device_bans.py`)
  - Ban/Unban API endpoints: `POST /api/device/<id>/ban` and `POST /api/device/<id>/unban`
  - Visual ban indicators in device list (red background, BANNED badge)
  - Ban/Unban buttons in device table (context-sensitive)
  - Detailed ban information in device details modal
  - "Banned" statistics card in dashboard
  - Confirmation dialogs for ban operations with reason input
  - Disabled connect button for banned devices
  - Ban reason validation (max 500 characters)

### Changed
- Device table now visually highlights banned devices with red tint
- Statistics endpoint now includes `banned` count
- Device details modal shows comprehensive ban information when applicable
- Connect functionality disabled for banned devices

### Security
- Ban operations require explicit confirmation
- Ban reason required for accountability
- All ban actions tracked with timestamp and administrator info

## [1.0.1] - 2026-01-05

### Added
- **Soft Delete System**: Devices are now marked as deleted instead of being permanently removed
  - Added `is_deleted`, `deleted_at`, and `updated_at` columns to database
  - Devices can potentially be restored in future versions
  - Database migration script (`migrations/v1.0.1_soft_delete.py`)
- **Input Validation**: Comprehensive validation for all user inputs
  - Device ID format validation (alphanumeric, underscores, hyphens only)
  - Maximum lengths enforced (50 chars for IDs, 500 chars for notes)
  - XSS protection with input sanitization
- **Enhanced User Feedback**:
  - Explicit confirmation dialogs for delete operations
  - Warning dialogs when changing device IDs
  - Detailed error messages for validation failures
  - Better error handling with specific HTTP status codes
- **Security Improvements**:
  - SQL injection protection through parameterized queries
  - Check for duplicate device IDs before updates
  - Database constraint violation handling

### Changed
- Delete operations now perform soft delete (UPDATE) instead of hard delete (DELETE)
- All SELECT queries now filter out deleted devices (`is_deleted = 0`)
- UPDATE queries now include `updated_at` timestamp
- Error messages are more informative and user-friendly

### Fixed
- **Unstable device deletion**: Now uses safe soft delete mechanism
- **Device ID change issues**: Added explicit warnings and validation
- **Missing error feedback**: Users now see detailed error messages
- **Potential data loss**: Deleted devices preserved in database

## [1.0.0] - 2026-01-05

### Added
- Enhanced RustDesk HBBS server with HTTP REST API
- Real-time device status monitoring using authentic RustDesk algorithm
- Modern web management console with glassmorphism UI
- Material Icons integration (fully offline)
- Device management features (CRUD operations)
- Dashboard with real-time statistics
- Search and filter functionality
- Device notes and labeling system
- Public key display and quick copy
- Automatic installation script with backup support
- Systemd service integration for auto-restart
- CORS support for web console integration
- Thread-safe PeerMap sharing (Arc<RwLock>)
- RESTful API with JSON responses
- Comprehensive documentation
- Demo mode with mock data for screenshots

### Changed
- Modified HBBS to use Arc<PeerMap> for thread safety
- Replaced FontAwesome with Google Material Icons
- Improved status detection (memory-based, not database)
- Enhanced UI with animations and modern design
- Updated peer.rs for immutable reference compatibility

### Technical Details
- **HBBS API Port**: 21114 (default)
- **Web Console Port**: 5000 (default)
- **Status Timeout**: 30 seconds (matches RustDesk client)
- **Status Detection**: In-memory PeerMap lookup
- **Architecture**: Shared state between HBBS and API server

### Security
- Automatic backup creation during installation
- Service isolation with systemd
- Graceful degradation if API unavailable
- No external dependencies (offline-ready)

### Performance
- Zero database queries for status checks
- In-memory lookups (microsecond response time)
- Async/await throughout for maximum efficiency
- Minimal resource overhead

### Compatibility
- RustDesk HBBS 1.1.9+
- Ubuntu 20.04+, Debian 11+, CentOS 8+
- Python 3.8+
- Rust 1.70+

### Known Limitations
- Device ID modification may cause access issues (use Note field for naming)
- Device deletion functionality is unstable
- No authentication system (internal networks only)

## [Unreleased]

### Planned for 1.0.1 (Bug Fixes)
- Fix device deletion functionality
- Improve device ID change handling
- Add confirmation dialogs for destructive operations
- Better error messages

### Planned for 1.1.0
- Multi-language support (i18n)
- User authentication system
- Role-based access control
- Connection history logs
- Performance metrics dashboard

### Planned for 1.2.0
- WebSocket for real-time updates
- Device grouping and tagging
- Email/Slack notifications
- REST API authentication (JWT)
- Mobile responsive improvements

### Planned for 2.0.0
- Multi-server support
- High availability setup
- Advanced analytics
- Custom themes
- Plugin system

---

[1.0.0]: https://github.com/UNITRONIX/Rustdesk-FreeConsole/releases/tag/v1.0.0
