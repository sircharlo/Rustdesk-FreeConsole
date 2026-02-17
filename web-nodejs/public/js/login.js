/**
 * BetterDesk Console - Login Page
 */

(function() {
    'use strict';
    
    document.addEventListener('DOMContentLoaded', init);
    
    function init() {
        const form = document.getElementById('login-form');
        const passwordToggle = document.getElementById('password-toggle');
        const passwordInput = document.getElementById('password');
        const loginBtn = document.getElementById('login-btn');
        const errorContainer = document.getElementById('login-error');
        const errorMessage = document.getElementById('error-message');
        
        if (!form) return;
        
        // Password visibility toggle
        passwordToggle?.addEventListener('click', () => {
            const isPassword = passwordInput.type === 'password';
            passwordInput.type = isPassword ? 'text' : 'password';
            passwordToggle.querySelector('.material-icons').textContent = 
                isPassword ? 'visibility_off' : 'visibility';
        });
        
        // Form submission
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            // Hide previous error
            errorContainer.classList.add('hidden');
            
            // Get form data
            const username = document.getElementById('username').value.trim();
            const password = document.getElementById('password').value;
            const remember = document.getElementById('remember').checked;
            
            if (!username || !password) {
                showError(_('auth.fill_all_fields'));
                return;
            }
            
            // Set loading state
            loginBtn.classList.add('loading');
            loginBtn.disabled = true;
            
            try {
                const response = await fetch('/api/auth/login', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    credentials: 'same-origin',
                    body: JSON.stringify({ username, password, remember })
                });
                
                const data = await response.json();
                
                if (!response.ok) {
                    throw new Error(data.error || data.message || _('auth.login_failed'));
                }
                
                // Success - redirect to dashboard
                window.location.href = data.redirect || '/';
                
            } catch (error) {
                showError(error.message);
            } finally {
                loginBtn.classList.remove('loading');
                loginBtn.disabled = false;
            }
        });
        
        function showError(message) {
            errorMessage.textContent = message;
            errorContainer.classList.remove('hidden');
            
            // Shake animation
            errorContainer.style.animation = 'shake 0.5s ease';
            setTimeout(() => {
                errorContainer.style.animation = '';
            }, 500);
        }
    }
    
    // Add shake animation
    const style = document.createElement('style');
    style.textContent = `
        @keyframes shake {
            0%, 100% { transform: translateX(0); }
            10%, 30%, 50%, 70%, 90% { transform: translateX(-5px); }
            20%, 40%, 60%, 80% { transform: translateX(5px); }
        }
    `;
    document.head.appendChild(style);
    
})();
