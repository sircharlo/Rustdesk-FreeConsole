"""
RustDesk Source Client Generator Module
Generates custom RustDesk clients by modifying source code and compiling

SUPPORTED PLATFORMS (Source Compilation from Linux server):
- Linux x64: Full support (native compilation)
- Linux ARM64: Cross-compilation with aarch64-linux-gnu

REQUIRES SPECIAL SETUP (not recommended for cross-compilation):
- Windows x64: Cross-compilation requires vcpkg with Windows-targeted dependencies
  (libvpx, libyuv, opus, aom, OpenSSL) - extremely complex setup
  RECOMMENDATION: Use 'Config Injection' method or build on native Windows

NOT SUPPORTED (use Config Injection instead):
- macOS: Requires macOS SDK and Apple hardware
- Android: Requires Android NDK and complex setup
- Windows x86 (32-bit): Limited demand

For Windows/macOS clients, use 'Config Injection' method which modifies
pre-built official RustDesk binaries instead of compiling from source.
"""

import os
import json
import shutil
import subprocess
import re
import base64
from datetime import datetime
import uuid
from pathlib import Path
import logging
import threading
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class BuildStatus:
    """Tracks build status and progress"""
    PENDING = "pending"
    PREPARING = "preparing"
    MODIFYING = "modifying"
    COMPILING = "compiling"
    PACKAGING = "packaging"
    COMPLETED = "completed"
    FAILED = "failed"


# Platform name aliases (UI names -> internal names)
PLATFORM_ALIASES = {
    'windows-64': 'windows-x64',
    'windows-32': 'windows-x86',
    'linux': 'linux-x64',
    'macos': 'macos-x64',
}

# Supported platforms for source compilation (from Linux server)
# Windows removed - cross-compilation requires vcpkg with Windows-targeted dependencies
# For Windows clients, use 'Config Injection' method instead
SUPPORTED_SOURCE_PLATFORMS = ['linux-x64', 'linux-arm64']

# Platforms that require special setup (warning will be shown but allowed)
EXPERIMENTAL_PLATFORMS = ['windows-x64']

# Platform to Rust target mapping
PLATFORM_TARGET_MAP = {
    'linux-x64': 'x86_64-unknown-linux-gnu',
    'linux': 'x86_64-unknown-linux-gnu',
    'linux-arm64': 'aarch64-unknown-linux-gnu',
    'windows-64': 'x86_64-pc-windows-gnu',
    'windows-x64': 'x86_64-pc-windows-gnu',
    # Not supported:
    'windows-32': 'i686-pc-windows-gnu',
    'windows-x86': 'i686-pc-windows-gnu',
}

# Binary file extensions by platform
BINARY_EXTENSIONS = {
    'linux-x64': '',
    'linux': '',
    'linux-arm64': '',
    'windows-64': '.exe',
    'windows-x64': '.exe',
    'windows-32': '.exe',
    'windows-x86': '.exe',
}

# Cross-compilation linkers configuration
CROSS_LINKERS = {
    'linux-arm64': 'aarch64-linux-gnu-gcc',
    'windows-x64': 'x86_64-w64-mingw32-gcc',
    'windows-64': 'x86_64-w64-mingw32-gcc',
}

# Environment variables for cross-compilation
CROSS_ENV = {
    'linux-arm64': {
        'CC': 'aarch64-linux-gnu-gcc',
        'CXX': 'aarch64-linux-gnu-g++',
        'AR': 'aarch64-linux-gnu-ar',
        'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER': 'aarch64-linux-gnu-gcc',
    },
    'windows-x64': {
        'CC': 'x86_64-w64-mingw32-gcc',
        'CXX': 'x86_64-w64-mingw32-g++',
        'AR': 'x86_64-w64-mingw32-ar',
        'CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER': 'x86_64-w64-mingw32-gcc',
    },
    'windows-64': {
        'CC': 'x86_64-w64-mingw32-gcc',
        'CXX': 'x86_64-w64-mingw32-g++',
        'AR': 'x86_64-w64-mingw32-ar',
        'CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER': 'x86_64-w64-mingw32-gcc',
    },
}


