/**
 * BetterDesk Console - Database Service
 * SQLite3 wrapper using better-sqlite3 (synchronous, fast)
 */

const Database = require('better-sqlite3');
const path = require('path');
const config = require('../config/config');

let db = null;
let authDb = null;

/**
 * Get the main RustDesk database connection
 */
function getDb() {
    if (!db) {
        db = new Database(config.dbPath, {
            readonly: false,
            fileMustExist: false
        });
        db.pragma('journal_mode = WAL');
        db.pragma('foreign_keys = ON');
        
        // Ensure peer table exists with all columns
        ensurePeerTable(db);
    }
    return db;
}

/**
 * Get the auth database connection (separate from RustDesk data)
 */
function getAuthDb() {
    if (!authDb) {
        const authDbPath = path.join(config.dataDir, 'auth.db');
        authDb = new Database(authDbPath, {
            readonly: false,
            fileMustExist: false
        });
        authDb.pragma('journal_mode = WAL');
        
        // Initialize auth tables
        initAuthTables(authDb);
    }
    return authDb;
}

/**
 * Ensure peer table has all required columns
 */
function ensurePeerTable(db) {
    // Create table if not exists
    db.exec(`
        CREATE TABLE IF NOT EXISTS peer (
            id TEXT PRIMARY KEY,
            uuid TEXT DEFAULT '',
            pk BLOB,
            note TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            status_online INTEGER DEFAULT 0,
            last_online TEXT,
            is_deleted INTEGER DEFAULT 0,
            info TEXT DEFAULT '',
            ip TEXT DEFAULT '',
            user TEXT DEFAULT '',
            is_banned INTEGER DEFAULT 0,
            banned_at TEXT,
            banned_reason TEXT DEFAULT ''
        )
    `);
    
    // Add missing columns if they don't exist
    const columns = [
        { name: 'status_online', sql: 'INTEGER DEFAULT 0' },
        { name: 'last_online', sql: 'TEXT' },
        { name: 'is_deleted', sql: 'INTEGER DEFAULT 0' },
        { name: 'user', sql: 'TEXT DEFAULT \'\'' },
        { name: 'is_banned', sql: 'INTEGER DEFAULT 0' },
        { name: 'banned_at', sql: 'TEXT' },
        { name: 'banned_reason', sql: 'TEXT DEFAULT \'\'' },
        { name: 'folder_id', sql: 'INTEGER DEFAULT NULL' }
    ];
    
    const tableInfo = db.prepare("PRAGMA table_info(peer)").all();
    const existingColumns = new Set(tableInfo.map(c => c.name));
    
    for (const col of columns) {
        if (!existingColumns.has(col.name)) {
            try {
                db.exec(`ALTER TABLE peer ADD COLUMN ${col.name} ${col.sql}`);
                console.log(`Added column ${col.name} to peer table`);
            } catch (err) {
                // Column might already exist
            }
        }
    }
}

/**
 * Initialize authentication tables
 */
function initAuthTables(db) {
    db.exec(`
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role TEXT DEFAULT 'admin',
            created_at TEXT DEFAULT (datetime('now')),
            last_login TEXT
        )
    `);
    
    db.exec(`
        CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            action TEXT NOT NULL,
            details TEXT,
            ip_address TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        )
    `);
    
    // Device folders table
    db.exec(`
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            color TEXT DEFAULT '#6366f1',
            icon TEXT DEFAULT 'folder',
            sort_order INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now'))
        )
    `);
}

// ==================== Device Operations ====================

/**
 * Parse info JSON and extract useful fields
 */
function parseDeviceInfo(device) {
    if (!device) return device;
    
    let info = {};
    if (device.info) {
        try {
            info = JSON.parse(device.info);
        } catch (e) {
            // Not valid JSON
        }
    }
    
    return {
        id: device.id,
        hostname: device.note || info.hostname || '',
        username: typeof device.user === 'string' ? device.user : '',
        platform: info.os || info.platform || '',
        ip: info.ip || '',
        note: device.note || '',
        online: device.status_online === 1,
        banned: device.is_banned === 1,
        created_at: device.created_at,
        last_online: device.last_online,
        ban_reason: device.ban_reason || device.banned_reason || '',
        folder_id: device.folder_id || null
    };
}

