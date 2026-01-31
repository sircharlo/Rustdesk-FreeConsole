/* Client Generator JavaScript */

// State
let selectedPlatform = 'windows-64';
let detectedPublicIP = null;

// Initialize
document.addEventListener('DOMContentLoaded', function() {
    initializePlatformSelection();
    initializeFileInputs();
    checkAuthentication();
});

function checkAuthentication() {
    const token = localStorage.getItem('authToken');
    if (!token) {
        window.location.href = '/login';
        return;
    }
    
    // Verify token
    fetch('/api/auth/verify', {
        headers: {
            'Authorization': `Bearer ${token}`
        }
    })
    .then(response => {
        if (!response.ok) {
            localStorage.removeItem('authToken');
            window.location.href = '/login';
        }
        return response.json();
    })
    .then(data => {
        if (data.user) {
            document.getElementById('sidebarUsername').textContent = data.user.username || 'User';
            const roleNames = {
                'admin': 'Administrator',
                'operator': 'Operator',
                'viewer': 'Viewer'
            };
            document.getElementById('sidebarUserRole').textContent = roleNames[data.user.role] || data.user.role;
        }
    })
    .catch(() => {
        window.location.href = '/login';
    });
}

function initializePlatformSelection() {
    const platformCards = document.querySelectorAll('.platform-card');
    
    platformCards.forEach(card => {
        card.addEventListener('click', function() {
            // Remove selected class from all cards
            platformCards.forEach(c => c.classList.remove('selected'));
            
            // Add selected class to clicked card
            this.classList.add('selected');
            
            // Update selected platform
            selectedPlatform = this.dataset.platform;
        });
    });
    
    // Select first platform by default
    if (platformCards.length > 0) {
        platformCards[0].classList.add('selected');
    }
}

function initializeFileInputs() {
    const iconInput = document.getElementById('customIcon');
    const logoInput = document.getElementById('customLogo');
    
    if (iconInput) {
        iconInput.addEventListener('change', function() {
            const fileName = this.files.length > 0 ? this.files[0].name : 'Nie wybrano pliku';
            document.getElementById('iconFileName').textContent = fileName;
        });
    }
    
    if (logoInput) {
        logoInput.addEventListener('change', function() {
            const fileName = this.files.length > 0 ? this.files[0].name : 'Nie wybrano pliku';
            document.getElementById('logoFileName').textContent = fileName;
        });
    }
}

function collectFormData() {
    // Collect all form data
    const formData = new FormData();
    
    // Platform
    formData.append('platform', selectedPlatform);
    formData.append('version', document.getElementById('rustdeskVersion').value);
    formData.append('fix_api_delay', document.getElementById('fixApiDelay').checked);
    
    // General
    formData.append('config_name', document.getElementById('configName').value);
    formData.append('custom_app_name', document.getElementById('customAppName').value);
    formData.append('connection_type', document.querySelector('input[name="connectionType"]:checked').value);
    formData.append('disable_installation', document.getElementById('disableInstallation').value);
    formData.append('disable_settings', document.getElementById('disableSettings').value);
    formData.append('android_app_id', document.getElementById('androidAppId').value);
    
    // Custom Server
    formData.append('server_host', document.getElementById('serverHost').value);
    formData.append('server_key', document.getElementById('serverKey').value);
    formData.append('server_api', document.getElementById('serverApi').value);
    formData.append('custom_url_links', document.getElementById('customUrlLinks').value);
    formData.append('custom_url_download', document.getElementById('customUrlDownload').value);
    formData.append('company_copyright', document.getElementById('companyCopyright').value);
    
    // Security
    formData.append('password_approve_mode', document.getElementById('passwordApproveMode').value);
    formData.append('permanent_password', document.getElementById('permanentPassword').value);
    formData.append('deny_lan_discovery', document.getElementById('denyLanDiscovery').checked);
    formData.append('enable_direct_ip', document.getElementById('enableDirectIp').checked);
    formData.append('auto_close_inactive', document.getElementById('autoCloseInactive').checked);
    formData.append('allow_hide_window', document.getElementById('allowHideWindow').checked);
    
    // Visual
    const iconFile = document.getElementById('customIcon').files[0];
    if (iconFile) {
        formData.append('custom_icon', iconFile);
    }
    
    const logoFile = document.getElementById('customLogo').files[0];
    if (logoFile) {
        formData.append('custom_logo', logoFile);
    }
    
    formData.append('theme', document.getElementById('theme').value);
    formData.append('theme_override', document.getElementById('themeOverride').value);
    
    // Permissions
    formData.append('permissions_mode', document.getElementById('permissionsMode').value);
    formData.append('permission_type', document.getElementById('permissionType').value);
    formData.append('perm_keyboard', document.getElementById('permKeyboard').checked);
    formData.append('perm_clipboard', document.getElementById('permClipboard').checked);
    formData.append('perm_file_transfer', document.getElementById('permFileTransfer').checked);
    formData.append('perm_audio', document.getElementById('permAudio').checked);
    formData.append('perm_tcp_tunnel', document.getElementById('permTcpTunnel').checked);
    formData.append('perm_remote_restart', document.getElementById('permRemoteRestart').checked);
    formData.append('perm_recording', document.getElementById('permRecording').checked);
    formData.append('perm_block_input', document.getElementById('permBlockInput').checked);
    formData.append('perm_remote_config', document.getElementById('permRemoteConfig').checked);
    formData.append('perm_printer', document.getElementById('permPrinter').checked);
    formData.append('perm_camera', document.getElementById('permCamera').checked);
    formData.append('perm_terminal', document.getElementById('permTerminal').checked);
    
    // Code Changes
    formData.append('code_monitor_cycle', document.getElementById('codeMonitorCycle').checked);
    formData.append('code_offline_x', document.getElementById('codeOfflineX').checked);
    formData.append('code_remove_version_notif', document.getElementById('codeRemoveVersionNotif').checked);
    
    // Other
    formData.append('remove_wallpaper', document.getElementById('removeWallpaper').checked);
    formData.append('default_settings', document.getElementById('defaultSettings').value);
    formData.append('override_settings', document.getElementById('overrideSettings').value);
    
    return formData;
}

