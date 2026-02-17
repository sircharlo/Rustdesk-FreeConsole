/**
 * BetterDesk Console - Auth Service
 * Handles user authentication, password hashing, session management
 */

const bcrypt = require('bcrypt');
const db = require('./database');
const config = require('../config/config');

const SALT_ROUNDS = 12;

/**
 * Hash a password using bcrypt
 */
async function hashPassword(password) {
    return bcrypt.hash(password, SALT_ROUNDS);
}

/**
 * Verify password against hash
 */
async function verifyPassword(password, hash) {
    return bcrypt.compare(password, hash);
}

/**
 * Authenticate user with username and password
 */
async function authenticate(username, password) {
    const user = db.getUserByUsername(username);
    
    if (!user) {
        // Timing-safe: still do a hash comparison to prevent timing attacks
        await bcrypt.compare(password, '$2b$12$invalid.hash.to.prevent.timing.attacks');
        return null;
    }
    
    const valid = await verifyPassword(password, user.password_hash);
    if (!valid) {
        return null;
    }
    
    // Update last login
    db.updateLastLogin(user.id);
    
    return {
        id: user.id,
        username: user.username,
        role: user.role
    };
}

/**
 * Create default admin user if no users exist
 */
async function ensureDefaultAdmin() {
    if (db.hasUsers()) {
        return false;
    }
    
    const defaultUsername = process.env.DEFAULT_ADMIN_USERNAME || 'admin';
    const defaultPassword = process.env.DEFAULT_ADMIN_PASSWORD || 'admin';
    
    const hash = await hashPassword(defaultPassword);
    db.createUser(defaultUsername, hash, 'admin');
    
    console.log(`Created default admin user: ${defaultUsername}`);
    console.log('IMPORTANT: Change the default password immediately!');
    
    return true;
}

/**
 * Change user password
 */
async function changePassword(userId, currentPassword, newPassword) {
    const user = db.getUserById(userId);
    if (!user) {
        return { success: false, error: 'User not found' };
    }
    
    const valid = await verifyPassword(currentPassword, user.password_hash);
    if (!valid) {
        return { success: false, error: 'Current password is incorrect' };
    }
    
    // Validate new password strength
    if (newPassword.length < 6) {
        return { success: false, error: 'Password must be at least 6 characters' };
    }
    
    const newHash = await hashPassword(newPassword);
    db.updateUserPassword(userId, newHash);
    
    return { success: true };
}

/**
 * Validate password strength
 */
function validatePasswordStrength(password) {
    const result = {
        score: 0,
        feedback: []
    };
    
    if (password.length >= 8) result.score += 1;
    else result.feedback.push('Use at least 8 characters');
    
    if (password.length >= 12) result.score += 1;
    
    if (/[a-z]/.test(password)) result.score += 1;
    else result.feedback.push('Add lowercase letters');
    
    if (/[A-Z]/.test(password)) result.score += 1;
    else result.feedback.push('Add uppercase letters');
    
    if (/[0-9]/.test(password)) result.score += 1;
    else result.feedback.push('Add numbers');
    
    if (/[^a-zA-Z0-9]/.test(password)) result.score += 1;
    else result.feedback.push('Add special characters');
    
    result.strength = result.score <= 2 ? 'weak' : result.score <= 4 ? 'medium' : 'strong';
    
    return result;
}

module.exports = {
    hashPassword,
    verifyPassword,
    authenticate,
    ensureDefaultAdmin,
    changePassword,
    validatePasswordStrength
};
