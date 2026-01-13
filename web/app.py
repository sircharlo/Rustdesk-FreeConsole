from flask import Flask, render_template, request, jsonify
import sqlite3
from datetime import datetime
import os
import requests
import re

app = Flask(__name__)

# Configuration
DB_PATH = '/opt/rustdesk/db_v2.sqlite3'
PUB_KEY_PATH = '/opt/rustdesk/id_ed25519.pub'
# API is on localhost-only port 21120 (not exposed to internet)
HBBS_API_URL = 'http://localhost:21120/api'

# Validation rules
MAX_NOTE_LENGTH = 500
MAX_DEVICE_ID_LENGTH = 50
DEVICE_ID_PATTERN = re.compile(r'^[a-zA-Z0-9_-]+$')

def validate_device_id(device_id):
    """Validate device ID format and length."""
    if not device_id:
        return False, "Device ID cannot be empty"
    if len(device_id) > MAX_DEVICE_ID_LENGTH:
        return False, f"Device ID too long (max {MAX_DEVICE_ID_LENGTH} characters)"
    if not DEVICE_ID_PATTERN.match(device_id):
        return False, "Device ID can only contain letters, numbers, underscores and hyphens"
    return True, None

def validate_note(note):
    """Validate note length."""
    if note and len(note) > MAX_NOTE_LENGTH:
        return False, f"Note too long (max {MAX_NOTE_LENGTH} characters)"
    return True, None

def sanitize_input(text):
    """Basic sanitization of user input."""
    if not text:
        return text
    # Remove potential XSS patterns
    text = text.replace('<script>', '').replace('</script>', '')
    text = text.replace('<iframe>', '').replace('</iframe>', '')
    return text.strip()

def get_db_connection():
    """Create a read-write connection to the SQLite database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def get_public_key():
    """Read the RustDesk public key from file - scans for any .pub file."""
    try:
        # First try default path
        if os.path.exists(PUB_KEY_PATH):
            with open(PUB_KEY_PATH, 'r') as f:
                key_content = f.read().strip()
                return f"[id_ed25519.pub] {key_content}"
        
        # If default doesn't exist, scan for any .pub file in directory
        rustdesk_dir = os.path.dirname(PUB_KEY_PATH)
        if os.path.exists(rustdesk_dir):
            pub_files = [f for f in os.listdir(rustdesk_dir) if f.endswith('.pub')]
            if pub_files:
                # Use the first .pub file found
                pub_file_path = os.path.join(rustdesk_dir, pub_files[0])
                with open(pub_file_path, 'r') as f:
                    key_content = f.read().strip()
                    return f"[{pub_files[0]}] {key_content}"
        
        return "❌ No public key file (.pub) found in RustDesk directory"
    except Exception as e:
        return f"Error reading key: {str(e)}"

@app.route('/')
def index():
    """Render the main dashboard page."""
    public_key = get_public_key()
    return render_template('index.html', public_key=public_key)

@app.route('/api/devices', methods=['GET'])
def get_devices():
    """Fetch all devices from the database with online status from HBBS API."""
    try:
        # Try to get status from HBBS API
        online_ids = set()
        api_device_info = {}
        try:
            response = requests.get(f'{HBBS_API_URL}/peers', timeout=2)
            if response.status_code == 200:
                api_data = response.json()
                if api_data.get('success') and api_data.get('data'):
                    # Collect online devices and their full info from API
                    for peer in api_data['data']:
                        device_id = peer.get('id')
                        if device_id:
                            api_device_info[device_id] = peer
                            if peer.get('online'):
                                online_ids.add(device_id)
        except Exception as e:
            print(f"Warning: Could not connect to HBBS API: {e}")
        
        # Get devices from database
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('''
            SELECT 
                guid,
                id,
                uuid,
                pk,
                created_at,
                user,
                status,
                note,
                info,
                is_banned,
                banned_at,
                banned_by,
                ban_reason
            FROM peer
            WHERE is_deleted = 0
            ORDER BY created_at DESC
        ''')
        
        devices = []
        for row in cursor.fetchall():
            device_id = row['id']
            
            # Determine online status
            # Use ONLY the API status (same logic as RustDesk desktop client)
            # This ensures consistency between web console and desktop client
            if device_id in api_device_info:
                # Device found in API - use the API's online status
                online = api_device_info[device_id].get('online', False)
            else:
                # Device not found in API - consider it offline
                # (If API is unreachable, fall back to database status)
                online = row['status'] == 1 if not api_device_info else False
            
            device = {
                'guid': row['guid'].hex() if row['guid'] else '',
                'id': device_id,
                'uuid': row['uuid'].hex() if row['uuid'] else '',
                'pk': row['pk'].hex() if row['pk'] else '',
                'created_at': row['created_at'],
                'user': row['user'].hex() if row['user'] else '',
                'status': row['status'],
                'online': online,
                'note': row['note'] or '',
                'info': row['info'] or '',
                'is_banned': row['is_banned'] == 1,
                'banned_at': row['banned_at'],
                'banned_by': row['banned_by'] or '',
                'ban_reason': row['ban_reason'] or ''
            }
            devices.append(device)
        
        conn.close()
        return jsonify({'success': True, 'devices': devices})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/device/<device_id>', methods=['PUT'])
def update_device(device_id):
    """Update a device's note and/or ID."""
    try:
        # Validate input device ID
        is_valid, error_msg = validate_device_id(device_id)
        if not is_valid:
            return jsonify({'success': False, 'error': error_msg}), 400
        
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No data provided'}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Build dynamic update query based on provided fields
        updates = []
        params = []
        
        if 'note' in data:
            # Validate and sanitize note
            is_valid, error_msg = validate_note(data['note'])
            if not is_valid:
                conn.close()
                return jsonify({'success': False, 'error': error_msg}), 400
            
            sanitized_note = sanitize_input(data['note'])
            updates.append('note = ?')
            params.append(sanitized_note)
        
        if 'new_id' in data and data['new_id']:
            # Validate new device ID
            is_valid, error_msg = validate_device_id(data['new_id'])
            if not is_valid:
                conn.close()
                return jsonify({'success': False, 'error': error_msg}), 400
            
            # Check if new ID already exists
            cursor.execute('SELECT id FROM peer WHERE id = ? AND is_deleted = 0', (data['new_id'],))
            if cursor.fetchone():
                conn.close()
                return jsonify({'success': False, 'error': 'Device ID already exists'}), 409
            
            updates.append('id = ?')
            params.append(data['new_id'])
        
        if not updates:
            conn.close()
            return jsonify({'success': False, 'error': 'No fields to update'}), 400
        
        # Add updated_at timestamp
        updates.append('updated_at = ?')
        params.append(int(datetime.now().timestamp() * 1000))
        
        params.append(device_id)
        query = f"UPDATE peer SET {', '.join(updates)} WHERE id = ? AND is_deleted = 0"
        
        cursor.execute(query, params)
        conn.commit()
        affected = cursor.rowcount
        conn.close()
        
        if affected == 0:
            return jsonify({'success': False, 'error': 'Device not found or already deleted'}), 404
        
        return jsonify({'success': True, 'message': 'Device updated successfully'})
    except sqlite3.IntegrityError as e:
        return jsonify({'success': False, 'error': f'Database constraint violation: {str(e)}'}), 409
    except Exception as e:
        return jsonify({'success': False, 'error': f'Unexpected error: {str(e)}'}), 500

