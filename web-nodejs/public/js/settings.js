/**
 * BetterDesk Console - Settings Page
 */

(function() {
    'use strict';
    
    document.addEventListener('DOMContentLoaded', init);
    
    function init() {
        initPasswordForm();
        initTotpSection();
        loadAuditLog();
        loadServerInfo();
        
        // Refresh handler
        window.addEventListener('app:refresh', loadAuditLog);
    }
    
    /**
     * Initialize password change form
     */
    function initPasswordForm() {
        const form = document.getElementById('password-form');
        const newPassword = document.getElementById('new-password');
        
        if (!form) return;
        
        // Real-time password validation
        newPassword?.addEventListener('input', () => {
            validatePassword(newPassword.value);
        });
        
        // Form submission
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const currentPassword = document.getElementById('current-password').value;
            const newPass = document.getElementById('new-password').value;
            const confirmPass = document.getElementById('confirm-password').value;
            
            // Validation
            if (!currentPassword || !newPass || !confirmPass) {
                Notifications.error(_('settings.fill_all_fields'));
                return;
            }
            
            if (newPass !== confirmPass) {
                Notifications.error(_('settings.passwords_not_match'));
                return;
            }
            
            if (!validatePassword(newPass)) {
                Notifications.error(_('settings.password_requirements_not_met'));
                return;
            }
            
            try {
                await Utils.api('/api/auth/password', {
                    method: 'POST',
                    body: {
                        current_password: currentPassword,
                        new_password: newPass
                    }
                });
                
                Notifications.success(_('settings.password_changed'));
                form.reset();
                
                // Reset validation indicators
                document.querySelectorAll('.password-requirements li').forEach(li => {
                    li.classList.remove('valid');
                });
                
            } catch (error) {
                Notifications.error(error.message || _('errors.password_change_failed'));
            }
        });
    }
    
    /**
     * Validate password and update UI indicators
     */
    function validatePassword(password) {
        const requirements = {
            'req-length': password.length >= 8,
            'req-uppercase': /[A-Z]/.test(password),
            'req-lowercase': /[a-z]/.test(password),
            'req-number': /[0-9]/.test(password)
        };
        
        let allMet = true;
        
        for (const [id, met] of Object.entries(requirements)) {
            const el = document.getElementById(id);
            if (el) {
                el.classList.toggle('valid', met);
            }
            if (!met) allMet = false;
        }
        
        return allMet;
    }
    
    /**
     * Load audit log
     */
    async function loadAuditLog() {
        const tbody = document.getElementById('audit-log-body');
        if (!tbody) return;
        
        try {
            const logs = await Utils.api('/api/settings/audit');
            
            if (!logs || logs.length === 0) {
                tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted">${_('settings.no_audit_logs')}</td></tr>`;
                return;
            }
            
            tbody.innerHTML = logs.map(log => `
                <tr>
                    <td>${Utils.formatDate(log.created_at)}</td>
                    <td>${Utils.escapeHtml(log.username || '-')}</td>
                    <td><span class="audit-action ${log.action}">${Utils.escapeHtml(log.action)}</span></td>
                    <td>${Utils.escapeHtml(log.details || '-')}</td>
                </tr>
            `).join('');
            
        } catch (error) {
            tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger">${_('errors.load_audit_failed')}</td></tr>`;
        }
    }
    
    /**
     * Load server info
     */
    async function loadServerInfo() {
        try {
            const data = await Utils.api('/api/settings/info');
            
            document.getElementById('db-path').textContent = data.paths?.database || '-';
            document.getElementById('uptime').textContent = formatUptime(data.server?.uptime);
            
        } catch (error) {
            console.error('Failed to load server info:', error);
        }
    }
    
    /**
     * Format uptime in human-readable format
     */
    function formatUptime(seconds) {
        if (!seconds || seconds < 0) return '-';
        
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        
        const parts = [];
        if (days > 0) parts.push(`${days}d`);
        if (hours > 0) parts.push(`${hours}h`);
        if (minutes > 0 || parts.length === 0) parts.push(`${minutes}m`);
        
        return parts.join(' ');
    }
    
    // ==================== TOTP (2FA) Section ====================
    
    /**
     * Initialize TOTP section
     */
    async function initTotpSection() {
        const container = document.getElementById('totp-status-container');
        if (!container) return;
        
        try {
            const data = await Utils.api('/api/auth/totp/status');
            
            if (data.enabled) {
                renderTotpEnabled(container);
            } else {
                renderTotpDisabled(container);
            }
        } catch (error) {
            container.innerHTML = `<p class="text-danger">${_('errors.server_error')}</p>`;
        }
    }
    
    /**
     * Render TOTP enabled state
     */
    function renderTotpEnabled(container) {
        container.innerHTML = `
            <div class="totp-status totp-enabled">
                <div class="totp-status-badge">
                    <span class="material-icons">verified_user</span>
                    <span>${_('settings.totp_enabled')}</span>
                </div>
                <p class="totp-status-desc">${_('settings.totp_enabled_desc')}</p>
                <button class="btn btn-danger" id="totp-disable-btn">
                    <span class="material-icons">lock_open</span>
                    ${_('settings.totp_disable')}
                </button>
            </div>
        `;
        
        document.getElementById('totp-disable-btn')?.addEventListener('click', handleDisableTotp);
    }
    
    /**
     * Render TOTP disabled state
     */
    function renderTotpDisabled(container) {
        container.innerHTML = `
            <div class="totp-status totp-disabled">
                <div class="totp-status-badge disabled">
                    <span class="material-icons">shield</span>
                    <span>${_('settings.totp_disabled')}</span>
                </div>
                <p class="totp-status-desc">${_('settings.totp_disabled_desc')}</p>
                <button class="btn btn-primary" id="totp-setup-btn">
                    <span class="material-icons">qr_code_2</span>
                    ${_('settings.totp_setup')}
                </button>
            </div>
        `;
        
        document.getElementById('totp-setup-btn')?.addEventListener('click', handleSetupTotp);
    }
    
    /**
     * Handle TOTP setup flow
     */
    async function handleSetupTotp() {
        const container = document.getElementById('totp-status-container');
        
        try {
            const data = await Utils.api('/api/auth/totp/setup', { method: 'POST' });
            
            container.innerHTML = `
                <div class="totp-setup">
                    <div class="totp-setup-steps">
                        <div class="totp-step">
                            <span class="step-number">1</span>
                            <span>${_('settings.totp_step1')}</span>
                        </div>
                        <div class="totp-step">
                            <span class="step-number">2</span>
                            <span>${_('settings.totp_step2')}</span>
                        </div>
                        <div class="totp-step">
                            <span class="step-number">3</span>
                            <span>${_('settings.totp_step3')}</span>
                        </div>
                    </div>
                    
                    <div class="totp-qr-container">
                        <img src="${data.qrCode}" alt="QR Code" class="totp-qr-image">
                    </div>
                    
                    <div class="totp-manual-key">
                        <p class="totp-manual-label">${_('settings.totp_manual_key')}:</p>
                        <code class="totp-secret-code">${data.secret}</code>
                        <button class="btn btn-sm btn-ghost" onclick="navigator.clipboard.writeText('${data.secret}')">
                            <span class="material-icons" style="font-size: 16px;">content_copy</span>
                        </button>
                    </div>
                    
                    <div class="totp-verify-form">
                        <label class="form-label">${_('settings.totp_enter_code')}:</label>
                        <div class="totp-verify-input-group">
                            <input type="text" id="totp-setup-code" class="form-input totp-input" 
                                   placeholder="000000" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" autofocus>
                            <button class="btn btn-primary" id="totp-verify-btn">
                                <span class="material-icons">check</span>
                                ${_('settings.totp_verify_enable')}
                            </button>
                        </div>
                    </div>
                    
                    <button class="btn btn-ghost totp-cancel-btn" id="totp-cancel-btn">
                        ${_('actions.cancel')}
                    </button>
                </div>
            `;
            
            // Handle verify
            document.getElementById('totp-verify-btn')?.addEventListener('click', async () => {
                const code = document.getElementById('totp-setup-code').value.trim();
                if (!code || code.length !== 6) {
                    Notifications.error(_('auth.totp_enter_code'));
                    return;
                }
                
                try {
                    const result = await Utils.api('/api/auth/totp/enable', {
                        method: 'POST',
                        body: { code }
                    });
                    
                    // Show recovery codes
                    showRecoveryCodes(container, result.recoveryCodes);
                    
                } catch (err) {
                    Notifications.error(err.message || _('auth.totp_invalid_code'));
                }
            });
            
            // Auto-submit on 6 digits
            document.getElementById('totp-setup-code')?.addEventListener('input', (e) => {
                e.target.value = e.target.value.replace(/[^0-9]/g, '');
            });
            
            // Cancel
            document.getElementById('totp-cancel-btn')?.addEventListener('click', () => {
                initTotpSection();
            });
            
        } catch (error) {
            Notifications.error(error.message || _('errors.server_error'));
        }
    }
    
    /**
     * Show recovery codes after enabling TOTP
     */
    function showRecoveryCodes(container, codes) {
        container.innerHTML = `
            <div class="totp-recovery">
                <div class="totp-success-header">
                    <span class="material-icons totp-success-icon">verified_user</span>
                    <h3>${_('settings.totp_enabled_success')}</h3>
                </div>
                
                <div class="totp-recovery-warning">
                    <span class="material-icons">warning</span>
                    <p>${_('settings.totp_recovery_warning')}</p>
                </div>
                
                <div class="totp-recovery-codes">
                    ${codes.map(code => `<code class="recovery-code">${code}</code>`).join('')}
                </div>
                
                <div class="totp-recovery-actions">
                    <button class="btn btn-secondary" id="copy-recovery-btn">
                        <span class="material-icons">content_copy</span>
                        ${_('actions.copy')}
                    </button>
                </div>
                
                <button class="btn btn-primary totp-done-btn" id="totp-done-btn">
                    <span class="material-icons">check</span>
                    ${_('settings.totp_done')}
                </button>
            </div>
        `;
        
        document.getElementById('copy-recovery-btn')?.addEventListener('click', () => {
            navigator.clipboard.writeText(codes.join('\n'));
            Notifications.success(_('common.copied'));
        });
        
        document.getElementById('totp-done-btn')?.addEventListener('click', () => {
            initTotpSection();
        });
        
        Notifications.success(_('settings.totp_enabled_success'));
    }
    
    /**
     * Handle TOTP disable
     */
    async function handleDisableTotp() {
        const container = document.getElementById('totp-status-container');
        
        container.innerHTML = `
            <div class="totp-disable-confirm">
                <div class="totp-disable-warning">
                    <span class="material-icons">warning</span>
                    <p>${_('settings.totp_disable_warning')}</p>
                </div>
                <div class="form-group">
                    <label class="form-label">${_('settings.current_password')}:</label>
                    <input type="password" id="totp-disable-password" class="form-input" 
                           placeholder="${_('auth.password_placeholder')}" required>
                </div>
                <div class="totp-disable-actions">
                    <button class="btn btn-danger" id="confirm-disable-btn">
                        <span class="material-icons">lock_open</span>
                        ${_('settings.totp_disable')}
                    </button>
                    <button class="btn btn-ghost" id="cancel-disable-btn">
                        ${_('actions.cancel')}
                    </button>
                </div>
            </div>
        `;
        
        document.getElementById('confirm-disable-btn')?.addEventListener('click', async () => {
            const password = document.getElementById('totp-disable-password').value;
            if (!password) {
                Notifications.error(_('auth.fill_all_fields'));
                return;
            }
            
            try {
                await Utils.api('/api/auth/totp/disable', {
                    method: 'POST',
                    body: { password }
                });
                
                Notifications.success(_('settings.totp_disabled_success'));
                initTotpSection();
                
            } catch (err) {
                Notifications.error(err.message || _('errors.server_error'));
            }
        });
        
        document.getElementById('cancel-disable-btn')?.addEventListener('click', () => {
            initTotpSection();
        });
    }
    
})();
