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
    
    # Platform mappings - real filenames from GitHub releases
    PLATFORM_FILES = {
        'windows-64': 'rustdesk-{version}-x86_64.exe',  # e.g., rustdesk-1.3.0-x86_64.exe
        'windows-32': 'rustdesk-{version}-x86-sciter.exe',  # e.g., rustdesk-1.3.0-x86-sciter.exe
        'linux': 'rustdesk-{version}-x86_64.AppImage',  # e.g., rustdesk-1.3.0-x86_64.AppImage
        'android': 'rustdesk-{version}-universal-signed.apk',  # e.g., rustdesk-1.3.0-universal-signed.apk
        'macos': 'rustdesk-{version}-x86_64.dmg'  # e.g., rustdesk-1.3.0-x86_64.dmg or aarch64
    }
    
    def __init__(self, output_dir='/tmp/rustdesk_builds'):
        """Initialize the generator with output directory"""
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)
    
    def get_download_url(self, version, platform):
        """Get download URL for specific version and platform"""
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
                    
                    # Search for matching asset
                    for asset in release.get('assets', []):
                        asset_name = asset.get('name', '')
                        
                        # Exact match first
                        if asset_name == expected_filename:
                            logger.info(f"Found exact match: {asset_name}")
                            download_url = asset.get('browser_download_url')
                            logger.info(f"Download URL: {download_url}")
                            return download_url
                        
                        # Partial match as fallback
                        # Extract base pattern (without version) for matching
                        base_parts = expected_filename.replace(clean_version, '*').split('*')
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
        """Create RustDesk configuration file"""
        config = {}
        
        # Server configuration
        if config_data.get('server_host'):
            config['relay-server'] = config_data['server_host']
            config['rendezvous-server'] = config_data['server_host']
        
        if config_data.get('server_key'):
            config['key'] = config_data['server_key']
        
        if config_data.get('server_api'):
            config['api-server'] = config_data['server_api']
        
        # Connection settings
        if config_data.get('connection_type'):
            conn_type = config_data['connection_type']
            if conn_type == 'incoming':
                config['direct-server'] = False
            elif conn_type == 'outgoing':
                config['enable-direct-server'] = True
        
        # Security settings
        if config_data.get('permanent_password'):
            config['password'] = config_data['permanent_password']
        
        if config_data.get('password_approve_mode'):
            config['approve-mode'] = config_data['password_approve_mode']
        
        if config_data.get('deny_lan_discovery'):
            config['enable-lan-discovery'] = 'N'
        
        if config_data.get('enable_direct_ip'):
            config['direct-ip-access'] = 'Y'
        
        # Visual settings
        if config_data.get('theme'):
            config['theme'] = config_data['theme']
        
        # Permissions
        permissions = {}
        if config_data.get('perm_keyboard') == False:
            permissions['keyboard'] = False
        if config_data.get('perm_clipboard') == False:
            permissions['clipboard'] = False
        if config_data.get('perm_file_transfer') == False:
            permissions['file-transfer'] = False
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
            elif platform == 'linux':
                output_filename = f"{client_name}.AppImage"
            elif platform == 'android':
                output_filename = f"{client_name}.apk"
            elif platform == 'macos':
                output_filename = f"{client_name}.dmg"
            else:
                output_filename = f"{client_name}.bin"
            
            output_path = os.path.join(self.output_dir, output_filename)
            
            # For Windows executables, we can append configuration
            if platform.startswith('windows'):
                shutil.copy2(base_client_path, output_path)
                
                # Create config file to bundle
                config_file = os.path.join(work_dir, 'rustdesk.toml')
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
                
                # Note: For production, you would use a tool like ResourceHacker
                # or similar to embed the config into the executable
                # For now, we create a companion config file
                config_output = output_path.replace('.exe', '.toml')
                shutil.copy2(config_file, config_output)
                
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
