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

const REG_TIMEOUT: i32 = 20_000;
const API_KEY_FILE: &str = "/opt/rustdesk/.api_key";

#[derive(Clone)]
pub struct ApiState {
    pub db_pool: SqlitePool,
    pub api_key: String,
}

#[derive(Serialize)]
struct PeerStatus {
    id: String,
    note: Option<String>,
    online: bool,
}

#[derive(Serialize)]
struct ApiResponse<T> {
    success: bool,
    data: Option<T>,
    error: Option<String>,
}

// Middleware to verify API key
fn verify_api_key(headers: &HeaderMap, state: &ApiState) -> Result<(), StatusCode> {
    match headers.get("X-API-Key") {
        Some(key) => {
            if key.to_str().unwrap_or("") == state.api_key {
                Ok(())
            } else {
                hbb_common::log::warn!("API: Invalid API key provided");
                Err(StatusCode::UNAUTHORIZED)
            }
        }
        None => {
            hbb_common::log::warn!("API: Missing X-API-Key header");
            Err(StatusCode::UNAUTHORIZED)
        }
    }
}

async fn get_online_peers(
    headers: HeaderMap,
    Extension(state): Extension<Arc<ApiState>>,
) -> Result<Json<ApiResponse<Vec<PeerStatus>>>, StatusCode> {
    // Verify API key
    verify_api_key(&headers, &state)?;
    match sqlx::query("SELECT id, note, info FROM peer WHERE (status IS NULL OR status = 0)")
        .fetch_all(&state.db_pool)
        .await
    {
        Ok(rows) => {
            let mut peers: Vec<PeerStatus> = Vec::new();
            
            for row in rows.iter() {
                let id: String = row.get("id");
                let note: Option<String> = row.get("note");
                let _info: String = row.get("info");
                
                // For now, mark all devices as offline since we can't determine online status from DB
                // Real online status requires querying the in-memory PeerMap which isn't accessible here
                let online = false;
                
                peers.push(PeerStatus {
                    id,
                    note,
                    online,
                });
            }

            Ok(Json(ApiResponse {
                success: true,
                data: Some(peers),
                error: None,
            }))
        }
        Err(e) => Ok(Json(ApiResponse {
            success: false,
            data: None,
            error: Some(e.to_string()),
        })),
    }
}

async fn health_check(
    headers: HeaderMap,
    Extension(state): Extension<Arc<ApiState>>,
) -> Result<Json<ApiResponse<String>>, StatusCode> {
    // Verify API key
    verify_api_key(&headers, &state)?;
    
    Ok(Json(ApiResponse {
        success: true,
        data: Some("RustDesk API is running".to_string()),
        error: None,
    }))
}

fn load_or_generate_api_key() -> String {
    // Try to read from file first
    if let Ok(key) = fs::read_to_string(API_KEY_FILE) {
        let key = key.trim().to_string();
        if !key.is_empty() {
            hbb_common::log::info!("API: Loaded API key from {}", API_KEY_FILE);
            return key;
        }
    }
    
    // Generate new key
    use hbb_common::rand::Rng;
    const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut rng = hbb_common::rand::thread_rng();
    let key: String = (0..64)
        .map(|_| {
            let idx = rng.gen_range(0..CHARSET.len());
            CHARSET[idx] as char
        })
        .collect();
    
    // Try to save to file
    if let Some(parent) = std::path::Path::new(API_KEY_FILE).parent() {
        let _ = fs::create_dir_all(parent);
    }
    
    if let Err(e) = fs::write(API_KEY_FILE, &key) {
        hbb_common::log::warn!("API: Could not save API key to file: {}", e);
    } else {
        hbb_common::log::info!("API: Generated and saved new API key to {}", API_KEY_FILE);
        // Set file permissions to 600 (owner read/write only)
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

pub async fn start_api_server(db_path: String, port: u16) -> Result<(), Box<dyn std::error::Error>> {
    use sqlx::sqlite::SqliteConnectOptions;
    use std::str::FromStr;
    
    let connect_options = SqliteConnectOptions::from_str(&format!("sqlite://{}", db_path))?
        .read_only(true)
        .create_if_missing(false);
    
    let pool = SqlitePool::connect_with(connect_options).await?;

    // Load or generate API key
    let api_key = load_or_generate_api_key();

    let state = Arc::new(ApiState { 
        db_pool: pool,
        api_key: api_key.clone(),
    });

    let app = Router::new()
        .route("/api/health", get(health_check))
        .route("/api/peers", get(get_online_peers))
        .layer(axum::Extension(state));

    // SECURITY UPDATE: Now binds to 0.0.0.0 (all interfaces) for LAN access
    // Protected by API key authentication (X-API-Key header required)
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    hbb_common::log::info!("HTTP API server listening on {} (LAN accessible, API key protected)", addr);
    hbb_common::log::info!("API key saved to: {}", API_KEY_FILE);
    hbb_common::log::info!("Use X-API-Key header with value from file for authentication");

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}
