/**
 * BetterDesk Console - Dashboard Page
 */

(function() {
    'use strict';
    
    document.addEventListener('DOMContentLoaded', init);
    
    let refreshInterval = null;
    
    function init() {
        loadStats();
        loadServerStatus();
        
        // Auto-refresh every 30 seconds
        refreshInterval = setInterval(() => {
            loadStats();
            loadServerStatus();
        }, 30000);
        
        // Manual refresh
        window.addEventListener('app:refresh', () => {
            loadStats();
            loadServerStatus();
        });
        
        // Refresh status button
        document.getElementById('refresh-status-btn')?.addEventListener('click', () => {
            loadServerStatus();
        });
        
        // Cleanup on page leave
        window.addEventListener('beforeunload', () => {
            if (refreshInterval) clearInterval(refreshInterval);
        });
    }
    
    /**
     * Load device statistics
     */
    async function loadStats() {
        console.log('loadStats called');
        try {
            const data = await Utils.api('/api/stats');
            console.log('Stats API response:', data);
            const stats = data.devices || data;
            console.log('Stats object:', stats);
            
            // Update stats with values
            setStatValue('stat-total', stats.total ?? 0);
            setStatValue('stat-online', stats.online ?? 0);
            setStatValue('stat-banned', stats.banned ?? 0);
            setStatValue('stat-connections', stats.offline ?? 0);
            
        } catch (error) {
            console.error('Failed to load stats:', error);
            // Show zeros on error
            setStatValue('stat-total', 0);
            setStatValue('stat-online', 0);
            setStatValue('stat-banned', 0);
            setStatValue('stat-connections', 0);
        }
    }
    
    /**
     * Set stat value directly (replacing skeleton)
     */
    function setStatValue(elementId, value) {
        const element = document.getElementById(elementId);
        if (!element) return;
        element.innerHTML = value;
    }
    
    /**
     * Update a stat element with animation
     */
    function updateStat(elementId, value) {
        const element = document.getElementById(elementId);
        if (!element) return;
        
        const currentValue = parseInt(element.textContent) || 0;
        
        if (currentValue === value) return;
        
        // Simple counter animation
        const duration = 500;
        const steps = 20;
        const stepValue = (value - currentValue) / steps;
        let step = 0;
        
        const interval = setInterval(() => {
            step++;
            if (step >= steps) {
                element.textContent = value;
                clearInterval(interval);
            } else {
                element.textContent = Math.round(currentValue + stepValue * step);
            }
        }, duration / steps);
    }
    
    /**
     * Load server status
     */
    async function loadServerStatus() {
        try {
            const status = await Utils.api('/api/server/status');
            
            updateServerStatus('hbbs-status', status.hbbs);
            updateServerStatus('hbbr-status', status.hbbr);
            
            if (status.api_port) {
                const apiPortEl = document.getElementById('api-port');
                if (apiPortEl) apiPortEl.textContent = status.api_port;
            }
            
        } catch (error) {
            console.error('Failed to load server status:', error);
            updateServerStatus('hbbs-status', { status: 'unknown' });
            updateServerStatus('hbbr-status', { status: 'unknown' });
        }
    }
    
    /**
     * Update server status indicator
     */
    function updateServerStatus(elementId, status) {
        const element = document.getElementById(elementId);
        if (!element) return;
        
        const statusDot = element.querySelector('.status-dot');
        const statusText = element.querySelector('.status-text');
        
        // Remove existing classes
        element.classList.remove('running', 'stopped', 'unknown');
        
        if (status?.status === 'running' || status?.online) {
            element.classList.add('running');
            statusText.textContent = _('status.running');
        } else if (status?.status === 'stopped' || status?.online === false) {
            element.classList.add('stopped');
            statusText.textContent = _('status.stopped');
        } else {
            element.classList.add('unknown');
            statusText.textContent = _('status.unknown');
        }
    }
    
})();