/**
 * Get all devices with optional filtering
 */
function getAllDevices(filters = {}) {
    const db = getDb();
    let sql = 'SELECT * FROM peer WHERE is_deleted = 0';
    const params = [];
    
    // Search filter
    if (filters.search) {
        sql += ' AND (id LIKE ? OR user LIKE ? OR note LIKE ?)';
        const search = `%${filters.search}%`;
        params.push(search, search, search);
    }
    
    // Status filter
    if (filters.status === 'online') {
        sql += ' AND status_online = 1';
    } else if (filters.status === 'offline') {
        sql += ' AND status_online = 0 AND is_banned = 0';
    } else if (filters.status === 'banned') {
        sql += ' AND is_banned = 1';
    }
    
    // Notes filter
    if (filters.hasNotes) {
        sql += " AND note IS NOT NULL AND note != ''";
    }
    
    // Sorting
    const sortColumn = filters.sortBy || 'last_online';
    const sortOrder = filters.sortOrder === 'asc' ? 'ASC' : 'DESC';
    const allowedColumns = ['id', 'user', 'created_at', 'last_online', 'status_online'];
    if (allowedColumns.includes(sortColumn)) {
        sql += ` ORDER BY ${sortColumn} ${sortOrder} NULLS LAST`;
    } else {
        sql += ' ORDER BY last_online DESC NULLS LAST';
    }
    
    // Note: No pagination in SQL - we load all and paginate client-side for filtering
    const rawDevices = db.prepare(sql).all(...params);
    
    // Transform to consistent format
    return rawDevices.map(parseDeviceInfo);
}

/**
 * Get device by ID
 */
function getDeviceById(id) {
    const device = getDb().prepare('SELECT * FROM peer WHERE id = ? AND is_deleted = 0').get(id);
    return parseDeviceInfo(device);
}

/**
 * Update device (user name, note)
 */
function updateDevice(id, data) {
    const fields = [];
    const params = [];
    
    if (data.user !== undefined) {
        fields.push('user = ?');
        params.push(data.user);
    }
    if (data.note !== undefined) {
        fields.push('note = ?');
        params.push(data.note);
    }
    
    if (fields.length === 0) return { changes: 0 };
    
    params.push(id);
    return getDb().prepare(`UPDATE peer SET ${fields.join(', ')} WHERE id = ?`).run(...params);
}

/**
 * Soft delete device
 */
function deleteDevice(id) {
    return getDb().prepare('UPDATE peer SET is_deleted = 1 WHERE id = ?').run(id);
}

/**
 * Ban/unban device
 */
function setBanStatus(id, banned, reason = '') {
    if (banned) {
        return getDb().prepare(
            'UPDATE peer SET is_banned = 1, banned_at = datetime(\'now\'), banned_reason = ? WHERE id = ?'
        ).run(reason, id);
    } else {
        return getDb().prepare(
            'UPDATE peer SET is_banned = 0, banned_at = NULL, banned_reason = \'\' WHERE id = ?'
        ).run(id);
    }
}

/**
 * Get device statistics
 */
function getStats() {
    const db = getDb();
    const total = db.prepare('SELECT COUNT(*) as count FROM peer WHERE is_deleted = 0').get().count;
    const online = db.prepare('SELECT COUNT(*) as count FROM peer WHERE is_deleted = 0 AND status_online = 1').get().count;
    const banned = db.prepare('SELECT COUNT(*) as count FROM peer WHERE is_deleted = 0 AND is_banned = 1').get().count;
    const withNotes = db.prepare("SELECT COUNT(*) as count FROM peer WHERE is_deleted = 0 AND note IS NOT NULL AND note != ''").get().count;
    
    return {
        total,
        online,
        offline: total - online,
        banned,
        withNotes
    };
}

