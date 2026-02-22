/**
 * BetterDesk Console - WAN API Security Middleware
 * 
 * Hardened security layer for the internet-facing RustDesk Client API (port 21114).
 * This middleware stack is applied ONLY to the dedicated API port, not the admin panel.
 * 
 * Security layers:
 *   1. Request size limit (1KB max body)
 *   2. Strict CORS (no browser access)
 *   3. Security headers (no information leakage)
 *   4. JSON-only content type enforcement
 *   5. Path whitelist (only 4 endpoints allowed)
 *   6. Rate limiting (aggressive per-IP)
 *   7. Request timeout (10s max)
 * 
 * @author UNITRONIX
 * @version 1.0.0
 */

const rateLimit = require('express-rate-limit');

/**
 * Allowed paths on the WAN API port.
 * Everything else returns 404 — zero attack surface.
 */
const ALLOWED_PATHS = new Set([
    '/api/login',
    '/api/logout',
    '/api/currentUser',
    '/api/login-options',
    '/api/heartbeat',
    '/api/sysinfo',
    '/api/ab',
    '/api/ab/personal',
    '/api/ab/tags',
    '/api/audit',
    '/api/users',
    '/api/peers',
    '/api/device-group',
    '/api/device-group/accessible',
    '/api/user/group',
    '/api/software',
    '/api/software/client-download-link'
]);

const ALLOWED_METHODS = {
    '/api/login': 'POST',
    '/api/logout': 'POST',
    '/api/currentUser': 'GET',
    '/api/login-options': 'GET',
    '/api/heartbeat': 'POST',
    '/api/sysinfo': 'POST',
    '/api/ab': '*',
    '/api/ab/personal': '*',
    '/api/ab/tags': 'GET',
    '/api/audit': 'GET',
    '/api/users': 'GET',
    '/api/peers': 'GET',
    '/api/device-group': 'GET',
    '/api/device-group/accessible': 'GET',
    '/api/user/group': 'GET',
    '/api/software': 'GET',
    '/api/software/client-download-link': 'GET'
};

/**
 * Maximum request body size in bytes (1KB — login payload is ~200 bytes)
 */
const MAX_BODY_SIZE = 1024;

/**
 * Path whitelist — reject any request not matching allowed endpoints
 */
function pathWhitelist(req, res, next) {
    if (!ALLOWED_PATHS.has(req.path)) {
        return res.status(404).end();
    }

    // Enforce correct HTTP method (* allows any method)
    const expectedMethod = ALLOWED_METHODS[req.path];
    if (expectedMethod && expectedMethod !== '*' && req.method !== expectedMethod && req.method !== 'OPTIONS') {
        return res.status(405).end();
    }

    next();
}

/**
 * Security headers for WAN-facing API
 * Strips all unnecessary information, prevents caching
 */
function securityHeaders(req, res, next) {
    // Remove server identification
    res.removeHeader('X-Powered-By');

    // Prevent caching of API responses (tokens, user data)
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, private');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');

    // Security headers
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '0');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Permissions-Policy', 'accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), usb=()');

    // Strict Content-Security-Policy (no HTML/JS/CSS on this port)
    res.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");

    // CORS — restrictive (RustDesk desktop client doesn't need CORS)
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.setHeader('Access-Control-Max-Age', '86400');

    // Handle OPTIONS preflight
    if (req.method === 'OPTIONS') {
        return res.status(204).end();
    }

    next();
}

/**
 * Content-Type enforcement — only accept application/json for POST
 */
function jsonOnly(req, res, next) {
    if (req.method === 'POST') {
        const contentType = req.headers['content-type'] || '';
        if (!contentType.includes('application/json')) {
            return res.status(415).json({ error: 'Content-Type must be application/json' });
        }
    }
    next();
}

/**
 * Request body size limit
 */
function bodySizeLimit(req, res, next) {
    let size = 0;
    const maxSize = MAX_BODY_SIZE;

    req.on('data', (chunk) => {
        size += chunk.length;
        if (size > maxSize) {
            req.destroy();
            res.status(413).json({ error: 'Request too large' });
        }
    });

    next();
}

/**
 * Request timeout — prevent slow loris attacks
 */
function requestTimeout(req, res, next) {
    req.setTimeout(10000, () => {
        res.status(408).end();
    });
    next();
}

/**
 * Aggressive rate limiter for the WAN API port
 * 5 requests per minute per IP for login, 20 globally
 */
const wanLoginLimiter = rateLimit({
    windowMs: 60 * 1000, // 1 minute window
    max: 5, // 5 attempts per IP per minute
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many requests, please try again later' },
    keyGenerator: (req) => {
        return req.headers['x-forwarded-for']?.split(',')[0]?.trim()
            || req.headers['x-real-ip']
            || req.socket?.remoteAddress
            || 'unknown';
    },
    skip: (req) => {
        // Only rate-limit login and logout, not currentUser or login-options
        return req.path !== '/api/login' && req.path !== '/api/logout';
    }
});

/**
 * Global rate limiter for all API endpoints on this port
 */
const wanGlobalLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 30, // 30 requests per IP per minute total
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many requests' },
    keyGenerator: (req) => {
        return req.headers['x-forwarded-for']?.split(',')[0]?.trim()
            || req.headers['x-real-ip']
            || req.socket?.remoteAddress
            || 'unknown';
    }
});

/**
 * Log all requests to this port (security audit trail)
 */
function requestLogger(req, res, next) {
    const ip = req.headers['x-forwarded-for']?.split(',')[0]?.trim()
        || req.headers['x-real-ip']
        || req.socket?.remoteAddress
        || 'unknown';
    const start = Date.now();

    res.on('finish', () => {
        const duration = Date.now() - start;
        const msg = `[API:${req.method}] ${req.path} ${res.statusCode} ${duration}ms IP:${ip}`;

        if (res.statusCode >= 400) {
            console.warn(msg);
        } else {
            console.log(msg);
        }
    });

    next();
}

/**
 * Get the complete middleware stack for WAN API
 * Apply these in order to the Express app on port 21114
 */
function getWanMiddlewareStack() {
    return [
        requestTimeout,
        securityHeaders,
        requestLogger,
        pathWhitelist,
        wanGlobalLimiter,
        wanLoginLimiter,
        bodySizeLimit,
        jsonOnly
    ];
}

module.exports = {
    pathWhitelist,
    securityHeaders,
    jsonOnly,
    bodySizeLimit,
    requestTimeout,
    wanLoginLimiter,
    wanGlobalLimiter,
    requestLogger,
    getWanMiddlewareStack
};
