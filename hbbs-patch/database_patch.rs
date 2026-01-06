// Patch dla database.rs - dodaje metodę is_device_banned()
// 
// Wstaw ten kod na końcu implementacji `impl Database`
// (przed zamykającym nawiasem klamrowym struktury)

    /// Check if a device is banned in the database
    /// Returns true if device has is_banned=1, false otherwise
    /// Uses separate synchronous SQLite connection to avoid nested runtime panic
    pub async fn is_device_banned(&self, id: &str) -> ResultType<bool> {
        use std::sync::Arc;
        
        // Database path - assuming same as used in HBBS (./db_v2.sqlite3)
        let db_path = "./db_v2.sqlite3";
        let id = id.to_string();
        
        // Execute synchronous query in blocking thread pool
        // This avoids "Cannot start a runtime from within a runtime" error
        let result = tokio::task::spawn_blocking(move || -> ResultType<bool> {
            use rusqlite::Connection;
            
            // Open synchronous connection (read-only)
            let conn = Connection::open_with_flags(
                db_path,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY
            )?;
            
            // Query for ban status
            let mut stmt = conn.prepare(
                "SELECT is_banned FROM peer WHERE id = ? AND is_deleted = 0"
            )?;
            
            let result: Option<i32> = stmt
                .query_row([&id], |row| row.get(0))
                .optional()?;
            
            // Return true if banned (is_banned = 1), false otherwise
            Ok(result.map(|banned| banned == 1).unwrap_or(false))
        })
        .await
        .map_err(|e| anyhow::anyhow!("Spawn blocking failed: {}", e))??;

        Ok(result)
    }


