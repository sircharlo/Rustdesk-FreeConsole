const config = require('./config/config');
const db = require('./services/database');

console.log('Config:');
console.log('  DB_PATH:', config.dbPath);
console.log('  DATA_DIR:', config.dataDir);
console.log('  KEYS_PATH:', config.keysPath);
console.log('');

try {
    const devices = db.getAllDevices({});
    console.log('Total devices:', devices.length);
    console.log('Type:', typeof devices);
    console.log('Is array:', Array.isArray(devices));
    if (devices.length > 0) {
        console.log('First device:', JSON.stringify(devices[0], null, 2));
    }
    
    const stats = db.getStats();
    console.log('Stats:', JSON.stringify(stats, null, 2));
    
    const auditLogs = db.getAuditLogs(5);
    console.log('Audit logs:', JSON.stringify(auditLogs, null, 2));
} catch (err) {
    console.error('Error:', err.message);
    console.error('Stack:', err.stack);
}
