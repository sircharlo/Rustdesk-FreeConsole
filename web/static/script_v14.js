// BetterDesk Console - Main JavaScript with Authentication v1.4.0
// Global variables
let allDevices = [];
let currentDeviceId = null;
let authToken = null;
let userRole = null;

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    // Check authentication
    checkAuth();
    
    // Load data
    loadDevices();
    loadStats();
    
    // Auto-refresh every 2 seconds
    setInterval(() => {
        loadDevices();
        loadStats();
    }, 2000);
});

// Authentication check
function checkAuth() {
    authToken = localStorage.getItem('authToken');
    userRole = localStorage.getItem('role');
    
    if (!authToken) {
        window.location.href = '/login';
        return false;
    }
    
    return true;
}

// Get auth headers for API calls
function getAuthHeaders() {
    return {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`
    };
}

// Handle authentication errors
function handleAuthError(error, response) {
    if (response && response.status === 401) {
        // Token expired or invalid
        localStorage.removeItem('authToken');
        localStorage.removeItem('username');
        localStorage.removeItem('role');
        window.location.href = '/login';
        return true;
    }
    return false;
}

// Load devices from API
async function loadDevices() {
    if (!checkAuth()) return;
    
    try {
        const response = await fetch('/api/devices', {
            headers: getAuthHeaders()
        });
        
        if (handleAuthError(null, response)) return;
        
        const data = await response.json();
        
        if (data.success) {
            allDevices = data.devices;
            renderDevices(allDevices);
            updateNavStats(allDevices);
        } else {
            showToast('Error loading devices: ' + data.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to load devices', 'error');
    }
}

// Load statistics
async function loadStats() {
    if (!checkAuth()) return;
    
    try {
        const response = await fetch('/api/stats', {
            headers: getAuthHeaders()
        });
        
        if (handleAuthError(null, response)) return;
        
        const data = await response.json();
        
        if (data.success) {
            document.getElementById('statTotal').textContent = data.stats.total;
            document.getElementById('statActive').textContent = data.stats.active;
            document.getElementById('statInactive').textContent = data.stats.inactive;
            document.getElementById('statBanned').textContent = data.stats.banned || 0;
            document.getElementById('statNotes').textContent = data.stats.with_notes;
            
            // Update top bar stats
            const topTotal = document.getElementById('topTotalDevices');
            const topActive = document.getElementById('topActiveDevices');
            if (topTotal) topTotal.querySelector('span').textContent = data.stats.total;
            if (topActive) topActive.querySelector('span').textContent = data.stats.active;
        }
    } catch (error) {
        console.error('Error loading stats:', error);
    }
}

// Update navigation stats
function updateNavStats(devices) {
    const total = devices.length;
    const active = devices.filter(d => d.online).length;
    
    const totalDevicesEl = document.querySelector('#totalDevices span');
    const activeDevicesEl = document.querySelector('#activeDevices span');
    
    if (totalDevicesEl) totalDevicesEl.textContent = total;
    if (activeDevicesEl) activeDevicesEl.textContent = active;
}

// Render devices table
function renderDevices(devices) {
    const tbody = document.getElementById('devicesTableBody');
    
    if (devices.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="5" class="loading">
                    <i class="fas fa-inbox"></i>
                    <span>No devices found</span>
                </td>
            </tr>
        `;
        return;
    }
    
    tbody.innerHTML = devices.map(device => {
        const isBanned = device.is_banned === true || device.is_banned === 1;
        const rowClass = isBanned ? 'style="opacity: 0.6; background: rgba(255, 0, 0, 0.05);"' : '';
        
        // Check permissions for actions
        const canEdit = userRole === 'admin' || userRole === 'operator';
        const canBan = userRole === 'admin' || userRole === 'operator';
        
        return `
        <tr ${rowClass}>
            <td>
                <strong>${escapeHtml(device.id)}</strong>
                ${isBanned ? '<br><span class="status-badge" style="background: #e74c3c; font-size: 0.75rem; margin-top: 4px;"><i class="fas fa-ban"></i> BANNED</span>' : ''}
            </td>
            <td>${escapeHtml(device.note) || '<span style="color: var(--text-secondary);">No note</span>'}</td>
            <td>
                <span class="status-badge ${device.online ? 'status-active' : 'status-inactive'}">
                    <i class="fas fa-circle"></i>
                    ${device.online ? 'Online' : 'Offline'}
                </span>
            </td>
            <td>${formatDate(device.created_at)}</td>
            <td>
                <button class="action-btn connect" onclick="connectDevice('${escapeHtml(device.id)}')" title="Connect" ${isBanned ? 'disabled style="opacity: 0.3; cursor: not-allowed;"' : ''}>
                    <i class="fas fa-plug"></i>
                </button>
                <button class="action-btn details" onclick="showDetails('${escapeHtml(device.id)}')" title="Details">
                    <i class="fas fa-info-circle"></i>
                </button>
                ${canEdit ? `
                <button class="action-btn edit" onclick="editDevice('${escapeHtml(device.id)}')" title="Edit">
                    <i class="fas fa-edit"></i>
                </button>
                ` : ''}
                ${canBan ? (isBanned ? 
                    `<button class="action-btn" onclick="unbanDevice('${escapeHtml(device.id)}')" title="Unban" style="background: #27ae60;">
                        <i class="fas fa-check-circle"></i>
                    </button>` :
                    `<button class="action-btn" onclick="banDevice('${escapeHtml(device.id)}')" title="Ban" style="background: #e74c3c;">
                        <i class="fas fa-ban"></i>
                    </button>`
                ) : ''}
                ${canEdit ? `
                <button class="action-btn delete" onclick="deleteDevice('${escapeHtml(device.id)}')" title="Delete">
                    <i class="fas fa-trash-alt"></i>
                </button>
                ` : ''}
            </td>
        </tr>
    `}).join('');
}

