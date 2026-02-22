/**
 * BetterDesk Console - Server Entry Point
 * Professional Web Management Panel for RustDesk Server
 * 
 * @author UNITRONIX
 * @version 2.1.0
 * @license AGPL-3.0
 */

const express = require('express');
const session = require('express-session');
const cookieParser = require('cookie-parser');
const path = require('path');
const fs = require('fs');
const http = require('http');
const https = require('https');

const config = require('./config/config');
const securityMiddleware = require('./middleware/security');
const { initI18n } = require('./middleware/i18n');
const { apiLimiter } = require('./middleware/rateLimiter');
const { csrfTokenProvider, doubleCsrfProtection } = require('./middleware/csrf');
const authService = require('./services/authService');
const { initWsProxy } = require('./services/wsRelay');
const routes = require('./routes');
const rustdeskApiRoutes = require('./routes/rustdesk-api.routes');
const { getWanMiddlewareStack } = require('./middleware/wanSecurity');

// Create Express app
const app = express();

// Trust proxy (for rate limiting behind reverse proxy)
// Configurable via TRUST_PROXY env var: 0=disabled, 1=single proxy, 'loopback'=localhost only
const trustProxy = process.env.TRUST_PROXY !== undefined ? 
    (isNaN(process.env.TRUST_PROXY) ? process.env.TRUST_PROXY : parseInt(process.env.TRUST_PROXY, 10)) : 1;
app.set('trust proxy', trustProxy);

// View engine setup
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Ensure data directory exists
if (!fs.existsSync(config.dataDir)) {
    fs.mkdirSync(config.dataDir, { recursive: true });
}

// ============ Middleware Pipeline ============

// Security headers (Helmet)
app.use(securityMiddleware);

// Body parsing
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Cookie parsing
app.use(cookieParser());

// Session management
app.use(session({
    secret: config.sessionSecret,
    name: 'betterdesk.sid',
    resave: false,
    saveUninitialized: false,
    cookie: {
        secure: config.httpsEnabled, // Secure cookies when HTTPS is enabled
        httpOnly: true,
        sameSite: 'lax',
        maxAge: config.sessionMaxAge
    }
}));

// Static files
app.use(express.static(path.join(__dirname, 'public'), {
    maxAge: config.isProduction ? '1d' : '0',
    etag: true
}));

// Serve proto files for remote client (protobufjs dynamic loading)
app.use('/protos', express.static(path.join(__dirname, 'protos'), {
    maxAge: config.isProduction ? '7d' : '0',
    etag: true
}));

// Rate limiting for API
app.use('/api/', apiLimiter);

// i18n middleware
app.use(initI18n());

// CSRF protection — generate token for views, validate on POST/PUT/DELETE/PATCH
app.use(csrfTokenProvider);
app.use(doubleCsrfProtection);

// ============ Routes ============

app.use('/', routes);

// ============ Error Handlers ============

// CSRF token mismatch
app.use((err, req, res, next) => {
    if (err.code === 'EBADCSRFTOKEN' || err.message?.includes('csrf')) {
        res.status(403);
        if (req.accepts('html')) {
            return res.render('errors/500', {
                title: 'Forbidden',
                activePage: 'error',
                error: 'Invalid or missing CSRF token. Please refresh the page and try again.'
            });
        }
        return res.json({ success: false, error: 'Invalid CSRF token' });
    }
    next(err);
});

// 404 Not Found
app.use((req, res, next) => {
    res.status(404);
    
    if (req.accepts('html')) {
        res.render('errors/404', {
            title: req.t('errors.not_found'),
            activePage: 'error'
        });
    } else {
        res.json({
            success: false,
            error: 'Not Found'
        });
    }
});

// 500 Server Error
app.use((err, req, res, next) => {
    console.error('Server error:', err);
    
    res.status(err.status || 500);
    
    if (req.accepts('html')) {
        res.render('errors/500', {
            title: req.t('errors.server_error'),
            activePage: 'error',
            error: config.isProduction ? null : err.message
        });
    } else {
        res.json({
            success: false,
            error: config.isProduction ? 'Internal Server Error' : err.message
        });
    }
});