/**
 * Count devices matching filters (for pagination)
 */
function countDevices(filters = {}) {
    const db = getDb();
    let sql = 'SELECT COUNT(*) as count FROM peer WHERE is_deleted = 0';
    const params = [];
    
    if (filters.search) {
        sql += ' AND (id LIKE ? OR user LIKE ? OR note LIKE ? OR ip LIKE ?)';
        const search = `%${filters.search}%`;
        params.push(search, search, search, search);
    }
    
    if (filters.status === 'online') {
        sql += ' AND status_online = 1';
    } else if (filters.status === 'offline') {
        sql += ' AND status_online = 0';
    } else if (filters.status === 'banned') {
        sql += ' AND is_banned = 1';
    }
    
    if (filters.hasNotes) {
        sql += " AND note IS NOT NULL AND note != ''";
    }
    
    return db.prepare(sql).get(...params).count;
}

// ==================== User Operations ====================

/**
 * Get user by username
 */
function getUserByUsername(username) {
    return getAuthDb().prepare('SELECT * FROM users WHERE username = ?').get(username);
}

/**
 * Get user by ID
 */
function getUserById(id) {
    return getAuthDb().prepare('SELECT * FROM users WHERE id = ?').get(id);
}

/**
 * Create user
 */
function createUser(username, passwordHash, role = 'admin') {
    return getAuthDb().prepare(
        'INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)'
    ).run(username, passwordHash, role);
}

/**
 * Update user password
 */
function updateUserPassword(id, passwordHash) {
    return getAuthDb().prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(passwordHash, id);
}

/**
 * Update last login
 */
function updateLastLogin(id) {
    return getAuthDb().prepare("UPDATE users SET last_login = datetime('now') WHERE id = ?").run(id);
}

/**
 * Check if any users exist
 */
function hasUsers() {
    return getAuthDb().prepare('SELECT COUNT(*) as count FROM users').get().count > 0;
}

// ==================== Audit Log ====================

/**
 * Log an action
 */
function logAction(userId, action, details, ipAddress) {
    return getAuthDb().prepare(
        'INSERT INTO audit_log (user_id, action, details, ip_address) VALUES (?, ?, ?, ?)'
    ).run(userId, action, details, ipAddress);
}

/**
 * Get recent audit logs
 */
function getAuditLogs(limit = 100) {
    return getAuthDb().prepare(
        'SELECT * FROM audit_log ORDER BY created_at DESC LIMIT ?'
    ).all(limit);
}

// ==================== Extended User Operations ====================

/**
 * Get all users
 */
function getAllUsers() {
    return getAuthDb().prepare('SELECT * FROM users ORDER BY created_at DESC').all();
}

/**
 * Update user role
 */
function updateUserRole(id, role) {
    return getAuthDb().prepare('UPDATE users SET role = ? WHERE id = ?').run(role, id);
}

/**
 * Delete user
 */
function deleteUser(id) {
    return getAuthDb().prepare('DELETE FROM users WHERE id = ?').run(id);
}

/**
 * Count admins
 */
function countAdmins() {
    return getAuthDb().prepare("SELECT COUNT(*) as count FROM users WHERE role = 'admin'").get().count;
}

/**
 * Force reset admin password (for installation scripts)
 */
function resetAdminPassword(passwordHash) {
    const admin = getAuthDb().prepare("SELECT * FROM users WHERE role = 'admin' ORDER BY id ASC LIMIT 1").get();
    if (admin) {
        return getAuthDb().prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(passwordHash, admin.id);
    }
    return null;
}

/**
 * Delete all users (for fresh install)
 */
function deleteAllUsers() {
    return getAuthDb().prepare('DELETE FROM users').run();
}

// ==================== Folder Operations ====================

/**
 * Get all folders
 */
