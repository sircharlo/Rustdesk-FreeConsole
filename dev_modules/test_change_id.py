#!/usr/bin/env python3
"""
Test script for ID change API endpoint

Usage:
    python test_change_id.py [old_id] [new_id]

Note: Configure API_KEY before running (get from /opt/rustdesk/.api_key)
"""

import requests
import sys
import os

old_id = sys.argv[1] if len(sys.argv) > 1 else "TESTID002"
new_id = sys.argv[2] if len(sys.argv) > 2 else "TESTID003"

# Get API key from environment or file
api_key = os.environ.get("HBBS_API_KEY", "")
if not api_key:
    print("ERROR: Set HBBS_API_KEY environment variable")
    print("  Linux:   export HBBS_API_KEY=$(cat /opt/rustdesk/.api_key)")
    print("  Windows: $env:HBBS_API_KEY = Get-Content C:\\rustdesk\\.api_key")
    sys.exit(1)

r = requests.post(
    f"http://localhost:21120/api/peers/{old_id}/change-id",
    json={"new_id": new_id},
    headers={"X-API-Key": api_key},
)
print(f"Status: {r.status_code}")
print(f"Response: {r.text}")
