#!/usr/bin/env python3
"""
BetterDesk Server Patch: ID Change Support
Patches the server source files in ~/rustdesk-server-1.1.14/src/
to add peer ID change support via RegisterPk old_id field.

Usage: python3 patch_id_change_v2.py [--dry-run]
"""

import os
import sys
import shutil
from datetime import datetime

SRC_DIR = os.path.expanduser("~/rustdesk-server-1.1.14/src")
DRY_RUN = "--dry-run" in sys.argv
BACKUP_SUFFIX = f".backup-pre-idchange-{datetime.now().strftime('%Y%m%d-%H%M%S')}"


def backup_file(path):
    backup = path + BACKUP_SUFFIX
    shutil.copy2(path, backup)
    print(f"  Backup: {backup}")


def patch_file(path, patches):
    """Apply a list of (old_text, new_text) patches to a file."""
    with open(path, "r") as f:
        content = f.read()

    original = content
    for i, (old, new) in enumerate(patches):
        if old not in content:
            print(f"  ERROR: Patch {i + 1} - target text not found!")
            print(f"  Looking for: {repr(old[:80])}...")
            return False
        count = content.count(old)
        if count > 1:
            print(
                f"  WARNING: Patch {i + 1} - found {count} matches, replacing first only"
            )
        content = content.replace(old, new, 1)
        print(f"  Patch {i + 1}: OK")

    if DRY_RUN:
        print(f"  [DRY RUN] Would write {len(content)} bytes")
    else:
        with open(path, "w") as f:
            f.write(content)
        print(f"  Written {len(content)} bytes (was {len(original)})")
    return True


def insert_before(path, marker, new_text):
    """Insert new_text before the line containing marker."""
    with open(path, "r") as f:
        content = f.read()

    if marker not in content:
        print(f"  ERROR: Marker not found: {repr(marker[:80])}")
        return False

    content = content.replace(marker, new_text + marker, 1)

    if DRY_RUN:
        print(f"  [DRY RUN] Would insert before marker")
    else:
        with open(path, "w") as f:
            f.write(content)
    return True


def patch_database():
    path = os.path.join(SRC_DIR, "database.rs")
    print(f"\n=== Patching {path} ===")
    backup_file(path)

    patches = [
        # 1. Add Row import to sqlx
        (
            "use sqlx::{\n    sqlite::SqliteConnectOptions, ConnectOptions, Connection, Error as SqlxError, SqliteConnection,\n};",
            "use sqlx::{\n    sqlite::SqliteConnectOptions, ConnectOptions, Connection, Error as SqlxError, Row, SqliteConnection,\n};",
        ),
        # 2. Add ensure_columns() call after create_tables()
        (
            "        db.create_tables().await?;\n        Ok(db)",
            "        db.create_tables().await?;\n        db.ensure_columns().await?;\n        Ok(db)",
        ),
        # 3. Add new methods before test module
        (
            "\n#[cfg(test)]",
            """
    /// Ensure additional columns exist (safe migration for older databases)
    async fn ensure_columns(&self) -> ResultType<()> {
        let migrations = [
            "ALTER TABLE peer ADD COLUMN previous_ids TEXT DEFAULT ''",
            "ALTER TABLE peer ADD COLUMN id_changed_at TEXT DEFAULT ''",
            "ALTER TABLE peer ADD COLUMN is_deleted INTEGER DEFAULT 0",
            "ALTER TABLE peer ADD COLUMN is_banned INTEGER DEFAULT 0",
            "ALTER TABLE peer ADD COLUMN last_online DATETIME DEFAULT NULL",
        ];
        for sql in &migrations {
            // Ignore errors - column may already exist
            let _ = sqlx::query(sql)
                .execute(self.pool.get().await?.deref_mut())
                .await;
        }
        log::debug!("Column migration check completed");
        Ok(())
    }

    /// Check if a peer ID is available (not taken by any existing peer)
    pub async fn is_id_available(&self, id: &str) -> ResultType<bool> {
        let row = sqlx::query("SELECT 1 FROM peer WHERE id = ?")
            .bind(id)
            .fetch_optional(self.pool.get().await?.deref_mut())
            .await?;
        Ok(row.is_none())
    }

    /// Change peer ID in the database with history tracking
    pub async fn change_peer_id(&self, old_id: &str, new_id: &str) -> ResultType<()> {
        let mut conn = self.pool.get().await?;

        // Get current previous_ids for history tracking
        let prev_row = sqlx::query("SELECT previous_ids FROM peer WHERE id = ?")
            .bind(old_id)
            .fetch_optional(conn.deref_mut())
            .await?;

        let prev_str = prev_row
            .and_then(|r| r.try_get::<String, _>("previous_ids").ok())
            .unwrap_or_default();

        // Build updated history: parse existing JSON array and append old_id
        let mut history: Vec<String> = if prev_str.is_empty() {
            Vec::new()
        } else {
            serde_json::from_str(&prev_str).unwrap_or_default()
        };
        history.push(old_id.to_string());
        let updated_history = serde_json::to_string(&history).unwrap_or_default();

        // Perform the ID change
        sqlx::query(
            "UPDATE peer SET id = ?, previous_ids = ?, id_changed_at = datetime('now') WHERE id = ?"
        )
            .bind(new_id)
            .bind(&updated_history)
            .bind(old_id)
            .execute(conn.deref_mut())
            .await?;

        log::info!("Database: ID changed {} -> {} (history: {})", old_id, new_id, updated_history);
        Ok(())
    }

    /// Check if a device is banned
    pub async fn is_device_banned(&self, id: &str) -> ResultType<bool> {
        let row = sqlx::query("SELECT is_banned FROM peer WHERE id = ?")
            .bind(id)
            .fetch_optional(self.pool.get().await?.deref_mut())
            .await?;
        match row {
            Some(r) => {
                let val: Option<i32> = r.try_get("is_banned").ok();
                Ok(val == Some(1))
            }
            None => Ok(false),
        }
    }
}

#[cfg(test)]""",
        ),
    ]

    return patch_file(path, patches)