// ============ Startup ============

/**
 * Load SSL certificates for HTTPS
 */
function loadSslCertificates() {
    const options = {};
    
    if (!config.sslCertPath || !config.sslKeyPath) {
        return null;
    }
    
    try {
        if (!fs.existsSync(config.sslCertPath)) {
            console.error(`SSL certificate not found: ${config.sslCertPath}`);
            return null;
        }
        if (!fs.existsSync(config.sslKeyPath)) {
            console.error(`SSL private key not found: ${config.sslKeyPath}`);
            return null;
        }
        
        options.cert = fs.readFileSync(config.sslCertPath);
        options.key = fs.readFileSync(config.sslKeyPath);
        
        // Optional CA bundle (for Let's Encrypt chain)
        if (config.sslCaPath && fs.existsSync(config.sslCaPath)) {
            options.ca = fs.readFileSync(config.sslCaPath);
        }
        
        return options;
    } catch (err) {
        console.error('Failed to load SSL certificates:', err.message);
        return null;
    }
}

/**
 * Create HTTP redirect server (redirects all HTTP to HTTPS)
 */
function createHttpRedirectServer() {
    const redirectApp = express();
    redirectApp.use((req, res) => {
        const httpsUrl = `https://${req.hostname}:${config.httpsPort}${req.url}`;
        res.redirect(301, httpsUrl);
    });
    
    return http.createServer(redirectApp);
}

async function startServer() {
    try {
        // Ensure default admin exists
        await authService.ensureDefaultAdmin();
        
        let server;
        let protocol = 'http';
        let displayPort = config.port;
        
        // HTTPS mode
        if (config.httpsEnabled) {
            const sslOptions = loadSslCertificates();
            
            if (sslOptions) {
                // Create HTTPS server
                server = https.createServer(sslOptions, app);
                protocol = 'https';
                displayPort = config.httpsPort;
                
                server.listen(config.httpsPort, config.host, () => {
                    printStartupBanner(protocol, displayPort);
                });
                
                // Optionally start HTTP redirect server
                if (config.httpRedirect) {
                    const redirectServer = createHttpRedirectServer();
                    redirectServer.listen(config.port, config.host, () => {
                        console.log(`  HTTP -> HTTPS redirect active on port ${config.port}`);
                        console.log('');
                    });
                    
                    // Graceful shutdown for redirect server too
                    const shutdownRedirect = () => { redirectServer.close(); };
                    process.on('SIGTERM', shutdownRedirect);
                    process.on('SIGINT', shutdownRedirect);
                }
            } else {
                console.warn('WARNING: HTTPS enabled but certificates not found/invalid');
                console.warn('Falling back to HTTP mode');
                server = http.createServer(app);
                server.listen(config.port, config.host, () => {
                    printStartupBanner(protocol, config.port);
                });
            }
        } else {
            // HTTP mode (default)
            server = http.createServer(app);
            server.listen(config.port, config.host, () => {
                printStartupBanner(protocol, config.port);
            });
        }
        
        // Initialize WebSocket proxy for remote desktop client
        initWsProxy(server);
        
        // ============ RustDesk Client API Server (dedicated port) ============
        let apiServer = null;
        if (config.apiEnabled) {
            apiServer = startRustDeskApiServer();
        }
        
        // ============ Periodic Housekeeping ============
        const housekeepingInterval = setInterval(() => {
            authService.cleanupHousekeeping();
        }, 60 * 60 * 1000); // Every hour
        
        // Graceful shutdown
        const shutdown = (signal) => {
            console.log(`\n${signal} received. Shutting down gracefully...`);
            clearInterval(housekeepingInterval);
            
            const closePromises = [new Promise(r => server.close(r))];
            if (apiServer) {
                closePromises.push(new Promise(r => apiServer.close(r)));
            }
            
            Promise.all(closePromises).then(() => {
                console.log('All servers closed.');
                process.exit(0);
            });
            
            // Force exit after 10 seconds
            setTimeout(() => {
                console.error('Forced shutdown after timeout');
                process.exit(1);
            }, 10000);
        };
        
        process.on('SIGTERM', () => shutdown('SIGTERM'));
        process.on('SIGINT', () => shutdown('SIGINT'));
        
    } catch (err) {
        console.error('Failed to start server:', err);
        process.exit(1);
    }
}

