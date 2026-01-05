# BetterDesk Console - Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/yourusername/BetterDeskConsole/releases/tag/v1.0.0
