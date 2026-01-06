#!/bin/bash
# HBBS Ban Check - Automatic Patch and Build Script
# 
# This script:
# 1. Clones RustDesk Server v1.1.14
# 2. Applies ban check patches
# 3. Compiles modified hbbs
# 4. Creates installation package

set -e

# Source cargo environment if exists
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}HBBS Ban Check - Build Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check requirements
echo -e "${YELLOW}[1/8] Checking requirements...${NC}"

if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ Git not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Git${NC}"

if ! command -v cargo &> /dev/null; then
    echo -e "${RED}✗ Rust/Cargo not installed${NC}"
    echo "Install from: https://rustup.rs/"
    exit 1
fi
echo -e "${GREEN}✓ Rust $(cargo --version)${NC}"

# Clone repository
echo ""
echo -e "${YELLOW}[2/8] Cloning RustDesk Server...${NC}"

if [ -d "rustdesk-server" ]; then
    echo "Removing existing directory..."
    rm -rf rustdesk-server
fi

git clone --depth 1 --branch 1.1.14 --recurse-submodules https://github.com/rustdesk/rustdesk-server.git
cd rustdesk-server

echo -e "${GREEN}✓ Cloned v1.1.14${NC}"

# Add rusqlite dependency
echo ""
echo -e "${YELLOW}[3/8] Adding rusqlite dependency...${NC}"

# Add rusqlite to Cargo.toml dependencies section
# Using version 0.27 to match libsqlite3-sys 0.24 (same as used by SQLx)
sed -i '/^\[dependencies\]/a rusqlite = { version = "0.27", features = ["bundled"] }' Cargo.toml

echo -e "${GREEN}✓ rusqlite added to Cargo.toml${NC}"

# Apply database.rs patch
echo ""
echo -e "${YELLOW}[4/8] Applying database.rs patch...${NC}"

# Insert is_device_banned method using synchronous rusqlite to avoid nested runtime panic
# Note: hbb_common re-exports both anyhow and tokio, so we use full paths
sed -i '/pub async fn update_pk/,/^    }$/{
/^    }$/ a\
\
    /// Check if a device is banned in the database\
    /// Returns true if device has is_banned=1, false otherwise\
    /// Uses synchronous rusqlite to avoid nested Tokio runtime panic\
    pub async fn is_device_banned(\&self, id: \&str) -> ResultType<bool> {\
        let db_path = "./db_v2.sqlite3";\
        let id = id.to_string();\
        \
        // Execute in blocking thread pool to avoid runtime conflict\
        let result = hbb_common::tokio::task::spawn_blocking(move || -> ResultType<bool> {\
            use rusqlite::{Connection, OptionalExtension};\
            \
            // Use READ_WRITE to support WAL mode (no actual writes performed)\
            let conn = Connection::open_with_flags(\
                db_path,\
                rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE\
            )?;\
            \
            let mut stmt = conn.prepare(\
                "SELECT is_banned FROM peer WHERE id = ? AND is_deleted = 0"\
            )?;\
            \
            let result: Option<i32> = stmt\
                .query_row([&id], |row| row.get(0))\
                .optional()?;\
            \
            Ok(result.map(|banned| banned == 1).unwrap_or(false))\
        })\
        .await\
        .map_err(|e| hbb_common::anyhow::anyhow!("Spawn blocking failed: {}", e))??;\
\
        Ok(result)\
    }
}' src/database.rs

echo -e "${GREEN}✓ database.rs patched${NC}"

# Apply peer.rs patch
echo ""
echo -e "${YELLOW}[5/8] Applying peer.rs patch...${NC}"

# Patch 1: Ban check in update_pk - reject and remove from memory
sed -i '/log::info!("update_pk/a\
        \
        // BAN CHECK: Verify device is not banned before registration\
        match self.db.is_device_banned(\&id).await {\
            Ok(true) => {\
                log::warn!("Registration REJECTED for device {}: DEVICE IS BANNED", id);\
                // Remove from memory to prevent cached access\
                self.map.write().await.remove(\&id);\
                return register_pk_response::Result::UUID_MISMATCH;\
            }\
            Ok(false) => {\
                log::debug!("Ban check passed for device {}", id);\
            }\
            Err(e) => {\
                log::error!("Failed to check ban status for device {}: {}. Allowing (fail-open)", id, e);\
            }\
        }' src/peer.rs

