/* Sidebar JavaScript for BetterDesk Console v1.4.0 */

// Initialize sidebar
document.addEventListener('DOMContentLoaded', function() {
    initializeSidebar();
    loadUserInfo();
    setupMenuNavigation();
    setupMobileMenu();
});

function initializeSidebar() {
    // Sidebar is always expanded - no toggle needed
    console.log('Sidebar initialized (always expanded)');
}

function loadUserInfo() {
    const username = localStorage.getItem('username') || 'User';
    const role = localStorage.getItem('role') || 'viewer';
    
    // Update sidebar user info
    const usernameEl = document.getElementById('sidebarUsername');
    const userRoleEl = document.getElementById('sidebarUserRole');
    
    if (usernameEl) {
        usernameEl.textContent = username;
    }
    
    if (userRoleEl) {
        const roleNames = {
            'admin': 'Administrator',
            'operator': 'Operator',
            'viewer': 'Viewer'
        };
        userRoleEl.textContent = roleNames[role] || role;
    }
    
    // Show/hide menu items based on role
    updateMenuVisibility(role);
}

function updateMenuVisibility(role) {
    const menuUsers = document.getElementById('menuUsers');
    const menuAudit = document.getElementById('menuAudit');
    const menuSettings = document.getElementById('menuSettings');
    const menuKey = document.getElementById('menuKey');
    
    // Admin sees everything
    if (role === 'admin') {
        if (menuUsers) menuUsers.style.display = 'flex';
        if (menuAudit) menuAudit.style.display = 'flex';
        if (menuSettings) menuSettings.style.display = 'flex';
        if (menuKey) menuKey.style.display = 'flex';
    }
    // Operator sees audit and settings
    else if (role === 'operator') {
        if (menuUsers) menuUsers.style.display = 'none';
        if (menuAudit) menuAudit.style.display = 'flex';
        if (menuSettings) menuSettings.style.display = 'flex';
        if (menuKey) menuKey.style.display = 'none';
    }
    // Viewer sees only settings
    else {
        if (menuUsers) menuUsers.style.display = 'none';
        if (menuAudit) menuAudit.style.display = 'none';
        if (menuSettings) menuSettings.style.display = 'flex';
        if (menuKey) menuKey.style.display = 'none';
    }
}

function setupMenuNavigation() {
    const menuItems = document.querySelectorAll('.menu-item[data-page]');
    
    menuItems.forEach(item => {
        item.addEventListener('click', function(e) {
            e.preventDefault();
            
            const page = this.dataset.page;
            
            // Update active menu item
            menuItems.forEach(mi => mi.classList.remove('active'));
            this.classList.add('active');
            
            // Show corresponding page
            showPage(page);
            
            // Close mobile menu if open
            closeMobileMenu();
        });
    });
}

function showPage(pageName) {
    // Hide all pages
    const pages = document.querySelectorAll('.page-content');
    pages.forEach(page => page.classList.remove('active'));
    
    // Show selected page
    const targetPage = document.getElementById(pageName + 'Page');
    if (targetPage) {
        targetPage.classList.add('active');
    }
    
    // Update page title
    const pageTitles = {
        'dashboard': 'Device Management',
        'users': 'User Management',
        'audit': 'Audit Log',
        'settings': 'Settings',
        'key': 'Public Key',
        'about': 'About BetterDesk'
    };
    
    const pageTitle = document.getElementById('pageTitle');
    if (pageTitle && pageTitles[pageName]) {
        pageTitle.textContent = pageTitles[pageName];
    }
    
    // Load page-specific data
    if (pageName === 'dashboard') {
        if (typeof refreshDevices === 'function') {
            refreshDevices();
        }
    } else if (pageName === 'users') {
        if (typeof loadUsers === 'function') {
            loadUsers();
        }
    }
}

function setupMobileMenu() {
    const mobileToggle = document.getElementById('mobileMenuToggle');
    const sidebar = document.getElementById('sidebar');
    
    if (mobileToggle) {
        mobileToggle.addEventListener('click', function() {
            sidebar.classList.toggle('mobile-open');
            
            // Create/remove overlay
            if (sidebar.classList.contains('mobile-open')) {
                createOverlay();
            } else {
                removeOverlay();
            }
        });
    }
}

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

async function logout() {
    if (!confirm('Are you sure you want to logout?')) {
        return;
    }
    
    const token = localStorage.getItem('authToken');
    
    // Call logout API
    try {
        await fetch('/api/auth/logout', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
    } catch (error) {
        console.error('Logout error:', error);
    }
    
    // Clear local storage
    localStorage.removeItem('authToken');
    localStorage.removeItem('username');
    localStorage.removeItem('role');
    
    // Redirect to login
    window.location.href = '/login';
}

function showChangePasswordModal() {
    // TODO: Implement change password modal
    alert('Change password functionality coming soon!');
}

// Export functions for use in other scripts
window.sidebarFunctions = {
    showPage,
    logout,
    loadUserInfo,
    updateMenuVisibility
};
