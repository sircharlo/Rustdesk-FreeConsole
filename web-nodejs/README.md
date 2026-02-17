# BetterDesk Console v2.0 (Node.js)

Modern web management console for RustDesk/BetterDesk server.

## Features

- 🎨 **Modern UI** - Dark theme, responsive design, Google Material Icons
- 🌍 **Multilingual** - English and Polish support, easy to add more
- 🔐 **Secure** - Session-based authentication, bcrypt password hashing, rate limiting
- 📱 **Devices** - View, search, filter, ban/unban, change ID, bulk delete
- 🔑 **Keys** - View public key, download file, QR code for mobile
- ⚙️ **Generator** - Generate client configuration strings
- 📊 **Dashboard** - Server status, device statistics

## Requirements

- **Node.js** 18.x or 20.x
- **npm** 9.x or later
- **SQLite3** (for better-sqlite3)

## Installation

### Development

```bash
cd web-nodejs
npm install
npm run dev
```

### Production

```bash
cd web-nodejs
npm install --production
npm start
```

### Docker

```bash
docker build -f Dockerfile.console.node -t betterdesk-console .
docker run -d -p 5000:5000 \
  -v /opt/rustdesk:/opt/rustdesk \
  -e SESSION_SECRET=your-secret-here \
  betterdesk-console
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `5000` | HTTP server port |
| `NODE_ENV` | `development` | Environment (`development` / `production`) |
| `DB_PATH` | `/opt/rustdesk/db_v2.sqlite3` | Path to SQLite database |
| `KEYS_PATH` | `/opt/rustdesk` | Path to key files directory |
| `SESSION_SECRET` | auto-generated | Session cookie secret |
| `HBBS_API_URL` | `http://127.0.0.1:21114` | HBBS API endpoint |
| `DEFAULT_LANG` | `en` | Default language code |

## Project Structure

```
web-nodejs/
├── config/
│   └── config.js        # Environment configuration
├── lang/
│   ├── en.json          # English translations
│   └── pl.json          # Polish translations
├── middleware/
│   ├── auth.js          # Authentication middleware
│   ├── i18n.js          # Language detection
│   ├── rateLimiter.js   # Rate limiting
│   └── security.js      # Security headers
├── public/
│   ├── css/             # Stylesheets
│   ├── js/              # Client-side JavaScript
│   └── favicon.svg      # App icon
├── routes/
│   ├── auth.routes.js   # Login/logout endpoints
│   ├── dashboard.routes.js
│   ├── devices.routes.js
│   ├── generator.routes.js
│   ├── i18n.routes.js
│   ├── index.js         # Route mounting
│   ├── keys.routes.js
│   └── settings.routes.js
├── services/
│   ├── authService.js   # Password hashing
│   ├── database.js      # SQLite operations
│   ├── hbbsApi.js       # HBBS REST API client
│   ├── i18nService.js   # Translation manager
│   └── keyService.js    # Key file operations
├── views/
│   ├── errors/          # Error pages
│   ├── layouts/         # Base templates
│   ├── partials/        # Reusable components
│   └── *.ejs            # Page templates
├── package.json
└── server.js            # Application entry point
```

## API Endpoints

### Authentication

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/login` | Login with username/password |
| POST | `/api/auth/logout` | Logout current session |
| GET | `/api/auth/verify` | Verify current session |
| POST | `/api/auth/password` | Change password |

### Devices

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/devices` | List all devices |
| GET | `/api/devices/:id` | Get device details |
| DELETE | `/api/devices/:id` | Delete device |
| POST | `/api/devices/:id/ban` | Ban device |
| POST | `/api/devices/:id/unban` | Unban device |
| POST | `/api/devices/:id/change-id` | Change device ID |
| POST | `/api/devices/bulk-delete` | Delete multiple devices |

### Keys

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/keys/public` | Get public key |
| GET | `/api/keys/qr` | Get public key as QR code |
| GET | `/api/keys/download` | Download key file |

### Other

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/stats` | Device statistics |
| GET | `/api/server/status` | Server status |
| POST | `/api/sync-status` | Sync online status from HBBS |
| GET | `/api/settings/server-info` | Server information |
| GET | `/api/settings/audit-log` | Audit log entries |

## Default Credentials

- **Username:** `admin`
- **Password:** `admin`

⚠️ **Change the default password immediately after installation!**

## Adding Languages

1. Copy `lang/en.json` to `lang/xx.json` (where `xx` is language code)
2. Translate all values (keep keys unchanged)
3. Update `meta.lang`, `meta.name`, `meta.native_name`
4. Restart the application

## License

MIT License - see LICENSE file for details.
