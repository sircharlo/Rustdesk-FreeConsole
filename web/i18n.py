"""
BetterDesk Console - Internationalization (i18n) System
========================================================

A JSON-based translation system that allows the community to easily add new languages.

Usage:
------
1. Create a new JSON file in web/lang/ directory (e.g., 'de.json' for German)
2. Copy the structure from 'en.json' and translate all values
3. Add the language to SUPPORTED_LANGUAGES dict below
4. The language will automatically appear in the language selector

In templates:
    {{ _('dashboard.title') }}
    {{ _('devices.online_count', count=5) }}

In Python:
    from i18n import get_translator
    _ = get_translator('pl')
    print(_('dashboard.title'))
"""

import json
import os
from functools import lru_cache
from typing import Dict, Any, Optional

# Directory containing language files
LANG_DIR = os.path.join(os.path.dirname(__file__), 'lang')

# Default language
DEFAULT_LANGUAGE = 'en'

# Supported languages with their display names and flags
# Add new languages here after creating the JSON file
SUPPORTED_LANGUAGES = {
    'en': {'name': 'English', 'native': 'English', 'flag': '🇬🇧', 'rtl': False},
    'pl': {'name': 'Polish', 'native': 'Polski', 'flag': '🇵🇱', 'rtl': False},
    # Community contributions - add new languages below:
    # 'de': {'name': 'German', 'native': 'Deutsch', 'flag': '🇩🇪', 'rtl': False},
    # 'fr': {'name': 'French', 'native': 'Français', 'flag': '🇫🇷', 'rtl': False},
    # 'es': {'name': 'Spanish', 'native': 'Español', 'flag': '🇪🇸', 'rtl': False},
    # 'it': {'name': 'Italian', 'native': 'Italiano', 'flag': '🇮🇹', 'rtl': False},
    # 'pt': {'name': 'Portuguese', 'native': 'Português', 'flag': '🇵🇹', 'rtl': False},
    # 'ru': {'name': 'Russian', 'native': 'Русский', 'flag': '🇷🇺', 'rtl': False},
    # 'zh': {'name': 'Chinese', 'native': '中文', 'flag': '🇨🇳', 'rtl': False},
    # 'ja': {'name': 'Japanese', 'native': '日本語', 'flag': '🇯🇵', 'rtl': False},
    # 'ko': {'name': 'Korean', 'native': '한국어', 'flag': '🇰🇷', 'rtl': False},
    # 'ar': {'name': 'Arabic', 'native': 'العربية', 'flag': '🇸🇦', 'rtl': True},
    # 'he': {'name': 'Hebrew', 'native': 'עברית', 'flag': '🇮🇱', 'rtl': True},
    # 'tr': {'name': 'Turkish', 'native': 'Türkçe', 'flag': '🇹🇷', 'rtl': False},
    # 'nl': {'name': 'Dutch', 'native': 'Nederlands', 'flag': '🇳🇱', 'rtl': False},
    # 'uk': {'name': 'Ukrainian', 'native': 'Українська', 'flag': '🇺🇦', 'rtl': False},
    # 'cs': {'name': 'Czech', 'native': 'Čeština', 'flag': '🇨🇿', 'rtl': False},
    # 'sv': {'name': 'Swedish', 'native': 'Svenska', 'flag': '🇸🇪', 'rtl': False},
}


