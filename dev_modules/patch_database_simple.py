#!/usr/bin/env python3
"""Patch database.rs to add change_id function - simplified version"""

with open("database.rs", "r") as f:
    content = f.read()

# Find place to add change_id function (after is_device_banned)
marker = '''    pub async fn is_device_banned(&self, id: &str) -> ResultType<bool> {'''

new_function = '''    /// Change device ID in database (for ID change feature)
    pub async fn change_id(&self, old_id: &str, new_id: &str) -> ResultType<()> {
        let old = old_id.to_string();
        let new = new_id.to_string();
        let url = self.url.clone();
        
        let mut opt = SqliteConnectOptions::from_str(&url).unwrap();
        opt.log_statements(log::LevelFilter::Debug);
        let mut conn = SqliteConnection::connect_with(&opt).await?;
        
        // Simple update - just change the ID and record timestamp
        // The previous_ids tracking is already handled in http_api.rs
        sqlx::query("UPDATE peer SET id = ?, id_changed_at = datetime('now') WHERE id = ?")
            .bind(&new)
            .bind(&old)
            .execute(&mut conn)
            .await?;
        
        log::info!("Database: Changed ID {} -> {}", old, new);
        Ok(())
    }

    ''' + marker

if marker in content:
    content = content.replace(marker, new_function)
    with open("database.rs", "w") as f:
        f.write(content)
    print("SUCCESS: Added change_id function to database.rs")
else:
    print("ERROR: Could not find target marker in database.rs")
