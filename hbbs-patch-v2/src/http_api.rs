// BetterDesk HTTP API v2.1.0
// Compatible with axum 0.5 and sqlx 0.6
// Added: POST /api/peers/:id/change-id endpoint

extern crate serde_json;

use axum::{
    extract::{Extension, Path},
    http::{StatusCode, HeaderMap},
    response::Json,
    routing::{get, post},
    Router,
};
use serde::{Serialize, Deserialize};
use sqlx::{sqlite::SqlitePool, Row};
use std::net::SocketAddr;
use std::sync::Arc;
use std::fs;
use std::time::Instant;

/// Get the API key file path.
/// Priority: 1) API_KEY_FILE env var  2) CWD-relative on Windows  3) /opt/rustdesk/.api_key on Linux
fn get_api_key_path() -> String {
    if let Ok(p) = std::env::var("API_KEY_FILE") {
        return p;
    }
    if cfg!(target_os = "windows") {
        // On Windows, use working directory (set to RUSTDESK_PATH by NSSM/ScheduledTask)
        ".api_key".to_string()
    } else {
        "/opt/rustdesk/.api_key".to_string()
    }
}

#[derive(Clone)]
pub struct ApiState {
    pub db_pool: SqlitePool,
    pub api_key: String,
    pub start_time: Instant,
}

#[derive(Serialize)]
struct PeerStatus {
    id: String,
    note: Option<String>,
    online: bool,
    last_online: Option<String>,
}

#[derive(Serialize)]
struct ApiResponse<T> {
    success: bool,
    data: Option<T>,
    error: Option<String>,
    timestamp: String,
}

#[derive(Serialize)]
struct HealthStatus {
    status: String,
    uptime_seconds: u64,
    version: String,
}

#[derive(Deserialize)]
struct ChangeIdRequest {
    new_id: String,
}

#[derive(Serialize)]
struct ChangeIdResponse {
    old_id: String,
    new_id: String,
    changed_at: String,
    previous_ids: Vec<String>,
}

fn verify_api_key(headers: &HeaderMap, state: &ApiState) -> Result<(), StatusCode> {
    match headers.get("X-API-Key") {
        Some(key) => {
            if key.to_str().unwrap_or("") == state.api_key {
                Ok(())
            } else {
                hbb_common::log::warn!("API: Invalid API key");
                Err(StatusCode::UNAUTHORIZED)
            }
        }
        None => {
            hbb_common::log::warn!("API: Missing X-API-Key header");
            Err(StatusCode::UNAUTHORIZED)
        }
    }
}

fn get_current_timestamp() -> String {
    chrono::Utc::now().to_rfc3339()
}

/// Check if a timestamp string is within the last N seconds (default 60s)
/// Supports formats: "YYYY-MM-DD HH:MM:SS" (SQLite) and RFC3339
fn is_online_recently(timestamp: &Option<String>, timeout_secs: i64) -> bool {
    match timestamp {
        Some(ts) => {
            // Try SQLite format first: "2026-02-06 14:00:27"
            if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(ts, "%Y-%m-%d %H:%M:%S") {
                let now = chrono::Utc::now().naive_utc();
                let diff = now.signed_duration_since(dt);
                return diff.num_seconds() < timeout_secs;
            }
            // Try RFC3339 format
            if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(ts) {
                let now = chrono::Utc::now();
                let diff = now.signed_duration_since(dt);
                return diff.num_seconds() < timeout_secs;
            }
            // If we can't parse, assume offline
            false
        }
        None => false,
    }
}

/// Default timeout for online status (60 seconds)
const ONLINE_TIMEOUT_SECS: i64 = 60;

async fn get_online_peers(
    headers: HeaderMap,
    Extension(state): Extension<Arc<ApiState>>,
) -> Result<Json<ApiResponse<Vec<PeerStatus>>>, StatusCode> {
    verify_api_key(&headers, &state)?;
    
    hbb_common::log::debug!("API: Fetching all peers");
    
    match sqlx::query(
        "SELECT id, note, last_online FROM peer WHERE is_deleted = 0"
    )
    .fetch_all(&state.db_pool)
    .await
    {
        Ok(rows) => {
            let mut peers: Vec<PeerStatus> = Vec::new();
            
            for row in rows.iter() {
                let id: String = row.get("id");
                let note: Option<String> = row.get("note");
                let last_online: Option<String> = row.get("last_online");
                let online = is_online_recently(&last_online, ONLINE_TIMEOUT_SECS);
                
                peers.push(PeerStatus {
                    id,
                    note,
                    online,
                    last_online,
                });
            }
            
            hbb_common::log::info!("API: Returned {} peers", peers.len());

            Ok(Json(ApiResponse {
                success: true,
                data: Some(peers),
                error: None,
                timestamp: get_current_timestamp(),
            }))
        }
        Err(e) => {
            hbb_common::log::error!("API: Database query failed: {}", e);
            Ok(Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Database error: {}", e)),
                timestamp: get_current_timestamp(),
            }))
        }
    }
}

