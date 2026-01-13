#!/bin/bash

#############################################################################
# RustDesk Key Repair Tool
# 
# This script helps diagnose and fix key-related issues in RustDesk
# installations. Use it when experiencing "Key mismatch" errors.
#
# Author: UNITRONIX
# License: MIT
#############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RUSTDESK_DIR="/opt/rustdesk"

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_rustdesk_directory() {
    if [ ! -d "$RUSTDESK_DIR" ]; then
        print_warning "Default RustDesk directory not found: $RUSTDESK_DIR"
        read -p "Enter your RustDesk installation directory: " custom_dir
        if [ -d "$custom_dir" ]; then
            RUSTDESK_DIR="$custom_dir"
            print_success "Using directory: $RUSTDESK_DIR"
        else
            print_error "Directory not found: $custom_dir"
            exit 1
        fi
    else
        print_success "Found RustDesk directory: $RUSTDESK_DIR"
    fi
}

show_key_info() {
    print_header "Current Key Information"
    
    echo "📁 Directory: $RUSTDESK_DIR"
    echo ""
    
    # List all key files with details
    if ls "$RUSTDESK_DIR"/*.pub &>/dev/null; then
        echo "🔑 Public key files (.pub):"
        for pubfile in "$RUSTDESK_DIR"/*.pub; do
            local size=$(stat -f%z "$pubfile" 2>/dev/null || stat -c%s "$pubfile" 2>/dev/null)
            local modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$pubfile" 2>/dev/null || stat -c "%y" "$pubfile" 2>/dev/null | cut -d'.' -f1)
            echo "  ├─ $(basename $pubfile)"
            echo "  │  ├─ Size: $size bytes"
            echo "  │  ├─ Modified: $modified"
            echo "  │  └─ Content:"
            cat "$pubfile" | sed 's/^/  │     /'
            echo ""
        done
    else
        print_warning "No .pub files found!"
        echo ""
    fi
    
    # Check for private keys
    if ls "$RUSTDESK_DIR"/id_* 2>/dev/null | grep -v ".pub" &>/dev/null; then
        echo "🔐 Private key files:"
        for keyfile in "$RUSTDESK_DIR"/id_*; do
            if [[ ! "$keyfile" =~ \.pub$ ]] && [ -f "$keyfile" ]; then
                local size=$(stat -f%z "$keyfile" 2>/dev/null || stat -c%s "$keyfile" 2>/dev/null)
                local perms=$(stat -f "%Sp" "$keyfile" 2>/dev/null || stat -c "%a" "$keyfile" 2>/dev/null)
                echo "  ├─ $(basename $keyfile)"
                echo "  │  ├─ Size: $size bytes"
                echo "  │  └─ Permissions: $perms"
            fi
        done
        echo ""
    fi
    
    # Check backups
    if ls "$RUSTDESK_DIR"/*.backup* &>/dev/null || ls "$RUSTDESK_DIR"/*-backup-* &>/dev/null; then
        echo "💾 Backup files found:"
        ls -lh "$RUSTDESK_DIR"/*.backup* "$RUSTDESK_DIR"/*-backup-* 2>/dev/null | awk '{print "  ├─ " $9 " (" $5 ")"}'
        echo ""
    fi
    
    # Check for backup directories
    if ls -d /opt/rustdesk-backup-* &>/dev/null; then
        echo "📦 Backup directories:"
        for backup_dir in /opt/rustdesk-backup-*; do
            echo "  ├─ $backup_dir"
            if ls "$backup_dir"/*.pub &>/dev/null; then
                echo "  │  └─ Contains .pub files ✓"
            fi
        done
        echo ""
    fi
}

verify_key_permissions() {
    print_header "Verifying Key Permissions"
    
    local fixed=0
    
    # Fix private key permissions (should be 600)
    for keyfile in "$RUSTDESK_DIR"/id_*; do
        if [[ ! "$keyfile" =~ \.pub$ ]] && [ -f "$keyfile" ]; then
            local current_perms=$(stat -f "%Sp" "$keyfile" 2>/dev/null || stat -c "%a" "$keyfile" 2>/dev/null)
            if [ "$current_perms" != "600" ] && [ "$current_perms" != "-rw-------" ]; then
                print_warning "Fixing permissions for $(basename $keyfile): $current_perms → 600"
                chmod 600 "$keyfile"
                ((fixed++))
            else
                print_success "$(basename $keyfile): Permissions OK ($current_perms)"
            fi
        fi
    done
    
    # Fix public key permissions (should be 644)
    for pubfile in "$RUSTDESK_DIR"/*.pub; do
        if [ -f "$pubfile" ]; then
            local current_perms=$(stat -f "%Sp" "$pubfile" 2>/dev/null || stat -c "%a" "$pubfile" 2>/dev/null)
            if [ "$current_perms" != "644" ] && [ "$current_perms" != "-rw-r--r--" ]; then
                print_warning "Fixing permissions for $(basename $pubfile): $current_perms → 644"
                chmod 644 "$pubfile"
                ((fixed++))
            else
                print_success "$(basename $pubfile): Permissions OK ($current_perms)"
            fi
        fi
    done
    
    if [ $fixed -gt 0 ]; then
        print_success "Fixed permissions for $fixed file(s)"
    else
        print_success "All permissions are correct"
    fi
}

export_public_key() {
    print_header "Export Public Key"
    
    local pub_files=("$RUSTDESK_DIR"/*.pub)
    
    if [ ! -f "${pub_files[0]}" ]; then
        print_error "No public key files found!"
        return 1
    fi
    
    echo "Available public keys:"
    local i=1
    for pubfile in "$RUSTDESK_DIR"/*.pub; do
        if [ -f "$pubfile" ]; then
            echo "  $i) $(basename $pubfile)"
            ((i++))
        fi
    done
    echo ""
    
    if [ $i -eq 2 ]; then
        # Only one file, use it automatically
        pubfile="${pub_files[0]}"
        print_info "Using: $(basename $pubfile)"
    else
        read -p "Select key to export [1-$((i-1))]: " choice
        pubfile="${pub_files[$((choice-1))]}"
    fi
    
    if [ ! -f "$pubfile" ]; then
        print_error "Invalid selection"
        return 1
    fi
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "PUBLIC KEY (copy this to RustDesk clients):"
    echo "════════════════════════════════════════════════════════════════"
    cat "$pubfile"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Offer to save to file
    read -p "Save to file? [y/N]: " save_choice
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        local export_file="$HOME/rustdesk_public_key_$(date +%Y%m%d_%H%M%S).txt"
        cat "$pubfile" > "$export_file"
        print_success "Saved to: $export_file"
    fi
}

regenerate_keys() {
    print_header "Regenerate Keys"
    
    echo -e "${RED}⚠️  WARNING: REGENERATING KEYS WILL BREAK ALL CLIENT CONNECTIONS ⚠️${NC}"
    echo ""
    echo "After regeneration, you MUST:"
    echo "  1. Stop and restart RustDesk services"
    echo "  2. Update ALL client configurations with new public key"
    echo "  3. Reconfigure each RustDesk client individually"
    echo ""
    echo "Impact:"
    echo "  • All existing clients will be unable to connect"
    echo "  • 'Key mismatch' errors will appear on all devices"
    echo "  • Manual reconfiguration required for each client"
    echo ""
    read -p "Are you ABSOLUTELY SURE? Type 'REGENERATE' to confirm: " confirm
    
    if [ "$confirm" != "REGENERATE" ]; then
        print_info "Operation cancelled"
        return 0
    fi
    
    # Backup existing keys
    print_info "Creating backup of existing keys..."
    local backup_suffix="pre-regenerate-$(date +%Y%m%d-%H%M%S)"
    
    for keyfile in "$RUSTDESK_DIR"/id_ed25519*; do
        if [ -f "$keyfile" ]; then
            cp "$keyfile" "$keyfile.$backup_suffix"
            print_success "Backed up: $(basename $keyfile)"
        fi
    done
    
    # Stop services
    print_info "Stopping RustDesk services..."
    systemctl stop rustdesksignal.service 2>/dev/null || true
    systemctl stop rustdeskrelay.service 2>/dev/null || true
    sleep 2
    
    # Remove old keys
    print_info "Removing old keys..."
    rm -f "$RUSTDESK_DIR/id_ed25519" "$RUSTDESK_DIR/id_ed25519.pub"
    
    # Generate new keys
    print_info "Generating new ED25519 key pair..."
    if command -v ssh-keygen &>/dev/null; then
        ssh-keygen -t ed25519 -f "$RUSTDESK_DIR/id_ed25519" -N "" -C "rustdesk-server-$(date +%Y%m%d)"
        
        if [ -f "$RUSTDESK_DIR/id_ed25519.pub" ]; then
            print_success "✓ New keys generated successfully!"
            echo ""
            echo "════════════════════════════════════════════════════════════════"
            echo "NEW PUBLIC KEY (configure this in ALL RustDesk clients):"
            echo "════════════════════════════════════════════════════════════════"
            cat "$RUSTDESK_DIR/id_ed25519.pub"
            echo "════════════════════════════════════════════════════════════════"
            echo ""
            
            # Save to file
            local key_file="$HOME/NEW_RUSTDESK_KEY_$(date +%Y%m%d_%H%M%S).txt"
            cat "$RUSTDESK_DIR/id_ed25519.pub" > "$key_file"
            print_success "Key saved to: $key_file"
            
            # Fix permissions
            chmod 600 "$RUSTDESK_DIR/id_ed25519"
            chmod 644 "$RUSTDESK_DIR/id_ed25519.pub"
            
            # Restart services
            print_info "Starting RustDesk services..."
            systemctl start rustdesksignal.service
            systemctl start rustdeskrelay.service
            sleep 2
            
            if systemctl is-active --quiet rustdesksignal.service; then
                print_success "✓ Services restarted successfully"
            else
                print_error "Failed to restart services - check logs"
            fi
        else
            print_error "Failed to generate keys"
            return 1
        fi
    else
        print_error "ssh-keygen not found - cannot generate keys"
        return 1
    fi
    
    echo ""
    print_warning "⚠️  NEXT STEPS:"
    echo "  1. Copy the new public key above"
    echo "  2. Open RustDesk on each client device"
    echo "  3. Go to Settings → ID/Relay Server"
    echo "  4. Paste the new public key"
    echo "  5. Save and test connection"
}

restore_from_backup() {
    print_header "Restore Keys from Backup"
    
    # Find backups
    local backups=($(ls -d /opt/rustdesk-backup-* 2>/dev/null))
    local key_backups=($(ls "$RUSTDESK_DIR"/*.backup* "$RUSTDESK_DIR"/*-backup-* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ] && [ ${#key_backups[@]} -eq 0 ]; then
        print_error "No backups found!"
        echo ""
        echo "Checked locations:"
        echo "  • /opt/rustdesk-backup-*"
        echo "  • $RUSTDESK_DIR/*.backup*"
        return 1
    fi
    
    echo "Available backups:"
    echo ""
    
    local options=()
    local i=1
    
    # List directory backups
    for backup in "${backups[@]}"; do
        if [ -d "$backup" ]; then
            echo "  $i) Directory backup: $(basename $backup)"
            if ls "$backup"/*.pub &>/dev/null; then
                echo "     Contains: $(ls "$backup"/*.pub | wc -l) public key file(s)"
            fi
            options+=("$backup")
            ((i++))
        fi
    done
    
    # List key file backups
    for backup in "${key_backups[@]}"; do
        if [ -f "$backup" ]; then
            echo "  $i) Key file: $(basename $backup)"
            options+=("$backup")
            ((i++))
        fi
    done
    
    echo ""
    read -p "Select backup to restore [1-$((i-1))]: " choice
    
    if [ $choice -lt 1 ] || [ $choice -ge $i ]; then
        print_error "Invalid selection"
        return 1
    fi
    
    local selected="${options[$((choice-1))]}"
    
    echo ""
    print_warning "This will restore keys from:"
    echo "  $selected"
    read -p "Continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        return 0
    fi
    
    # Stop services
    print_info "Stopping services..."
    systemctl stop rustdesksignal.service 2>/dev/null || true
    systemctl stop rustdeskrelay.service 2>/dev/null || true
    sleep 2
    
    # Restore
    if [ -d "$selected" ]; then
        # Restore from directory
        print_info "Restoring from directory backup..."
        cp "$selected"/id_ed25519* "$RUSTDESK_DIR/" 2>/dev/null || true
        cp "$selected"/*.pub "$RUSTDESK_DIR/" 2>/dev/null || true
    else
        # Restore individual file
        print_info "Restoring key file..."
        local original_name=$(echo "$selected" | sed 's/\.[^.]*$//' | sed 's/-backup-[0-9]*$//')
        cp "$selected" "$original_name"
    fi
    
    # Fix permissions
    chmod 600 "$RUSTDESK_DIR"/id_ed25519 2>/dev/null || true
    chmod 644 "$RUSTDESK_DIR"/*.pub 2>/dev/null || true
    
    # Restart services
    print_info "Starting services..."
    systemctl start rustdesksignal.service
    systemctl start rustdeskrelay.service
    sleep 2
    
    if systemctl is-active --quiet rustdesksignal.service; then
        print_success "✓ Keys restored and services restarted!"
        echo ""
        echo "Current public key:"
        cat "$RUSTDESK_DIR"/*.pub 2>/dev/null | head -1
    else
        print_error "Failed to restart services - check logs"
    fi
}

# Main menu
main() {
    clear
    print_header "🔧 RustDesk Key Repair Tool"
    
    check_root
    detect_rustdesk_directory
    
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  1) 📋 Show current key information"
    echo "  2) 🔐 Verify and fix key permissions"
    echo "  3) 📤 Export public key"
    echo "  4) 🔄 Regenerate keys (⚠️  BREAKS existing connections)"
    echo "  5) 💾 Restore keys from backup"
    echo "  6) 🚪 Exit"
    echo ""
    read -p "Choose option [1-6]: " choice
    
    case $choice in
        1)
            show_key_info
            ;;
        2)
            verify_key_permissions
            ;;
        3)
            export_public_key
            ;;
        4)
            regenerate_keys
            ;;
        5)
            restore_from_backup
            ;;
        6)
            print_info "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
    
    echo ""
    read -p "Press ENTER to exit..."
}

main "$@"