function getAllFolders() {
    const db = getAuthDb();
    const folders = db.prepare('SELECT * FROM folders ORDER BY sort_order ASC, name ASC').all();
    
    // Get device count per folder
    const mainDb = getDb();
    return folders.map(folder => {
        const count = mainDb.prepare(
            'SELECT COUNT(*) as count FROM peer WHERE is_deleted = 0 AND folder_id = ?'
        ).get(folder.id);
        return {
            ...folder,
            device_count: count?.count || 0
        };
    });
}

/**
 * Get folder by ID
 */
function getFolderById(id) {
    return getAuthDb().prepare('SELECT * FROM folders WHERE id = ?').get(id);
}

/**
 * Create folder
 */
function createFolder(name, color, icon) {
    return getAuthDb().prepare(
        'INSERT INTO folders (name, color, icon) VALUES (?, ?, ?)'
    ).run(name, color, icon);
}

/**
 * Update folder
 */
function updateFolder(id, updates) {
    const sets = [];
    const params = [];
    
    if (updates.name !== undefined) {
        sets.push('name = ?');
        params.push(updates.name);
    }
    if (updates.color !== undefined) {
        sets.push('color = ?');
        params.push(updates.color);
    }
    if (updates.icon !== undefined) {
        sets.push('icon = ?');
        params.push(updates.icon);
    }
    if (updates.sort_order !== undefined) {
        sets.push('sort_order = ?');
        params.push(updates.sort_order);
    }
    
    if (sets.length === 0) return;
    
    params.push(id);
    return getAuthDb().prepare(
        `UPDATE folders SET ${sets.join(', ')} WHERE id = ?`
    ).run(...params);
}

/**
 * Delete folder
 */
function deleteFolder(id) {
    return getAuthDb().prepare('DELETE FROM folders WHERE id = ?').run(id);
}

/**
 * Assign single device to folder
 */
function assignDeviceToFolder(deviceId, folderId) {
    return getDb().prepare('UPDATE peer SET folder_id = ? WHERE id = ?').run(folderId, deviceId);
}

/**
 * Assign multiple devices to folder
 */
function assignDevicesToFolder(deviceIds, folderId) {
    const db = getDb();
    const stmt = db.prepare('UPDATE peer SET folder_id = ? WHERE id = ?');
    const assignAll = db.transaction((ids) => {
        for (const id of ids) {
            stmt.run(folderId, id);
        }
    });
    return assignAll(deviceIds);
}

/**
 * Unassign all devices from folder
 */
function unassignDevicesFromFolder(folderId) {
    return getDb().prepare('UPDATE peer SET folder_id = NULL WHERE folder_id = ?').run(folderId);
}

/**
 * Get unassigned device count
 */
function getUnassignedDeviceCount() {
    return getDb().prepare(
        'SELECT COUNT(*) as count FROM peer WHERE is_deleted = 0 AND folder_id IS NULL'
    ).get().count;
}

// ==================== Close connections ====================

function closeAll() {
    if (db) {
        db.close();
        db = null;
    }
    if (authDb) {
        authDb.close();
        authDb = null;
    }
}

module.exports = {
    getDb,
    getAuthDb,
    // Devices
    getAllDevices,
    getDeviceById,
    updateDevice,
    deleteDevice,
    setBanStatus,
    getStats,
    countDevices,
    // Users
    getUserByUsername,
    getUserById,
    createUser,
    updateUserPassword,
    updateLastLogin,
    hasUsers,
    getAllUsers,
    updateUserRole,
    deleteUser,
    countAdmins,
    resetAdminPassword,
    deleteAllUsers,
    // Folders
    getAllFolders,
    getFolderById,
    createFolder,
    updateFolder,
    deleteFolder,
    assignDeviceToFolder,
    assignDevicesToFolder,
    unassignDevicesFromFolder,
    getUnassignedDeviceCount,
    // Audit
    logAction,
    getAuditLogs,
    // Cleanup
    closeAll
};
