#!/bin/bash
# Test ban/unban API endpoints

echo "=== Testing Device Banning System ==="
echo ""

# Get first device ID from database
DEVICE_ID=$(ssh YOUR_SSH_USER@YOUR_SERVER_IP "python3 -c \"import sqlite3; conn = sqlite3.connect('/opt/rustdesk/db_v2.sqlite3'); cursor = conn.cursor(); cursor.execute('SELECT id FROM peer WHERE is_deleted=0 AND is_banned=0 LIMIT 1'); print(cursor.fetchone()[0]); conn.close()\"")

echo "Selected device for testing: $DEVICE_ID"
echo ""

# Test 1: Ban the device
echo "Test 1: Banning device $DEVICE_ID"
ssh YOUR_SSH_USER@YOUR_SERVER_IP "curl -s -X POST http://localhost:5000/api/device/$DEVICE_ID/ban -H 'Content-Type: application/json' -d '{\"reason\":\"Test ban\",\"banned_by\":\"admin\"}'"
echo ""
echo ""

# Test 2: Check stats (should show banned: 1)
echo "Test 2: Checking stats after ban"
ssh YOUR_SSH_USER@YOUR_SERVER_IP "curl -s http://localhost:5000/api/stats | grep -E 'banned|success'"
echo ""
echo ""

# Test 3: Try to ban again (should fail with 409)
echo "Test 3: Trying to ban already banned device (should fail)"
ssh YOUR_SSH_USER@YOUR_SERVER_IP "curl -s -X POST http://localhost:5000/api/device/$DEVICE_ID/ban -H 'Content-Type: application/json' -d '{\"reason\":\"Test\",\"banned_by\":\"admin\"}'"
echo ""
echo ""

# Test 4: Unban the device
echo "Test 4: Unbanning device $DEVICE_ID"
ssh YOUR_SSH_USER@YOUR_SERVER_IP "curl -s -X POST http://localhost:5000/api/device/$DEVICE_ID/unban"
echo ""
echo ""

# Test 5: Check stats again (should show banned: 0)
echo "Test 5: Checking stats after unban"
ssh YOUR_SSH_USER@YOUR_SERVER_IP "curl -s http://localhost:5000/api/stats | grep -E 'banned|success'"
echo ""
echo ""

echo "=== Tests completed ==="
