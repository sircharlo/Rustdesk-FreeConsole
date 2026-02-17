/**
 * BetterDesk Console - Security Middleware
 * Configures Helmet and custom security headers
 */

const helmet = require('helmet');
const config = require('../config/config');

/**
 * Configure Helmet with appropriate CSP for our app
 * Note: Disabled some policies for HTTP internal network use
 */
const helmetMiddleware = helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'", "'unsafe-inline'"], // Allow inline scripts for EJS
            styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
            fontSrc: ["'self'", "https://fonts.gstatic.com"],
            imgSrc: ["'self'", "data:", "blob:"],
            connectSrc: ["'self'"],
            frameSrc: ["'none'"],
            objectSrc: ["'none'"],
            baseUri: ["'self'"],
            formAction: ["'self'"],
            upgradeInsecureRequests: null // Don't force HTTPS
        }
    },
    crossOriginEmbedderPolicy: false,
    crossOriginResourcePolicy: false,
    crossOriginOpenerPolicy: false, // Disable for HTTP
    originAgentCluster: false, // Disable for HTTP
    strictTransportSecurity: false // Disable HSTS for HTTP
});

/**
 * Custom security headers
 */
function customSecurityHeaders(req, res, next) {
    // Prevent clickjacking
    res.setHeader('X-Frame-Options', 'DENY');
    
    // Prevent MIME type sniffing
    res.setHeader('X-Content-Type-Options', 'nosniff');
    
    // XSS Protection (legacy browsers)
    res.setHeader('X-XSS-Protection', '1; mode=block');
    
    // Referrer policy
    res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
    
    // Permissions policy
    res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
    
    next();
}

/**
 * Combined security middleware
 */
function securityMiddleware(req, res, next) {
    helmetMiddleware(req, res, () => {
        customSecurityHeaders(req, res, next);
    });
}

module.exports = securityMiddleware;
