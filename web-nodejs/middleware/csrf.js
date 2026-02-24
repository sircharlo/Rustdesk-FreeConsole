/**
 * BetterDesk Console - CSRF Protection Middleware
 * Uses csrf-csrf (double-submit cookie pattern) for stateless CSRF protection.
 *
 * Token flow:
 *   1. Server generates token, sets it as a cookie + passes to EJS views
 *   2. Client JS reads window.BetterDesk.csrfToken and sends it in X-CSRF-Token header
 *   3. Middleware validates header matches cookie on state-changing requests (POST/PUT/DELETE/PATCH)
 */

const { doubleCsrf } = require("csrf-csrf");
const config = require("../config/config");

const { generateToken, doubleCsrfProtection: internalProtection } = doubleCsrf({
  getSecret: () => config.sessionSecret,
  cookieName: "__csrf",
  cookieOptions: {
    httpOnly: true,
    sameSite: "lax",
    secure: config.httpsEnabled,
    path: "/",
  },
  // Explicitly ignore GET, HEAD, and OPTIONS requests
  ignoredMethods: ["GET", "HEAD", "OPTIONS"],
  getTokenFromRequest: (req) => {
    // Read token from X-CSRF-Token header (set by public/js/utils.js)
    const token = req.headers["x-csrf-token"] || req.body?._csrf || "";
    // Only log missing tokens for state-changing requests
    if (!["GET", "HEAD", "OPTIONS"].includes(req.method) && !token) {
      console.warn(`CSRF: Missing token for ${req.method} ${req.path}`);
    }
    return token;
  },
});

/**
 * Wrapped protection middleware that GUARANTEES GET requests are skipped.
 * This works around issues where the library might still attempt validation on GET.
 */
function doubleCsrfProtection(req, res, next) {
  console.log(`[CSRF Protection] Checking ${req.method} ${req.path}`);
  if (["GET", "HEAD", "OPTIONS"].includes(req.method)) {
    console.log(`[CSRF Protection] Skipping validation for ${req.method}`);
    return next();
  }
  console.log(`[CSRF Protection] Validating token for ${req.method}`);
  return internalProtection(req, res, next);
}

/**
 * Middleware that generates a CSRF token and makes it available to views.
 * Must be applied AFTER cookie-parser and session middleware.
 */
function csrfTokenProvider(req, res, next) {
  try {
    // Generate token (also sets the cookie)
    const token = generateToken(req, res);

    // Make token available in all rendered views
    res.locals.csrfToken = token;

    next();
  } catch (err) {
    if (err.message === "invalid csrf token") {
      console.warn(
        `[CSRF] Corrupt cookie detected for ${req.path} - clearing and retrying`,
      );
      // Clear the cookie that is likely causing the "invalid csrf token" error during generation
      res.clearCookie("__csrf");

      try {
        // Try generating again with a clean state
        const token = generateToken(req, res);
        res.locals.csrfToken = token;
        return next();
      } catch (retryErr) {
        console.error(`[CSRF] Retry failed:`, retryErr.message);
      }
    }

    console.error(
      `[CSRF Provider Error] ${req.method} ${req.path}:`,
      err.message,
    );
    next(err);
  }
}

module.exports = {
  csrfTokenProvider,
  doubleCsrfProtection,
};
