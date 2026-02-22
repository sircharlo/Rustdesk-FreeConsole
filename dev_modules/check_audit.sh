#!/bin/bash
sqlite3 ~/web-nodejs/data/auth.db "SELECT action, details, ip_address, created_at FROM audit_log WHERE action LIKE 'api_%' ORDER BY created_at DESC LIMIT 15;"