# Patch 2: Ban check in get() - prevent loading banned devices from DB
sed -i '/let peer = Peer {/i\
            // BAN CHECK: Do not load banned devices into memory\
            if let Ok(true) = self.db.is_device_banned(id).await {\
                log::warn!("Blocked loading banned device {} from database", id);\
                return None;\
            }' src/peer.rs

# Patch 3: Add method to find device ID by socket address  
# Add AFTER the closing brace of is_in_memory() method
sed -i '/self\.map\.read()\.await\.contains_key(id)/,/^    }$/{
/^    }$/a\
\
    /// Find device ID by socket address (for ban enforcement)\
    /// Returns the ID of the peer with matching socket address, or None\
    pub(crate) async fn get_id_by_addr(\&self, addr: SocketAddr) -> Option<String> {\
        let map = self.map.read().await;\
        for (id, peer) in map.iter() {\
            let peer_addr = peer.read().await.socket_addr;\
            if peer_addr == addr {\
                return Some(id.clone());\
            }\
        }\
        None\
    }
}' src/peer.rs

echo -e "${GREEN}✓ peer.rs patched${NC}"

# Apply rendezvous_server.rs patch - block banned devices from relay and P2P connections  
echo ""
echo -e "${YELLOW}[6/8] Applying rendezvous_server.rs patches...${NC}"

# Patch 1: Block RequestRelay for banned devices (target only - more reliable)
sed -i '/Some(rendezvous_message::Union::RequestRelay(mut rf)) => {/,/return true;/{
/Some(rendezvous_message::Union::RequestRelay(mut rf)) => {/a\
                    // BAN CHECK: Block relay if target is banned\
                    match self.pm.db.is_device_banned(\&rf.id).await {\
                        Ok(true) => {\
                            log::warn!("Relay REJECTED - target {} is banned", rf.id);\
                            return true;\
                        }\
                        Ok(false) => {},\
                        Err(e) => {\
                            log::error!("Ban check failed for relay target {}: {}", rf.id, e);\
                        }\
                    }\
                    // BAN CHECK: Block relay if sender (uuid) is banned\
                    if !rf.uuid.is_empty() {\
                        match self.pm.db.is_device_banned(\&rf.uuid).await {\
                            Ok(true) => {\
                                log::warn!("Relay REJECTED - sender {} (uuid) is banned", rf.uuid);\
                                return true;\
                            }\
                            Ok(false) => {},\
                            Err(e) => {\
                                log::error!("Ban check failed for sender {}: {}", rf.uuid, e);\
                            }\
                        }\
                    }
}' src/rendezvous_server.rs

# Patch 2: Block PunchHoleRequest for banned devices (target only - sender will be caught by message relay)
sed -i '/async fn handle_punch_hole_request(/,/let id = ph.id;/{
/let id = ph.id;/a\
        \
        // BAN CHECK 1: Block if TARGET device is banned\
        match self.pm.db.is_device_banned(\&id).await {\
            Ok(true) => {\
                log::warn!("Punch hole REJECTED - target {} is BANNED", id);\
                let mut msg_out = RendezvousMessage::new();\
                msg_out.set_punch_hole_response(PunchHoleResponse {\
                    failure: punch_hole_response::Failure::OFFLINE.into(),\
                    ..Default::default()\
                });\
                return Ok((msg_out, None));\
            }\
            Ok(false) => {\
                log::debug!("Target ban check passed for {}", id);\
            }\
            Err(e) => {\
                log::error!("Failed to check target ban status for {}: {}", id, e);\
            }\
        }\
        \
        // BAN CHECK 2: Block if SOURCE device (initiating connection) is banned\
        if let Some(source_id) = self.pm.get_id_by_addr(addr).await {\
            match self.pm.db.is_device_banned(\&source_id).await {\
                Ok(true) => {\
                    log::warn!("Punch hole REJECTED - source {} (from {}) is BANNED", source_id, addr);\
                    let mut msg_out = RendezvousMessage::new();\
                    msg_out.set_punch_hole_response(PunchHoleResponse {\
                        failure: punch_hole_response::Failure::LICENSE_MISMATCH.into(),\
                        ..Default::default()\
                    });\
                    return Ok((msg_out, None));\
                }\
                Ok(false) => {\
                    log::debug!("Source ban check passed for {}", source_id);\
                }\
                Err(e) => {\
                    log::error!("Failed to check source ban status for {}: {}", source_id, e);\
                }\
            }\
        } else {\
            log::debug!("Could not find source device ID for address {}", addr);\
        }
}' src/rendezvous_server.rs