function validateForm() {
    const configName = document.getElementById('configName').value;
    
    // Validate config name
    if (configName && !/^[a-zA-Z0-9_-]+$/.test(configName)) {
        showError('Configuration name can only contain letters, numbers, underscores and hyphens');
        return false;
    }
    
    // Validate JSON fields
    const defaultSettings = document.getElementById('defaultSettings').value;
    const overrideSettings = document.getElementById('overrideSettings').value;
    
    if (defaultSettings) {
        try {
            JSON.parse(defaultSettings);
        } catch (e) {
            showError('Default settings must be valid JSON');
            return false;
        }
    }
    
    if (overrideSettings) {
        try {
            JSON.parse(overrideSettings);
        } catch (e) {
            showError('Override settings must be valid JSON');
            return false;
        }
    }
    
    return true;
}

async function generateClient() {
    // Validate form
    if (!validateForm()) {
        return;
    }
    
    // Get form data
    const formData = collectFormData();
    
    // Show status
    const statusDiv = document.getElementById('generationStatus');
    const statusMessage = document.getElementById('statusMessage');
    const progressFill = document.getElementById('progressFill');
    const generateBtn = document.getElementById('generateBtn');
    
    statusDiv.style.display = 'block';
    generateBtn.disabled = true;
    generateBtn.classList.add('generating');
    
    // Update progress
    updateProgress(10, 'Preparing configuration...');
    
    try {
        const token = localStorage.getItem('authToken');
        
        // Send request
        const response = await fetch('/api/generate-client', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`
            },
            body: formData
        });
        
        updateProgress(50, 'Processing...');
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.error || 'Failed to generate client');
        }
        
        const result = await response.json();
        
        updateProgress(90, 'Finalizing...');
        
        if (result.success) {
            updateProgress(100, 'Client generated successfully!');
            statusMessage.classList.add('success');
            statusMessage.innerHTML = `
                <i class="fas fa-check-circle"></i> Client generated successfully!
                <br>
                <button onclick="downloadGeneratedClient('${result.filename}')" class="download-link">
                    <i class="fas fa-download"></i> Download Client
                </button>
            `;
        } else {
            throw new Error(result.error || 'Unknown error');
        }
        
    } catch (error) {
        console.error('Generation error:', error);
        updateProgress(0, '');
        statusMessage.classList.add('error');
        statusMessage.innerHTML = `<i class="fas fa-exclamation-circle"></i> Error: ${error.message}`;
    } finally {
        generateBtn.disabled = false;
        generateBtn.classList.remove('generating');
    }
}

function updateProgress(percent, message) {
    const progressFill = document.getElementById('progressFill');
    const statusMessage = document.getElementById('statusMessage');
    
    progressFill.style.width = percent + '%';
    progressFill.textContent = percent + '%';
    statusMessage.textContent = message;
    statusMessage.className = 'status-message';
}

function showError(message) {
    alert('Error: ' + message);
}

async function downloadGeneratedClient(filename) {
    try {
        showInfo('Downloading client...');
        
        const token = localStorage.getItem('authToken');
        
        const response = await fetch(`/api/download-client/${filename}`, {
            method: 'GET',
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
        
        if (!response.ok) {
            throw new Error('Failed to download client');
        }
        
        // Get the blob
        const blob = await response.blob();
        
        // Create download link
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.style.display = 'none';
        a.href = url;
        a.download = filename;
        
        document.body.appendChild(a);
        a.click();
        
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
        
        showSuccess('Client downloaded successfully!');
        
    } catch (error) {
        console.error('Download error:', error);
        showError('Failed to download client: ' + error.message);
    }
}

function logout() {
    if (!confirm('Are you sure you want to logout?')) {
        return;
    }
    
    const token = localStorage.getItem('authToken');
    
    // Call logout API
    fetch('/api/auth/logout', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${token}`
        }
    }).catch(error => {
        console.error('Logout error:', error);
    });
    
    // Clear local storage
    localStorage.removeItem('authToken');
    localStorage.removeItem('username');
    localStorage.removeItem('role');
    
    // Redirect to login
    window.location.href = '/login';
}

