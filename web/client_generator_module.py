"""
RustDesk Client Generator Module
Generates custom RustDesk clients with specified configurations
"""

import os
import json
import tempfile
import shutil
import subprocess
from datetime import datetime
import uuid
import requests
from pathlib import Path
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ClientGenerator:
    """Handles the generation of custom RustDesk clients"""
    
    # RustDesk GitHub releases URL
    GITHUB_RELEASES = "https://api.github.com/repos/rustdesk/rustdesk/releases"
    
    # Platform name normalization (UI names -> internal names)
    PLATFORM_ALIASES = {
        'windows-x64': 'windows-64',
        'windows-x86': 'windows-32',
        'linux-x64': 'linux',
        'macos-x64': 'macos',
    }
    
    # Platform mappings - real filenames from GitHub releases
    # Format: platform -> (primary pattern, fallback patterns)
    PLATFORM_FILES = {
        'windows-64': 'rustdesk-{version}-x86_64.exe',
        'windows-32': 'rustdesk-{version}-x86-sciter.exe',
        'linux': 'rustdesk-{version}-x86_64.AppImage',
        'linux-arm64': 'rustdesk-{version}-aarch64.AppImage',
        'android': 'rustdesk-{version}-universal-signed.apk',
        'macos': 'rustdesk-{version}-x86_64.dmg',
        'macos-arm64': 'rustdesk-{version}-aarch64.dmg',
    }
    
    # Alternative filename patterns for different versions
    PLATFORM_ALTERNATIVES = {
        'windows-64': ['rustdesk-{version}.exe', 'rustdesk-{version}-x86_64-windows.exe'],
        'windows-32': ['rustdesk-{version}-x86.exe'],
        'linux': ['rustdesk-{version}.AppImage', 'rustdesk-{version}-x86_64-linux.AppImage'],
        'linux-arm64': ['rustdesk-{version}-arm64.AppImage'],
        'android': ['rustdesk-{version}.apk', 'rustdesk-{version}-arm64-v8a.apk'],
        'macos': ['rustdesk-{version}.dmg', 'rustdesk-{version}-x86_64-macos.dmg'],
        'macos-arm64': ['rustdesk-{version}-arm64.dmg'],
    }
    
    def __init__(self, output_dir='/tmp/rustdesk_builds'):
        """Initialize the generator with output directory"""
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)
    
    def normalize_platform(self, platform):
        """Normalize platform name from UI to internal format"""
        return self.PLATFORM_ALIASES.get(platform, platform)
    
    def get_download_url(self, version, platform):
        """Get download URL for specific version and platform"""
        platform = self.normalize_platform(platform)
        try:
            logger.info(f"Fetching releases from GitHub for version {version}, platform {platform}")
            # Get releases from GitHub API
            response = requests.get(self.GITHUB_RELEASES, timeout=10)
            response.raise_for_status()
            releases = response.json()
            
            logger.info(f"Found {len(releases)} releases")
            
            # Normalize version (remove 'v' prefix if present)
            clean_version = version.lstrip('v')
            
            # Find the matching version
            for release in releases:
                tag = release.get('tag_name', '').lstrip('v')
                logger.debug(f"Checking release: {tag}")
                
                if tag == clean_version:
                    logger.info(f"Found matching release: {release.get('tag_name')}")
                    
                    # Get the filename pattern for this platform
                    filename_pattern = self.PLATFORM_FILES.get(platform, '')
                    if not filename_pattern:
                        logger.error(f"No filename pattern for platform: {platform}")
                        return None
                    
                    # Build expected filename with clean version
                    expected_filename = filename_pattern.format(version=clean_version)
                    logger.info(f"Looking for file: {expected_filename}")
                    
                    # List all available assets for debugging
                    available_assets = [asset.get('name', '') for asset in release.get('assets', [])]
                    logger.info(f"Available assets: {', '.join(available_assets[:5])}...")
                    
                    # Build list of patterns to try (primary + alternatives)
                    patterns_to_try = [expected_filename]
                    
                    # Add alternative patterns if available
                    alt_patterns = self.PLATFORM_ALTERNATIVES.get(platform, [])
                    for alt_pattern in alt_patterns:
                        patterns_to_try.append(alt_pattern.format(version=clean_version))
                    
                    logger.info(f"Patterns to try: {patterns_to_try}")
                    
                    # Search for matching asset
                    for asset in release.get('assets', []):
                        asset_name = asset.get('name', '')
                        
                        # Try each pattern
                        for pattern in patterns_to_try:
                            # Exact match first
                            if asset_name == pattern:
                                logger.info(f"Found exact match: {asset_name}")
                                download_url = asset.get('browser_download_url')
                                logger.info(f"Download URL: {download_url}")
                                return download_url
                    
                    # Fallback: partial match for any pattern
                    for asset in release.get('assets', []):
                        asset_name = asset.get('name', '')
                        
                        for pattern in patterns_to_try:
                            # Partial match as fallback
                            base_parts = pattern.replace(clean_version, '*').split('*')
                            if len(base_parts) >= 2:
                                starts_with = base_parts[0]
                                ends_with = base_parts[-1] if base_parts[-1] else ''
                                
                                if asset_name.startswith(starts_with) and asset_name.endswith(ends_with):
                                    logger.info(f"Found partial match: {asset_name}")
                                    download_url = asset.get('browser_download_url')
                                    logger.info(f"Download URL: {download_url}")
                                    return download_url
            
            logger.error(f"No matching asset found for version {version}, platform {platform}")
            return None
            
        except Exception as e:
            logger.error(f"Error getting download URL: {e}", exc_info=True)
            return None
    
    def download_client(self, version, platform):
        """Download the base RustDesk client"""
        download_url = self.get_download_url(version, platform)
        
        if not download_url:
            logger.error(f"Could not find download URL for version {version} platform {platform}")
            raise Exception(f"Could not find download URL for version {version} platform {platform}")
        
        logger.info(f"Downloading from: {download_url}")
        
        # Download the file
        temp_file = os.path.join(self.output_dir, f"rustdesk_base_{uuid.uuid4()}.tmp")
        
        try:
            response = requests.get(download_url, stream=True, timeout=60)
            response.raise_for_status()
            
            total_size = int(response.headers.get('content-length', 0))
            logger.info(f"Downloading {total_size} bytes to {temp_file}")
            
            downloaded = 0
            with open(temp_file, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
            
            logger.info(f"Download complete: {downloaded} bytes")
            return temp_file
            
        except Exception as e:
            logger.error(f"Failed to download client: {e}", exc_info=True)
            if os.path.exists(temp_file):
                os.remove(temp_file)
            raise Exception(f"Failed to download client: {e}")
    
    def create_config_file(self, config_data):
        """Create RustDesk configuration file - using SNAKE_CASE format required by RustDesk"""
        config = {}
        
        # Server configuration - RustDesk uses snake_case!
        if config_data.get('server_host'):
            config['relay_server'] = config_data['server_host']
            config['rendezvous_server'] = config_data['server_host']
        
        if config_data.get('server_key'):
            config['key'] = config_data['server_key']
        
        if config_data.get('server_api'):
            config['api_server'] = config_data['server_api']
        
        # Branding / Customization - snake_case
        if config_data.get('app_name'):
            config['app_name'] = config_data['app_name']
        
        if config_data.get('logo_base64'):
            # Extract just the base64 data (remove data:image/xxx;base64, prefix)
            logo_data = config_data['logo_base64']
            if ',' in logo_data:
                logo_data = logo_data.split(',', 1)[1]
            config['logo'] = logo_data
        elif config_data.get('logo_url'):
            # For URL, we'd need to download and encode - for now just note it
            config['logo_url'] = config_data['logo_url']
        
        if config_data.get('custom_text'):
            config['custom_text'] = config_data['custom_text']
        
        # Connection settings - snake_case
        if config_data.get('connection_type'):
            conn_type = config_data['connection_type']
            if conn_type == 'incoming':
                config['direct_server'] = 'N'
            elif conn_type == 'outgoing':
                config['enable_direct_server'] = 'Y'
        
        # Security settings - snake_case
        if config_data.get('permanent_password'):
            config['password'] = config_data['permanent_password']
        
        if config_data.get('password_approve_mode'):
            config['approve_mode'] = config_data['password_approve_mode']
        
        if config_data.get('deny_lan_discovery'):
            config['enable_lan_discovery'] = 'N'
        
        if config_data.get('enable_direct_ip'):
            config['direct_ip_access'] = 'Y'
        
        # Visual settings
        if config_data.get('theme'):
            config['theme'] = config_data['theme']
        
        # Permissions - snake_case
        permissions = {}
        if config_data.get('perm_keyboard') == False:
            permissions['keyboard'] = False
        if config_data.get('perm_clipboard') == False:
            permissions['clipboard'] = False
        if config_data.get('perm_file_transfer') == False:
            permissions['file_transfer'] = False
        if config_data.get('perm_audio') == False:
            permissions['audio'] = False
        
        if permissions:
            config['permissions'] = permissions
        
        # Default settings (merge with provided default_settings)
        if config_data.get('default_settings'):
            try:
                default_settings = json.loads(config_data['default_settings'])
                config.update(default_settings)
            except json.JSONDecodeError:
                pass
        
        # Override settings (merge with provided override_settings)
        if config_data.get('override_settings'):
            try:
                override_settings = json.loads(config_data['override_settings'])
                config['override'] = override_settings
            except json.JSONDecodeError:
                pass
        
        return config
    
    def modify_client(self, base_client_path, config_data, platform):
        """Modify the client with custom configuration"""
        
        # Create configuration
        config = self.create_config_file(config_data)
        
        # Create a temporary directory for modification
        work_dir = os.path.join(self.output_dir, f"work_{uuid.uuid4()}")
        os.makedirs(work_dir, exist_ok=True)
        
        try:
            # Copy base client
            client_name = config_data.get('config_name', 'custom-rustdesk')
            
            # Determine output filename based on platform
            if platform.startswith('windows'):
                output_filename = f"{client_name}.exe"
            elif platform.startswith('linux'):
                output_filename = f"{client_name}.AppImage"
            elif platform.startswith('android'):
                output_filename = f"{client_name}.apk"
            elif platform.startswith('macos'):
                output_filename = f"{client_name}.dmg"
            else:
                output_filename = f"{client_name}.bin"
            
            output_path = os.path.join(self.output_dir, output_filename)
            
            # For Windows executables, embed configuration using RustDesk's method
            if platform.startswith('windows'):
                shutil.copy2(base_client_path, output_path)
                
                # RustDesk custom client config embedding
                # The config is appended to the end of the exe with a special marker
                # Format: CONFIG_JSON + EXE_SUFFIX (which RustDesk looks for)
                
                config_json = json.dumps(config)
                config_bytes = config_json.encode('utf-8')
                
                # RustDesk looks for config embedded with specific markers
                # Method 1: Append config with marker "<<<RUSTDESK_CONFIG>>>"
                marker = b'<<<RUSTDESK_CONFIG>>>'
                
                with open(output_path, 'ab') as f:
                    f.write(marker)
                    f.write(config_bytes)
                    f.write(marker)
                
                logger.info(f"Embedded config into {output_path}")
                logger.info(f"Config: {config_json}")
                
                # Also create a companion rustdesk2.toml file for testing/backup
                config_file = os.path.join(work_dir, 'rustdesk2.toml')
                with open(config_file, 'w') as f:
                    # Write TOML format
                    for key, value in config.items():
                        if isinstance(value, dict):
                            f.write(f"\n[{key}]\n")
                            for k, v in value.items():
                                if isinstance(v, str):
                                    f.write(f'{k} = "{v}"\n')
                                else:
                                    f.write(f'{k} = {str(v).lower()}\n')
                        else:
                            if isinstance(value, str):
                                f.write(f'{key} = "{value}"\n')
                            else:
                                f.write(f'{key} = {str(value).lower()}\n')
                
                # Create a ZIP with both files
                import zipfile
                zip_path = output_path.replace('.exe', '.zip')
                with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
                    zf.write(output_path, os.path.basename(output_path))
                    zf.write(config_file, 'rustdesk2.toml')
                
                # Remove the exe and rename zip
                os.remove(output_path)
                output_path = zip_path
                output_filename = os.path.basename(zip_path)
                
            else:
                # For other platforms, just copy for now
                shutil.copy2(base_client_path, output_path)
            
            # Save metadata
            metadata = {
                'platform': platform,
                'version': config_data.get('version', '1.4.5'),
                'config_name': client_name,
                'created_at': datetime.now().isoformat(),
                'config': config
            }
            
            metadata_path = output_path + '.json'
            with open(metadata_path, 'w') as f:
                json.dump(metadata, f, indent=2)
            
            return output_path, metadata_path
            
        except Exception as e:
            raise Exception(f"Failed to modify client: {e}")
        finally:
            # Cleanup work directory
            if os.path.exists(work_dir):
                shutil.rmtree(work_dir, ignore_errors=True)
    
    def generate(self, config_data):
        """Main method to generate a custom client"""
        
        platform = config_data.get('platform', 'windows-64')
        platform = self.normalize_platform(platform)  # Normalize to internal format
        version = config_data.get('version', '1.4.5')
        
        try:
            # Download base client
            base_client = self.download_client(version, platform)
            
            # Modify client with configuration
            output_path, metadata_path = self.modify_client(base_client, config_data, platform)
            
            # Cleanup base client
            if os.path.exists(base_client):
                os.remove(base_client)
            
            return {
                'success': True,
                'client_path': output_path,
                'metadata_path': metadata_path,
                'filename': os.path.basename(output_path)
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }
    
    def cleanup_old_files(self, max_age_hours=24):
        """Clean up old generated files"""
        try:
            import time
            current_time = time.time()
            
            for filename in os.listdir(self.output_dir):
                filepath = os.path.join(self.output_dir, filename)
                
                if os.path.isfile(filepath):
                    file_age = current_time - os.path.getmtime(filepath)
                    if file_age > (max_age_hours * 3600):
                        os.remove(filepath)
                        
        except Exception as e:
            print(f"Error cleaning up old files: {e}")


def generate_custom_client(config_data):
    """Helper function to generate a custom client"""
    generator = ClientGenerator()
    
    # Cleanup old files first
    generator.cleanup_old_files()
    
    # Generate new client
    result = generator.generate(config_data)
    
    return result
