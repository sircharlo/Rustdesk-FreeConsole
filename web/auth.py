"""
Authentication and Authorization Module for BetterDesk Console
"""

import sqlite3
import secrets
import bcrypt
import functools
import os
from datetime import datetime, timedelta
from flask import request, jsonify, g
from typing import Optional


# Database path
DB_PATH = '/opt/rustdesk/db_v2.sqlite3'

# Session expiry (24 hours)
SESSION_EXPIRY_HOURS = 24

# Roles
ROLE_ADMIN = 'admin'
ROLE_OPERATOR = 'operator'
ROLE_VIEWER = 'viewer'

ROLES_HIERARCHY = {
    ROLE_ADMIN: 3,      # Full access
    ROLE_OPERATOR: 2,   # Can ban/unban, edit devices
    ROLE_VIEWER: 1      # Read-only
}


class AuthError(Exception):
    """Custom exception for authentication errors"""
    pass


def get_auth_db():
    """Get database connection for auth operations"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_auth_tables():
    """Initialize authentication tables if they don't exist.
    Called automatically when the module is imported.
    """
    conn = get_auth_db()
    cursor = conn.cursor()
    
    # Check if users table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
    if not cursor.fetchone():
        print("🔧 Creating auth tables (first run)...")
        
        # Create users table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username VARCHAR(50) UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                role VARCHAR(20) NOT NULL DEFAULT 'viewer',
                created_at DATETIME NOT NULL,
                last_login DATETIME,
                is_active BOOLEAN NOT NULL DEFAULT 1,
                CHECK (role IN ('admin', 'operator', 'viewer'))
            )
        ''')
        
        # Create sessions table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS sessions (
                token VARCHAR(64) PRIMARY KEY,
                user_id INTEGER NOT NULL,
                created_at DATETIME NOT NULL,
                expires_at DATETIME NOT NULL,
                last_activity DATETIME NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        ''')
        
        # Create audit_log table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                action VARCHAR(50) NOT NULL,
                device_id VARCHAR(100),
                details TEXT,
                ip_address VARCHAR(45),
                timestamp DATETIME NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
            )
        ''')
        
        # Create default admin user
        default_password = secrets.token_urlsafe(12)
        password_hash = bcrypt.hashpw(default_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        
        cursor.execute('''
            INSERT INTO users (username, password_hash, role, created_at, is_active)
            VALUES (?, ?, 'admin', ?, 1)
        ''', ('admin', password_hash, datetime.now()))
        
        conn.commit()
        
        print("=" * 50)
        print("🔐 DEFAULT ADMIN CREDENTIALS")
        print("=" * 50)
        print(f"   Username: admin")
        print(f"   Password: {default_password}")
        print("=" * 50)
        print("⚠️  CHANGE THIS PASSWORD AFTER FIRST LOGIN!")
        print("=" * 50)
        
        # Save credentials to file
        try:
            creds_file = os.path.join(os.path.dirname(DB_PATH), 'admin_credentials.txt')
            with open(creds_file, 'w') as f:
                f.write(f"BetterDesk Console - Default Admin Credentials\n")
                f.write(f"Generated: {datetime.now()}\n\n")
                f.write(f"Username: admin\n")
                f.write(f"Password: {default_password}\n\n")
                f.write(f"⚠️ CHANGE THIS PASSWORD AFTER FIRST LOGIN!\n")
            os.chmod(creds_file, 0o600)
            print(f"📄 Credentials saved to: {creds_file}")
        except Exception as e:
            print(f"⚠️ Could not save credentials file: {e}")
    
    conn.close()


# Initialize tables on module import
try:
    init_auth_tables()
except Exception as e:
    print(f"⚠️ Auth tables initialization failed: {e}")


def hash_password(password: str) -> str:
    """Hash password using bcrypt"""
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')


def verify_password(password: str, password_hash: str) -> bool:
    """Verify password against hash"""
    return bcrypt.checkpw(password.encode('utf-8'), password_hash.encode('utf-8'))


def generate_session_token() -> str:
    """Generate secure session token"""
    return secrets.token_urlsafe(32)


def create_user(username: str, password: str, role: str = ROLE_VIEWER) -> dict:
    """Create a new user"""
    if role not in ROLES_HIERARCHY:
        raise AuthError(f"Invalid role: {role}")
    
    password_hash = hash_password(password)
    conn = get_auth_db()
    cursor = conn.cursor()
    
    try:
        cursor.execute('''
            INSERT INTO users (username, password_hash, role, created_at, is_active)
            VALUES (?, ?, ?, ?, 1)
        ''', (username, password_hash, role, datetime.now()))
        
        conn.commit()
        user_id = cursor.lastrowid
        
        return {
            'id': user_id,
            'username': username,
            'role': role
        }
    except sqlite3.IntegrityError:
        raise AuthError("Username already exists")
    finally:
        conn.close()


def authenticate(username: str, password: str) -> dict:
    """Authenticate user and return user data"""
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT id, username, password_hash, role, is_active
        FROM users
        WHERE username = ?
    ''', (username,))
    
    user = cursor.fetchone()
    conn.close()
    
    if not user:
        raise AuthError("Invalid username or password")
    
    if not user['is_active']:
        raise AuthError("Account is disabled")
    
    if not verify_password(password, user['password_hash']):
        raise AuthError("Invalid username or password")
    
    return {
        'id': user['id'],
        'username': user['username'],
        'role': user['role']
    }


def create_session(user_id: int) -> str:
    """Create a new session and return token"""
    token = generate_session_token()
    expires_at = datetime.now() + timedelta(hours=SESSION_EXPIRY_HOURS)
    
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT INTO sessions (token, user_id, created_at, expires_at, last_activity)
        VALUES (?, ?, ?, ?, ?)
    ''', (token, user_id, datetime.now(), expires_at, datetime.now()))
    
    # Update last login
    cursor.execute('''
        UPDATE users SET last_login = ? WHERE id = ?
    ''', (datetime.now(), user_id))
    
    conn.commit()
    conn.close()
    
    return token


def verify_session(token: str) -> dict:
    """Verify session token and return user data"""
    if not token:
        raise AuthError("No authentication token provided")
    
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT s.user_id, s.expires_at, u.username, u.role, u.is_active
        FROM sessions s
        JOIN users u ON s.user_id = u.id
        WHERE s.token = ?
    ''', (token,))
    
    session = cursor.fetchone()
    
    if not session:
        conn.close()
        raise AuthError("Invalid session token")
    
    # Check if session expired
    expires_at = datetime.fromisoformat(session['expires_at'])
    if datetime.now() > expires_at:
        # Delete expired session
        cursor.execute('DELETE FROM sessions WHERE token = ?', (token,))
        conn.commit()
        conn.close()
        raise AuthError("Session expired")
    
    # Check if user is active
    if not session['is_active']:
        conn.close()
        raise AuthError("Account is disabled")
    
    # Update last activity
    cursor.execute('''
        UPDATE sessions SET last_activity = ? WHERE token = ?
    ''', (datetime.now(), token))
    
    conn.commit()
    conn.close()
    
    return {
        'user_id': session['user_id'],
        'username': session['username'],
        'role': session['role']
    }


def delete_session(token: str):
    """Delete session (logout)"""
    conn = get_auth_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM sessions WHERE token = ?', (token,))
    conn.commit()
    conn.close()


def cleanup_expired_sessions():
    """Remove expired sessions from database"""
    conn = get_auth_db()
    cursor = conn.cursor()
    cursor.execute('DELETE FROM sessions WHERE expires_at < ?', (datetime.now(),))
    deleted = cursor.rowcount
    conn.commit()
    conn.close()
    return deleted


def log_audit(user_id: int, action: str, device_id: Optional[str] = None, 
              details: Optional[str] = None, ip_address: Optional[str] = None):
    """Log user action for audit trail"""
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT INTO audit_log (user_id, action, device_id, details, ip_address, timestamp)
        VALUES (?, ?, ?, ?, ?, ?)
    ''', (user_id, action, device_id, details, ip_address or 'unknown', datetime.now()))
    
    conn.commit()
    conn.close()


def get_user_by_id(user_id: int) -> Optional[dict]:
    """Get user data by ID"""
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT id, username, role, created_at, last_login, is_active
        FROM users WHERE id = ?
    ''', (user_id,))
    
    user = cursor.fetchone()
    conn.close()
    
    if not user:
        return None
    
    return dict(user)


def list_users() -> list:
    """List all users (admin only)"""
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT id, username, role, created_at, last_login, is_active
        FROM users
        ORDER BY created_at DESC
    ''')
    
    users = [dict(row) for row in cursor.fetchall()]
    conn.close()
    
    return users


def update_user_role(user_id: int, new_role: str):
    """Update user role (admin only)"""
    if new_role not in ROLES_HIERARCHY:
        raise AuthError(f"Invalid role: {new_role}")
    
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('UPDATE users SET role = ? WHERE id = ?', (new_role, user_id))
    conn.commit()
    conn.close()


def deactivate_user(user_id: int):
    """Deactivate user account"""
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('UPDATE users SET is_active = 0 WHERE id = ?', (user_id,))
    # Also delete all sessions for this user
    cursor.execute('DELETE FROM sessions WHERE user_id = ?', (user_id,))
    
    conn.commit()
    conn.close()


def activate_user(user_id: int):
    """Activate user account"""
    conn = get_auth_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE users SET is_active = 1 WHERE id = ?', (user_id,))
    conn.commit()
    conn.close()


def delete_user(user_id: int):
    """Delete user account (admin only)"""
    conn = get_auth_db()
    cursor = conn.cursor()
    
    # Delete all sessions first
    cursor.execute('DELETE FROM sessions WHERE user_id = ?', (user_id,))
    # Delete user
    cursor.execute('DELETE FROM users WHERE id = ?', (user_id,))
    
    conn.commit()
    conn.close()


def change_password(user_id: int, old_password: str, new_password: str) -> str:
    """Change user password and return new session token"""
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('SELECT password_hash FROM users WHERE id = ?', (user_id,))
    user = cursor.fetchone()
    
    if not user:
        conn.close()
        raise AuthError("User not found")
    
    if not verify_password(old_password, user['password_hash']):
        conn.close()
        raise AuthError("Current password is incorrect")
    
    new_hash = hash_password(new_password)
    cursor.execute('UPDATE users SET password_hash = ? WHERE id = ?', (new_hash, user_id))
    
    # Invalidate all sessions
    cursor.execute('DELETE FROM sessions WHERE user_id = ?', (user_id,))
    
    conn.commit()
    conn.close()
    
    # Create new session
    return create_session(user_id)


def reset_password(user_id: int, new_password: str):
    """Reset user password (admin only)"""
    new_hash = hash_password(new_password)
    
    conn = get_auth_db()
    cursor = conn.cursor()
    
    cursor.execute('UPDATE users SET password_hash = ? WHERE id = ?', (new_hash, user_id))
    # Invalidate all sessions for this user
    cursor.execute('DELETE FROM sessions WHERE user_id = ?', (user_id,))
    
    conn.commit()
    conn.close()


# Flask decorators

def require_auth(f):
    """Decorator to require authentication"""
    @functools.wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('Authorization')
        
        if token and token.startswith('Bearer '):
            token = token[7:]  # Remove 'Bearer ' prefix
        
        if not token:
            return jsonify({'success': False, 'error': 'No authorization token provided'}), 401
        
        try:
            user_data = verify_session(token)
            g.user = user_data  # Store in Flask's g object
            return f(*args, **kwargs)
        except AuthError as e:
            return jsonify({'success': False, 'error': str(e)}), 401
    
    return decorated_function


def require_role(*allowed_roles):
    """Decorator to require specific role(s)"""
    def decorator(f):
        @functools.wraps(f)
        def decorated_function(*args, **kwargs):
            if not hasattr(g, 'user'):
                return jsonify({'success': False, 'error': 'Authentication required'}), 401
            
            user_role = g.user['role']
            
            if user_role not in allowed_roles:
                return jsonify({
                    'success': False, 
                    'error': f'Insufficient permissions. Required: {", ".join(allowed_roles)}'
                }), 403
            
            return f(*args, **kwargs)
        
        return decorated_function
    return decorator


def optional_auth(f):
    """Decorator for optional authentication (doesn't fail if not authenticated)"""
    @functools.wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('Authorization')
        
        if token and token.startswith('Bearer '):
            token = token[7:]
            try:
                user_data = verify_session(token)
                g.user = user_data
            except AuthError:
                g.user = None
        else:
            g.user = None
        
        return f(*args, **kwargs)
    
    return decorated_function
