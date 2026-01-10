# BetterDesk Console - Project Structure

This document describes the organization of the BetterDesk Console project.

## 📁 Directory Structure

```
BetterDeskConsole/
│
├── 📄 README.md                    # Main project documentation
├── 📄 LICENSE                      # AGPL-3.0 License (RustDesk compatible)
├── 📄 VERSION                      # Current version (1.2.0-v8)
├── 📄 .gitignore                   # Git ignore rules
├── 📄 CHANGELOG.md                 # Version history
│
├── 🔧 install.sh                   # Main installation script (uses precompiled binaries)
├── 🔧 update.sh                    # Update script for existing installations
├── 🔧 restore_hbbs.sh              # Restore original HBBS (rollback script)
│
├── 📁 web/                         # Web Console Application
│   ├── app.py                      # Flask backend with ban management
│   ├── app_demo.py                 # Demo version (no database)
│   ├── requirements.txt            # Python dependencies
│   ├── betterdesk.service          # Systemd service file
│   ├── templates/                  # HTML templates
│   │   └── index.html             # Main dashboard
│   └── static/                     # Static assets
│       ├── style.css              # Glassmorphism stylesheet
│       ├── script.js              # JavaScript frontend
│       └── MATERIAL_ICONS.md      # Material Icons attribution
│
├── 📁 hbbs-patch/                  # HBBS Server Modifications
│   ├── README.md                   # Patch documentation overview
│   ├── QUICKSTART.md              # Quick setup guide
│   ├── BAN_ENFORCEMENT.md          # Ban enforcement technical docs (v8)
│   ├── BAN_CHECK_PATCH.md         # Legacy patch documentation
│   ├── SECURITY_AUDIT.md          # Security audit report
│   │
│   ├── 📁 bin/                    # Precompiled Binaries (NEW in v8)
│   │   ├── hbbs-v8                # Signal server with bidirectional bans
│   │   ├── hbbr-v8                # Relay server with bidirectional bans
│   │   └── README.md              # Binary documentation
│   │
│   ├── 📁 src/                    # Source code patches (reference)
│   │   ├── database.rs            # Ban check functions
│   │   ├── http_api.rs            # REST API endpoints
│   │   ├── main.rs                # Main entry point
│   │   ├── peer.rs                # Peer management with ban checks
│   │   ├── rendezvous_server.rs   # Punch hole with dual ban check
│   │   └── relay_server.rs        # Relay with dual ban check (not included in v8)
│   │
│   ├── build.sh                    # Automated build script (for rebuilding)
│   ├── deploy-v8.sh                # Deployment script for v8
│   ├── deploy-v6.ps1               # Windows deployment (legacy)
│   ├── deploy.ps1                  # Windows deployment (legacy)
│   └── test_ban_enforcement.ps1    # Ban enforcement test script
│
│   ├── build.sh                   # Automated build script
│   ├── install.sh                 # Installation script
│   ├── database_patch.rs          # Database code snippet
│   ├── peer_patch.rs              # Peer registration code snippet
│   └── src/                       # Full source code patches
│       ├── database.rs            # Modified database module
│       ├── peer.rs                # Modified peer module
│       └── http_api.rs            # HTTP API module
│
├── 📁 migrations/                  # Database Migrations
│   ├── v1.0.1_soft_delete.py      # Soft delete system
│   └── v1.1.0_device_bans.py      # Device banning columns
│
├── 📁 screenshots/                 # Project Screenshots
│   ├── README.md                   # Screenshot descriptions
│   └── *.png                      # UI screenshots
│
├── 📁 docs/                        # 📚 Documentation Hub
│   ├── README.md                   # Documentation index
│   ├── CHANGELOG.md               # Version history
│   ├── RELEASE_NOTES_v1.2.0.md    # Latest release details
│   ├── CONTRIBUTING.md            # Contribution guidelines
│   ├── DEPRECATION_NOTICE.md      # Deprecated features info
│   ├── DEVELOPMENT_ROADMAP.md     # Future plans
│   ├── UPDATE_GUIDE.md            # How to update
│   ├── UPDATE_REFERENCE.md        # Detailed update procedures
│   ├── QUICKSTART_UPDATE.md       # Quick update instructions
│   └── GITHUB_RELEASE_CHECKLIST.md # Release process checklist
│
├── 📁 dev_modules/                 # 🛠️ Development Tools
│   ├── README.md                   # Developer tools documentation
│   ├── check_database.py          # Database inspection tool
│   ├── test_ban_api.sh            # API testing script
│   └── update.ps1                 # PowerShell update script (Windows)
│
└── 📁 deprecated/                  # ⚠️ Obsolete Components
    ├── README.md                   # Deprecation information
    ├── ban_enforcer.py            # Old Python ban daemon (v1.1.0)
    ├── install_ban_enforcer.sh    # Old installation script
    ├── rustdesk-ban-enforcer.service # Old systemd service
    ├── BAN_ENFORCER.md            # Old documentation
    └── BAN_ENFORCER_TEST.md       # Old testing guide
```