class TranslationManager:
    """Manages loading and accessing translations."""
    
    def __init__(self):
        self._translations: Dict[str, Dict[str, Any]] = {}
        self._load_all_languages()
    
    def _load_all_languages(self):
        """Load all available language files."""
        if not os.path.exists(LANG_DIR):
            os.makedirs(LANG_DIR, exist_ok=True)
            return
        
        for lang_code in SUPPORTED_LANGUAGES.keys():
            self._load_language(lang_code)
    
    def _load_language(self, lang_code: str) -> bool:
        """Load a specific language file."""
        file_path = os.path.join(LANG_DIR, f'{lang_code}.json')
        
        if not os.path.exists(file_path):
            print(f"Warning: Language file not found: {file_path}")
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                self._translations[lang_code] = json.load(f)
            return True
        except json.JSONDecodeError as e:
            print(f"Error parsing language file {file_path}: {e}")
            return False
        except Exception as e:
            print(f"Error loading language file {file_path}: {e}")
            return False
    
    def reload_language(self, lang_code: str) -> bool:
        """Reload a specific language file (useful for development)."""
        return self._load_language(lang_code)
    
    def reload_all(self):
        """Reload all language files."""
        self._translations = {}
        self._load_all_languages()
    
    def get_translation(self, lang_code: str, key: str, **kwargs) -> str:
        """
        Get a translation for the given key.
        
        Args:
            lang_code: Language code (e.g., 'en', 'pl')
            key: Dot-separated key (e.g., 'dashboard.title', 'devices.online_count')
            **kwargs: Variables for string interpolation
            
        Returns:
            Translated string or the key itself if not found
        """
        # Fallback chain: requested language -> default language -> key
        translations = self._translations.get(lang_code)
        
        if not translations:
            translations = self._translations.get(DEFAULT_LANGUAGE, {})
        
        # Navigate nested keys
        value = translations
        for part in key.split('.'):
            if isinstance(value, dict):
                value = value.get(part)
            else:
                value = None
                break
        
        # Fallback to default language if key not found
        if value is None and lang_code != DEFAULT_LANGUAGE:
            default_translations = self._translations.get(DEFAULT_LANGUAGE, {})
            value = default_translations
            for part in key.split('.'):
                if isinstance(value, dict):
                    value = value.get(part)
                else:
                    value = None
                    break
        
        # Return key if no translation found
        if value is None:
            return key
        
        # String interpolation for variables
        if kwargs and isinstance(value, str):
            try:
                value = value.format(**kwargs)
            except KeyError:
                pass
        
        return value
    
    def get_available_languages(self) -> Dict[str, Dict[str, Any]]:
        """Get list of available languages with their metadata."""
        available = {}
        for lang_code, meta in SUPPORTED_LANGUAGES.items():
            file_path = os.path.join(LANG_DIR, f'{lang_code}.json')
            if os.path.exists(file_path) or lang_code == DEFAULT_LANGUAGE:
                available[lang_code] = meta
        return available
    
    def get_all_keys(self, lang_code: str = None) -> list:
        """Get all translation keys (useful for validation)."""
        lang_code = lang_code or DEFAULT_LANGUAGE
        translations = self._translations.get(lang_code, {})
        
        def extract_keys(d, prefix=''):
            keys = []
            for k, v in d.items():
                full_key = f"{prefix}.{k}" if prefix else k
                if isinstance(v, dict):
                    keys.extend(extract_keys(v, full_key))
                else:
                    keys.append(full_key)
            return keys
        
        return extract_keys(translations)
    
    def validate_language(self, lang_code: str) -> Dict[str, list]:
        """
        Validate a language file against the default language.
        
        Returns:
            Dict with 'missing' and 'extra' keys
        """
        default_keys = set(self.get_all_keys(DEFAULT_LANGUAGE))
        lang_keys = set(self.get_all_keys(lang_code))
        
        return {
            'missing': sorted(default_keys - lang_keys),
            'extra': sorted(lang_keys - default_keys)
        }


# Global translation manager instance
_manager = TranslationManager()


def get_translator(lang_code: str = None):
    """
    Get a translator function for the given language.
    
    Usage:
        _ = get_translator('pl')
        text = _('dashboard.title')
    """
    lang = lang_code or DEFAULT_LANGUAGE
    
    def translate(key: str, **kwargs) -> str:
        return _manager.get_translation(lang, key, **kwargs)
    
    return translate


def translate(lang_code: str, key: str, **kwargs) -> str:
    """Direct translation function."""
    return _manager.get_translation(lang_code, key, **kwargs)


def get_available_languages() -> Dict[str, Dict[str, Any]]:
    """Get all available languages."""
    return _manager.get_available_languages()


def reload_translations():
    """Reload all translation files."""
    _manager.reload_all()


def validate_language(lang_code: str) -> Dict[str, list]:
    """Validate a language file against the default."""
    return _manager.validate_language(lang_code)


