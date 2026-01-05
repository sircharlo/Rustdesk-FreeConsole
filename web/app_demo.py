#!/usr/bin/env python3
"""
BetterDesk Console - Demo Version with Mock Data
For creating screenshots without exposing real device information
"""

from flask import Flask, render_template, jsonify, request
import json
from datetime import datetime, timedelta
import random

app = Flask(__name__)

# Mock data for screenshots
MOCK_DEVICES = [
    {"id": "1234567890", "note": "Production Server - NYC", "online": True, "created_at": "2025-12-01 10:30:00", "user": "admin", "info": '{"os": "Ubuntu 22.04", "version": "1.2.3"}'},
    {"id": "0987654321", "note": "Development Workstation", "online": True, "created_at": "2025-12-05 14:20:00", "user": "dev_team", "info": '{"os": "Windows 11", "version": "1.2.3"}'},
    {"id": "5555555555", "note": "Marketing Office PC", "online": False, "created_at": "2025-11-20 09:15:00", "user": "marketing", "info": '{"os": "macOS 14", "version": "1.2.2"}'},
    {"id": "7777777777", "note": "Database Server - LA", "online": True, "created_at": "2025-12-10 16:45:00", "user": "dba", "info": '{"os": "Ubuntu 24.04", "version": "1.2.3"}'},
    {"id": "9999999999", "note": "Sales Laptop", "online": False, "created_at": "2025-11-15 11:30:00", "user": "sales", "info": '{"os": "Windows 10", "version": "1.2.1"}'},
    {"id": "1111111111", "note": "Backup Server", "online": True, "created_at": "2025-12-08 13:00:00", "user": "admin", "info": '{"os": "Debian 12", "version": "1.2.3"}'},
    {"id": "2222222222", "note": "Test Environment", "online": True, "created_at": "2025-12-12 08:45:00", "user": "qa_team", "info": '{"os": "Ubuntu 22.04", "version": "1.2.3"}'},
    {"id": "3333333333", "note": "HR Department PC", "online": False, "created_at": "2025-11-25 10:00:00", "user": "hr", "info": '{"os": "Windows 11", "version": "1.2.2"}'},
    {"id": "4444444444", "note": "Web Server - EU", "online": True, "created_at": "2025-12-15 15:30:00", "user": "webmaster", "info": '{"os": "CentOS 9", "version": "1.2.3"}'},
    {"id": "6666666666", "note": "Design Workstation", "online": True, "created_at": "2025-12-03 12:20:00", "user": "design", "info": '{"os": "macOS 14", "version": "1.2.3"}'},
    {"id": "8888888888", "note": None, "online": False, "created_at": "2025-11-10 14:00:00", "user": None, "info": None},
    {"id": "1212121212", "note": None, "online": False, "created_at": "2025-11-05 09:30:00", "user": None, "info": None},
]

MOCK_PUBLIC_KEY = "AGH8B3pM5QVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV="

@app.route('/')
def index():
    return render_template('index.html', public_key=MOCK_PUBLIC_KEY)

@app.route('/api/devices', methods=['GET'])
def get_devices():
    return jsonify({"success": True, "devices": MOCK_DEVICES, "error": None})

@app.route('/api/stats', methods=['GET'])
def get_stats():
    total = len(MOCK_DEVICES)
    active = sum(1 for d in MOCK_DEVICES if d['online'])
    inactive = total - active
    with_notes = sum(1 for d in MOCK_DEVICES if d['note'])
    
    return jsonify({
        "stats": {
            "total": total,
            "active": active,
            "inactive": inactive,
            "with_notes": with_notes
        }
    })

@app.route('/api/device/<device_id>', methods=['GET'])
def get_device(device_id):
    device = next((d for d in MOCK_DEVICES if d['id'] == device_id), None)
    if device:
        return jsonify({"success": True, "device": device, "error": None})
    return jsonify({"success": False, "device": None, "error": "Device not found"}), 404

if __name__ == '__main__':
    print("=" * 60)
    print("BetterDesk Console - DEMO MODE")
    print("=" * 60)
    print("This version uses mock data for screenshots.")
    print("Running on: http://localhost:5001")
    print("=" * 60)
    app.run(host='0.0.0.0', port=5001, debug=True)