@app.route('/api/device/<device_id>', methods=['DELETE'])
def delete_device(device_id):
    """Soft delete a device from the database."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Soft delete: set is_deleted=1 and timestamp
        deleted_at = int(datetime.now().timestamp() * 1000)
        cursor.execute(
            'UPDATE peer SET is_deleted = 1, deleted_at = ? WHERE id = ? AND is_deleted = 0',
            (deleted_at, device_id)
        )
        conn.commit()
        affected = cursor.rowcount
        conn.close()
        
        if affected == 0:
            return jsonify({'success': False, 'error': 'Device not found or already deleted'}), 404
        
        return jsonify({'success': True, 'message': 'Device deleted successfully'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get statistics about the devices."""
    try:
        # Try to get online count from HBBS API
        online_count = 0
        try:
            response = requests.get(f'{HBBS_API_URL}/peers', timeout=2)
            if response.status_code == 200:
                api_data = response.json()
                if api_data.get('success') and api_data.get('data'):
                    online_count = sum(1 for peer in api_data['data'] if peer.get('online'))
        except Exception as e:
            print(f"Warning: Could not connect to HBBS API for stats: {e}")
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Total devices (excluding deleted)
        cursor.execute('SELECT COUNT(*) as total FROM peer WHERE is_deleted = 0')
        total = cursor.fetchone()['total']
        
        # Banned devices count
        cursor.execute('SELECT COUNT(*) as banned FROM peer WHERE is_banned = 1 AND is_deleted = 0')
        banned = cursor.fetchone()['banned']
        
        # If HBBS API didn't work, fallback to database status
        if online_count == 0:
            cursor.execute('SELECT COUNT(*) as active FROM peer WHERE status = 1 AND is_deleted = 0')
            online_count = cursor.fetchone()['active']
        
        # Devices with notes (excluding deleted)
        cursor.execute('SELECT COUNT(*) as with_notes FROM peer WHERE note IS NOT NULL AND note != "" AND is_deleted = 0')
        with_notes = cursor.fetchone()['with_notes']
        
        conn.close()
        
        return jsonify({
            'success': True,
            'stats': {
                'total': total,
                'active': online_count,
                'inactive': total - online_count,
                'with_notes': with_notes,
                'banned': banned
            }
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/hbbs/status', methods=['GET'])
def hbbs_status():
    """Check if HBBS API is available."""
    try:
        response = requests.get(f'{HBBS_API_URL}/health', timeout=2)
        if response.status_code == 200:
            return jsonify({'success': True, 'message': 'HBBS API is running', 'api_data': response.json()})
        else:
            return jsonify({'success': False, 'message': f'HBBS API returned status {response.status_code}'})
    except Exception as e:
        return jsonify({'success': False, 'message': f'HBBS API not available: {str(e)}'})

@app.route('/api/device/<device_id>/ban', methods=['POST'])
def ban_device(device_id):
    """Ban a device."""
    try:
        # Validate device ID
        is_valid, error_msg = validate_device_id(device_id)
        if not is_valid:
            return jsonify({'success': False, 'error': error_msg}), 400
        
        data = request.get_json() or {}
        
        # Validate ban reason
        ban_reason = sanitize_input(data.get('reason', ''))
        if ban_reason and len(ban_reason) > 500:
            return jsonify({'success': False, 'error': 'Ban reason too long (max 500 characters)'}), 400
        
        banned_by = sanitize_input(data.get('banned_by', 'admin'))
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if device exists and is not deleted
        cursor.execute('SELECT id, is_banned FROM peer WHERE id = ? AND is_deleted = 0', (device_id,))
        device = cursor.fetchone()
        
        if not device:
            conn.close()
            return jsonify({'success': False, 'error': 'Device not found or already deleted'}), 404
        
        if device['is_banned'] == 1:
            conn.close()
            return jsonify({'success': False, 'error': 'Device is already banned'}), 409
        
        # Ban the device
        banned_at = int(datetime.now().timestamp() * 1000)
        cursor.execute('''
            UPDATE peer 
            SET is_banned = 1, 
                banned_at = ?, 
                banned_by = ?,
                ban_reason = ?,
                updated_at = ?
            WHERE id = ? AND is_deleted = 0
        ''', (banned_at, banned_by, ban_reason, banned_at, device_id))
        
        conn.commit()
        affected = cursor.rowcount
        conn.close()
        
        if affected == 0:
            return jsonify({'success': False, 'error': 'Failed to ban device'}), 500
        
        return jsonify({
            'success': True, 
            'message': f'Device {device_id} banned successfully',
            'banned_at': banned_at,
            'banned_by': banned_by
        })
    
    except sqlite3.Error as e:
        return jsonify({'success': False, 'error': f'Database error: {str(e)}'}), 500
    except Exception as e:
        return jsonify({'success': False, 'error': f'Unexpected error: {str(e)}'}), 500

@app.route('/api/device/<device_id>/unban', methods=['POST'])
def unban_device(device_id):
    """Unban a device."""
    try:
        # Validate device ID
        is_valid, error_msg = validate_device_id(device_id)
        if not is_valid:
            return jsonify({'success': False, 'error': error_msg}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if device exists and is banned
        cursor.execute('SELECT id, is_banned FROM peer WHERE id = ? AND is_deleted = 0', (device_id,))
        device = cursor.fetchone()
        
        if not device:
            conn.close()
            return jsonify({'success': False, 'error': 'Device not found or already deleted'}), 404
        
        if device['is_banned'] == 0:
            conn.close()
            return jsonify({'success': False, 'error': 'Device is not banned'}), 409
        
        # Unban the device
        updated_at = int(datetime.now().timestamp() * 1000)
        cursor.execute('''
            UPDATE peer 
            SET is_banned = 0, 
                banned_at = NULL, 
                banned_by = NULL,
                ban_reason = NULL,
                updated_at = ?
            WHERE id = ? AND is_deleted = 0
        ''', (updated_at, device_id))
        
        conn.commit()
        affected = cursor.rowcount
        conn.close()
        
        if affected == 0:
            return jsonify({'success': False, 'error': 'Failed to unban device'}), 500
        
        return jsonify({
            'success': True, 
            'message': f'Device {device_id} unbanned successfully'
        })
    
    except sqlite3.Error as e:
        return jsonify({'success': False, 'error': f'Database error: {str(e)}'}), 500
    except Exception as e:
        return jsonify({'success': False, 'error': f'Unexpected error: {str(e)}'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
