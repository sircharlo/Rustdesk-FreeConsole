from flask import Flask, render_template, request, jsonify, redirect, url_for, g, send_file
import sqlite3
import json
from datetime import datetime
import os
import requests
import re
from flask_wtf.csrf import CSRFProtect, generate_csrf
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.utils import secure_filename

# Import authentication module
from auth import (
    require_auth, require_role, optional_auth,
    authenticate, create_session, verify_session, delete_session,
    log_audit, cleanup_expired_sessions,
    change_password,
    ROLE_ADMIN, ROLE_OPERATOR, ROLE_VIEWER,
    AuthError
)

# Import client generator (optional - feature under development)
try:
    from client_generator_module import generate_custom_client
    CLIENT_GENERATOR_AVAILABLE = True
except ImportError:
    CLIENT_GENERATOR_AVAILABLE = False
    def generate_custom_client(*args, **kwargs):
        return {'error': 'Client Generator module not available'}

# Import source client generator (compiles from source)
try:
    from source_client_generator import generate_from_source, get_build_status
    SOURCE_GENERATOR_AVAILABLE = True
except ImportError:
    SOURCE_GENERATOR_AVAILABLE = False
    def generate_from_source(*args, **kwargs):
        return {'success': False, 'error': 'Source Client Generator module not available'}
    def get_build_status(*args, **kwargs):
        return {'status': 'unavailable', 'message': 'Source Client Generator not available'}

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('FLASK_SECRET_KEY', os.urandom(32))
app.config['WTF_CSRF_CHECK_DEFAULT'] = False  # Manual CSRF for API

# Load version for cache busting
VERSION_FILE = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'VERSION')
APP_VERSION = 'v1.5.0'  # Default
try:
    if os.path.exists(VERSION_FILE):
        with open(VERSION_FILE, 'r') as f:
            version_line = f.readline().strip()
            if version_line:
                APP_VERSION = version_line
except:
    pass

# Context processor to inject version into all templates
@app.context_processor
def inject_version():
    return {'app_version': APP_VERSION}

# Cache control for static files
@app.after_request
def add_cache_headers(response):
    """Add cache control headers to responses."""
    if request.path.startswith('/static/'):
        # Static files: cache for 1 year if versioned, otherwise 5 minutes
        if 'v=' in request.query_string.decode():
            response.cache_control.max_age = 31536000  # 1 year
            response.cache_control.public = True
        else:
            response.cache_control.max_age = 300  # 5 minutes
    elif request.path == '/' or request.path.endswith('.html'):
        # HTML pages: no cache (always get fresh)
        response.cache_control.no_cache = True
        response.cache_control.no_store = True
        response.cache_control.must_revalidate = True
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
    return response

# Initialize CSRF protection
csrf = CSRFProtect()
csrf.init_app(app)

# Initialize rate limiter
limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["1000 per hour", "100 per minute"],
    storage_uri="memory://"
)

# Configuration
DB_PATH = '/opt/rustdesk/db_v2.sqlite3'
PUB_KEY_PATH = '/opt/rustdesk/id_ed25519.pub'
API_KEY_PATH = '/opt/rustdesk/.api_key'
# HBBS API URL (optional - will fallback to database status if API unavailable)
HBBS_API_URL = 'http://localhost:21120/api'

# Client Generator Configuration
UPLOAD_FOLDER = '/tmp/rustdesk_uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_FILE_SIZE

# Create upload folder if not exists
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# Load HBBS API key
def get_hbbs_api_key():
    """Load HBBS API key from file or environment variable."""
    # Try environment variable first
    api_key = os.environ.get('HBBS_API_KEY')
    if api_key:
        return api_key
    
    # Try reading from file
    try:
        if os.path.exists(API_KEY_PATH):
            with open(API_KEY_PATH, 'r') as f:
                return f.read().strip()
    except Exception as e:
        print(f"Warning: Could not read API key from {API_KEY_PATH}: {e}")
    
    return None

HBBS_API_KEY = get_hbbs_api_key()

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


def validate_password_strength(password):
    """Validate password strength - minimum 8 characters, letters and numbers."""
    if len(password) < 8:
        return False, "Password must be at least 8 characters long"
    if not re.search(r'[A-Za-z]', password):
        return False, "Password must contain at least one letter"
    if not re.search(r'[0-9]', password):
        return False, "Password must contain at least one number"
    return True, None


def sanitize_input(text):
    """Basic sanitization of user input."""
    if not text:
        return text
    from markupsafe import escape
    return str(escape(text)).strip()