def patch_peer():
    path = os.path.join(SRC_DIR, "peer.rs")
    print(f"\n=== Patching {path} ===")
    backup_file(path)

    patches = [
        # 1. Add ID_CHANGE_COOLDOWN to lazy_static block
        (
            "    pub(crate) static ref IP_CHANGES: Mutex<IpChangesMap> = Default::default();\n}",
            "    pub(crate) static ref IP_CHANGES: Mutex<IpChangesMap> = Default::default();\n    pub(crate) static ref ID_CHANGE_COOLDOWN: Mutex<HashMap<String, Instant>> = Default::default();\n}",
        ),
        # 2. Add ID_CHANGE_COOLDOWN_SECS constant after IP_BLOCK_DUR
        (
            "pub const IP_BLOCK_DUR: u64 = 60;\n",
            "pub const IP_BLOCK_DUR: u64 = 60;\nconst ID_CHANGE_COOLDOWN_SECS: u64 = 300; // 5 minutes between ID changes per device\n",
        ),
        # 3. Add change_id() method after update_pk() (before get())
        (
            "        register_pk_response::Result::OK\n    }\n\n    #[inline]\n    pub(crate) async fn get(",
            """        register_pk_response::Result::OK
    }

    /// Handle ID change request from RegisterPk with old_id
    /// Validates format, rate limit, UUID match, new ID availability
    pub(crate) async fn change_id(
        &mut self,
        old_id: String,
        new_id: String,
        addr: SocketAddr,
        uuid: Bytes,
        pk: Bytes,
        ip: String,
    ) -> register_pk_response::Result {
        log::info!("change_id: {} -> {} from {}", old_id, new_id, ip);

        // Rate limit check (per device, 5 min cooldown)
        {
            let mut cooldown = ID_CHANGE_COOLDOWN.lock().await;
            if let Some(last) = cooldown.get(&old_id) {
                if last.elapsed().as_secs() < ID_CHANGE_COOLDOWN_SECS {
                    log::warn!("ID change rate limited for {}", old_id);
                    return register_pk_response::Result::TOO_FREQUENT;
                }
            }
        }

        // Ban check
        match self.db.is_device_banned(&old_id).await {
            Ok(true) => {
                log::warn!("ID change rejected for banned device {}", old_id);
                return register_pk_response::Result::UUID_MISMATCH;
            }
            Ok(false) => {}
            Err(e) => {
                log::error!("Ban check failed for {}: {}", old_id, e);
            }
        }

        // Verify old_id exists and UUID matches
        match self.get(&old_id).await {
            Some(peer) => {
                let peer_data = peer.read().await;
                if peer_data.uuid != uuid {
                    log::warn!("UUID mismatch for ID change {} -> {}", old_id, new_id);
                    return register_pk_response::Result::UUID_MISMATCH;
                }
            }
            None => {
                log::warn!("Peer {} not found for ID change", old_id);
                return register_pk_response::Result::UUID_MISMATCH;
            }
        }

        // Check new_id is available in database
        match self.db.is_id_available(&new_id).await {
            Ok(true) => {}
            Ok(false) => {
                log::info!("ID {} already exists, cannot change from {}", new_id, old_id);
                return register_pk_response::Result::UUID_MISMATCH;
            }
            Err(e) => {
                log::error!("Failed to check ID availability: {}", e);
                return register_pk_response::Result::SERVER_ERROR;
            }
        }

        // Also check memory map
        if self.is_in_memory(&new_id).await {
            log::info!("ID {} exists in memory, cannot change from {}", new_id, old_id);
            return register_pk_response::Result::UUID_MISMATCH;
        }

        // Perform database change
        if let Err(e) = self.db.change_peer_id(&old_id, &new_id).await {
            log::error!("Database ID change failed {} -> {}: {}", old_id, new_id, e);
            return register_pk_response::Result::SERVER_ERROR;
        }

        // Update memory map: remove old_id, insert with new_id
        {
            let mut map = self.map.write().await;
            if let Some(peer) = map.remove(&old_id) {
                {
                    let mut w = peer.write().await;
                    w.socket_addr = addr;
                    w.pk = pk;
                    w.last_reg_time = Instant::now();
                    w.info.ip = ip;
                }
                map.insert(new_id.clone(), peer);
            }
        }

        // Update rate limit cooldown
        {
            let mut cooldown = ID_CHANGE_COOLDOWN.lock().await;
            cooldown.insert(new_id.clone(), Instant::now());
        }

        log::info!("ID change successful: {} -> {}", old_id, new_id);
        register_pk_response::Result::OK
    }

    #[inline]
    pub(crate) async fn get(""",
        ),
    ]

    return patch_file(path, patches)


