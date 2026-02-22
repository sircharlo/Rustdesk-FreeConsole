/**
 * BetterDesk Console - CSRF Protection Middleware
 * Uses csrf-csrf (double-submit cookie pattern) for stateless CSRF protection.
 * 
 * Token flow:
 *   1. Server generates token, sets it as a cookie + passes to EJS views
 *   2. Client JS reads window.BetterDesk.csrfToken and sends it in X-CSRF-Token header
 *   3. Middleware validates header matches cookie on state-changing requests (POST/PUT/DELETE/PATCH)
 */

const { doubleCsrf } = require('csrf-csrf');
const config = require('../config/config');

const {
    generateToken,
    doubleCsrfProtection
} = doubleCsrf({
    getSecret: () => config.sessionSecret,
    cookieName: '__csrf',
    cookieOptions: {
        httpOnly: true,
        sameSite: 'lax',
        secure: config.httpsEnabled,
        path: '/'
    },
    getTokenFromRequest: (req) => {
        // Read token from X-CSRF-Token header (set by public/js/utils.js)
        return req.headers['x-csrf-token'] || req.body?._csrf || '';
    }
});

/**
 * Middleware that generates a CSRF token and makes it available to views.
 * Must be applied AFTER cookie-parser and session middleware.
 */
function csrfTokenProvider(req, res, next) {
    // Generate token (also sets the cookie)
    const token = generateToken(req, res);

    // Make token available in all rendered views
    res.locals.csrfToken = token;

    next();
}

module.exports = {
    csrfTokenProvider,
    doubleCsrfProtection
};
