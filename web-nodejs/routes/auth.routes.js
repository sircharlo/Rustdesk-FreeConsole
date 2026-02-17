/**
 * BetterDesk Console - Auth Routes
 * Login, logout, session verification
 */

const express = require('express');
const router = express.Router();
const authService = require('../services/authService');
const db = require('../services/database');
const { guestOnly, requireAuth } = require('../middleware/auth');
const { loginLimiter, passwordChangeLimiter } = require('../middleware/rateLimiter');

/**
 * GET /login - Login page
 */
router.get('/login', guestOnly, (req, res) => {
    res.render('login', {
        title: req.t('nav.login'),
        activePage: 'login'
    });
});

/**
 * POST /api/auth/login - Login API
 */
router.post('/api/auth/login', loginLimiter, async (req, res) => {
    try {
        const { username, password } = req.body;
        
        if (!username || !password) {
            return res.status(400).json({
                success: false,
                error: req.t('auth.invalid_credentials')
            });
        }
        
        const user = await authService.authenticate(username, password);
        
        if (!user) {
            // Log failed attempt
            db.logAction(null, 'login_failed', `Username: ${username}`, req.ip);
            
            return res.status(401).json({
                success: false,
                error: req.t('auth.invalid_credentials')
            });
        }
        
        // Set session
        req.session.userId = user.id;
        req.session.user = user;
        
        // Log successful login
        db.logAction(user.id, 'login', `User logged in`, req.ip);
        
        res.json({
            success: true,
            user: {
                username: user.username,
                role: user.role
            }
        });
    } catch (err) {
        console.error('Login error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * POST /api/auth/logout - Logout API
 */
router.post('/api/auth/logout', (req, res) => {
    const userId = req.session?.userId;
    
    if (userId) {
        db.logAction(userId, 'logout', 'User logged out', req.ip);
    }
    
    req.session.destroy((err) => {
        if (err) {
            console.error('Session destroy error:', err);
        }
        res.clearCookie('connect.sid');
        res.json({ success: true });
    });
});

/**
 * GET /api/auth/verify - Verify session is valid
 */
router.get('/api/auth/verify', requireAuth, (req, res) => {
    res.json({
        success: true,
        user: req.session.user
    });
});

/**
 * POST /api/auth/password - Change password
 */
router.post('/api/auth/password', requireAuth, passwordChangeLimiter, async (req, res) => {
    try {
        const { currentPassword, newPassword, confirmPassword } = req.body;
        
        if (!currentPassword || !newPassword) {
            return res.status(400).json({
                success: false,
                error: req.t('auth.password_required')
            });
        }
        
        if (newPassword !== confirmPassword) {
            return res.status(400).json({
                success: false,
                error: req.t('auth.passwords_mismatch')
            });
        }
        
        const result = await authService.changePassword(
            req.session.userId,
            currentPassword,
            newPassword
        );
        
        if (!result.success) {
            return res.status(400).json({
                success: false,
                error: result.error
            });
        }
        
        // Log password change
        db.logAction(req.session.userId, 'password_changed', 'Password changed', req.ip);
        
        res.json({ success: true });
    } catch (err) {
        console.error('Password change error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * GET /logout - Logout (redirect)
 */
router.get('/logout', (req, res) => {
    req.session.destroy(() => {
        res.clearCookie('connect.sid');
        res.redirect('/login');
    });
});

module.exports = router;
