/**
 * BetterDesk i18n JavaScript Module
 * Client-side internationalization support
 * 
 * Usage:
 *   - Add data-i18n="key.path" attribute to elements
 *   - Add data-i18n-placeholder="key.path" for input placeholders
 *   - Add data-i18n-title="key.path" for title attributes
 *   - Call i18n.init() after DOM is ready
 *   - Call i18n.setLanguage('en') to change language
 */

const i18n = (function() {
    'use strict';

    let translations = {};
    let currentLang = 'en';
    let availableLanguages = [];
    let onLanguageChange = null;

    /**
     * Get nested value from object using dot notation
     * @param {Object} obj - The translations object
     * @param {string} path - Dot-separated path (e.g., 'sidebar.dashboard')
     * @returns {string|undefined} The translated string or undefined
     */
    function getNestedValue(obj, path) {
        if (!path) return undefined;
        const keys = path.split('.');
        let value = obj;
        for (const key of keys) {
            if (value && typeof value === 'object' && key in value) {
                value = value[key];
            } else {
                return undefined;
            }
        }
        return typeof value === 'string' ? value : undefined;
    }

    /**
     * Translate a key
     * @param {string} key - Translation key in dot notation
     * @param {Object} params - Optional parameters for interpolation
     * @returns {string} Translated text or key if not found
     */
    function t(key, params = {}) {
        let text = getNestedValue(translations, key);
        if (text === undefined) {
            console.warn(`[i18n] Missing translation: ${key}`);
            return key;
        }
        
        // Simple interpolation: replace {name} with params.name
        Object.keys(params).forEach(param => {
            text = text.replace(new RegExp(`{${param}}`, 'g'), params[param]);
        });
        
        return text;
    }

    /**
     * Load translations for a language
     * @param {string} lang - Language code (e.g., 'en', 'pl')
     * @returns {Promise<boolean>} Success status
     */
    async function loadLanguage(lang) {
        try {
            const response = await fetch(`/api/i18n/translations/${lang}`);
            if (!response.ok) {
                throw new Error(`Failed to load ${lang}: ${response.status}`);
            }
            const data = await response.json();
            if (data.success && data.translations) {
                translations = data.translations;
                currentLang = data.language || lang;
                return true;
            }
            return false;
        } catch (error) {
            console.error('[i18n] Error loading translations:', error);
            return false;
        }
    }

    /**
     * Load available languages list
     * @returns {Promise<Array>} List of available languages
     */
    async function loadAvailableLanguages() {
        try {
            const response = await fetch('/api/i18n/languages');
            if (!response.ok) return [];
            const data = await response.json();
            availableLanguages = data.languages || [];
            return availableLanguages;
        } catch (error) {
            console.error('[i18n] Error loading languages:', error);
            return [];
        }
    }

    /**
     * Apply translations to all elements with data-i18n attributes
     */
    function translatePage() {
        // Translate text content
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.getAttribute('data-i18n');
            const translated = t(key);
            if (translated !== key) {
                el.textContent = translated;
            }
        });

        // Translate placeholders
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            const key = el.getAttribute('data-i18n-placeholder');
            const translated = t(key);
            if (translated !== key) {
                el.placeholder = translated;
            }
        });

        // Translate title attributes
        document.querySelectorAll('[data-i18n-title]').forEach(el => {
            const key = el.getAttribute('data-i18n-title');
            const translated = t(key);
            if (translated !== key) {
                el.title = translated;
            }
        });

        // Translate aria-labels
        document.querySelectorAll('[data-i18n-aria]').forEach(el => {
            const key = el.getAttribute('data-i18n-aria');
            const translated = t(key);
            if (translated !== key) {
                el.setAttribute('aria-label', translated);
            }
        });

        // Update page title if specified
        const titleEl = document.querySelector('[data-i18n-page-title]');
        if (titleEl) {
            document.title = t(titleEl.getAttribute('data-i18n-page-title'));
        }
    }

    /**
     * Set the current language and update the page
     * @param {string} lang - Language code
     * @param {boolean} save - Whether to save preference to cookie
     * @returns {Promise<boolean>} Success status
     */
    async function setLanguage(lang, save = true) {
        const success = await loadLanguage(lang);
        if (success) {
            if (save) {
                // Set cookie for server-side language detection
                document.cookie = `lang=${lang};path=/;max-age=${365*24*60*60}`;
                
                // Notify server about language change
                try {
                    await fetch(`/api/i18n/set/${lang}`, { method: 'POST' });
                } catch (e) {
                    // Ignore - cookie is set anyway
                }
            }
            
            translatePage();
            
            // Update HTML lang attribute
            document.documentElement.lang = lang;
            
            // Call callback if registered
            if (typeof onLanguageChange === 'function') {
                onLanguageChange(lang);
            }
            
            return true;
        }
        return false;
    }

    /**
     * Get saved language from cookie or browser preference
     * @returns {string} Language code
     */
    function getPreferredLanguage() {
        // Check cookie first
        const match = document.cookie.match(/lang=(\w+)/);
        if (match) return match[1];
        
        // Check browser language
        const browserLang = navigator.language?.split('-')[0] || 'en';
        return browserLang;
    }

    /**
     * Initialize the i18n system
     * @param {Object} options - Configuration options
     * @returns {Promise<void>}
     */
    async function init(options = {}) {
        const defaultLang = options.defaultLang || 'en';
        onLanguageChange = options.onLanguageChange || null;
        
        // Load available languages
        await loadAvailableLanguages();
        
        // Determine initial language
        let lang = getPreferredLanguage();
        
        // Check if preferred language is available
        if (availableLanguages.length > 0 && !availableLanguages.includes(lang)) {
            lang = defaultLang;
        }
        
        // Load and apply translations
        await setLanguage(lang, false);
        
        console.log(`[i18n] Initialized with language: ${currentLang}`);
    }

    /**
     * Create a language selector dropdown
     * @param {string} containerId - ID of container element
     * @returns {HTMLElement|null} The created selector or null
     */
    function createLanguageSelector(containerId) {
        const container = document.getElementById(containerId);
        if (!container) return null;
        
        const selector = document.createElement('div');
        selector.className = 'language-selector';
        selector.innerHTML = `
            <button class="lang-btn" id="langToggle">
                <i class="fas fa-globe"></i>
                <span id="currentLangLabel">${currentLang.toUpperCase()}</span>
                <i class="fas fa-chevron-down"></i>
            </button>
            <div class="lang-dropdown" id="langDropdown">
                ${availableLanguages.map(lang => `
                    <div class="lang-option ${lang === currentLang ? 'active' : ''}" data-lang="${lang}">
                        <span class="lang-name">${getLanguageName(lang)}</span>
                        <span class="lang-code">${lang.toUpperCase()}</span>
                    </div>
                `).join('')}
            </div>
        `;
        
        container.appendChild(selector);
        
        // Toggle dropdown
        const toggle = selector.querySelector('#langToggle');
        const dropdown = selector.querySelector('#langDropdown');
        
        toggle.addEventListener('click', (e) => {
            e.stopPropagation();
            dropdown.classList.toggle('show');
        });
        
        // Language selection
        selector.querySelectorAll('.lang-option').forEach(option => {
            option.addEventListener('click', async () => {
                const lang = option.dataset.lang;
                if (lang !== currentLang) {
                    await setLanguage(lang);
                    
                    // Update selector UI
                    selector.querySelectorAll('.lang-option').forEach(o => {
                        o.classList.toggle('active', o.dataset.lang === lang);
                    });
                    document.getElementById('currentLangLabel').textContent = lang.toUpperCase();
                }
                dropdown.classList.remove('show');
            });
        });
        
        // Close dropdown when clicking outside
        document.addEventListener('click', () => {
            dropdown.classList.remove('show');
        });
        
        return selector;
    }

    /**
     * Get human-readable language name
     * @param {string} code - Language code
     * @returns {string} Language name
     */
    function getLanguageName(code) {
        const names = {
            'en': 'English',
            'pl': 'Polski',
            'de': 'Deutsch',
            'fr': 'Français',
            'es': 'Español',
            'it': 'Italiano',
            'ru': 'Русский',
            'zh': '中文',
            'ja': '日本語',
            'pt': 'Português',
            'nl': 'Nederlands',
            'tr': 'Türkçe',
            'uk': 'Українська'
        };
        return names[code] || code.toUpperCase();
    }

    // Public API
    return {
        init,
        t,
        setLanguage,
        translatePage,
        loadAvailableLanguages,
        createLanguageSelector,
        getLanguageName,
        get currentLang() { return currentLang; },
        get availableLanguages() { return availableLanguages; },
        get translations() { return translations; }
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = i18n;
}
