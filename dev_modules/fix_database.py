#!/usr/bin/env python3
"""Fix database.rs imports and change_id function"""

with open("database.rs", "r") as f:
    content = f.read()

# Fix import
old_import = '''use sqlx::Row;\\nuse sqlx::{'''
new_import = '''use sqlx::{
    Row,'''

content = content.replace(old_import, new_import)

# Also fix the get call and closure
old_code = '''            let prev: Option<String> = r.get("previous_ids");
            prev.and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()'''

new_code = '''            let prev: Option<String> = r.get("previous_ids");
            prev.and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()'''

# Just rewrite the function properly
old_func = '''    /// Change device ID in database
    pub async fn change_id(&self, old_id: &str, new_id: &str) -> ResultType<()> {
        let old = old_id.to_string();
        let new = new_id.to_string();
        let url = self.url.clone();
        
        let mut opt = SqliteConnectOptions::from_str(&url).unwrap();
        opt.log_statements(log::LevelFilter::Debug);
        let mut conn = SqliteConnection::connect_with(&opt).await?;
        
        // Get current previous_ids
        let row = sqlx::query("SELECT previous_ids FROM peer WHERE id = ?")
            .bind(&old)
            .fetch_optional(&mut conn)
            .await?;
        
        let mut prev_ids: Vec<String> = if let Some(r) = row {
            let prev: Option<String> = r.get("previous_ids");
            prev.and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
        } else {
            Vec::new()
        };
        
        // Add old_id to history
        if !prev_ids.contains(&old) {
            prev_ids.push(old.clone());
        }
        
        let prev_json = serde_json::to_string(&prev_ids).unwrap_or("[]".to_string());
        
        // Update ID
        sqlx::query("UPDATE peer SET id = ?, previous_ids = ?, id_changed_at = datetime('now') WHERE id = ?")
            .bind(&new)
            .bind(&prev_json)
            .bind(&old)
            .execute(&mut conn)
            .await?;
        
        log::info!("Database: Changed ID {} -> {}", old, new);
        Ok(())
    }'''

new_func = '''    /// Change device ID in database
    pub async fn change_id(&self, old_id: &str, new_id: &str) -> ResultType<()> {
        let old = old_id.to_string();
        let new = new_id.to_string();
        let url = self.url.clone();
        
        let mut opt = SqliteConnectOptions::from_str(&url).unwrap();
        opt.log_statements(log::LevelFilter::Debug);
        let mut conn = SqliteConnection::connect_with(&opt).await?;
        
        // Get current previous_ids
        let row: Option<(Option<String>,)> = sqlx::query_as("SELECT previous_ids FROM peer WHERE id = ?")
            .bind(&old)
            .fetch_optional(&mut conn)
            .await?;
        
        let mut prev_ids: Vec<String> = match row {
            Some((Some(s),)) => serde_json::from_str(&s).unwrap_or_default(),
            _ => Vec::new()
        };
        
        // Add old_id to history
        if !prev_ids.contains(&old) {
            prev_ids.push(old.clone());
        }
        
        let prev_json = serde_json::to_string(&prev_ids).unwrap_or("[]".to_string());
        
        // Update ID
        sqlx::query("UPDATE peer SET id = ?, previous_ids = ?, id_changed_at = datetime('now') WHERE id = ?")
            .bind(&new)
            .bind(&prev_json)
            .bind(&old)
            .execute(&mut conn)
            .await?;
        
        log::info!("Database: Changed ID {} -> {}", old, new);
        Ok(())
    }'''

content = content.replace(old_func, new_func)

with open("database.rs", "w") as f:
    f.write(content)

print("Fixed database.rs")
