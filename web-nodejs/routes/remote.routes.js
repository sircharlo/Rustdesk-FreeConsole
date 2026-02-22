/**
 * BetterDesk Console - Remote Desktop Routes
 * Serves the web-based remote desktop viewer page
 */

const express = require('express');
const router = express.Router();
const fs = require('fs');
const db = require('../services/database');
const config = require('../config/config');
const { requireAuth } = require('../middleware/auth');

// Read server public key once at startup
let serverPubKey = '';
try {
    if (fs.existsSync(config.pubKeyPath)) {
        serverPubKey = fs.readFileSync(config.pubKeyPath, 'utf8').trim();
    }
} catch (err) {
    console.warn('Warning: Could not read server public key:', err.message);
}

/**
 * GET /remote/:deviceId - Remote desktop viewer page
 */
router.get('/remote/:deviceId', requireAuth, (req, res) => {
    const deviceId = req.params.deviceId;

    // Validate device ID format
    if (!deviceId || !/^[A-Za-z0-9_-]{3,32}$/.test(deviceId)) {
        return res.redirect('/devices');
    }

    // Look up device in database for display info (optional, not blocking)
    let device = null;
    try {
        const stmt = db.getDatabase().prepare(
            'SELECT id, hostname, platform, note FROM peer WHERE id = ?'
        );
        device = stmt.get(deviceId);
    } catch {
        // Database lookup failure is non-blocking - viewer can still work
    }

    res.render('remote', {
        title: `${req.t('remote.title')} - ${deviceId}`,
        activePage: 'remote',
        deviceId: deviceId,
        device: device || { id: deviceId, hostname: '', platform: '', note: '' },
        serverPubKey: serverPubKey,
        // Use viewer layout instead of main layout
        layout: 'viewer'
    });
});

module.exports = router;
