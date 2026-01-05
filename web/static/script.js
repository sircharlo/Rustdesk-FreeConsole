// Global variables
let allDevices = [];
let currentDeviceId = null;

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    loadDevices();
    loadStats();
    
    // Auto-refresh every 5 seconds
    setInterval(() => {
        loadDevices();
        loadStats();
    }, 5000);
});

// Load devices from API
async function loadDevices() {
    try {
        const response = await fetch('/api/devices');
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
    try {
        const response = await fetch('/api/stats');
        const data = await response.json();
        
        if (data.success) {
            document.getElementById('statTotal').textContent = data.stats.total;
            document.getElementById('statActive').textContent = data.stats.active;
            document.getElementById('statInactive').textContent = data.stats.inactive;
            document.getElementById('statNotes').textContent = data.stats.with_notes;
        }
    } catch (error) {
        console.error('Error loading stats:', error);
    }
}

// Update navigation stats
function updateNavStats(devices) {
    const total = devices.length;
    const active = devices.filter(d => d.online).length;
    
    document.querySelector('#totalDevices span').textContent = total;
    document.querySelector('#activeDevices span').textContent = active;
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
    
    tbody.innerHTML = devices.map(device => `
        <tr>
            <td>
                <strong>${escapeHtml(device.id)}</strong>
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
                <button class="action-btn connect" onclick="connectDevice('${escapeHtml(device.id)}')" title="Connect">
                    <i class="fas fa-plug"></i>
                </button>
                <button class="action-btn details" onclick="showDetails('${escapeHtml(device.id)}')" title="Details">
                    <i class="fas fa-info-circle"></i>
                </button>
                <button class="action-btn edit" onclick="editDevice('${escapeHtml(device.id)}')" title="Edit">
                    <i class="fas fa-edit"></i>
                </button>
                <button class="action-btn delete" onclick="deleteDevice('${escapeHtml(device.id)}')" title="Delete">
                    <i class="fas fa-trash-alt"></i>
                </button>
            </td>
        </tr>
    `).join('');
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
    
    const detailsContent = document.getElementById('detailsContent');
    detailsContent.innerHTML = `
        <div class="detail-item">
            <div class="detail-label">ID:</div>
            <div class="detail-value">${escapeHtml(device.id)}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">GUID:</div>
            <div class="detail-value">${device.guid || 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">UUID:</div>
            <div class="detail-value">${device.uuid || 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">Public Key:</div>
            <div class="detail-value">${device.pk || 'N/A'}</div>
        </div>
        <div class="detail-item">
            <div class="detail-label">User:</div>
            <div class="detail-value">${device.user || 'N/A'}</div>
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
    const newId = document.getElementById('editNewId').value.trim();
    const note = document.getElementById('editNote').value.trim();
    
    const data = { note };
    if (newId) {
        data.new_id = newId;
    }
    
    try {
        const response = await fetch(`/api/device/${currentDeviceId}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });
        
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
    try {
        const response = await fetch(`/api/device/${currentDeviceId}`, {
            method: 'DELETE'
        });
        
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

// Show public key modal
function showPublicKey() {
    openModal('keyModal');
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

function closeKeyModal() {
    closeModal('keyModal');
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
    
    // Update icon based on type
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