async fn health_check(
    headers: HeaderMap,
    Extension(state): Extension<Arc<ApiState>>,
) -> Result<Json<ApiResponse<HealthStatus>>, StatusCode> {
    verify_api_key(&headers, &state)?;
    
    let uptime = state.start_time.elapsed().as_secs();
    
    Ok(Json(ApiResponse {
        success: true,
        data: Some(HealthStatus {
            status: "running".to_string(),
            uptime_seconds: uptime,
            version: "2.0.0".to_string(),
        }),
        error: None,
        timestamp: get_current_timestamp(),
    }))
}

async fn get_peer_details(
    headers: HeaderMap,
    Extension(state): Extension<Arc<ApiState>>,
    axum::extract::Path(peer_id): axum::extract::Path<String>,
) -> Result<Json<ApiResponse<PeerStatus>>, StatusCode> {
    verify_api_key(&headers, &state)?;
    
    hbb_common::log::debug!("API: Fetching details for peer {}", peer_id);
    
    match sqlx::query(
        "SELECT id, note, last_online FROM peer WHERE id = ? AND is_deleted = 0"
    )
    .bind(&peer_id)
    .fetch_optional(&state.db_pool)
    .await
    {
        Ok(Some(row)) => {
            let id: String = row.get("id");
            let note: Option<String> = row.get("note");
            let last_online: Option<String> = row.get("last_online");
            let online = is_online_recently(&last_online, ONLINE_TIMEOUT_SECS);
            
            Ok(Json(ApiResponse {
                success: true,
                data: Some(PeerStatus {
                    id,
                    note,
                    online,
                    last_online,
                }),
                error: None,
                timestamp: get_current_timestamp(),
            }))
        }
        Ok(None) => {
            Ok(Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Peer {} not found", peer_id)),
                timestamp: get_current_timestamp(),
            }))
        }
        Err(e) => {
            hbb_common::log::error!("API: Database query failed: {}", e);
            Ok(Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Database error: {}", e)),
                timestamp: get_current_timestamp(),
            }))
        }
    }
}

/// Change peer ID (admin endpoint)
/// POST /api/peers/:id/change-id
/// Body: { "new_id": "NEW123456" }
async fn change_peer_id(
    headers: HeaderMap,
    Extension(state): Extension<Arc<ApiState>>,
    Path(old_id): Path<String>,
    Json(payload): Json<ChangeIdRequest>,
) -> Result<Json<ApiResponse<ChangeIdResponse>>, StatusCode> {
    verify_api_key(&headers, &state)?;
    
    let new_id = payload.new_id.trim().to_uppercase();
    let old_id = old_id.trim().to_uppercase();
    
    hbb_common::log::info!("API: Change ID request: {} -> {}", old_id, new_id);
    
    // Validate new ID format (6-16 chars, alphanumeric/dash/underscore)
    if new_id.len() < 6 || new_id.len() > 16 {
        return Ok(Json(ApiResponse {
            success: false,
            data: None,
            error: Some("New ID must be 6-16 characters".to_string()),
            timestamp: get_current_timestamp(),
        }));
    }
    
    if !new_id.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        return Ok(Json(ApiResponse {
            success: false,
            data: None,
            error: Some("New ID can only contain letters, numbers, dash and underscore".to_string()),
            timestamp: get_current_timestamp(),
        }));
    }
    
    // Check if old_id exists
    let old_peer = sqlx::query("SELECT previous_ids FROM peer WHERE id = ? AND is_deleted = 0")
        .bind(&old_id)
        .fetch_optional(&state.db_pool)
        .await;
    
    let old_row = match old_peer {
        Ok(Some(row)) => row,
        Ok(None) => {
            return Ok(Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Peer '{}' not found", old_id)),
                timestamp: get_current_timestamp(),
            }));
        }
        Err(e) => {
            return Ok(Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Database error: {}", e)),
                timestamp: get_current_timestamp(),
            }));
        }
    };
    
    // Check if new_id already exists
    let new_exists = sqlx::query("SELECT 1 FROM peer WHERE id = ? AND is_deleted = 0")
        .bind(&new_id)
        .fetch_optional(&state.db_pool)
        .await;
    
    if let Ok(Some(_)) = new_exists {
        return Ok(Json(ApiResponse {
            success: false,
            data: None,
            error: Some(format!("ID '{}' is already in use", new_id)),
            timestamp: get_current_timestamp(),
        }));
    }
    
    // Get and update previous_ids
    let previous_ids_str: String = old_row.try_get("previous_ids").unwrap_or_default();
    let mut previous_ids: Vec<String> = if previous_ids_str.is_empty() {
        Vec::new()
    } else {
        serde_json::from_str(&previous_ids_str).unwrap_or_default()
    };
    previous_ids.push(old_id.clone());
    let updated_history = serde_json::to_string(&previous_ids).unwrap_or_default();
    
    let now = get_current_timestamp();
    
    // Perform the update
    let result = sqlx::query(
        "UPDATE peer SET id = ?, previous_ids = ?, id_changed_at = ? WHERE id = ? AND is_deleted = 0"
    )
        .bind(&new_id)
        .bind(&updated_history)
        .bind(&now)
        .bind(&old_id)
        .execute(&state.db_pool)
        .await;
    
    match result {
        Ok(res) if res.rows_affected() > 0 => {
            hbb_common::log::info!("API: ID changed successfully: {} -> {}", old_id, new_id);
            Ok(Json(ApiResponse {
                success: true,
                data: Some(ChangeIdResponse {
                    old_id,
                    new_id,
                    changed_at: now,
                    previous_ids,
                }),
                error: None,
                timestamp: get_current_timestamp(),
            }))
        }
        Ok(_) => {
            Ok(Json(ApiResponse {
                success: false,
                data: None,
                error: Some("No rows affected".to_string()),
                timestamp: get_current_timestamp(),
            }))
        }
        Err(e) => {
            hbb_common::log::error!("API: Failed to change ID: {}", e);
            Ok(Json(ApiResponse {
                success: false,
                data: None,
                error: Some(format!("Failed to change ID: {}", e)),
                timestamp: get_current_timestamp(),
            }))
        }
    }
}

