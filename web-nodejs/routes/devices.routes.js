/**
 * BetterDesk Console - Devices Routes
 */

const express = require('express');
const router = express.Router();
const db = require('../services/database');
const hbbsApi = require('../services/hbbsApi');
const { requireAuth } = require('../middleware/auth');

/**
 * GET /devices - Devices list page
 */
router.get('/devices', requireAuth, (req, res) => {
    res.render('devices', {
        title: req.t('nav.devices'),
        activePage: 'devices'
    });
});

/**
 * GET /api/devices - Get devices list (JSON)
 */
router.get('/api/devices', requireAuth, (req, res) => {
    try {
        const filters = {
            search: req.query.search || '',
            status: req.query.status || '',
            hasNotes: req.query.hasNotes === 'true',
            sortBy: req.query.sortBy || 'last_online',
            sortOrder: req.query.sortOrder || 'desc'
        };
        
        const devices = db.getAllDevices(filters);
        
        res.json({
            success: true,
            data: {
                devices,
                total: devices.length
            }
        });
    } catch (err) {
        console.error('Get devices error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * GET /api/devices/:id - Get single device
 */
router.get('/api/devices/:id', requireAuth, (req, res) => {
    try {
        const device = db.getDeviceById(req.params.id);
        
        if (!device) {
            return res.status(404).json({
                success: false,
                error: req.t('devices.not_found')
            });
        }
        
        res.json({
            success: true,
            data: device
        });
    } catch (err) {
        console.error('Get device error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * PATCH /api/devices/:id - Update device (name, note)
 */
router.patch('/api/devices/:id', requireAuth, (req, res) => {
    try {
        const { user, note } = req.body;
        const id = req.params.id;
        
        // Check device exists
        const device = db.getDeviceById(id);
        if (!device) {
            return res.status(404).json({
                success: false,
                error: req.t('devices.not_found')
            });
        }
        
        const result = db.updateDevice(id, { user, note });
        
        // Log action
        db.logAction(req.session.userId, 'device_updated', `Device ${id} updated`, req.ip);
        
        res.json({
            success: true,
            data: { changes: result.changes }
        });
    } catch (err) {
        console.error('Update device error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * DELETE /api/devices/:id - Delete device (soft delete)
 */
router.delete('/api/devices/:id', requireAuth, (req, res) => {
    try {
        const id = req.params.id;
        
        const device = db.getDeviceById(id);
        if (!device) {
            return res.status(404).json({
                success: false,
                error: req.t('devices.not_found')
            });
        }
        
        db.deleteDevice(id);
        
        // Log action
        db.logAction(req.session.userId, 'device_deleted', `Device ${id} deleted`, req.ip);
        
        res.json({ success: true });
    } catch (err) {
        console.error('Delete device error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * POST /api/devices/:id/ban - Ban device
 */
router.post('/api/devices/:id/ban', requireAuth, (req, res) => {
    try {
        const id = req.params.id;
        const { reason } = req.body;
        
        const device = db.getDeviceById(id);
        if (!device) {
            return res.status(404).json({
                success: false,
                error: req.t('devices.not_found')
            });
        }
        
        db.setBanStatus(id, true, reason || '');
        
        // Log action
        db.logAction(req.session.userId, 'device_banned', `Device ${id} banned: ${reason}`, req.ip);
        
        res.json({ success: true });
    } catch (err) {
        console.error('Ban device error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * POST /api/devices/:id/unban - Unban device
 */
router.post('/api/devices/:id/unban', requireAuth, (req, res) => {
    try {
        const id = req.params.id;
        
        const device = db.getDeviceById(id);
        if (!device) {
            return res.status(404).json({
                success: false,
                error: req.t('devices.not_found')
            });
        }
        
        db.setBanStatus(id, false);
        
        // Log action
        db.logAction(req.session.userId, 'device_unbanned', `Device ${id} unbanned`, req.ip);
        
        res.json({ success: true });
    } catch (err) {
        console.error('Unban device error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * POST /api/devices/:id/change-id - Change device ID
 */
router.post('/api/devices/:id/change-id', requireAuth, async (req, res) => {
    try {
        const oldId = req.params.id;
        const { newId } = req.body;
        
        if (!newId || newId.length < 6 || newId.length > 16) {
            return res.status(400).json({
                success: false,
                error: req.t('devices.invalid_id')
            });
        }
        
        // Validate format (alphanumeric + dash + underscore)
        if (!/^[A-Za-z0-9_-]+$/.test(newId)) {
            return res.status(400).json({
                success: false,
                error: req.t('devices.invalid_id_format')
            });
        }
        
        // Check if new ID already exists
        const existing = db.getDeviceById(newId);
        if (existing) {
            return res.status(400).json({
                success: false,
                error: req.t('devices.id_exists')
            });
        }
        
        // Try to change via HBBS API
        const result = await hbbsApi.changePeerId(oldId, newId);
        
        if (!result || !result.success) {
            return res.status(400).json({
                success: false,
                error: result?.error || req.t('devices.change_id_failed')
            });
        }
        
        // Log action
        db.logAction(req.session.userId, 'device_id_changed', `Device ID changed from ${oldId} to ${newId}`, req.ip);
        
        res.json({ success: true });
    } catch (err) {
        console.error('Change ID error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

/**
 * POST /api/devices/bulk-delete - Delete multiple devices
 */
router.post('/api/devices/bulk-delete', requireAuth, (req, res) => {
    try {
        const { ids } = req.body;
        
        if (!Array.isArray(ids) || ids.length === 0) {
            return res.status(400).json({
                success: false,
                error: req.t('devices.no_selection')
            });
        }
        
        let deleted = 0;
        for (const id of ids) {
            const result = db.deleteDevice(id);
            deleted += result.changes;
        }
        
        // Log action
        db.logAction(req.session.userId, 'devices_bulk_deleted', `${deleted} devices deleted`, req.ip);
        
        res.json({
            success: true,
            data: { deleted }
        });
    } catch (err) {
        console.error('Bulk delete error:', err);
        res.status(500).json({
            success: false,
            error: req.t('errors.server_error')
        });
    }
});

module.exports = router;