def normalize_platform(platform):
    """Normalize platform name from UI to internal format"""
    return PLATFORM_ALIASES.get(platform, platform)


def get_supported_platforms():
    """Return list of platforms supported for source compilation"""
    return SUPPORTED_SOURCE_PLATFORMS.copy()


def is_platform_supported(platform):
    """Check if platform is supported for source compilation (with alias support)"""
    normalized = normalize_platform(platform)
    return normalized in SUPPORTED_SOURCE_PLATFORMS


class SourceClientGenerator:
    """Handles the generation of custom RustDesk clients from source"""
    
    # Path to the cloned RustDesk source
    SOURCE_DIR = os.path.expanduser("~/rustdesk-build/rustdesk-source")
    
    # Build output directory
    BUILD_DIR = os.path.expanduser("~/rustdesk-build/builds")
    
    # RustDesk GitHub repository
    RUSTDESK_REPO = "https://github.com/rustdesk/rustdesk.git"
    
    # Default version to clone
    DEFAULT_VERSION = "1.4.5"
    
    # Key source files to modify
    CONFIG_RS = "libs/hbb_common/src/config.rs"
    CARGO_TOML = "Cargo.toml"
    LOGO_SVG = "res/logo.svg"
    LOGO_PNG = "res/logo.png"
    
    def __init__(self):
        """Initialize the generator"""
        os.makedirs(self.BUILD_DIR, exist_ok=True)
        
        # Build status tracking
        self._builds = {}
        self._lock = threading.Lock()
    
    def _get_build_work_dir(self, build_id):
        """Get working directory for a specific build"""
        return os.path.join(self.BUILD_DIR, f"build_{build_id}")
    
    def _update_status(self, build_id, status, message=None, progress=0):
        """Update build status"""
        with self._lock:
            if build_id not in self._builds:
                self._builds[build_id] = {}
            
            self._builds[build_id].update({
                'status': status,
                'message': message,
                'progress': progress,
                'updated_at': datetime.now().isoformat()
            })
    
    def get_build_status(self, build_id):
        """Get current status of a build"""
        with self._lock:
            return self._builds.get(build_id, {
                'status': BuildStatus.PENDING,
                'message': 'Build not found'
            })
    
    def _clone_source(self, version="1.4.5"):
        """Clone RustDesk source from GitHub"""
        logger.info(f"Cloning RustDesk source v{version} from {self.RUSTDESK_REPO}")
        
        # Create parent directory
        parent_dir = os.path.dirname(self.SOURCE_DIR)
        os.makedirs(parent_dir, exist_ok=True)
        
        # Clone with specific version/tag
        cmd = [
            "git", "clone",
            "--branch", version,
            "--depth", "1",
            self.RUSTDESK_REPO,
            self.SOURCE_DIR
        ]
        
        logger.info(f"Running: {' '.join(cmd)}")
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10 minutes timeout for clone
        )
        
        if result.returncode != 0:
            raise Exception(f"Failed to clone RustDesk source: {result.stderr}")
        
        logger.info("Clone completed, initializing submodules...")
        
        # Initialize submodules
        cmd_submodule = ["git", "submodule", "update", "--init", "--recursive"]
        
        result = subprocess.run(
            cmd_submodule,
            cwd=self.SOURCE_DIR,
            capture_output=True,
            text=True,
            timeout=600
        )
        
        if result.returncode != 0:
            logger.warning(f"Submodule initialization warning: {result.stderr}")
        
        logger.info("Source cloned and submodules initialized successfully")
        return True
    
    def _check_source_version(self, required_version):
        """Check if cloned source matches required version"""
        try:
            # Try to get current tag/branch
            result = subprocess.run(
                ["git", "describe", "--tags", "--exact-match"],
                cwd=self.SOURCE_DIR,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                current_version = result.stdout.strip().lstrip('v')
                return current_version == required_version.lstrip('v')
            
            # Fallback: check branch
            result = subprocess.run(
                ["git", "branch", "--show-current"],
                cwd=self.SOURCE_DIR,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                current_branch = result.stdout.strip()
                return current_branch == required_version or current_branch == f"v{required_version}"
            
            return False
        except Exception as e:
            logger.warning(f"Could not check source version: {e}")
            return True  # Assume it's okay if we can't check
    
    def ensure_source_exists(self, version="1.4.5"):
        """Ensure source code exists, clone if necessary"""
        
        # Check if source directory exists and has required files
        cargo_toml = os.path.join(self.SOURCE_DIR, "Cargo.toml")
        
        if os.path.exists(cargo_toml):
            logger.info(f"Source already exists at {self.SOURCE_DIR}")
            
            # Check if version matches (optional - could re-clone if different)
            if not self._check_source_version(version):
                logger.warning(f"Source version mismatch, but continuing with existing source")
            
            # Ensure submodules are initialized
            config_rs = os.path.join(self.SOURCE_DIR, self.CONFIG_RS)
            if not os.path.exists(config_rs):
                logger.info("Submodules not initialized, initializing now...")
                subprocess.run(
                    ["git", "submodule", "update", "--init", "--recursive"],
                    cwd=self.SOURCE_DIR,
                    capture_output=True,
                    timeout=600
                )
            
            return True
        
        # Source doesn't exist, need to clone
        logger.info(f"Source not found at {self.SOURCE_DIR}, cloning...")
        return self._clone_source(version)
    
    def prepare_source(self, build_id, version="1.4.5"):
        """Copy source to working directory, auto-download if needed"""
        self._update_status(build_id, BuildStatus.PREPARING, "Preparing source files...", 5)
        
        work_dir = self._get_build_work_dir(build_id)
        
        # Auto-download source if not exists
        if not os.path.exists(os.path.join(self.SOURCE_DIR, "Cargo.toml")):
            self._update_status(build_id, BuildStatus.PREPARING, "Downloading RustDesk source (first build only)...", 2)
            try:
                self.ensure_source_exists(version)
            except Exception as e:
                raise Exception(f"Failed to download RustDesk source: {e}")
        
        # Verify source exists now
        if not os.path.exists(self.SOURCE_DIR):
            raise Exception(f"RustDesk source not found at {self.SOURCE_DIR}")
        
        # Clean up previous work directory if exists
        if os.path.exists(work_dir):
            shutil.rmtree(work_dir)
        
        # Copy source to work directory
        logger.info(f"Copying source from {self.SOURCE_DIR} to {work_dir}")
        shutil.copytree(self.SOURCE_DIR, work_dir, symlinks=True)
        
        self._update_status(build_id, BuildStatus.PREPARING, "Source files copied", 10)
        
        return work_dir
    
    def modify_server_config(self, work_dir, server_host, server_key):
        """Modify server configuration in source"""
        config_path = os.path.join(work_dir, self.CONFIG_RS)
        
        if not os.path.exists(config_path):
            logger.warning(f"Config file not found: {config_path}")
            return False
        
        logger.info(f"Modifying server config in {config_path}")
        
        with open(config_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        modified = False
        
        # Modify RENDEZVOUS_SERVERS
        if server_host:
            # Pattern: pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];
            pattern = r'(pub\s+const\s+RENDEZVOUS_SERVERS:\s*&\[&str\]\s*=\s*&\[)[^\]]+(\];)'
            replacement = f'\\1"{server_host}"\\2'
            new_content, count = re.subn(pattern, replacement, content)
            if count > 0:
                content = new_content
                modified = True
                logger.info(f"Modified RENDEZVOUS_SERVERS to {server_host}")
        
        # Modify RS_PUB_KEY
        if server_key:
            # Pattern: pub const RS_PUB_KEY: &str = "...";
            pattern = r'(pub\s+const\s+RS_PUB_KEY:\s*&str\s*=\s*")[^"]*(")'
            replacement = f'\\1{server_key}\\2'
            new_content, count = re.subn(pattern, replacement, content)
            if count > 0:
                content = new_content
                modified = True
                logger.info(f"Modified RS_PUB_KEY")
        
        if modified:
            with open(config_path, 'w', encoding='utf-8') as f:
                f.write(content)
        
        return modified
    
    def modify_app_name(self, work_dir, app_name, app_description=None):
        """Modify application name in Cargo.toml"""
        cargo_path = os.path.join(work_dir, self.CARGO_TOML)
        
        if not os.path.exists(cargo_path):
            logger.warning(f"Cargo.toml not found: {cargo_path}")
            return False
        
        logger.info(f"Modifying app name in {cargo_path}")
        
        with open(cargo_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        modified = False
        
        # Modify package name
        if app_name:
            # Sanitize app name for package naming (lowercase, no spaces)
            safe_name = re.sub(r'[^a-zA-Z0-9_-]', '_', app_name.lower())
            
            # Modify package name (first occurrence)
            pattern = r'(name\s*=\s*")(rustdesk)(")'
            new_content, count = re.subn(pattern, f'\\g<1>{safe_name}\\3', content, count=1)
            if count > 0:
                content = new_content
                modified = True
                logger.info(f"Modified package name to {safe_name}")
            
            # Modify default-run to match the new name
            pattern_default_run = r'(default-run\s*=\s*")(rustdesk)(")'
            new_content, count = re.subn(pattern_default_run, f'\\g<1>{safe_name}\\3', content, count=1)
            if count > 0:
                content = new_content
                logger.info(f"Modified default-run to {safe_name}")
            
            # Also need to add a [[bin]] entry for our new app name
            # Check if rustdesk bin exists and add our custom one
            if f'[[bin]]\nname = "{safe_name}"' not in content:
                # Add custom binary entry after [lib] section
                bin_entry = f'\n[[bin]]\nname = "{safe_name}"\npath = "src/main.rs"\n'
                
                # Insert after [lib] section
                lib_match = re.search(r'(\[lib\].*?crate-type\s*=\s*\[[^\]]+\])', content, re.DOTALL)
                if lib_match:
                    insert_pos = lib_match.end()
                    content = content[:insert_pos] + bin_entry + content[insert_pos:]
                    logger.info(f"Added [[bin]] entry for {safe_name}")
        
        # Modify description
        if app_description:
            pattern = r'(description\s*=\s*")[^"]*(")'
            replacement = f'\\1{app_description}\\2'
            new_content, count = re.subn(pattern, replacement, content, count=1)
            if count > 0:
                content = new_content
                modified = True
                logger.info(f"Modified description to {app_description}")
        
        if modified:
            with open(cargo_path, 'w', encoding='utf-8') as f:
                f.write(content)
        
        return modified
    
    def modify_logo(self, work_dir, logo_base64=None, logo_svg_content=None):
        """Replace logo files with custom logo"""
        modified = False
        
        # Handle SVG logo
        if logo_svg_content:
            svg_path = os.path.join(work_dir, self.LOGO_SVG)
            if os.path.exists(svg_path):
                logger.info(f"Replacing SVG logo at {svg_path}")
                with open(svg_path, 'w', encoding='utf-8') as f:
                    f.write(logo_svg_content)
                modified = True
        
        # Handle base64 encoded image (convert to PNG)
        if logo_base64:
            png_path = os.path.join(work_dir, self.LOGO_PNG)
            
            # Remove data URI prefix if present
            if ',' in logo_base64:
                logo_base64 = logo_base64.split(',', 1)[1]
            
            try:
                logo_data = base64.b64decode(logo_base64)
                
                logger.info(f"Writing PNG logo to {png_path}")
                with open(png_path, 'wb') as f:
                    f.write(logo_data)
                modified = True
                
            except Exception as e:
                logger.error(f"Failed to decode/write logo: {e}")
        
        return modified
    
    def modify_icon(self, work_dir, icon_base64=None):
        """Replace Windows icon with custom icon"""
        if not icon_base64:
            return False
        
        icon_path = os.path.join(work_dir, "res", "icon.ico")
        
        # Remove data URI prefix if present
        if ',' in icon_base64:
            icon_base64 = icon_base64.split(',', 1)[1]
        
        try:
            icon_data = base64.b64decode(icon_base64)
            
            logger.info(f"Writing custom icon to {icon_path}")
            with open(icon_path, 'wb') as f:
                f.write(icon_data)
            return True
            
        except Exception as e:
            logger.error(f"Failed to decode/write icon: {e}")
            return False
    
    def run_compile(self, work_dir, target="x86_64-unknown-linux-gnu", release=True, platform=None):
        """Run cargo build compilation with cross-compilation support"""
        cargo_path = os.path.expanduser("~/.cargo/bin/cargo")
        
        if not os.path.exists(cargo_path):
            # Try system cargo
            cargo_path = shutil.which("cargo")
            if not cargo_path:
                raise Exception("Cargo not found. Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh")
        
        cmd = [cargo_path, "build"]
        
        if release:
            cmd.append("--release")
        
        # Add target if specified
        if target:
            cmd.extend(["--target", target])
        
        # For Windows, build without default features to avoid GUI dependencies
        if platform and 'windows' in platform:
            cmd.extend(["--no-default-features", "--features", "cli"])
        
        logger.info(f"Running compilation: {' '.join(cmd)}")
        
        # Set up environment
        env = os.environ.copy()
        env["PATH"] = os.path.expanduser("~/.cargo/bin") + ":" + env.get("PATH", "")
        
        # Add cross-compilation environment variables
        if platform and platform in CROSS_ENV:
            for key, value in CROSS_ENV[platform].items():
                env[key] = value
                logger.info(f"Setting {key}={value} for cross-compilation")
        
        # Write cargo config for cross-compilation linker
        if platform and platform in CROSS_LINKERS:
            cargo_config_dir = os.path.join(work_dir, ".cargo")
            os.makedirs(cargo_config_dir, exist_ok=True)
            cargo_config_path = os.path.join(cargo_config_dir, "config.toml")
            
            linker = CROSS_LINKERS[platform]
            target_name = PLATFORM_TARGET_MAP.get(platform, target)
            
            config_content = f"""
[target.{target_name}]
linker = "{linker}"
"""
            with open(cargo_config_path, 'w') as f:
                f.write(config_content)
            logger.info(f"Created cargo config for {target_name} with linker {linker}")
        
        process = subprocess.Popen(
            cmd,
            cwd=work_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
            universal_newlines=True
        )
        
        output_lines = []
        for line in process.stdout:
            output_lines.append(line)
            logger.info(f"[cargo] {line.rstrip()}")
        
        return_code = process.wait()
        
        if return_code != 0:
            raise Exception(f"Compilation failed (exit code: {return_code})\n{''.join(output_lines[-50:])}")
        
        return True
    
    def get_compiled_binary(self, work_dir, target="x86_64-unknown-linux-gnu", release=True, app_name="rustdesk"):
        """Get path to compiled binary"""
        profile = "release" if release else "debug"
        
        # Sanitize app name (same as in modify_app_name)
        safe_name = re.sub(r'[^a-zA-Z0-9_-]', '_', app_name.lower()) if app_name else "rustdesk"
        
        if target:
            binary_path = os.path.join(work_dir, "target", target, profile, safe_name)
        else:
            binary_path = os.path.join(work_dir, "target", profile, safe_name)
        
        # Add .exe extension for Windows targets
        if "windows" in (target or ""):
            binary_path += ".exe"
        
        if os.path.exists(binary_path):
            return binary_path
        
        # Fallback: look for rustdesk binary if custom name not found
        fallback_path = binary_path.replace(safe_name, "rustdesk")
        if os.path.exists(fallback_path):
            return fallback_path
        
        # List what we have in target directory
        target_dir = os.path.join(work_dir, "target", target or "", profile)
        if os.path.exists(target_dir):
            files = os.listdir(target_dir)
            logger.info(f"Files in {target_dir}: {files[:20]}")
            
            # Find any executable
            for f in files:
                fpath = os.path.join(target_dir, f)
                if os.path.isfile(fpath) and os.access(fpath, os.X_OK):
                    if not f.endswith('.d') and not f.endswith('.so') and 'lib' not in f:
                        return fpath
        
        raise Exception(f"Compiled binary not found: {binary_path}")
    
    def generate(self, config_data):
        """Main method to generate a custom client from source"""
        
        build_id = str(uuid.uuid4())[:8]
        
        try:
            # Extract configuration
            server_host = config_data.get('server_host', '')
            server_key = config_data.get('server_key', '')
            app_name = config_data.get('app_name', '')
            custom_text = config_data.get('custom_text', '')
            logo_base64 = config_data.get('logo_base64', '')
            icon_base64 = config_data.get('icon_base64', '')
            platform = config_data.get('platform', 'linux-x64')
            version = config_data.get('version', '1.4.5')
            
            # Normalize platform name using global function
            platform_normalized = normalize_platform(platform)
            
            logger.info(f"Build request: platform={platform}, normalized={platform_normalized}")
            
            # Check if platform is supported for source compilation
            if not is_platform_supported(platform_normalized):
                # Provide specific error messages for different platforms
                if 'windows' in platform_normalized.lower():
                    raise Exception(
                        f"Windows cross-compilation from Linux is not supported. "
                        f"Building RustDesk for Windows requires vcpkg with Windows-targeted "
                        f"dependencies (OpenSSL, libvpx, libyuv, opus, aom) which are complex to set up. "
                        f"RECOMMENDED: Use 'Config Injection' method instead, which modifies "
                        f"pre-built official RustDesk binaries without recompilation."
                    )
                elif 'macos' in platform_normalized.lower():
                    raise Exception(
                        f"macOS compilation requires Apple hardware and macOS SDK. "
                        f"RECOMMENDED: Use 'Config Injection' method instead."
                    )
                else:
                    supported_list = ', '.join(SUPPORTED_SOURCE_PLATFORMS)
                    raise Exception(
                        f"Platform '{platform}' is not supported for source compilation. "
                        f"Supported platforms: {supported_list}. "
                        f"For other platforms, use 'Config Injection' method."
                    )
            
            # Get target for platform
            target = PLATFORM_TARGET_MAP.get(platform_normalized, PLATFORM_TARGET_MAP.get(platform))
            if not target:
                target = 'x86_64-unknown-linux-gnu'
            
            logger.info(f"Using Rust target: {target}")
            
            # Step 1: Prepare source
            self._update_status(build_id, BuildStatus.PREPARING, "Copying source files...", 5)
            work_dir = self.prepare_source(build_id, version)
            
            # Step 2: Modify source files
            self._update_status(build_id, BuildStatus.MODIFYING, "Modifying source code...", 15)
            
            # Modify server config
            if server_host or server_key:
                self.modify_server_config(work_dir, server_host, server_key)
                self._update_status(build_id, BuildStatus.MODIFYING, "Server configuration updated", 20)
            
            # Modify app name
            if app_name:
                self.modify_app_name(work_dir, app_name, custom_text or f"{app_name} Remote Desktop")
                self._update_status(build_id, BuildStatus.MODIFYING, f"App name changed to {app_name}", 25)
            
            # Modify logo
            if logo_base64:
                self.modify_logo(work_dir, logo_base64=logo_base64)
                self._update_status(build_id, BuildStatus.MODIFYING, "Logo updated", 30)
            
            # Modify icon
            if icon_base64:
                self.modify_icon(work_dir, icon_base64=icon_base64)
                self._update_status(build_id, BuildStatus.MODIFYING, "Icon updated", 35)
            
            # Step 3: Compile
            self._update_status(build_id, BuildStatus.COMPILING, "Compiling (may take 5-15 minutes)...", 40)
            
            logger.info(f"Starting compilation for target: {target}, platform: {platform_normalized}")
            self.run_compile(work_dir, target=target, release=True, platform=platform_normalized)
            
            self._update_status(build_id, BuildStatus.COMPILING, "Compilation completed", 90)
            
            # Step 4: Get compiled binary
            self._update_status(build_id, BuildStatus.PACKAGING, "Packaging...", 95)
            
            binary_path = self.get_compiled_binary(
                work_dir, 
                target=target, 
                release=True,
                app_name=app_name or "rustdesk"
            )
            
            # Copy to output directory
            output_name = config_data.get('config_name', app_name or 'custom-rustdesk')
            output_name = re.sub(r'[^a-zA-Z0-9_-]', '_', output_name)
            
            if "windows" in platform:
                output_filename = f"{output_name}.exe"
            else:
                output_filename = output_name
            
            output_path = os.path.join(self.BUILD_DIR, output_filename)
            shutil.copy2(binary_path, output_path)
            
            # Make executable on Linux
            if "linux" in platform:
                os.chmod(output_path, 0o755)
            
            # Save metadata
            metadata = {
                'build_id': build_id,
                'platform': platform,
                'target': target,
                'version': version,
                'app_name': app_name,
                'server_host': server_host,
                'created_at': datetime.now().isoformat(),
                'output_file': output_filename
            }
            
            metadata_path = output_path + '.json'
            with open(metadata_path, 'w') as f:
                json.dump(metadata, f, indent=2)
            
            self._update_status(build_id, BuildStatus.COMPLETED, f"Completed: {output_filename}", 100)
            
            # Cleanup work directory (optional - keep for debugging)
            # shutil.rmtree(work_dir, ignore_errors=True)
            
            return {
                'success': True,
                'build_id': build_id,
                'client_path': output_path,
                'metadata_path': metadata_path,
                'filename': output_filename,
                'message': f'Client compiled successfully: {output_filename}'
            }
            
        except Exception as e:
            logger.error(f"Build failed: {e}", exc_info=True)
            self._update_status(build_id, BuildStatus.FAILED, str(e), 0)
            
            return {
                'success': False,
                'build_id': build_id,
                'error': str(e)
            }
    
    def cleanup_old_builds(self, max_age_hours=24):
        """Clean up old build files"""
        try:
            current_time = time.time()
            
            for item in os.listdir(self.BUILD_DIR):
                item_path = os.path.join(self.BUILD_DIR, item)
                
                item_age = current_time - os.path.getmtime(item_path)
                if item_age > (max_age_hours * 3600):
                    if os.path.isdir(item_path):
                        shutil.rmtree(item_path, ignore_errors=True)
                    else:
                        os.remove(item_path)
                    logger.info(f"Cleaned up old build: {item}")
                        
        except Exception as e:
            logger.error(f"Error cleaning up old builds: {e}")


# Singleton instance
_generator_instance = None


def get_generator():
    """Get or create generator instance"""
    global _generator_instance
    if _generator_instance is None:
        _generator_instance = SourceClientGenerator()
    return _generator_instance


def generate_from_source(config_data):
    """Helper function to generate a custom client from source"""
    generator = get_generator()
    
    # Cleanup old builds first
    generator.cleanup_old_builds()
    
    # Generate new client
    result = generator.generate(config_data)
    
    return result


def get_build_status(build_id):
    """Get status of a specific build"""
    generator = get_generator()
    return generator.get_build_status(build_id)


# Test configuration
if __name__ == "__main__":
    test_config = {
        'server_host': '127.0.0.1',
        'server_key': 'TestKey123==',
        # Change server_host to your actual server IP before running
        'app_name': 'MyRemoteApp',
        'platform': 'linux',
        'version': '1.4.5'
    }
    
    print("Starting source compilation test...")
    result = generate_from_source(test_config)
    print(f"Result: {json.dumps(result, indent=2)}")
