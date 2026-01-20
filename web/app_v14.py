from flask import Flask, render_template, request, jsonify, redirect, url_for, g
import sqlite3
from datetime import datetime
import os
import requests
import re
from flask_wtf.csrf import CSRFProtect, generate_csrf
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

# Import authentication module
from auth import (
    require_auth, require_role, optional_auth,
    authenticate, create_session, verify_session, delete_session,
    log_audit, cleanup_expired_sessions,
    change_password,
    ROLE_ADMIN, ROLE_OPERATOR, ROLE_VIEWER,
    AuthError
)

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('FLASK_SECRET_KEY', os.urandom(32))
app.config['WTF_CSRF_CHECK_DEFAULT'] = False  # Manual CSRF for API

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
                return f"[id_ed25519.pub] {key_content}"
        
        rustdesk_dir = os.path.dirname(PUB_KEY_PATH)
        if os.path.exists(rustdesk_dir):
            pub_files = [f for f in os.listdir(rustdesk_dir) if f.endswith('.pub')]
            if pub_files:
                pub_file_path = os.path.join(rustdesk_dir, pub_files[0])
                with open(pub_file_path, 'r') as f:
                    key_content = f.read().strip()
                    return f"[{pub_files[0]}] {key_content}"
        
        return "❌ No public key file (.pub) found in RustDesk directory"
    except Exception as e:
        return f"Error reading key: {str(e)}"


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
        return jsonify({'success': False, 'error': 'Login failed'}), 500


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


# ============================================================================
# MAIN ROUTES
# ============================================================================

@app.route('/')
def index():
    """Render the main dashboard page. Auth check done by JavaScript on client side."""
    return render_template('index_v15.html')


@app.route('/api/devices', methods=['GET'])
@require_auth
@limiter.exempt  # Authenticated users bypass rate limit
def get_devices():
    """Fetch all devices from the database with online status from HBBS API."""
    try:
        # Try to get status from HBBS API
        online_ids = set()
        api_device_info = {}
        try:
            headers = {}
            if HBBS_API_KEY:
                headers['X-API-Key'] = HBBS_API_KEY
            
            response = requests.get(f'{HBBS_API_URL}/peers', headers=headers, timeout=2)
            if response.status_code == 200:
                api_data = response.json()
                if api_data.get('success') and api_data.get('data'):
                    for peer in api_data['data']:
                        device_id = peer.get('id')
                        if device_id:
                            api_device_info[device_id] = peer
                            if peer.get('online'):
                                online_ids.add(device_id)
            elif response.status_code == 401:
                print(f"Warning: HBBS API authentication failed. Check API key.")
        except Exception as e:
            print(f"Warning: Could not connect to HBBS API: {e}")
        
        # Get devices from database
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('''
            SELECT 
                guid, id, uuid, pk, created_at, user, status, note, info,
                is_banned, banned_at, banned_by, ban_reason
            FROM peer
            WHERE is_deleted = 0
            ORDER BY created_at DESC
        ''')
        
        devices = []
        for row in cursor.fetchall():
            device_id = row['id']
            
            # WAŻNE: API /peers ma bug w http_api.rs:
            # 1. Query: "WHERE (status IS NULL OR status = 0)" - zwraca tylko offline
            # 2. Hardcoded: online = false - zawsze false dla wszystkich
            # Z powodu tych bugów, API nie nadaje się do określania statusu online
            # 
            # ROZWIĄZANIE: Używamy TYLKO pola status z bazy danych (aktualizowane przez HBBS)
            # status = 1 = online, status = 0/NULL = offline
            # To jest źródło prawdy - HBBS aktualizuje to pole w czasie rzeczywistym
            
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
            
            updates.append('id = ?')
            params.append(data['new_id'])
        
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