## 📂 Folder Purposes

### Core Directories

#### `web/`
Flask-based web management console with:
- Device listing and management
- Real-time status monitoring
- Ban/unban interface
- RESTful HTTP API

#### `hbbs-patch/`
Modified RustDesk HBBS server with:
- Native ban enforcement
- HTTP status API
- Automated build scripts
- Complete documentation

#### `migrations/`
Database schema evolution scripts:
- Soft delete system (v1.0.1)
- Device banning columns (v1.1.0)
- Future migrations go here

### Documentation

#### `docs/`
**Comprehensive project documentation**:
- Release notes and changelogs
- Update and contribution guides
- Roadmap and future plans
- GitHub release procedures

Keep this folder for:
- Understanding project history
- Planning updates
- Contributing to project
- Creating new releases

### Development

#### `dev_modules/`
**Tools for developers and testing**:
- Database inspection utilities
- API testing scripts
- Development-specific scripts

Use this folder when:
- Testing new features
- Debugging issues
- Validating database state
- Developing contributions

#### `deprecated/`
**Obsolete components (DO NOT USE)**:
- Ban Enforcer Python daemon (replaced in v1.2.0)
- Related installation scripts
- Old documentation

Kept for:
- Historical reference
- Emergency rollback
- Understanding system evolution

⚠️ **Do not use deprecated components in new installations!**

## 🎯 For New Users

Start with these files in order:

1. **[README.md](README.md)** - Project overview and features
2. **[install.sh](install.sh)** - Install web console
3. **[hbbs-patch/QUICKSTART.md](hbbs-patch/QUICKSTART.md)** - Install HBBS patch
4. **[docs/CHANGELOG.md](docs/CHANGELOG.md)** - Version history

## 🔄 For Existing Users

When updating:

1. **[docs/UPDATE_GUIDE.md](docs/UPDATE_GUIDE.md)** - General update process
2. **[update.sh](update.sh)** - Run automated update
3. **[docs/CHANGELOG.md](docs/CHANGELOG.md)** - See what changed

## 🤝 For Contributors

Before contributing:

1. **[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)** - Contribution guidelines
2. **[docs/DEVELOPMENT_ROADMAP.md](docs/DEVELOPMENT_ROADMAP.md)** - Planned features
3. **[dev_modules/](dev_modules/)** - Development tools

## 📋 File Naming Conventions

- **UPPERCASE.md** - Important documentation files
- **lowercase.sh** - Shell scripts (Linux/macOS)
- **lowercase.ps1** - PowerShell scripts (Windows)
- **lowercase.py** - Python scripts
- **lowercase.rs** - Rust source files

## 🚫 What NOT to Commit

See [.gitignore](.gitignore) for full list:
- `__pycache__/` - Python bytecode
- `target/` - Rust build artifacts
- `*.sqlite3` - Database files
- `*.log` - Log files
- `*.key`, `*.pem` - Private keys
- `.env` - Environment secrets

## 📦 Clean Repository

This structure ensures:
- ✅ Clear separation of concerns
- ✅ Easy navigation for new users
- ✅ Organized documentation
- ✅ Developer-friendly tooling
- ✅ Historical preservation
- ✅ Professional appearance

---

Last updated: v1.2.0 (January 5, 2026)