def patch_rendezvous_server():
    path = os.path.join(SRC_DIR, "rendezvous_server.rs")
    print(f"\n=== Patching {path} ===")
    backup_file(path)

    # Replace the RegisterPk handler to add old_id support
    old_handler = """                Some(rendezvous_message::Union::RegisterPk(rk)) => {
                    if rk.uuid.is_empty() || rk.pk.is_empty() {
                        return Ok(());
                    }
                    let id = rk.id;
                    let ip = addr.ip().to_string();
                    if id.len() < 6 {
                        return send_rk_res(socket, addr, UUID_MISMATCH).await;
                    } else if !self.check_ip_blocker(&ip, &id).await {"""

    new_handler = """                Some(rendezvous_message::Union::RegisterPk(rk)) => {
                    if rk.uuid.is_empty() || rk.pk.is_empty() {
                        return Ok(());
                    }
                    let id = rk.id;
                    let old_id = rk.old_id;
                    let ip = addr.ip().to_string();

                    // =========================================================
                    // ID Change flow - when client sends old_id with a new id
                    // =========================================================
                    if !old_id.is_empty() && old_id != id {
                        log::info!("ID change request: {} -> {} from {}", old_id, id, ip);
                        if id.len() < 6 || id.len() > 16 {
                            log::warn!("Invalid ID format for change: {}", id);
                            return send_rk_res(socket, addr, UUID_MISMATCH).await;
                        }
                        if !id.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
                            log::warn!("Invalid ID characters for change: {}", id);
                            return send_rk_res(socket, addr, UUID_MISMATCH).await;
                        }
                        if !self.check_ip_blocker(&ip, &old_id).await {
                            return send_rk_res(socket, addr, TOO_FREQUENT).await;
                        }
                        let result = self.pm.change_id(
                            old_id, id, addr, rk.uuid, rk.pk, ip
                        ).await;
                        let mut msg_out = RendezvousMessage::new();
                        msg_out.set_register_pk_response(RegisterPkResponse {
                            result: result.into(),
                            ..Default::default()
                        });
                        socket.send(&msg_out, addr).await?;
                        return Ok(());
                    }

                    // =========================================================
                    // Normal registration flow
                    // =========================================================
                    if id.len() < 6 {
                        return send_rk_res(socket, addr, UUID_MISMATCH).await;
                    } else if !self.check_ip_blocker(&ip, &id).await {"""

    patches = [(old_handler, new_handler)]
    return patch_file(path, patches)


def main():
    print("BetterDesk Server Patch: ID Change Support")
    print(f"Source directory: {SRC_DIR}")
    print(f"Mode: {'DRY RUN' if DRY_RUN else 'LIVE'}")

    if not os.path.isdir(SRC_DIR):
        print(f"ERROR: Source directory not found: {SRC_DIR}")
        sys.exit(1)

    ok = True
    ok = patch_database() and ok
    ok = patch_peer() and ok
    ok = patch_rendezvous_server() and ok

    if ok:
        print("\n=== All patches applied successfully! ===")
    else:
        print("\n=== ERRORS occurred during patching ===")
        sys.exit(1)


if __name__ == "__main__":
    main()