echo -e "${GREEN}✓ rendezvous_server.rs patched${NC}"

# NEW CRITICAL PATCH 3: Block RelayResponse - THE actual message relay
echo ""
echo -e "${YELLOW}[6.5/8] Adding RelayResponse ban check (CRITICAL)...${NC}"

# This blocks the actual data being relayed between devices
sed -i '/Some(rendezvous_message::Union::RelayResponse(mut rr)) => {/a\
                    // CRITICAL BAN CHECK: Block relay response if sender or target is banned\
                    // This is where actual remote control data flows\
                    let relay_id = rr.id();\
                    if !relay_id.is_empty() {\
                        // Check if relay ID (could be sender or target) is banned\
                        match self.pm.db.is_device_banned(relay_id).await {\
                            Ok(true) => {\
                                log::warn!("RelayResponse BLOCKED - device {} is banned", relay_id);\
                                return true;\
                            }\
                            Ok(false) => {},\
                            Err(e) => {\
                                log::error!("Ban check failed for relay {}: {}", relay_id, e);\
                            }\
                        }\
                    }' src/rendezvous_server.rs

echo -e "${GREEN}✓ RelayResponse ban check added${NC}"

# NEW CRITICAL PATCH 4: Block HBBR relay_server.rs - actual data relay
echo ""
echo -e "${YELLOW}[6.6/8] Adding HBBR relay server ban check (MOST CRITICAL)...${NC}"

# Add ban check to make_pair_ before pairing
# Strategy: Check if ANY device from the initiating IP is banned
sed -i '/if let Some(rendezvous_message::Union::RequestRelay(rf)) = msg_in.union {/,/if !rf.uuid.is_empty() {/{
/if !rf.uuid.is_empty() {/a\
                    // CRITICAL BAN CHECK: Block relay if device from this IP is banned\
                    // Strategy: Query database for all devices with recent activity from this IP\
                    // and check if any of them is banned\
                    let db_path = "./db_v2.sqlite3";\
                    let client_ip = addr.ip().to_string();\
                    let target_id = rf.id.clone();\
                    \
                    let is_banned = hbb_common::tokio::task::spawn_blocking(move || {\
                        use rusqlite::{Connection, OptionalExtension};\
                        \
                        match Connection::open_with_flags(\
                            db_path,\
                            rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE\
                        ) {\
                            Ok(conn) => {\
                                // Check if target device is banned\
                                if !target_id.is_empty() {\
                                    if let Ok(Some(Some(banned))) = conn\
                                        .prepare("SELECT is_banned FROM peer WHERE id = ? AND is_deleted = 0")\
                                        .and_then(|mut stmt| stmt.query_row([&target_id], |row| row.get::<_, Option<i32>>(0)).optional()) {\
                                        if banned == 1 {\
                                            log::warn!("HBBR Relay BLOCKED - target device {} is BANNED", target_id);\
                                            return true;\
                                        }\
                                    }\
                                }\
                                \
                                // Check if ANY device from this IP is banned\
                                // This catches the initiating device even if we don'\''t have its exact ID\
                                let info_pattern = format!("%{}%", client_ip);\
                                match conn.prepare(\
                                    "SELECT id, is_banned FROM peer WHERE info LIKE ? AND is_deleted = 0 LIMIT 10"\
                                ) {\
                                    Ok(mut stmt) => {\
                                        if let Ok(mut rows) = stmt.query([&info_pattern]) {\
                                            while let Ok(Some(row)) = rows.next() {\
                                                if let (Ok(id), Ok(Some(banned))) = (\
                                                    row.get::<_, String>(0),\
                                                    row.get::<_, Option<i32>>(1)\
                                                ) {\
                                                    if banned == 1 {\
                                                        log::warn!("HBBR Relay BLOCKED - device {} from IP {} is BANNED", id, client_ip);\
                                                        return true;\
                                                    }\
                                                }\
                                            }\
                                        }\
                                    }\
                                    Err(_) => {}\
                                }\
                                false\
                            }\
                            Err(_) => false\
                        }\
                    }).await;\
                    \
                    match is_banned {\
                        Ok(true) => {\
                            log::warn!("HBBR Relay REJECTED from {}", addr);\
                            return;\
                        }\
                        Ok(false) => {\
                            log::debug!("HBBR Relay allowed from {}", addr);\
                        }\
                        Err(e) => {\
                            log::error!("HBBR ban check spawn failed: {}", e);\
                        }\
                    }
}' src/relay_server.rs

