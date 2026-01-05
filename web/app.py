from flask import Flask, render_template, request, jsonify
import sqlite3
from datetime import datetime
import os
import requests

app = Flask(__name__)

# Configuration
DB_PATH = '/opt/rustdesk/db_v2.sqlite3'
PUB_KEY_PATH = '/opt/rustdesk/id_ed25519.pub'
HBBS_API_URL = 'http://localhost:21114/api'

def get_db_connection():
    """Create a read-write connection to the SQLite database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def get_public_key():
    """Read the RustDesk public key from file."""
    try:
        with open(PUB_KEY_PATH, 'r') as f:
            return f.read().strip()
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
        try:
            response = requests.get(f'{HBBS_API_URL}/peers', timeout=2)
            if response.status_code == 200:
                api_data = response.json()
                if api_data.get('success') and api_data.get('data'):
                    online_ids = {peer['id'] for peer in api_data['data'] if peer.get('online')}
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
                info
            FROM peer
            ORDER BY created_at DESC
        ''')
        
        devices = []
        for row in cursor.fetchall():
            device_id = row['id']
            # Prefer HBBS API status, fallback to database status
            if online_ids:
                online = device_id in online_ids
            else:
                online = row['status'] == 1
            
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
                'info': row['info'] or ''
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
        data = request.get_json()
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Build dynamic update query based on provided fields
        updates = []
        params = []
        
        if 'note' in data:
            updates.append('note = ?')
            params.append(data['note'])
        
        if 'new_id' in data and data['new_id']:
            updates.append('id = ?')
            params.append(data['new_id'])
        
        if not updates:
            return jsonify({'success': False, 'error': 'No fields to update'}), 400
        
        params.append(device_id)
        query = f"UPDATE peer SET {', '.join(updates)} WHERE id = ?"
        
        cursor.execute(query, params)
        conn.commit()
        affected = cursor.rowcount
        conn.close()
        
        if affected == 0:
            return jsonify({'success': False, 'error': 'Device not found'}), 404
        
        return jsonify({'success': True, 'message': 'Device updated successfully'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/device/<device_id>', methods=['DELETE'])
def delete_device(device_id):
    """Delete a device from the database."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('DELETE FROM peer WHERE id = ?', (device_id,))
        conn.commit()
        affected = cursor.rowcount
        conn.close()
        
        if affected == 0:
            return jsonify({'success': False, 'error': 'Device not found'}), 404
        
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
        
        # Total devices
        cursor.execute('SELECT COUNT(*) as total FROM peer')
        total = cursor.fetchone()['total']
        
        # If HBBS API didn't work, fallback to database status
        if online_count == 0:
            cursor.execute('SELECT COUNT(*) as active FROM peer WHERE status = 1')
            online_count = cursor.fetchone()['active']
        
        # Devices with notes
        cursor.execute('SELECT COUNT(*) as with_notes FROM peer WHERE note IS NOT NULL AND note != ""')
        with_notes = cursor.fetchone()['with_notes']
        
        conn.close()
        
        return jsonify({
            'success': True,
            'stats': {
                'total': total,
                'active': online_count,
                'inactive': total - online_count,
                'with_notes': with_notes
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

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