def get_db_connection():
    """Create a read-write connection to the SQLite database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def get_public_key():
    """Read the RustDesk public key from file."""
    try:
        if os.path.exists(PUB_KEY_PATH):
            with open(PUB_KEY_PATH, 'r') as f:
                key_content = f.read().strip()
                return key_content
        
        rustdesk_dir = os.path.dirname(PUB_KEY_PATH)
        if os.path.exists(rustdesk_dir):
            pub_files = [f for f in os.listdir(rustdesk_dir) if f.endswith('.pub')]
            if pub_files:
                pub_file_path = os.path.join(rustdesk_dir, pub_files[0])
                with open(pub_file_path, 'r') as f:
                    key_content = f.read().strip()
                    return key_content
        
        return ""
    except Exception as e:
        return ""


# ============================================================================
# AUTHENTICATION ROUTES
# ============================================================================

@app.route('/login')
def login_page():
    """Render login page"""
    return render_template('login.html')


@app.route('/api/auth/login', methods=['POST'])
@limiter.limit("5 per minute")
@csrf.exempt  # CSRF exempt for login, validated by credentials
def login():
    """Login endpoint"""
    try:
        data = request.get_json()
        username = data.get('username', '').strip()
        password = data.get('password', '')
        
        if not username or not password:
            return jsonify({'success': False, 'error': 'Username and password required'}), 400
        
        # Note: Password strength is only validated on creation/change, not login
        # (to allow legacy accounts with weaker passwords to still login)
        
        # Authenticate user
        user = authenticate(username, password)
        
        # Create session
        token = create_session(user['id'])
        
        # Log login
        log_audit(user['id'], 'login', None, f"Login from {request.remote_addr}", request.remote_addr)
        
        return jsonify({
            'success': True,
            'token': token,
            'username': user['username'],
            'role': user['role']
        })
        
    except AuthError as e:
        return jsonify({'success': False, 'error': str(e)}), 401
    except Exception as e:
        # Log the actual error for debugging
        import traceback
        print(f"Login error: {e}")
        print(traceback.format_exc())
        return jsonify({'success': False, 'error': f'Login failed: {str(e)}'}), 500


@app.route('/api/auth/logout', methods=['POST'])
@require_auth
def logout():
    """Logout endpoint"""
    try:
        token = request.headers.get('Authorization', '').replace('Bearer ', '')
        
        # Log logout
        log_audit(g.user['user_id'], 'logout', None, 'User logged out', request.remote_addr)
        
        # Delete session
        delete_session(token)
        
        return jsonify({'success': True, 'message': 'Logged out successfully'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/auth/verify', methods=['GET'])
@require_auth
def verify_token():
    """Verify authentication token"""
    return jsonify({
        'success': True,
        'user': {
            'username': g.user['username'],
            'role': g.user['role']
        }
    })


@app.route('/health')
def health_check():
    """Health check endpoint for Docker and load balancers"""
    try:
        # Test database connection
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        conn.close()
        
        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'version': '1.5.0',
            'database': 'accessible'
        }), 200
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'timestamp': datetime.now().isoformat(),
            'error': str(e)
        }), 503


# ============================================================================
# MAIN ROUTES
# ============================================================================

@app.route('/')
def index():
    """Render the main dashboard page. Auth check done by JavaScript on client side."""
    return render_template('index.html')


@app.route('/client-generator')
def client_generator():
    """Render the client generator page. Auth check done by JavaScript on client side."""
    return render_template('client_generator.html')


@app.route('/api/devices', methods=['GET'])
@require_auth
@limiter.exempt  # Authenticated users bypass rate limit
def get_devices():
    """Fetch all devices from the database with online status based on last_online."""
    try:
        # Get server config for timeout settings
        config = get_server_config()
        peer_timeout_secs = config.get('peer_timeout_secs', 60)
        warning_threshold = config.get('warning_threshold', 2)
        critical_threshold = config.get('critical_threshold', 4)
        heartbeat_interval = config.get('heartbeat_interval_secs', 5)
        
        # Get devices from database
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if last_online column exists
        cursor.execute("PRAGMA table_info(peer)")
        columns = [row[1] for row in cursor.fetchall()]
        has_last_online = 'last_online' in columns
        
        if has_last_online:
            cursor.execute('''
                SELECT 
                    guid, id, uuid, pk, created_at, user, status, note, info,
                    is_banned, banned_at, banned_by, ban_reason,
                    previous_ids, id_changed_at, last_online
                FROM peer
                WHERE is_deleted = 0
                ORDER BY created_at DESC
            ''')
        else:
            cursor.execute('''
                SELECT 
                    guid, id, uuid, pk, created_at, user, status, note, info,
                    is_banned, banned_at, banned_by, ban_reason,
                    previous_ids, id_changed_at
                FROM peer
                WHERE is_deleted = 0
                ORDER BY created_at DESC
            ''')
        
        devices = []
        now = datetime.now()
        
        for row in cursor.fetchall():
            device_id = row['id']
            
            # Determine online status based on last_online timestamp
            online = False
            status_detail = 'offline'
            last_online = None
            
            if has_last_online and row['last_online']:
                last_online = row['last_online']
                try:
                    # Parse timestamp - handle both formats
                    if isinstance(last_online, str):
                        if 'T' in last_online:
                            last_online_dt = datetime.fromisoformat(last_online.replace('Z', '+00:00').replace('+00:00', ''))
                        else:
                            last_online_dt = datetime.strptime(last_online, '%Y-%m-%d %H:%M:%S')
                    else:
                        last_online_dt = last_online
                    
                    # Calculate time since last activity
                    seconds_since = (now - last_online_dt).total_seconds()
                    
                    if seconds_since <= peer_timeout_secs:
                        # Within timeout - check for degraded/critical states
                        missed_heartbeats = int(seconds_since / heartbeat_interval)
                        
                        if missed_heartbeats >= critical_threshold:
                            online = True
                            status_detail = 'critical'
                        elif missed_heartbeats >= warning_threshold:
                            online = True
                            status_detail = 'degraded'
                        else:
                            online = True
                            status_detail = 'online'
                    else:
                        status_detail = 'offline'
                except Exception as e:
                    print(f"Warning: Could not parse last_online for {device_id}: {e}")
                    # Fallback to status field
                    online = row['status'] == 1
                    status_detail = 'online' if online else 'offline'
            else:
                # No last_online - fallback to status field
                online = row['status'] == 1
                status_detail = 'online' if online else 'offline'
            
            device = {
                'guid': row['guid'].hex() if row['guid'] else '',
                'id': device_id,
                'uuid': row['uuid'].hex() if row['uuid'] else '',
                'pk': row['pk'].hex() if row['pk'] else '',
                'created_at': row['created_at'],
                'user': row['user'].hex() if row['user'] else '',
                'status': row['status'],
                'online': online,
                'status_detail': status_detail,
                'last_online': last_online,
                'note': row['note'] or '',
                'info': row['info'] or '',
                'is_banned': row['is_banned'] == 1,
                'banned_at': row['banned_at'],
                'banned_by': row['banned_by'] or '',
                'ban_reason': row['ban_reason'] or '',
                'previous_ids': json.loads(row['previous_ids']) if row['previous_ids'] else [],
                'id_changed_at': row['id_changed_at'] or ''
            }
            devices.append(device)
        
        conn.close()
        return jsonify({'success': True, 'devices': devices, 'config': config})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/device/<device_id>', methods=['PUT'])
@require_auth
@require_role(ROLE_ADMIN, ROLE_OPERATOR)
def update_device(device_id):
    """Update a device's note and/or ID."""
    try:
        is_valid, error_msg = validate_device_id(device_id)
        if not is_valid:
            return jsonify({'success': False, 'error': error_msg}), 400
        
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No data provided'}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        updates = []
        params = []
        
        if 'note' in data:
            is_valid, error_msg = validate_note(data['note'])
            if not is_valid:
                conn.close()
                return jsonify({'success': False, 'error': error_msg}), 400
            
            sanitized_note = sanitize_input(data['note'])
            updates.append('note = ?')
            params.append(sanitized_note)
        
        if 'new_id' in data and data['new_id']:
            is_valid, error_msg = validate_device_id(data['new_id'])
            if not is_valid:
                conn.close()
                return jsonify({'success': False, 'error': error_msg}), 400
            
            cursor.execute('SELECT id FROM peer WHERE id = ? AND is_deleted = 0', (data['new_id'],))
            if cursor.fetchone():
                conn.close()
                return jsonify({'success': False, 'error': 'Device ID already exists'}), 409
            
            # Get current previous_ids and add old_id to history
            cursor.execute('SELECT previous_ids FROM peer WHERE id = ? AND is_deleted = 0', (device_id,))
            row = cursor.fetchone()
            previous_ids = []
            if row and row[0]:
                try:
                    previous_ids = json.loads(row[0]) if row[0] else []
                except:
                    previous_ids = []
            previous_ids.append(device_id)
            
            updates.append('id = ?')
            params.append(data['new_id'])
            updates.append('previous_ids = ?')
            params.append(json.dumps(previous_ids))
            updates.append('id_changed_at = ?')
            params.append(datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
        
        if not updates:
            conn.close()
            return jsonify({'success': False, 'error': 'No fields to update'}), 400
        
        updates.append('updated_at = ?')
        params.append(int(datetime.now().timestamp() * 1000))
        params.append(device_id)
        
        query = f"UPDATE peer SET {', '.join(updates)} WHERE id = ? AND is_deleted = 0"
        cursor.execute(query, params)
        conn.commit()
        affected = cursor.rowcount
        conn.close()
        
        if affected == 0:
            return jsonify({'success': False, 'error': 'Device not found'}), 404
        
        # Log audit with selective data
        audit_details = []
        if 'note' in data:
            audit_details.append(f"note: {data.get('note', '')[:50]}...")  # First 50 chars
        if 'new_id' in data:
            audit_details.append(f"new_id: {data['new_id']}")
        log_audit(g.user['user_id'], 'update_device', device_id, 
                 f"Updated: {', '.join(audit_details)}", request.remote_addr or 'unknown')
        
        return jsonify({'success': True, 'message': 'Device updated successfully'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/device/<device_id>', methods=['DELETE'])
@require_auth
@require_role(ROLE_ADMIN, ROLE_OPERATOR)
def delete_device(device_id):
    """Soft delete a device from the database."""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        deleted_at = int(datetime.now().timestamp() * 1000)
        cursor.execute(
            'UPDATE peer SET is_deleted = 1, deleted_at = ? WHERE id = ? AND is_deleted = 0',
            (deleted_at, device_id)
        )
        conn.commit()
        affected = cursor.rowcount
        conn.close()
        
        if affected == 0:
            return jsonify({'success': False, 'error': 'Device not found'}), 404
        
        # Log audit
        log_audit(g.user['user_id'], 'delete_device', device_id, 
                 'Device deleted', request.remote_addr or 'unknown')
        
        return jsonify({'success': True, 'message': 'Device deleted successfully'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/stats', methods=['GET'])
@require_auth
@limiter.exempt  # Authenticated users bypass rate limit
def get_stats():
    """Get statistics about the devices."""
    try:
        online_count = 0
        try:
            headers = {}
            if HBBS_API_KEY:
                headers['X-API-Key'] = HBBS_API_KEY
            
            response = requests.get(f'{HBBS_API_URL}/peers', headers=headers, timeout=2)
            if response.status_code == 200:
                api_data = response.json()
                if api_data.get('success') and api_data.get('data'):
                    online_count = sum(1 for peer in api_data['data'] if peer.get('online'))
        except Exception as e:
            print(f"Warning: Could not connect to HBBS API for stats: {e}")
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT COUNT(*) as total FROM peer WHERE is_deleted = 0')
        total = cursor.fetchone()['total']
        
        cursor.execute('SELECT COUNT(*) as banned FROM peer WHERE is_banned = 1 AND is_deleted = 0')
        banned = cursor.fetchone()['banned']
        
        if online_count == 0:
            cursor.execute('SELECT COUNT(*) as active FROM peer WHERE status = 1 AND is_deleted = 0')
            online_count = cursor.fetchone()['active']
        
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


# Default server configuration
DEFAULT_SERVER_CONFIG = {
    'peer_timeout_secs': 60,
    'heartbeat_interval_secs': 5,
    'warning_threshold': 2,
    'critical_threshold': 4
}

def ensure_server_config_table():
    """Ensure server_config table exists."""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS server_config (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

def get_server_config():
    """Get server configuration from database."""
    ensure_server_config_table()
    config = DEFAULT_SERVER_CONFIG.copy()
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT key, value FROM server_config')
        rows = cursor.fetchall()
        conn.close()
        for row in rows:
            key = row['key']
            if key in config:
                try:
                    config[key] = int(row['value'])
                except ValueError:
                    config[key] = row['value']
    except Exception as e:
        print(f"Warning: Could not load server config: {e}")
    return config

def save_server_config(config):
    """Save server configuration to database."""
    ensure_server_config_table()
    conn = get_db_connection()
    cursor = conn.cursor()
    for key, value in config.items():
        cursor.execute('''
            INSERT OR REPLACE INTO server_config (key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
        ''', (key, str(value)))
    conn.commit()
    conn.close()


@app.route('/api/server/config', methods=['GET'])
@require_auth
@limiter.exempt
def get_server_config_endpoint():
    """Get server configuration."""
    try:
        config = get_server_config()
        return jsonify({
            'success': True,
            'config': config
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/server/config', methods=['POST'])
@require_auth
@require_role(ROLE_ADMIN)
def update_server_config_endpoint():
    """Update server configuration (admin only)."""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No data provided'}), 400
        
        # Validate and sanitize config values
        config = get_server_config()
        
        if 'peer_timeout_secs' in data:
            val = int(data['peer_timeout_secs'])
            if val < 10 or val > 300:
                return jsonify({'success': False, 'error': 'peer_timeout_secs must be between 10 and 300'}), 400
            config['peer_timeout_secs'] = val
        
        if 'heartbeat_interval_secs' in data:
            val = int(data['heartbeat_interval_secs'])
            if val < 1 or val > 30:
                return jsonify({'success': False, 'error': 'heartbeat_interval_secs must be between 1 and 30'}), 400
            config['heartbeat_interval_secs'] = val
        
        if 'warning_threshold' in data:
            val = int(data['warning_threshold'])
            if val < 1 or val > 10:
                return jsonify({'success': False, 'error': 'warning_threshold must be between 1 and 10'}), 400
            config['warning_threshold'] = val
        
        if 'critical_threshold' in data:
            val = int(data['critical_threshold'])
            if val < 2 or val > 20:
                return jsonify({'success': False, 'error': 'critical_threshold must be between 2 and 20'}), 400
            config['critical_threshold'] = val
        
        # Validate thresholds relationship
        if config['warning_threshold'] >= config['critical_threshold']:
            return jsonify({'success': False, 'error': 'warning_threshold must be less than critical_threshold'}), 400
        
        save_server_config(config)
        
        # Log the change
        user_id = g.user.get('id') if g.user else None
        log_audit(user_id, 'config_change', None, f"Server config updated: {config}")
        
        return jsonify({
            'success': True,
            'message': 'Configuration saved successfully',
            'config': config
        })
    except ValueError as e:
        return jsonify({'success': False, 'error': 'Invalid numeric value'}), 400
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/device/<device_id>/ban', methods=['POST'])
@require_auth
@require_role(ROLE_ADMIN, ROLE_OPERATOR)
def ban_device(device_id):
    """Ban a device."""
    try:
        is_valid, error_msg = validate_device_id(device_id)
        if not is_valid:
            return jsonify({'success': False, 'error': error_msg}), 400
        
        data = request.get_json() or {}
        
        ban_reason = sanitize_input(data.get('reason', ''))
        if ban_reason and len(ban_reason) > 500:
            return jsonify({'success': False, 'error': 'Ban reason too long'}), 400
        
        banned_by = g.user['username']
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT id, is_banned FROM peer WHERE id = ? AND is_deleted = 0', (device_id,))
        device = cursor.fetchone()
        
        if not device:
            conn.close()
            return jsonify({'success': False, 'error': 'Device not found'}), 404
        
        if device['is_banned'] == 1:
            conn.close()
            return jsonify({'success': False, 'error': 'Device is already banned'}), 409
        
        banned_at = int(datetime.now().timestamp() * 1000)
        cursor.execute('''
            UPDATE peer 
            SET is_banned = 1, banned_at = ?, banned_by = ?, ban_reason = ?, updated_at = ?
            WHERE id = ? AND is_deleted = 0
        ''', (banned_at, banned_by, ban_reason, banned_at, device_id))
        
        conn.commit()
        conn.close()
        
        # Log audit
        log_audit(g.user['user_id'], 'ban_device', device_id, 
                 f"Banned device. Reason: {ban_reason}", request.remote_addr)
        
        return jsonify({
            'success': True, 
            'message': f'Device {device_id} banned successfully',
            'banned_at': banned_at,
            'banned_by': banned_by
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/device/<device_id>/unban', methods=['POST'])
@require_auth
@require_role(ROLE_ADMIN, ROLE_OPERATOR)
def unban_device(device_id):
    """Unban a device."""
    try:
        is_valid, error_msg = validate_device_id(device_id)
        if not is_valid:
            return jsonify({'success': False, 'error': error_msg}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT id, is_banned FROM peer WHERE id = ? AND is_deleted = 0', (device_id,))
        device = cursor.fetchone()
        
        if not device:
            conn.close()
            return jsonify({'success': False, 'error': 'Device not found'}), 404
        
        if device['is_banned'] == 0:
            conn.close()
            return jsonify({'success': False, 'error': 'Device is not banned'}), 409
        
        updated_at = int(datetime.now().timestamp() * 1000)
        cursor.execute('''
            UPDATE peer 
            SET is_banned = 0, banned_at = NULL, banned_by = NULL, ban_reason = NULL, updated_at = ?
            WHERE id = ? AND is_deleted = 0
        ''', (updated_at, device_id))
        
        conn.commit()
        conn.close()
        
        # Log audit
        log_audit(g.user['user_id'], 'unban_device', device_id, 
                 'Device unbanned', request.remote_addr)
        
        return jsonify({
            'success': True, 
            'message': f'Device {device_id} unbanned successfully'
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================================================
# USER MANAGEMENT ROUTES (Admin only)
# ============================================================================

@app.route('/api/users', methods=['GET'])
@require_auth
@require_role(ROLE_ADMIN)
def list_all_users():
    """List all users (admin only)"""
    try:
        from auth import list_users
        users = list_users()
        
        # Don't send password hashes
        for user in users:
            user.pop('password_hash', None)
        
        return jsonify({'success': True, 'users': users})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/users', methods=['POST'])
@require_auth
@require_role(ROLE_ADMIN)
def create_new_user():
    """Create new user (admin only)"""
    try:
        data = request.get_json()
        username = sanitize_input(data.get('username', ''))
        password = data.get('password', '')
        role = data.get('role', ROLE_VIEWER)
        
        if not username or not password:
            return jsonify({'success': False, 'error': 'Username and password required'}), 400
        
        # Validate password strength
        is_valid, error_msg = validate_password_strength(password)
        if not is_valid:
            return jsonify({'success': False, 'error': error_msg}), 400
        
        from auth import create_user
        user = create_user(username, password, role)
        
        # Log audit
        log_audit(g.user['user_id'], 'create_user', None, 
                 f"Created user: {username} with role: {role}", request.remote_addr)
        
        return jsonify({'success': True, 'message': 'User created successfully', 'user': user})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 400


@app.route('/api/users/<int:user_id>', methods=['PUT'])
@require_auth
@require_role(ROLE_ADMIN)
def update_user(user_id):
    """Update user (admin only)"""
    try:
        data = request.get_json()
        action = data.get('action')
        
        from auth import update_user_role, activate_user, deactivate_user, reset_password
        
        if action == 'change_role':
            new_role = data.get('role')
            if not new_role:
                return jsonify({'success': False, 'error': 'Role required'}), 400
            
            update_user_role(user_id, new_role)
            log_audit(g.user['user_id'], 'update_user_role', None, 
                     f"Changed role of user {user_id} to {new_role}", request.remote_addr)
            return jsonify({'success': True, 'message': 'User role updated'})
        
        elif action == 'activate':
            activate_user(user_id)
            log_audit(g.user['user_id'], 'activate_user', None, 
                     f"Activated user {user_id}", request.remote_addr)
            return jsonify({'success': True, 'message': 'User activated'})
        
        elif action == 'deactivate':
            deactivate_user(user_id)
            log_audit(g.user['user_id'], 'deactivate_user', None, 
                     f"Deactivated user {user_id}", request.remote_addr)
            return jsonify({'success': True, 'message': 'User deactivated'})
        
        elif action == 'reset_password':
            new_password = data.get('password')
            if not new_password:
                return jsonify({'success': False, 'error': 'Password required'}), 400
            
            # Validate password strength
            is_valid, error_msg = validate_password_strength(new_password)
            if not is_valid:
                return jsonify({'success': False, 'error': error_msg}), 400
            
            reset_password(user_id, new_password)
            log_audit(g.user['user_id'], 'reset_password', None, 
                     f"Reset password for user {user_id}", request.remote_addr)
            return jsonify({'success': True, 'message': 'Password reset successfully'})
        
        else:
            return jsonify({'success': False, 'error': 'Invalid action'}), 400
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 400


@app.route('/api/users/<int:user_id>', methods=['DELETE'])
@require_auth
@require_role(ROLE_ADMIN)
def delete_user_account(user_id):
    """Delete user (admin only)"""
    try:
        # Prevent self-deletion
        if user_id == g.user['user_id']:
            return jsonify({'success': False, 'error': 'Cannot delete your own account'}), 400
        
        from auth import delete_user
        delete_user(user_id)
        
        log_audit(g.user['user_id'], 'delete_user', None, 
                 f"Deleted user {user_id}", request.remote_addr)
        
        return jsonify({'success': True, 'message': 'User deleted successfully'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================================================
# PASSWORD CHANGE & KEY VERIFICATION
# ============================================================================

@app.route('/api/auth/change-password', methods=['POST'])
@require_auth
def change_user_password():
    """Change current user's password"""
    try:
        data = request.get_json()
        old_password = data.get('old_password', '')
        new_password = data.get('new_password', '')
        
        if not old_password or not new_password:
            return jsonify({'success': False, 'error': 'Old and new password required'}), 400
        
        # Validate password strength
        is_valid, error_msg = validate_password_strength(new_password)
        if not is_valid:
            return jsonify({'success': False, 'error': error_msg}), 400
        
        # Change password and get new token
        new_token = change_password(g.user['user_id'], old_password, new_password)
        
        log_audit(g.user['user_id'], 'change_password', None, 
                 'User changed password', request.remote_addr)
        
        return jsonify({
            'success': True, 
            'message': 'Password changed successfully',
            'token': new_token
        })
    except AuthError as e:
        return jsonify({'success': False, 'error': str(e)}), 400
    except Exception as e:
        return jsonify({'success': False, 'error': 'Password change failed'}), 500


@app.route('/api/auth/verify-password', methods=['POST'])
@require_auth
def verify_password_endpoint():
    """Verify user's password (for accessing protected content like public key)"""
    try:
        data = request.get_json()
        password = data.get('password', '')
        
        if not password:
            return jsonify({'success': False, 'error': 'Password required'}), 400
        
        # Verify user's password
        from auth import verify_password as verify_pwd, get_auth_db
        conn = get_auth_db()
        cursor = conn.cursor()
        cursor.execute('SELECT password_hash FROM users WHERE id = ?', (g.user['user_id'],))
        user = cursor.fetchone()
        conn.close()
        
        if not user or not verify_pwd(password, user['password_hash']):
            log_audit(g.user['user_id'], 'password_verify_failed', None, 
                     'Failed password verification', request.remote_addr)
            return jsonify({'success': False, 'error': 'Invalid password'}), 401
        
        log_audit(g.user['user_id'], 'password_verify_success', None, 
                 'Password verified successfully', request.remote_addr)
        
        return jsonify({'success': True, 'message': 'Password verified'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/public-key', methods=['GET'])
@require_auth
def get_public_key_endpoint():
    """Get server public key (requires prior password verification in frontend)"""
    try:
        # Only admin and operator can view key
        if g.user['role'] not in [ROLE_ADMIN, ROLE_OPERATOR]:
            return jsonify({'success': False, 'error': 'Insufficient permissions'}), 403
        
        public_key = get_public_key()
        
        log_audit(g.user['user_id'], 'view_public_key', None, 
                 'Accessed public key', request.remote_addr)
        
        return jsonify({'success': True, 'key': public_key})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================================================
# CLIENT GENERATOR ROUTES (v2 - improved)
# ============================================================================

import requests as http_requests  # Avoid conflict with Flask request


@app.route('/api/generator/versions')
@require_auth
def api_generator_versions():
    """Get available RustDesk versions from GitHub"""
    try:
        response = http_requests.get(
            'https://api.github.com/repos/rustdesk/rustdesk/releases',
            timeout=10,
            headers={'Accept': 'application/vnd.github.v3+json'}
        )
        response.raise_for_status()
        releases = response.json()
        
        versions = []
        for release in releases[:15]:  # Last 15 releases
            tag = release.get('tag_name', '')
            if tag:
                versions.append({
                    'tag': tag.lstrip('v'),
                    'name': release.get('name', tag),
                    'published': release.get('published_at', ''),
                    'prerelease': release.get('prerelease', False)
                })
        
        return jsonify({
            'success': True,
            'versions': versions
        })
    except Exception as e:
        # Fallback versions (updated)
        return jsonify({
            'success': True,
            'versions': [
                {'tag': '1.4.5', 'name': 'v1.4.5', 'prerelease': False},
                {'tag': '1.4.4', 'name': 'v1.4.4', 'prerelease': False},
                {'tag': '1.3.7', 'name': 'v1.3.7', 'prerelease': False},
                {'tag': '1.3.6', 'name': 'v1.3.6', 'prerelease': False},
                {'tag': '1.3.5', 'name': 'v1.3.5', 'prerelease': False},
                {'tag': '1.3.2', 'name': 'v1.3.2', 'prerelease': False},
            ]
        })


@app.route('/api/generator/info')
@require_auth
def api_generator_info():
    """Get generator capabilities info"""
    try:
        return jsonify({
            'success': True,
            'sourceCompilationAvailable': SOURCE_GENERATOR_AVAILABLE,
            'configInjectionAvailable': CLIENT_GENERATOR_AVAILABLE,
            'supportedPlatformsSource': ['linux-x64', 'linux-arm64', 'windows-x64', 'windows-x86'] if SOURCE_GENERATOR_AVAILABLE else [],
            'supportedPlatformsConfig': ['windows-x64', 'windows-x86', 'linux-x64', 'linux-arm64', 'macos-x64', 'macos-arm64', 'android'],
            'defaultVersion': '1.4.5',
            'recommendedMethod': 'source' if SOURCE_GENERATOR_AVAILABLE else 'config',
            'notes': {
                'source': 'Source compilation - full customization, may take 5-15 minutes',
                'config': 'Config injection - fast, limited customization'
            }
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/generator/build', methods=['POST'])
@require_auth
@csrf.exempt
def api_generator_build():
    """Generate a custom RustDesk client (JSON API)"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'success': False, 'error': 'No data provided'}), 400
        
        # Validate required fields
        if not data.get('serverHost'):
            return jsonify({'success': False, 'error': 'Server address is required'}), 400
        if not data.get('serverKey'):
            return jsonify({'success': False, 'error': 'Server public key is required'}), 400
        
        # Log the action
        log_audit(g.user['username'], 'generate_client', 
                 f"Building client for {data.get('platform', 'unknown')}", request.remote_addr)
        
        # Check if source compilation is requested
        compile_from_source = data.get('compileFromSource', False)
        
        # Get original platform name from request
        original_platform = data.get('platform', 'windows-x64')
        
        # Map platform names (only for config injection method)
        platform_map = {
            'windows-x64': 'windows-64',
            'windows-x86': 'windows-32',
            'linux-x64': 'linux',
            'linux-arm64': 'linux-arm64',
            'macos-x64': 'macos',
            'macos-arm64': 'macos-arm64',
            'android': 'android'
        }
        
        # Use original platform for source compilation, mapped for config injection
        if compile_from_source and SOURCE_GENERATOR_AVAILABLE:
            platform_for_generator = original_platform  # source generator expects windows-x64, linux-x64 etc.
        else:
            platform_for_generator = platform_map.get(original_platform, 'windows-64')
        
        # Build config for generator module
        config_data = {
            'platform': platform_for_generator,
            'version': data.get('version', '1.4.5'),
            'config_name': data.get('clientName', 'Custom-RustDesk'),
            
            # Server config
            'server_host': data.get('serverHost', ''),
            'server_key': data.get('serverKey', ''),
            'server_api': data.get('apiServer', ''),
            'rendezvous_server': data.get('rendezvousServer', ''),
            
            # Branding / Customization
            'app_name': data.get('appName', ''),
            'logo_base64': data.get('logoBase64', ''),
            'logo_url': data.get('logoUrl', ''),
            'custom_text': data.get('customText', ''),
            'icon_base64': data.get('iconBase64', ''),
            
            # Security
            'password_approve_mode': data.get('approvalMode', 'both'),
            'permanent_password': data.get('permanentPassword', ''),
            'deny_lan_discovery': data.get('denyLanDiscovery', False),
            'enable_direct_ip': data.get('enableDirectIP', False),
            
            # Display
            'theme': data.get('theme', 'system'),
            'view_mode': data.get('viewMode', 'adaptive'),
            'remove_wallpaper': data.get('removeWallpaper', False),
            'show_quality_monitor': data.get('showQualityMonitor', False),
            
            # Permissions
            'perm_keyboard': data.get('permissions', {}).get('keyboard', True),
            'perm_clipboard': data.get('permissions', {}).get('clipboard', True),
            'perm_file_transfer': data.get('permissions', {}).get('fileTransfer', True),
            'perm_audio': data.get('permissions', {}).get('audio', True),
            'perm_tcp_tunnel': data.get('permissions', {}).get('tcpTunnel', False),
            'perm_remote_restart': data.get('permissions', {}).get('restart', False),
            'perm_recording': data.get('permissions', {}).get('recording', False),
            'perm_block_input': data.get('permissions', {}).get('blockInput', False),
            
            # Advanced
            'default_settings': data.get('defaultSettings', ''),
            'override_settings': data.get('overrideSettings', ''),
        }
        
        # Choose generator based on compile mode
        app.logger.info(f"Build request: compile_from_source={compile_from_source}, SOURCE_GENERATOR_AVAILABLE={SOURCE_GENERATOR_AVAILABLE}")
        if compile_from_source and SOURCE_GENERATOR_AVAILABLE:
            # Use source compilation
            app.logger.info(f"Using SOURCE compilation for {data.get('platform', 'unknown')}")
            log_audit(g.user['username'], 'compile_client', 
                     f"Starting source compilation for {data.get('platform', 'unknown')}", request.remote_addr)
            result = generate_from_source(config_data)
        else:
            # Use legacy config-injection method
            app.logger.info(f"Using CONFIG INJECTION for {data.get('platform', 'unknown')}")
            result = generate_custom_client(config_data)
        
        if result.get('success'):
            import os
            filename = result.get('filename', 'client')
            file_path = result.get('client_path', '')
            file_size = 'N/A'
            
            if file_path and os.path.exists(file_path):
                size_bytes = os.path.getsize(file_path)
                if size_bytes > 1024 * 1024:
                    file_size = f"{size_bytes / (1024 * 1024):.1f} MB"
                else:
                    file_size = f"{size_bytes / 1024:.1f} KB"
            
            # Generate build ID from filename
            build_id = result.get('build_id', filename.replace('.', '_'))
            
            # Determine download URL based on generator type
            if compile_from_source and SOURCE_GENERATOR_AVAILABLE:
                download_url = f'/api/download-client/{filename}'
            else:
                download_url = f'/api/generator/download/{filename}'
            
            return jsonify({
                'success': True,
                'filename': filename,
                'buildId': build_id,
                'size': file_size,
                'downloadUrl': download_url,
                'compiledFromSource': compile_from_source and SOURCE_GENERATOR_AVAILABLE,
                'message': result.get('message', 'Build completed successfully')
            })
        else:
            return jsonify({
                'success': False,
                'error': result.get('error', 'Generation failed')
            }), 500
            
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/generator/download/<filename>')
@require_auth
def api_generator_download(filename):
    """Download a generated client"""
    try:
        from werkzeug.utils import secure_filename as sf
        filename = sf(filename)
        
        file_path = os.path.join('/tmp/rustdesk_builds', filename)
        
        if not os.path.exists(file_path):
            return jsonify({'success': False, 'error': 'File not found'}), 404
        
        log_audit(g.user['username'], 'download_client', 
                 f'Downloaded {filename}', request.remote_addr)
        
        return send_file(
            file_path,
            as_attachment=True,
            download_name=filename
        )
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================================================
# CLIENT GENERATOR ROUTES (Legacy - kept for compatibility)
# ============================================================================

def allowed_file(filename):
    """Check if file extension is allowed"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


@app.route('/api/generate-client', methods=['POST'])
@require_auth
@csrf.exempt
def api_generate_client():
    """Generate a custom RustDesk client"""
    try:
        # Log the action
        log_audit(g.user['username'], 'generate_client', 
                 f'Generating custom RustDesk client', request.remote_addr)
        
        # Collect form data
        config_data = {
            'platform': request.form.get('platform', 'windows-64'),
            'version': request.form.get('version', '1.4.5'),
            'fix_api_delay': request.form.get('fix_api_delay') == 'true',
            
            # General
            'config_name': request.form.get('config_name', 'custom-rustdesk'),
            'custom_app_name': request.form.get('custom_app_name', ''),
            'connection_type': request.form.get('connection_type', 'bidirectional'),
            'disable_installation': request.form.get('disable_installation', 'no'),
            'disable_settings': request.form.get('disable_settings', 'no'),
            'android_app_id': request.form.get('android_app_id', ''),
            
            # Server
            'server_host': request.form.get('server_host', ''),
            'server_key': request.form.get('server_key', ''),
            'server_api': request.form.get('server_api', ''),
            'custom_url_links': request.form.get('custom_url_links', ''),
            'custom_url_download': request.form.get('custom_url_download', ''),
            'company_copyright': request.form.get('company_copyright', ''),
            
            # Security
            'password_approve_mode': request.form.get('password_approve_mode', 'both'),
            'permanent_password': request.form.get('permanent_password', ''),
            'deny_lan_discovery': request.form.get('deny_lan_discovery') == 'true',
            'enable_direct_ip': request.form.get('enable_direct_ip') == 'true',
            'auto_close_inactive': request.form.get('auto_close_inactive') == 'true',
            'allow_hide_window': request.form.get('allow_hide_window') == 'true',
            
            # Visual
            'theme': request.form.get('theme', 'follow'),
            'theme_override': request.form.get('theme_override', 'default'),
            
            # Permissions
            'permissions_mode': request.form.get('permissions_mode', 'default'),
            'permission_type': request.form.get('permission_type', 'custom'),
            'perm_keyboard': request.form.get('perm_keyboard') == 'true',
            'perm_clipboard': request.form.get('perm_clipboard') == 'true',
            'perm_file_transfer': request.form.get('perm_file_transfer') == 'true',
            'perm_audio': request.form.get('perm_audio') == 'true',
            'perm_tcp_tunnel': request.form.get('perm_tcp_tunnel') == 'true',
            'perm_remote_restart': request.form.get('perm_remote_restart') == 'true',
            'perm_recording': request.form.get('perm_recording') == 'true',
            'perm_block_input': request.form.get('perm_block_input') == 'true',
            'perm_remote_config': request.form.get('perm_remote_config') == 'true',
            'perm_printer': request.form.get('perm_printer') == 'true',
            'perm_camera': request.form.get('perm_camera') == 'true',
            'perm_terminal': request.form.get('perm_terminal') == 'true',
            
            # Code changes
            'code_monitor_cycle': request.form.get('code_monitor_cycle') == 'true',
            'code_offline_x': request.form.get('code_offline_x') == 'true',
            'code_remove_version_notif': request.form.get('code_remove_version_notif') == 'true',
            
            # Other
            'remove_wallpaper': request.form.get('remove_wallpaper') == 'true',
            'default_settings': request.form.get('default_settings', ''),
            'override_settings': request.form.get('override_settings', ''),
        }
        
        # Handle file uploads
        if 'custom_icon' in request.files:
            icon_file = request.files['custom_icon']
            if icon_file and icon_file.filename and allowed_file(icon_file.filename):
                filename = secure_filename(icon_file.filename)
                icon_path = os.path.join(app.config['UPLOAD_FOLDER'], f"{config_data['config_name']}_icon_{filename}")
                icon_file.save(icon_path)
                config_data['custom_icon_path'] = icon_path
        
        if 'custom_logo' in request.files:
            logo_file = request.files['custom_logo']
            if logo_file and logo_file.filename and allowed_file(logo_file.filename):
                filename = secure_filename(logo_file.filename)
                logo_path = os.path.join(app.config['UPLOAD_FOLDER'], f"{config_data['config_name']}_logo_{filename}")
                logo_file.save(logo_path)
                config_data['custom_logo_path'] = logo_path
        
        # Generate the client
        result = generate_custom_client(config_data)
        
        if result['success']:
            # Create download URL
            filename = result['filename']
            download_url = f'/api/download-client/{filename}'
            
            return jsonify({
                'success': True,
                'download_url': download_url,
                'filename': filename
            })
        else:
            return jsonify({
                'success': False,
                'error': result.get('error', 'Unknown error occurred')
            }), 500
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/download-client/<filename>')
@require_auth
def download_client(filename):
    """Download a generated client"""
    try:
        # Sanitize filename
        filename = secure_filename(filename)
        
        # Try source generator builds directory first
        source_build_path = os.path.expanduser(f'~/rustdesk-build/builds/{filename}')
        
        # Fallback to legacy client generator path
        legacy_path = os.path.join('/tmp/rustdesk_builds', filename)
        
        # Check which file exists
        if os.path.exists(source_build_path):
            file_path = source_build_path
        elif os.path.exists(legacy_path):
            file_path = legacy_path
        else:
            return jsonify({'success': False, 'error': 'File not found'}), 404
        
        # Log the download
        log_audit(g.user['username'], 'download_client', 
                 f'Downloaded client: {filename}', request.remote_addr)
        
        # Send file
        return send_file(file_path, as_attachment=True, download_name=filename)
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/compile-client', methods=['POST'])
@require_auth
@csrf.exempt
def api_compile_client():
    """Compile a custom RustDesk client from source"""
    try:
        if not SOURCE_GENERATOR_AVAILABLE:
            return jsonify({
                'success': False,
                'error': 'Source compilation not available on this server'
            }), 503
        
        # Log the action
        log_audit(g.user['username'], 'compile_client', 
                 f'Starting source compilation', request.remote_addr)
        
        # Collect form data
        config_data = {
            'platform': request.form.get('platform', 'linux'),
            'version': request.form.get('version', '1.4.5'),
            
            # General
            'config_name': request.form.get('config_name', 'custom-rustdesk'),
            'app_name': request.form.get('app_name', ''),
            'custom_text': request.form.get('custom_text', ''),
            
            # Server
            'server_host': request.form.get('server_host', ''),
            'server_key': request.form.get('server_key', ''),
            'server_api': request.form.get('server_api', ''),
            
            # Branding
            'logo_base64': request.form.get('logo_base64', ''),
            'icon_base64': request.form.get('icon_base64', ''),
        }
        
        # Compile the client from source
        result = generate_from_source(config_data)
        
        if result['success']:
            # Create download URL
            filename = result['filename']
            download_url = f'/api/download-client/{filename}'
            
            return jsonify({
                'success': True,
                'build_id': result.get('build_id', ''),
                'download_url': download_url,
                'filename': filename,
                'message': result.get('message', 'Compilation completed successfully')
            })
        else:
            return jsonify({
                'success': False,
                'build_id': result.get('build_id', ''),
                'error': result.get('error', 'Unknown compilation error')
            }), 500
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/build-status/<build_id>')
@require_auth
def api_build_status(build_id):
    """Get status of a specific build"""
    try:
        if not SOURCE_GENERATOR_AVAILABLE:
            return jsonify({
                'status': 'unavailable',
                'message': 'Source compilation not available'
            })
        
        status = get_build_status(build_id)
        return jsonify(status)
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500


@app.route('/api/server-info')
@require_auth
def api_server_info():
    """Get server information for client generator"""
    try:
        info = {
            'source_compilation_available': SOURCE_GENERATOR_AVAILABLE,
            'client_generator_available': CLIENT_GENERATOR_AVAILABLE,
            'supported_platforms': ['linux', 'linux-arm64', 'windows-64', 'windows-32'] if SOURCE_GENERATOR_AVAILABLE else [],
            'default_version': '1.4.5'
        }
        return jsonify(info)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# Cleanup expired sessions periodically
@app.before_request
def before_request():
    """Run before each request"""
    # Cleanup expired sessions (every 100th request to avoid overhead)
    import random
    if random.randint(1, 100) == 1:
        try:
            cleanup_expired_sessions()
        except:
            pass


@app.after_request
def add_security_headers(response):
    """Add security headers to all responses"""
    # Content Security Policy
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com; "
        "font-src 'self' https://fonts.gstatic.com https://cdnjs.cloudflare.com; "
        "img-src 'self' data:; "
        "connect-src 'self'"
    )
    # Additional security headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    return response


# Note: Authentication is handled by @require_auth decorator on each endpoint
# No global before_request check needed - let JavaScript on pages handle redirects


if __name__ == '__main__':
    DEBUG = os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    HOST = os.environ.get('FLASK_HOST', '0.0.0.0')
    PORT = int(os.environ.get('FLASK_PORT', 5000))
    app.run(host=HOST, port=PORT, debug=DEBUG)
