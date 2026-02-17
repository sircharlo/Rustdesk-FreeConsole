/**
 * BetterDesk Console - Settings Routes
 */

const express = require('express');
const router = express.Router();
const config = require('../config/config');
const hbbsApi = require('../services/hbbsApi');
const keyService = require('../services/keyService');
const db = require('../services/database');
const { requireAuth } = require('../middleware/auth');
const os = require('os');

/**
 * GET /settings - Settings page
 */
router.get('/settings', requireAuth, (req, res) => {
    res.render('settings', {
        title: req.t('nav.settings'),
        activePage: 'settings'
    });
});

/**
 * GET /api/settings/info - Get server configuration info
 */
router.get('/api/settings/info', requireAuth, async (req, res) => {
    try {
        const hbbsHealth = await hbbsApi.getHealth();
        const serverConfig = keyService.getServerConfig();
        const stats = db.getStats();
        
        res.json({
            success: true,
            data: {
                app: {
                    name: config.appName,
                    version: config.appVersion,
                    nodeVersion: process.version,
                    env: config.nodeEnv
                },
                server: {
                    hostname: os.hostname(),
                    platform: os.platform(),
                    arch: os.arch(),
                    uptime: Math.floor(process.uptime()),
                    memoryUsage: process.memoryUsage().heapUsed
                },
                hbbs: hbbsHealth,
                paths: {
                    database: config.dbPath,
                    publicKey: config.pubKeyPath,
                    apiKey: config.apiKeyPath
                },
                stats: stats
            }
        });
    } catch (err) {
        console.error('Get server info error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * GET /api/settings/server-info - Alias for /api/keys/server-info (backward compatibility)
 */
router.get('/api/settings/server-info', requireAuth, (req, res) => {
    try {
        const apiKey = keyService.getApiKey(true);
        
        let serverIp = req.headers['x-forwarded-host'] || req.headers.host || req.hostname || '-';
        serverIp = serverIp.split(':')[0];
        
        res.json({
            success: true,
            data: {
                server_id: serverIp,
                relay_server: serverIp,
                api_key_masked: apiKey || '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022'
            }
        });
    } catch (err) {
        console.error('Get server info error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * GET /api/settings/audit - Get audit log
 */
router.get('/api/settings/audit', requireAuth, (req, res) => {
    try {
        const limit = parseInt(req.query.limit, 10) || 100;
        const logs = db.getAuditLogs(limit);
        
        res.json({
            success: true,
            data: logs
        });
    } catch (err) {
        console.error('Get audit logs error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

module.exports = router;
