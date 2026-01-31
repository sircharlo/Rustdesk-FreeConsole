#!/usr/bin/env python3
"""
Test script for RustDesk Client Generator
Tests if the generator can properly fetch download URLs from GitHub
"""

import sys
sys.path.insert(0, '/opt/BetterDeskConsole')

from client_generator_module import ClientGenerator

def test_download_urls():
    generator = ClientGenerator()
    
    test_cases = [
        ('1.3.0', 'windows-64', 'rustdesk-1.3.0-x86_64.exe'),
        ('1.3.0', 'windows-32', 'rustdesk-1.3.0-x86-sciter.exe'),
        ('1.3.0', 'linux', 'rustdesk-1.3.0-x86_64.AppImage'),
        ('1.3.0', 'android', 'rustdesk-1.3.0-universal-signed.apk'),
        ('1.3.0', 'macos', 'rustdesk-1.3.0-x86_64.dmg'),
    ]
    
    print("Testing download URL fetching...\n")
    
    for version, platform, expected_file in test_cases:
        print(f"Testing {platform} version {version}...")
        url = generator.get_download_url(version, platform)
        
        if url:
            print(f"  ✓ Found URL: {url}")
            if expected_file in url:
                print(f"  ✓ Filename matches: {expected_file}")
            else:
                print(f"  ⚠ Filename mismatch! Expected: {expected_file}")
        else:
            print(f"  ✗ Failed to get URL")
        print()

if __name__ == '__main__':
    test_download_urls()