// Filter devices by search
function filterDevices() {
    const searchTerm = document.getElementById('searchInput').value.toLowerCase();
    
    if (!searchTerm) {
        renderDevices(allDevices);
        return;
    }
    
    const filtered = allDevices.filter(device => 
        device.id.toLowerCase().includes(searchTerm) ||
        (device.note && device.note.toLowerCase().includes(searchTerm))
    );
    
    renderDevices(filtered);
}

// Connect to device via rustdesk:// protocol
function connectDevice(deviceId) {
    window.location.href = `rustdesk://${deviceId}`;
    showToast(`Connecting to ${deviceId}...`);
}

// Show device details modal
function showDetails(deviceId) {
    const device = allDevices.find(d => d.id === deviceId);
    if (!device) return;
    
    const isBanned = device.is_banned === true || device.is_banned === 1;
    
    const detailsContent = document.getElementById('detailsContent');
    detailsContent.innerHTML = `
        <div class="detail-item">
            <div class="detail-label">ID:</div>
            <div class="detail-value">${escapeHtml(device.id)}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">GUID:</div>
            <div class="detail-value">${escapeHtml(device.guid) || 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">UUID:</div>
            <div class="detail-value">${escapeHtml(device.uuid) || 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">Public Key:</div>
            <div class="detail-value">${escapeHtml(device.pk) || 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">User:</div>
            <div class="detail-value">${escapeHtml(device.user) || 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">Status:</div>
            <div class="detail-value">
                <span class="status-badge ${device.online ? 'status-active' : 'status-inactive'}">
                    <i class="fas fa-circle"></i>
                    ${device.online ? 'Online' : 'Offline'}
                </span>
            </div>
        </div>
        ${isBanned ? `
        <div class="detail-item" style="background: rgba(231, 76, 60, 0.1); padding: 12px; border-radius: 8px; margin: 12px 0;">
            <div class="detail-label" style="color: #e74c3c; font-weight: bold;"><i class="fas fa-ban"></i> BAN STATUS:</div>
            <div class="detail-value" style="color: #e74c3c; font-weight: bold;">BANNED</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">Banned At:</div>
            <div class="detail-value">${device.banned_at ? formatDate(device.banned_at) : 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">Banned By:</div>
            <div class="detail-value">${escapeHtml(device.banned_by) || 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">Ban Reason:</div>
            <div class="detail-value">${escapeHtml(device.ban_reason) || 'No reason provided'}</div>
        </div>
        ` : ''}
        <div class="detail-item">
            <div class="detail-label">Note:</div>
            <div class="detail-value">${escapeHtml(device.note) || 'No note'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">Created:</div>
            <div class="detail-value">${formatDate(device.created_at)}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">Info:</div>
            <div class="detail-value">${escapeHtml(device.info) || 'N/A'}</div>
        </div>
    `;
    
    openModal('detailsModal');
}

// Edit device
function editDevice(deviceId) {
    const device = allDevices.find(d => d.id === deviceId);
    if (!device) return;
    
    currentDeviceId = deviceId;
    document.getElementById('editDeviceId').value = deviceId;
    document.getElementById('editNewId').value = '';
    document.getElementById('editNote').value = device.note || '';
    
    openModal('editModal');
}

// Save device changes
async function saveDevice() {
    if (!checkAuth()) return;
    
    const newId = document.getElementById('editNewId').value.trim();
    const note = document.getElementById('editNote').value.trim();
    
    if (note.length > 500) {
        showToast('Note is too long (max 500 characters)', 'error');
        return;
    }
    
    if (newId && newId.length > 50) {
        showToast('Device ID is too long (max 50 characters)', 'error');
        return;
    }
    
    if (newId && !/^[a-zA-Z0-9_-]+$/.test(newId)) {
        showToast('Device ID can only contain letters, numbers, underscores and hyphens', 'error');
        return;
    }
    
    if (newId && newId !== currentDeviceId) {
        if (!confirm(`⚠️ WARNING: Changing device ID!\n\nOld ID: ${currentDeviceId}\nNew ID: ${newId}\n\nAre you sure?`)) {
            return;
        }
    }
    
    const data = { note };
    if (newId) data.new_id = newId;
    
    try {
        const response = await fetch(`/api/device/${currentDeviceId}`, {
            method: 'PUT',
            headers: getAuthHeaders(),
            body: JSON.stringify(data)
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            showToast('Device updated successfully');
            closeEditModal();
            await loadDevices();
            await loadStats();
        } else {
            showToast('Error: ' + result.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to update device', 'error');
    }
}

// Delete device
function deleteDevice(deviceId) {
    currentDeviceId = deviceId;
    document.getElementById('deleteDeviceId').textContent = deviceId;
    openModal('deleteModal');
}

// Confirm delete
async function confirmDelete() {
    if (!checkAuth()) return;
    
    const device = allDevices.find(d => d.id === currentDeviceId);
    
    if (!confirm(`⚠️ DELETE DEVICE: ${currentDeviceId}\n\nAre you absolutely sure?`)) {
        return;
    }
    
    try {
        const response = await fetch(`/api/device/${currentDeviceId}`, {
            method: 'DELETE',
            headers: getAuthHeaders()
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            showToast('Device deleted successfully');
            closeDeleteModal();
            await loadDevices();
            await loadStats();
        } else {
            showToast('Error: ' + result.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to delete device', 'error');
    }
}

// Copy public key to clipboard
function copyPublicKey() {
    const keyText = document.getElementById('publicKeyDisplay').textContent;
    navigator.clipboard.writeText(keyText).then(() => {
        showToast('Public key copied to clipboard');
    }).catch(err => {
        console.error('Error copying:', err);
        showToast('Failed to copy public key', 'error');
    });
}

// Refresh devices manually
async function refreshDevices() {
    showToast('Refreshing devices...');
    await loadDevices();
    await loadStats();
}

// Modal functions
function openModal(modalId) {
    document.getElementById(modalId).classList.add('active');
}

function closeModal(modalId) {
    document.getElementById(modalId).classList.remove('active');
}

function closeEditModal() {
    closeModal('editModal');
    currentDeviceId = null;
}

function closeDeleteModal() {
    closeModal('deleteModal');
    currentDeviceId = null;
}

function closeDetailsModal() {
    closeModal('detailsModal');
}

// Close modal when clicking outside
window.onclick = function(event) {
    if (event.target.classList.contains('modal')) {
        event.target.classList.remove('active');
    }
}

// Toast notification
function showToast(message, type = 'success') {
    const toast = document.getElementById('toast');
    const icon = toast.querySelector('i');
    
    if (type === 'error') {
        icon.className = 'fas fa-exclamation-circle';
        icon.style.color = 'var(--danger-color)';
    } else {
        icon.className = 'fas fa-check-circle';
        icon.style.color = 'var(--success-color)';
    }
    
    document.getElementById('toastMessage').textContent = message;
    toast.classList.add('show');
    
    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

// Utility functions
function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function formatDate(dateString) {
    if (!dateString) return 'N/A';
    const date = new Date(dateString);
    const options = { 
        year: 'numeric', 
        month: 'short', 
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    };
    return date.toLocaleDateString('en-US', options);
}

// Ban device
async function banDevice(deviceId) {
    if (!checkAuth()) return;
    
    const reason = prompt(`⚠️ BAN DEVICE: ${deviceId}\n\nEnter ban reason (optional):`);
    
    if (reason === null) return;
    
    if (reason && reason.length > 500) {
        showToast('Ban reason is too long (max 500 characters)', 'error');
        return;
    }
    
    if (!confirm(`Are you sure you want to BAN device ${deviceId}?`)) {
        return;
    }
    
    try {
        const response = await fetch(`/api/device/${deviceId}/ban`, {
            method: 'POST',
            headers: getAuthHeaders(),
            body: JSON.stringify({
                reason: reason || '',
                banned_by: 'admin'
            })
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            showToast(`Device ${deviceId} banned successfully`);
            await loadDevices();
            await loadStats();
        } else {
            showToast('Error: ' + result.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to ban device', 'error');
    }
}

// Unban device
async function unbanDevice(deviceId) {
    if (!checkAuth()) return;
    
    if (!confirm(`✓ UNBAN DEVICE: ${deviceId}\n\nAre you sure?`)) {
        return;
    }
    
    try {
        const response = await fetch(`/api/device/${deviceId}/unban`, {
            method: 'POST',
            headers: getAuthHeaders()
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            showToast(`Device ${deviceId} unbanned successfully`);
            await loadDevices();
            await loadStats();
        } else {
            showToast('Error: ' + result.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to unban device', 'error');
    }
}
// ============================================================================
// PUBLIC KEY VERIFICATION
// ============================================================================

async function verifyPasswordForKey() {
    const password = document.getElementById('keyPassword').value;
    
    if (!password) {
        showToast('Please enter your password', 'error');
        return;
    }
    
    try {
        const response = await fetch('/api/key/verify', {
            method: 'POST',
            headers: getAuthHeaders(),
            body: JSON.stringify({ password: password })
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            document.getElementById('publicKeyDisplay').textContent = result.key;
            document.getElementById('keyPasswordForm').style.display = 'none';
            document.getElementById('keyDisplay').style.display = 'block';
            document.getElementById('keyPassword').value = '';
            showToast('Public key revealed');
        } else {
            showToast('Error: ' + result.error, 'error');
            document.getElementById('keyPassword').value = '';
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to verify password', 'error');
    }
}

function copyPublicKey() {
    const keyText = document.getElementById('publicKeyDisplay').textContent;
    navigator.clipboard.writeText(keyText).then(() => {
        showToast('Public key copied to clipboard');
    }).catch(err => {
        showToast('Failed to copy', 'error');
    });
}

// ============================================================================
// PASSWORD CHANGE
// ============================================================================

function showChangePasswordModal() {
    document.getElementById('changePasswordModal').classList.add('show');
}

function closeChangePasswordModal() {
    document.getElementById('changePasswordModal').classList.remove('show');
    document.getElementById('currentPassword').value = '';
    document.getElementById('newPassword').value = '';
    document.getElementById('confirmPassword').value = '';
}

async function confirmChangePassword() {
    const currentPassword = document.getElementById('currentPassword').value;
    const newPassword = document.getElementById('newPassword').value;
    const confirmPassword = document.getElementById('confirmPassword').value;
    
    if (!currentPassword || !newPassword || !confirmPassword) {
        showToast('All fields are required', 'error');
        return;
    }
    
    if (newPassword.length < 6) {
        showToast('New password must be at least 6 characters', 'error');
        return;
    }
    
    if (newPassword !== confirmPassword) {
        showToast('New passwords do not match', 'error');
        return;
    }
    
    try {
        const response = await fetch('/api/auth/change-password', {
            method: 'POST',
            headers: getAuthHeaders(),
            body: JSON.stringify({
                old_password: currentPassword,
                new_password: newPassword
            })
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            showToast('Password changed successfully');
            closeChangePasswordModal();
        } else {
            showToast('Error: ' + result.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to change password', 'error');
    }
}

// ============================================================================
// USER MANAGEMENT
// ============================================================================

async function loadUsers() {
    if (!checkAuth()) return;
    
    try {
        const response = await fetch('/api/users', {
            headers: getAuthHeaders()
        });
        
        if (handleAuthError(null, response)) return;
        
        const data = await response.json();
        
        if (data.success) {
            renderUsers(data.users);
        } else {
            showToast('Error loading users: ' + data.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to load users', 'error');
    }
}

function renderUsers(users) {
    const tbody = document.getElementById('usersTableBody');
    
    if (users.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="no-data">No users found</td></tr>';
        return;
    }
    
    tbody.innerHTML = users.map(user => {
        const statusBadge = user.is_active ? 
            '<span class="badge badge-success">Active</span>' : 
            '<span class="badge badge-danger">Inactive</span>';
        
        const roleColor = user.role === 'admin' ? 'danger' : 
                          user.role === 'operator' ? 'warning' : 'info';
        const roleBadge = `<span class="badge badge-${roleColor}">${user.role}</span>`;
        
        const createdDate = user.created_at ? new Date(user.created_at).toLocaleDateString() : 'N/A';
        const lastLogin = user.last_login ? new Date(user.last_login).toLocaleString() : 'Never';
        
        return `
            <tr>
                <td>${user.username}</td>
                <td>${roleBadge}</td>
                <td>${statusBadge}</td>
                <td>${createdDate}</td>
                <td>${lastLogin}</td>
                <td class="actions-column">
                    <button class="btn-icon" onclick="showEditUserModal(${user.id}, '${user.username}', '${user.role}')" title="Edit">
                        <i class="fas fa-edit"></i>
                    </button>
                    <button class="btn-icon danger" onclick="showDeleteUserModal(${user.id}, '${user.username}')" title="Delete">
                        <i class="fas fa-trash-alt"></i>
                    </button>
                    ${user.is_active ? 
                        `<button class="btn-icon" onclick="toggleUserStatus(${user.id}, false)" title="Deactivate">
                            <i class="fas fa-user-slash"></i>
                        </button>` :
                        `<button class="btn-icon success" onclick="toggleUserStatus(${user.id}, true)" title="Activate">
                            <i class="fas fa-user-check"></i>
                        </button>`
                    }
                </td>
            </tr>
        `;
    }).join('');
}

// Add User Modal
function showAddUserModal() {
    document.getElementById('addUserModal').classList.add('show');
}

function closeAddUserModal() {
    document.getElementById('addUserModal').classList.remove('show');
    document.getElementById('newUsername').value = '';
    document.getElementById('newUserPassword').value = '';
    document.getElementById('newUserRole').value = 'viewer';
}

async function confirmAddUser() {
    const username = document.getElementById('newUsername').value.trim();
    const password = document.getElementById('newUserPassword').value;
    const role = document.getElementById('newUserRole').value;
    
    if (!username || !password) {
        showToast('Username and password are required', 'error');
        return;
    }
    
    if (password.length < 6) {
        showToast('Password must be at least 6 characters', 'error');
        return;
    }
    
    try {
        const response = await fetch('/api/users', {
            method: 'POST',
            headers: getAuthHeaders(),
            body: JSON.stringify({ username, password, role })
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            showToast(`User ${username} created successfully`);
            closeAddUserModal();
            loadUsers();
        } else {
            showToast('Error: ' + result.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to create user', 'error');
    }
}

// Edit User Modal
function showEditUserModal(userId, username, role) {
    document.getElementById('editUserId').value = userId;
    document.getElementById('editUserUsername').value = username;
    document.getElementById('editUserRole').value = role;
    document.getElementById('resetUserPassword').value = '';
    document.getElementById('editUserModal').classList.add('show');
}

function closeEditUserModal() {
    document.getElementById('editUserModal').classList.remove('show');
}

async function confirmEditUser() {
    const userId = document.getElementById('editUserId').value;
    const role = document.getElementById('editUserRole').value;
    const password = document.getElementById('resetUserPassword').value;
    
    try {
        // Change role
        const roleResponse = await fetch(`/api/users/${userId}`, {
            method: 'PUT',
            headers: getAuthHeaders(),
            body: JSON.stringify({ action: 'change_role', role })
        });
        
        if (handleAuthError(null, roleResponse)) return;
        
        const roleResult = await roleResponse.json();
        
        if (!roleResult.success) {
            showToast('Error: ' + roleResult.error, 'error');
            return;
        }
        
        // Reset password if provided
        if (password && password.length >= 6) {
            const passResponse = await fetch(`/api/users/${userId}`, {
                method: 'PUT',
                headers: getAuthHeaders(),
                body: JSON.stringify({ action: 'reset_password', password })
            });
            
            const passResult = await passResponse.json();
            
            if (!passResult.success) {
                showToast('Role updated but password reset failed: ' + passResult.error, 'error');
                closeEditUserModal();
                loadUsers();
                return;
            }
        }
        
        showToast('User updated successfully');
        closeEditUserModal();
        loadUsers();
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to update user', 'error');
    }
}

// Delete User Modal
function showDeleteUserModal(userId, username) {
    document.getElementById('deleteUserId').value = userId;
    document.getElementById('deleteUserUsername').textContent = username;
    document.getElementById('deleteUserModal').classList.add('show');
}

function closeDeleteUserModal() {
    document.getElementById('deleteUserModal').classList.remove('show');
}

async function confirmDeleteUser() {
    const userId = document.getElementById('deleteUserId').value;
    
    try {
        const response = await fetch(`/api/users/${userId}`, {
            method: 'DELETE',
            headers: getAuthHeaders()
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            showToast('User deleted successfully');
            closeDeleteUserModal();
            loadUsers();
        } else {
            showToast('Error: ' + result.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to delete user', 'error');
    }
}

// Toggle User Status
async function toggleUserStatus(userId, activate) {
    const action = activate ? 'activate' : 'deactivate';
    
    try {
        const response = await fetch(`/api/users/${userId}`, {
            method: 'PUT',
            headers: getAuthHeaders(),
            body: JSON.stringify({ action })
        });
        
        if (handleAuthError(null, response)) return;
        
        const result = await response.json();
        
        if (result.success) {
            showToast(`User ${activate ? 'activated' : 'deactivated'} successfully`);
            loadUsers();
        } else {
            showToast('Error: ' + result.error, 'error');
        }
    } catch (error) {
        console.error('Error:', error);
        showToast('Failed to change user status', 'error');
    }
}