# Flask integration helpers
def init_app(app, csrf=None):
    """
    Initialize i18n for a Flask application.
    
    Usage in app.py:
        from i18n import init_app
        init_app(app)
        # Or with CSRF protection:
        init_app(app, csrf)
    """
    from flask import request, session, g
    
    @app.before_request
    def set_language():
        """Set the current language for the request."""
        # Priority: URL param > Cookie > Accept-Language header > Default
        lang = request.args.get('lang')
        
        if not lang:
            lang = request.cookies.get('betterdesk_lang')
        
        if not lang:
            # Parse Accept-Language header
            accept_lang = request.headers.get('Accept-Language', '')
            for part in accept_lang.split(','):
                lang_part = part.split(';')[0].strip().split('-')[0]
                if lang_part in SUPPORTED_LANGUAGES:
                    lang = lang_part
                    break
        
        if not lang or lang not in SUPPORTED_LANGUAGES:
            lang = DEFAULT_LANGUAGE
        
        g.lang = lang
        g.is_rtl = SUPPORTED_LANGUAGES.get(lang, {}).get('rtl', False)
    
    @app.context_processor
    def inject_i18n():
        """Inject translation function and language info into templates."""
        lang = getattr(g, 'lang', DEFAULT_LANGUAGE)
        
        def _(key: str, **kwargs) -> str:
            return _manager.get_translation(lang, key, **kwargs)
        
        return {
            '_': _,
            'current_lang': lang,
            'available_languages': get_available_languages(),
            'is_rtl': getattr(g, 'is_rtl', False),
        }
    
    @app.route('/api/i18n/languages')
    def api_languages():
        """API endpoint to get available languages."""
        from flask import jsonify
        return jsonify({
            'success': True,
            'languages': get_available_languages(),
            'current': getattr(g, 'lang', DEFAULT_LANGUAGE)
        })
    
    @app.route('/api/i18n/translations/<lang_code>')
    def api_translations(lang_code):
        """API endpoint to get all translations for a language (for JS)."""
        from flask import jsonify
        
        if lang_code not in SUPPORTED_LANGUAGES:
            return jsonify({'success': False, 'error': 'Language not supported'}), 404
        
        translations = _manager._translations.get(lang_code, {})
        return jsonify({
            'success': True,
            'lang': lang_code,
            'translations': translations
        })
    
    @app.route('/api/i18n/set/<lang_code>', methods=['POST'])
    def api_set_language(lang_code):
        """API endpoint to set user's preferred language."""
        from flask import jsonify, make_response
        
        if lang_code not in SUPPORTED_LANGUAGES:
            return jsonify({'success': False, 'error': 'Language not supported'}), 400
        
        response = make_response(jsonify({
            'success': True,
            'lang': lang_code,
            'message': f'Language set to {SUPPORTED_LANGUAGES[lang_code]["name"]}'
        }))
        
        # Set cookie for 1 year
        response.set_cookie(
            'betterdesk_lang',
            lang_code,
            max_age=365*24*60*60,
            httponly=True,
            samesite='Lax'
        )
        
        return response

    @app.route('/api/i18n/upload', methods=['POST'])
    def api_upload_language():
        """
        API endpoint to upload a custom language pack.
        
        Expects multipart/form-data with:
        - file: JSON file with translations
        
        Or JSON body with:
        - lang_code: Language code (e.g., 'de')
        - translations: Translation dictionary
        - meta: Optional metadata (name, native, flag, rtl)
        """
        from flask import jsonify, request
        import json
        
        try:
            # Handle file upload
            if request.files and 'file' in request.files:
                file = request.files['file']
                if file.filename == '':
                    return jsonify({'success': False, 'error': 'No file selected'}), 400
                
                if not file.filename.endswith('.json'):
                    return jsonify({'success': False, 'error': 'File must be a JSON file'}), 400
                
                # Read and parse JSON
                try:
                    content = file.read().decode('utf-8')
                    translations = json.loads(content)
                except json.JSONDecodeError as e:
                    return jsonify({'success': False, 'error': f'Invalid JSON: {str(e)}'}), 400
                except UnicodeDecodeError:
                    return jsonify({'success': False, 'error': 'File must be UTF-8 encoded'}), 400
                
                # Extract language code from filename or meta
                lang_code = file.filename.replace('.json', '').lower()
                if '_meta' in translations and 'code' in translations['_meta']:
                    lang_code = translations['_meta']['code'].lower()
                
            # Handle JSON body
            elif request.content_type and 'json' in request.content_type:
                try:
                    data = request.get_json(force=True)
                except Exception as e:
                    return jsonify({'success': False, 'error': f'Invalid JSON body: {str(e)}'}), 400
                    
                lang_code = data.get('lang_code', '').lower()
                translations = data.get('translations', {})
                
                if not lang_code:
                    return jsonify({'success': False, 'error': 'lang_code is required'}), 400
                if not translations:
                    return jsonify({'success': False, 'error': 'translations is required'}), 400
            else:
                return jsonify({'success': False, 'error': 'Upload a JSON file or provide JSON body'}), 400
            
            # Validate language code
            if not lang_code or len(lang_code) < 2 or len(lang_code) > 5:
                return jsonify({'success': False, 'error': 'Invalid language code (2-5 characters required)'}), 400
            
            if not lang_code.isalpha():
                return jsonify({'success': False, 'error': 'Language code must contain only letters'}), 400
            
            # Ensure lang directory exists
            os.makedirs(LANG_DIR, exist_ok=True)
            
            # Save the language file
            file_path = os.path.join(LANG_DIR, f'{lang_code}.json')
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(translations, f, ensure_ascii=False, indent=2)
            
            # Extract metadata for SUPPORTED_LANGUAGES
            meta = translations.get('_meta', {})
            lang_name = meta.get('language', lang_code.upper())
            native_name = meta.get('native_name', lang_name)
            
            # Update SUPPORTED_LANGUAGES dynamically
            global SUPPORTED_LANGUAGES
            if lang_code not in SUPPORTED_LANGUAGES:
                SUPPORTED_LANGUAGES[lang_code] = {
                    'name': lang_name,
                    'native': native_name,
                    'flag': get_flag_for_language(lang_code),
                    'rtl': meta.get('rtl', False)
                }
            
            # Reload the language
            _manager.reload_language(lang_code)
            
            # Validate against default language
            validation = _manager.validate_language(lang_code)
            
            return jsonify({
                'success': True,
                'lang_code': lang_code,
                'message': f'Language pack "{lang_name}" uploaded successfully',
                'file_path': file_path,
                'validation': validation,
                'note': 'Refresh the page to see the new language'
            })
            
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)}), 500

    @app.route('/api/i18n/delete/<lang_code>', methods=['DELETE'])
    def api_delete_language(lang_code):
        """API endpoint to delete a custom language pack (cannot delete en/pl)."""
        from flask import jsonify
        
        # Protect core languages
        if lang_code in ['en', 'pl']:
            return jsonify({'success': False, 'error': 'Cannot delete core language packs'}), 403
        
        file_path = os.path.join(LANG_DIR, f'{lang_code}.json')
        
        if not os.path.exists(file_path):
            return jsonify({'success': False, 'error': 'Language pack not found'}), 404
        
        try:
            os.remove(file_path)
            
            # Remove from SUPPORTED_LANGUAGES
            global SUPPORTED_LANGUAGES
            if lang_code in SUPPORTED_LANGUAGES:
                del SUPPORTED_LANGUAGES[lang_code]
            
            # Reload translations
            _manager.reload_all()
            
            return jsonify({
                'success': True,
                'message': f'Language pack "{lang_code}" deleted'
            })
        except Exception as e:
            return jsonify({'success': False, 'error': str(e)}), 500

    # Exempt upload and delete endpoints from CSRF protection
    if csrf:
        csrf.exempt(api_upload_language)
        csrf.exempt(api_delete_language)


