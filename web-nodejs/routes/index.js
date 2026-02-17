/**
 * BetterDesk Console - Routes Index
 * Mounts all route modules
 */

const express = require('express');
const router = express.Router();

const authRoutes = require('./auth.routes');
const dashboardRoutes = require('./dashboard.routes');
const devicesRoutes = require('./devices.routes');
const keysRoutes = require('./keys.routes');
const settingsRoutes = require('./settings.routes');
const generatorRoutes = require('./generator.routes');
const i18nRoutes = require('./i18n.routes');
const usersRoutes = require('./users.routes');
const foldersRoutes = require('./folders.routes');

// Health check (no auth required)
router.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Mount routes
router.use('/', authRoutes);
router.use('/', dashboardRoutes);
router.use('/', devicesRoutes);
router.use('/', keysRoutes);
router.use('/', settingsRoutes);
router.use('/', generatorRoutes);
router.use('/', usersRoutes);
router.use('/', foldersRoutes);
router.use('/api/i18n', i18nRoutes);

module.exports = router;