echo -e "${GREEN}✓ HBBR relay ban check added${NC}"

# Compile
echo ""
echo -e "${YELLOW}[7/8] Compiling hbbs...${NC}"
echo "This may take 5-10 minutes on first build..."

cargo build --release --bin hbbs

if [ ! -f "target/release/hbbs" ]; then
    echo -e "${RED}✗ HBBS build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ HBBS compiled${NC}"

# Compile HBBR (relay server) - CRITICAL for ban enforcement
echo ""
echo -e "${YELLOW}[8/8] Compiling hbbr (relay server)...${NC}"
echo "HBBR handles actual data relay - must have ban checks!"

cargo build --release --bin hbbr

if [ ! -f "target/release/hbbr" ]; then
    echo -e "${RED}✗ HBBR build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ HBBR compiled${NC}"
echo -e "${GREEN}✓ All builds successful${NC}"

# Create package
echo ""
echo -e "${YELLOW}[9/8] Creating installation package...${NC}"

mkdir -p ../hbbs-ban-check-package
cp target/release/hbbs ../hbbs-ban-check-package/
cp target/release/hbbr ../hbbs-ban-check-package/
cp /opt/rustdesk/id_ed25519.pub ../hbbs-ban-check-package/ 2>/dev/null || echo "Note: No existing public key"

# Create install script
cat > ../hbbs-ban-check-package/install.sh << 'INSTALL_EOF'
#!/bin/bash
# HBBS Ban Check - Installation Script

set -e

if [ "$EUID" -ne 0 ]; then
   echo "Please run as root (sudo)"
   exit 1
fi

echo "Installing HBBS with ban check..."

# Backup
systemctl stop hbbs
cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.backup.$(date +%Y%m%d-%H%M%S)

# Install
cp hbbs /opt/rustdesk/
chmod +x /opt/rustdesk/hbbs

# Restart
systemctl start hbbs
sleep 2

if systemctl is-active --quiet hbbs; then
    echo "✓ HBBS with ban check installed successfully"
    journalctl -u hbbs -n 10 --no-pager
else
    echo "✗ HBBS failed to start. Restoring backup..."
    systemctl stop hbbs
    cp /opt/rustdesk/hbbs.backup.* /opt/rustdesk/hbbs
    systemctl start hbbs
    exit 1
fi
INSTALL_EOF

chmod +x ../hbbs-ban-check-package/install.sh

echo -e "${GREEN}✓ Package created${NC}"

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Package location:"
echo "  $(pwd)/../hbbs-ban-check-package/"
echo ""
echo "Installation:"
echo "  1. Copy package to server:"
echo "     scp -r hbbs-ban-check-package/ user@server:/tmp/"
echo ""
echo "  2. On server, run:"
echo "     cd /tmp/hbbs-ban-check-package"
echo "     sudo ./install.sh"
echo ""
echo "Binary size: $(ls -lh target/release/hbbs | awk '{print $5}')"
echo ""