def get_flag_for_language(lang_code: str) -> str:
    """Get a flag emoji for common language codes."""
    flags = {
        'en': '🇬🇧', 'pl': '🇵🇱', 'de': '🇩🇪', 'fr': '🇫🇷', 'es': '🇪🇸',
        'it': '🇮🇹', 'pt': '🇵🇹', 'ru': '🇷🇺', 'zh': '🇨🇳', 'ja': '🇯🇵',
        'ko': '🇰🇷', 'ar': '🇸🇦', 'he': '🇮🇱', 'tr': '🇹🇷', 'nl': '🇳🇱',
        'uk': '🇺🇦', 'cs': '🇨🇿', 'sv': '🇸🇪', 'da': '🇩🇰', 'fi': '🇫🇮',
        'no': '🇳🇴', 'el': '🇬🇷', 'hu': '🇭🇺', 'ro': '🇷🇴', 'bg': '🇧🇬',
        'hr': '🇭🇷', 'sk': '🇸🇰', 'sl': '🇸🇮', 'et': '🇪🇪', 'lv': '🇱🇻',
        'lt': '🇱🇹', 'vi': '🇻🇳', 'th': '🇹🇭', 'id': '🇮🇩', 'ms': '🇲🇾'
    }
    return flags.get(lang_code, '🌐')
