/**
 * BetterDesk Console - Server Entry Point
 * Professional Web Management Panel for RustDesk Server
 * 
 * @author UNITRONIX
 * @version 2.0.0
 * @license AGPL-3.0
 */

const express = require('express');
const session = require('express-session');
const cookieParser = require('cookie-parser');
const path = require('path');
const fs = require('fs');

const config = require('./config/config');
const securityMiddleware = require('./middleware/security');
const { initI18n } = require('./middleware/i18n');
const { apiLimiter } = require('./middleware/rateLimiter');
const authService = require('./services/authService');
const routes = require('./routes');

// Create Express app
const app = express();

// Trust proxy (for rate limiting behind reverse proxy)
app.set('trust proxy', 1);

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
        secure: false, // Set to true only if using HTTPS reverse proxy
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

// Rate limiting for API
app.use('/api/', apiLimiter);

// i18n middleware
app.use(initI18n());

// ============ Routes ============

app.use('/', routes);

// ============ Error Handlers ============

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

async function startServer() {
    try {
        // Ensure default admin exists
        await authService.ensureDefaultAdmin();
        
        // Start HTTP server
        const server = app.listen(config.port, config.host, () => {
            console.log('');
            console.log('  ╔══════════════════════════════════════════════════╗');
            console.log('  ║                                                  ║');
            console.log('  ║   🖥️  BetterDesk Console v' + config.appVersion.padEnd(23) + '  ║');
            console.log('  ║                                                  ║');
            console.log('  ╠══════════════════════════════════════════════════╣');
            console.log('  ║                                                  ║');
            console.log(`  ║   Server:    http://${config.host}:${config.port}`.padEnd(53) + '║');
            console.log(`  ║   Mode:      ${config.nodeEnv}`.padEnd(53) + '║');
            console.log(`  ║   Database:  ${path.basename(config.dbPath)}`.padEnd(53) + '║');
            console.log('  ║                                                  ║');
            console.log('  ╚══════════════════════════════════════════════════╝');
            console.log('');
        });
        
        // Graceful shutdown
        const shutdown = (signal) => {
            console.log(`\n${signal} received. Shutting down gracefully...`);
            server.close(() => {
                console.log('Server closed.');
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

// Start the server
startServer();

module.exports = app;
