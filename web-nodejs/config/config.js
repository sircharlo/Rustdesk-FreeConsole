/**
 * BetterDesk Console - Configuration
 * Loads settings from environment variables with sensible defaults
 */

const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

// Read version from package.json
let pkgVersion = '2.0.0';
try {
    const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));
    pkgVersion = pkg.version || pkgVersion;
} catch (e) { /* use default */ }

// Environment detection
const NODE_ENV = process.env.NODE_ENV || 'development';
const isProduction = NODE_ENV === 'production';
const isDocker = fs.existsSync('/.dockerenv') || process.env.DOCKER === 'true';

// Base paths
// Support multiple env var names for compatibility with different install scripts
const DATA_DIR = process.env.DATA_DIR || (isDocker ? '/app/data' : path.join(__dirname, '..', 'data'));
const KEYS_PATH = process.env.KEYS_PATH || process.env.RUSTDESK_DIR || process.env.RUSTDESK_PATH || (isDocker ? '/opt/rustdesk' : '/opt/rustdesk');
const RUSTDESK_DIR = KEYS_PATH;

// Database path
const DB_PATH = process.env.DB_PATH || path.join(RUSTDESK_DIR, 'db_v2.sqlite3');

// Key paths
const PUB_KEY_PATH = process.env.PUB_KEY_PATH || path.join(KEYS_PATH, 'id_ed25519.pub');
const API_KEY_PATH = process.env.API_KEY_PATH || path.join(KEYS_PATH, '.api_key');

// Read API key from file if exists
let hbbsApiKey = process.env.HBBS_API_KEY || '';
if (!hbbsApiKey && fs.existsSync(API_KEY_PATH)) {
    try {
        hbbsApiKey = fs.readFileSync(API_KEY_PATH, 'utf8').trim();
    } catch (err) {
        console.warn('Warning: Could not read API key file:', err.message);
    }
}

// Session secret - generate if not provided
let sessionSecret = process.env.SESSION_SECRET;
if (!sessionSecret) {
    const secretFile = path.join(DATA_DIR, '.session_secret');
    if (fs.existsSync(secretFile)) {
        sessionSecret = fs.readFileSync(secretFile, 'utf8').trim();
    } else {
        sessionSecret = crypto.randomBytes(32).toString('hex');
        try {
            fs.mkdirSync(DATA_DIR, { recursive: true });
            fs.writeFileSync(secretFile, sessionSecret, { mode: 0o600 });
        } catch (err) {
            console.warn('Warning: Could not save session secret:', err.message);
        }
    }
}

module.exports = {
    // Environment
    nodeEnv: NODE_ENV,
    isProduction,
    isDocker,
    
    // Server
    port: parseInt(process.env.PORT, 10) || 5000,
    host: process.env.HOST || '0.0.0.0',
    
    // RustDesk Client API (dedicated WAN-facing port)
    apiPort: parseInt(process.env.API_PORT, 10) || 21121,
    apiEnabled: (process.env.API_ENABLED || 'true').toLowerCase() !== 'false',
    
    // HTTPS / SSL
    httpsEnabled: (process.env.HTTPS_ENABLED || 'false').toLowerCase() === 'true',
    httpsPort: parseInt(process.env.HTTPS_PORT, 10) || 5443,
    sslCertPath: process.env.SSL_CERT_PATH || '',
    sslKeyPath: process.env.SSL_KEY_PATH || '',
    sslCaPath: process.env.SSL_CA_PATH || '',
    httpRedirect: (process.env.HTTP_REDIRECT_HTTPS || 'true').toLowerCase() === 'true',
    
    // Paths
    dataDir: DATA_DIR,
    keysPath: KEYS_PATH,
    rustdeskDir: RUSTDESK_DIR,
    dbPath: DB_PATH,
    pubKeyPath: PUB_KEY_PATH,
    apiKeyPath: API_KEY_PATH,
    
    // HBBS API
    hbbsApiUrl: process.env.HBBS_API_URL || 'http://localhost:21114/api',
    hbbsApiKey: hbbsApiKey,
    hbbsApiTimeout: parseInt(process.env.HBBS_API_TIMEOUT, 10) || 3000,
    
    // Session
    sessionSecret: sessionSecret,
    sessionMaxAge: parseInt(process.env.SESSION_MAX_AGE, 10) || 24 * 60 * 60 * 1000, // 24 hours
    
    // Rate limiting
    rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS, 10) || 60 * 1000, // 1 minute
    rateLimitMax: parseInt(process.env.RATE_LIMIT_MAX, 10) || 100,
    loginRateLimitMax: parseInt(process.env.LOGIN_RATE_LIMIT_MAX, 10) || 5,
    
    // i18n
    defaultLanguage: process.env.DEFAULT_LANGUAGE || 'en',
    langDir: path.join(__dirname, '..', 'lang'),
    
    // WebSocket Proxy (for remote desktop web client)
    wsProxy: {
        hbbsHost: process.env.WS_HBBS_HOST || 'localhost',
        hbbsPort: parseInt(process.env.WS_HBBS_PORT, 10) || 21116,
        hbbrHost: process.env.WS_HBBR_HOST || 'localhost',
        hbbrPort: parseInt(process.env.WS_HBBR_PORT, 10) || 21117
    },
    
    // App info
    appName: 'BetterDesk Console',
    appVersion: pkgVersion
};