/**
 * Start the dedicated RustDesk Client API server on a separate port.
 * This is a minimal, hardened Express app with only 4 endpoints.
 * Designed for WAN/internet exposure with aggressive security.
 */
function startRustDeskApiServer() {
    const apiApp = express();

    // Trust proxy (for correct IP extraction behind reverse proxy)
    apiApp.set('trust proxy', 1);

    // Apply WAN security middleware stack
    const wanMiddleware = getWanMiddlewareStack();
    for (const mw of wanMiddleware) {
        apiApp.use(mw);
    }

    // JSON body parser with size limit (64KB for address book sync)
    apiApp.use(express.json({ limit: '64kb', strict: true }));

    // Mount RustDesk-compatible API routes
    apiApp.use('/', rustdeskApiRoutes);

    // Catch-all for any unmatched routes (should not reach here due to pathWhitelist)
    apiApp.use((req, res) => {
        res.status(404).end();
    });

    // Error handler — never leak internal errors
    apiApp.use((err, req, res, next) => {
        if (err.type === 'entity.parse.failed') {
            console.warn('RustDesk API: JSON parse error from', req.socket?.remoteAddress);
            return res.status(400).json({ error: 'Invalid JSON' });
        }
        if (err.type === 'entity.too.large') {
            return res.status(413).json({ error: 'Request too large' });
        }
        console.error('RustDesk API error:', err.message);
        res.status(500).json({ error: 'Server error' });
    });

    // Start HTTP server
    const apiServerInstance = http.createServer(apiApp);
    
    apiServerInstance.on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
            console.error(`  ║   API Port:  ${config.apiPort} FAILED (port in use)`.padEnd(53) + '║');
            console.error(`  ║   Hint: Set API_PORT env var to use different port`.padEnd(53) + '║');
            console.log('  ║                                                  ║');
            console.error(`WARNING: RustDesk Client API could not start on port ${config.apiPort}`);
            console.error('The admin panel continues to run normally on port ' + config.port);
            return; // Don't crash — let the panel continue running
        }
        throw err;
    });
    
    apiServerInstance.listen(config.apiPort, config.host, () => {
        console.log(`  ║   API Port:  ${config.apiPort} (RustDesk Client)`.padEnd(53) + '║');
        console.log('  ║                                                  ║');
    });

    // Set connection timeout (prevent slow loris)
    apiServerInstance.headersTimeout = 15000;
    apiServerInstance.requestTimeout = 10000;
    apiServerInstance.keepAliveTimeout = 5000;

    return apiServerInstance;
}

/**
 * Print startup banner with server info
 */
function printStartupBanner(protocol, port) {
    const sslStatus = config.httpsEnabled ? '🔒 HTTPS' : '🔓 HTTP';
    const apiStatus = config.apiEnabled ? `✅ Port ${config.apiPort}` : '❌ Disabled';
    console.log('');
    console.log('  ╔══════════════════════════════════════════════════╗');
    console.log('  ║                                                  ║');
    console.log('  ║   🖥️  BetterDesk Console v' + config.appVersion.padEnd(23) + '  ║');
    console.log('  ║                                                  ║');
    console.log('  ╠══════════════════════════════════════════════════╣');
    console.log('  ║                                                  ║');
    console.log(`  ║   Panel:     ${protocol}://${config.host}:${port}`.padEnd(53) + '║');
    console.log(`  ║   Client API: ${apiStatus}`.padEnd(53) + '║');
    console.log(`  ║   Mode:      ${config.nodeEnv}`.padEnd(53) + '║');
    console.log(`  ║   Security:  ${sslStatus}`.padEnd(53) + '║');
    console.log(`  ║   Database:  ${path.basename(config.dbPath)}`.padEnd(53) + '║');
    console.log('  ║                                                  ║');
    console.log('  ╚══════════════════════════════════════════════════╝');
    console.log('');
}

// Start the server
startServer();

module.exports = app;