fn load_or_generate_api_key() -> String {
    let api_key_file = get_api_key_path();
    
    if let Ok(key) = fs::read_to_string(&api_key_file) {
        let key = key.trim().to_string();
        if !key.is_empty() {
            hbb_common::log::info!("API: Loaded API key from {}", api_key_file);
            return key;
        }
    }
    
    use hbb_common::rand::Rng;
    const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut rng = hbb_common::rand::thread_rng();
    let key: String = (0..64)
        .map(|_| {
            let idx = rng.gen_range(0..CHARSET.len());
            CHARSET[idx] as char
        })
        .collect();
    
    if let Some(parent) = std::path::Path::new(&api_key_file).parent() {
        let _ = fs::create_dir_all(parent);
    }
    
    if let Err(e) = fs::write(&api_key_file, &key) {
        hbb_common::log::warn!("API: Could not save API key: {}", e);
    } else {
        hbb_common::log::info!("API: Generated new API key saved to {}", api_key_file);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if let Ok(metadata) = fs::metadata(&api_key_file) {
                let mut perms = metadata.permissions();
                perms.set_mode(0o600);
                let _ = fs::set_permissions(&api_key_file, perms);
            }
        }
    }
    
    key
}

pub async fn start_api_server(db_path: String, port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    use sqlx::sqlite::SqliteConnectOptions;
    use std::str::FromStr;
    
    hbb_common::log::info!("API: Initializing with database: {}", db_path);
    
    // Try to connect, but don't fail if DB doesn't exist yet
    let connect_options = match SqliteConnectOptions::from_str(&format!("sqlite://{}", db_path)) {
        Ok(opts) => opts.read_only(false).create_if_missing(false),
        Err(e) => {
            hbb_common::log::error!("API: Invalid database path: {}", e);
            return Err(e.into());
        }
    };
    
    let pool = match SqlitePool::connect_with(connect_options).await {
        Ok(p) => p,
        Err(e) => {
            hbb_common::log::warn!("API: Could not connect to database: {}. API will retry later.", e);
            // Wait and retry
            hbb_common::tokio::time::sleep(std::time::Duration::from_secs(10)).await;
            let opts = SqliteConnectOptions::from_str(&format!("sqlite://{}", db_path))?
                .read_only(false)
                .create_if_missing(false);
            SqlitePool::connect_with(opts).await?
        }
    };
    
    hbb_common::log::info!("API: Database connection pool created");

    let api_key = load_or_generate_api_key();

    let state = Arc::new(ApiState { 
        db_pool: pool,
        api_key,
        start_time: Instant::now(),
    });

    let app = Router::new()
        .route("/api/health", get(health_check))
        .route("/api/peers", get(get_online_peers))
        .route("/api/peers/:id", get(get_peer_details))
        .route("/api/peers/:id/change-id", post(change_peer_id))
        .layer(Extension(state));

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    
    hbb_common::log::info!("========================================");
    hbb_common::log::info!("HTTP API Server on port {}", port);
    hbb_common::log::info!("========================================");
    hbb_common::log::info!("Endpoints:");
    hbb_common::log::info!("  GET  /api/health");
    hbb_common::log::info!("  GET  /api/peers");
    hbb_common::log::info!("  GET  /api/peers/:id");
    hbb_common::log::info!("  POST /api/peers/:id/change-id");
    hbb_common::log::info!("========================================");

    // axum 0.5 uses Server::bind
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}
