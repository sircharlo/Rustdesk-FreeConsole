// BetterDesk HTTP API v2.0.0
// Compatible with axum 0.5 and sqlx 0.6

use axum::{
    extract::Extension,
    http::{StatusCode, HeaderMap},
    response::Json,
    routing::get,
    Router,
};
use serde::Serialize;
use sqlx::{sqlite::SqlitePool, Row};
use std::net::SocketAddr;
use std::sync::Arc;
use std::fs;
use std::time::Instant;

const API_KEY_FILE: &str = "/opt/rustdesk/.api_key";

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

async fn get_online_peers(
    headers: HeaderMap,
    Extension(state): Extension<Arc<ApiState>>,
) -> Result<Json<ApiResponse<Vec<PeerStatus>>>, StatusCode> {
    verify_api_key(&headers, &state)?;
    
    hbb_common::log::debug!("API: Fetching online peers");
    
    match sqlx::query(
        "SELECT id, note, last_online FROM peer WHERE (status IS NULL OR status = 0) AND is_deleted = 0"
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
                let online = last_online.is_some();
                
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
            let online = last_online.is_some();
            
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

fn load_or_generate_api_key() -> String {
    if let Ok(key) = fs::read_to_string(API_KEY_FILE) {
        let key = key.trim().to_string();
        if !key.is_empty() {
            hbb_common::log::info!("API: Loaded API key from {}", API_KEY_FILE);
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
    
    if let Some(parent) = std::path::Path::new(API_KEY_FILE).parent() {
        let _ = fs::create_dir_all(parent);
    }
    
    if let Err(e) = fs::write(API_KEY_FILE, &key) {
        hbb_common::log::warn!("API: Could not save API key: {}", e);
    } else {
        hbb_common::log::info!("API: Generated new API key saved to {}", API_KEY_FILE);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if let Ok(metadata) = fs::metadata(API_KEY_FILE) {
                let mut perms = metadata.permissions();
                perms.set_mode(0o600);
                let _ = fs::set_permissions(API_KEY_FILE, perms);
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
        Ok(opts) => opts.read_only(true).create_if_missing(false),
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
                .read_only(true)
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
        .layer(Extension(state));

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    
    hbb_common::log::info!("========================================");
    hbb_common::log::info!("HTTP API Server on port {}", port);
    hbb_common::log::info!("========================================");
    hbb_common::log::info!("Endpoints:");
    hbb_common::log::info!("  GET /api/health");
    hbb_common::log::info!("  GET /api/peers");
    hbb_common::log::info!("  GET /api/peers/:id");
    hbb_common::log::info!("========================================");

    // axum 0.5 uses Server::bind
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}
