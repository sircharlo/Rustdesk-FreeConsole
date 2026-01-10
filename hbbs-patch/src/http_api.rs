use axum::{
    extract::Extension,
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use serde::Serialize;
use sqlx::{sqlite::SqlitePool, Row};
use std::net::SocketAddr;
use std::sync::Arc;
use crate::peer::PeerMap;

const REG_TIMEOUT: i32 = 20_000;

#[derive(Clone)]
pub struct ApiState {
    pub db_pool: SqlitePool,
    pub peer_map: Arc<PeerMap>,
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

async fn get_online_peers(
    Extension(state): Extension<Arc<ApiState>>,
) -> Result<Json<ApiResponse<Vec<PeerStatus>>>, StatusCode> {
    match sqlx::query("SELECT id, note FROM peer")
        .fetch_all(&state.db_pool)
        .await
    {
        Ok(rows) => {
            let mut peers: Vec<PeerStatus> = Vec::new();
            
            for row in rows.iter() {
                let id: String = row.get("id");
                let note: Option<String> = row.get("note");
                
                // Check real-time online status from PeerMap (same logic as RustDesk client)
                let online = if let Some(peer) = state.peer_map.get_in_memory(&id).await {
                    let elapsed = peer.read().await.last_reg_time.elapsed().as_millis() as i32;
                    elapsed < REG_TIMEOUT
                } else {
                    false
                };
                
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

async fn health_check() -> Json<ApiResponse<String>> {
    Json(ApiResponse {
        success: true,
        data: Some("RustDesk API is running".to_string()),
        error: None,
    })
}

pub async fn start_api_server(db_path: String, port: u16, peer_map: Arc<PeerMap>) -> Result<(), Box<dyn std::error::Error>> {
    use sqlx::sqlite::SqliteConnectOptions;
    use std::str::FromStr;
    
    let connect_options = SqliteConnectOptions::from_str(&format!("sqlite://{}", db_path))?
        .read_only(true)
        .create_if_missing(false);
    
    let pool = SqlitePool::connect_with(connect_options).await?;

    let state = Arc::new(ApiState { 
        db_pool: pool,
        peer_map,
    });

    let app = Router::new()
        .route("/api/health", get(health_check))
        .route("/api/peers", get(get_online_peers))
        .layer(axum::Extension(state));

    // SECURITY: Bind only to localhost (127.0.0.1) - not exposed to internet
    // Web console connects locally, so no need for external access
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    hbb_common::log::info!("HTTP API server listening on {} (localhost only)", addr);

    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await?;

    Ok(())
}
