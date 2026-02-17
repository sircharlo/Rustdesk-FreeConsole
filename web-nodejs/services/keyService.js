/**
 * BetterDesk Console - Key Service
 * Reads public key and API key from filesystem
 */

const fs = require('fs');
const QRCode = require('qrcode');
const config = require('../config/config');

/**
 * Read public key from file
 */
function getPublicKey() {
    try {
        if (fs.existsSync(config.pubKeyPath)) {
            return fs.readFileSync(config.pubKeyPath, 'utf8').trim();
        }
        return null;
    } catch (err) {
        console.warn('Could not read public key:', err.message);
        return null;
    }
}

/**
 * Get API key (masked for display)
 */
function getApiKey(masked = true) {
    try {
        if (fs.existsSync(config.apiKeyPath)) {
            const key = fs.readFileSync(config.apiKeyPath, 'utf8').trim();
            if (masked && key.length > 8) {
                return key.substring(0, 4) + '****' + key.substring(key.length - 4);
            }
            return key;
        }
        return null;
    } catch (err) {
        console.warn('Could not read API key:', err.message);
        return null;
    }
}

/**
 * Generate QR code for public key
 */
async function getPublicKeyQR() {
    const pubKey = getPublicKey();
    if (!pubKey) {
        return null;
    }
    
    try {
        const qrDataUrl = await QRCode.toDataURL(pubKey, {
            errorCorrectionLevel: 'M',
            type: 'image/png',
            width: 256,
            margin: 2,
            color: {
                dark: '#e6edf3',
                light: '#0d1117'
            }
        });
        return qrDataUrl;
    } catch (err) {
        console.warn('Could not generate QR code:', err.message);
        return null;
    }
}

/**
 * Get server configuration info
 */
function getServerConfig() {
    return {
        publicKey: getPublicKey(),
        apiKeyMasked: getApiKey(true),
        hbbsApiUrl: config.hbbsApiUrl,
        dbPath: config.dbPath,
        pubKeyPath: config.pubKeyPath,
        apiKeyPath: config.apiKeyPath
    };
}

module.exports = {
    getPublicKey,
    getApiKey,
    getPublicKeyQR,
    getServerConfig
};