// Mobile menu setup
document.addEventListener('DOMContentLoaded', function() {
    const mobileToggle = document.getElementById('mobileMenuToggle');
    const sidebar = document.getElementById('sidebar');
    
    if (mobileToggle) {
        mobileToggle.addEventListener('click', function() {
            sidebar.classList.toggle('mobile-open');
            
            if (sidebar.classList.contains('mobile-open')) {
                createOverlay();
            } else {
                removeOverlay();
            }
        });
    }
});

function createOverlay() {
    const existing = document.querySelector('.sidebar-overlay');
    if (existing) return;
    
    const overlay = document.createElement('div');
    overlay.className = 'sidebar-overlay';
    overlay.addEventListener('click', closeMobileMenu);
    document.body.appendChild(overlay);
}

function removeOverlay() {
    const overlay = document.querySelector('.sidebar-overlay');
    if (overlay) {
        overlay.remove();
    }
}

function closeMobileMenu() {
    const sidebar = document.getElementById('sidebar');
    sidebar.classList.remove('mobile-open');
    removeOverlay();
}

// Auto-fill functions
async function detectPublicIP() {
    try {
        showInfo('Detecting public IP address...');
        
        // Try multiple services for reliability
        const services = [
            'https://api.ipify.org?format=json',
            'https://api.my-ip.io/ip.json',
            'https://ipapi.co/json/'
        ];
        
        for (const service of services) {
            try {
                const response = await fetch(service, { timeout: 5000 });
                const data = await response.json();
                
                // Different services return IP in different formats
                const ip = data.ip || data.IP || data.query;
                
                if (ip) {
                    detectedPublicIP = ip;
                    showSuccess(`Public IP detected: ${ip}`);
                    return ip;
                }
            } catch (err) {
                console.log(`Service ${service} failed:`, err);
                continue;
            }
        }
        
        showError('Could not detect public IP. Please enter manually.');
        return null;
        
    } catch (error) {
        console.error('Error detecting public IP:', error);
        showError('Failed to detect public IP');
        return null;
    }
}

async function loadPublicKey() {
    try {
        showInfo('Loading public key from server...');
        
        const token = localStorage.getItem('authToken');
        const response = await fetch('/api/public-key', {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
        
        if (!response.ok) {
            throw new Error('Failed to load public key');
        }
        
        const data = await response.json();
        
        if (data.success && data.key) {
            document.getElementById('serverKey').value = data.key;
            showSuccess('Public key loaded successfully');
        } else {
            throw new Error(data.error || 'No public key found');
        }
        
    } catch (error) {
        console.error('Error loading public key:', error);
        showError('Failed to load public key: ' + error.message);
    }
}

async function usePublicIP() {
    if (!detectedPublicIP) {
        detectedPublicIP = await detectPublicIP();
    }
    
    if (detectedPublicIP) {
        document.getElementById('serverHost').value = detectedPublicIP;
        showSuccess('Public IP applied to Host field');
    }
}

async function autoFillServerConfig() {
    try {
        showInfo('Auto-filling server configuration...');
        
        // Detect public IP
        const ip = await detectPublicIP();
        
        if (!ip) {
            showError('Could not detect public IP');
            return;
        }
        
        // Load public key
        const token = localStorage.getItem('authToken');
        const keyResponse = await fetch('/api/public-key', {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
        
        if (!keyResponse.ok) {
            throw new Error('Failed to load public key');
        }
        
        const keyData = await keyResponse.json();
        
        if (!keyData.success || !keyData.key) {
            throw new Error('No public key found');
        }
        
        // Fill in the fields
        document.getElementById('serverHost').value = ip;
        document.getElementById('serverKey').value = keyData.key;
        document.getElementById('serverApi').value = `https://${ip}`;
        
        showSuccess('Server configuration auto-filled successfully!');
        
    } catch (error) {
        console.error('Error auto-filling config:', error);
        showError('Failed to auto-fill configuration: ' + error.message);
    }
}

function showInfo(message) {
    // Simple info notification
    const statusDiv = document.getElementById('generationStatus');
    const statusMessage = document.getElementById('statusMessage');
    
    if (statusDiv && statusMessage) {
        statusDiv.style.display = 'block';
        statusMessage.textContent = message;
        statusMessage.className = 'status-message';
        
        setTimeout(() => {
            if (statusMessage.textContent === message) {
                statusDiv.style.display = 'none';
            }
        }, 3000);
    }
}

function showSuccess(message) {
    const statusDiv = document.getElementById('generationStatus');
    const statusMessage = document.getElementById('statusMessage');
    
    if (statusDiv && statusMessage) {
        statusDiv.style.display = 'block';
        statusMessage.textContent = message;
        statusMessage.className = 'status-message success';
        
        setTimeout(() => {
            if (statusMessage.textContent === message) {
                statusDiv.style.display = 'none';
            }
        }, 3000);
    }
}
