// Enhanced peer.rs with improved heartbeat and monitoring
use crate::common::*;
use crate::database;
use hbb_common::{
    bytes::Bytes,
    log,
    rendezvous_proto::*,
    tokio::sync::{Mutex, RwLock},
    ResultType,
};
use serde_derive::{Deserialize, Serialize};
use std::{collections::HashMap, collections::HashSet, net::SocketAddr, sync::Arc, time::Instant};

type IpBlockMap = HashMap<String, ((u32, Instant), (HashSet<String>, Instant))>;
type UserStatusMap = HashMap<Vec<u8>, Arc<(Option<Vec<u8>>, bool)>>;
type IpChangesMap = HashMap<String, (Instant, HashMap<String, i32>)>;

lazy_static::lazy_static! {
    pub(crate) static ref IP_BLOCKER: Mutex<IpBlockMap> = Default::default();
    pub(crate) static ref USER_STATUS: RwLock<UserStatusMap> = Default::default();
    pub(crate) static ref IP_CHANGES: Mutex<IpChangesMap> = Default::default();
}

pub const IP_CHANGE_DUR: u64 = 180;
pub const IP_CHANGE_DUR_X2: u64 = IP_CHANGE_DUR * 2;
pub const DAY_SECONDS: u64 = 3600 * 24;
pub const IP_BLOCK_DUR: u64 = 60;

#[derive(Debug, Default, Serialize, Deserialize, Clone)]
pub(crate) struct PeerInfo {
    #[serde(default)]
    pub(crate) ip: String,
}

pub(crate) struct Peer {
    pub(crate) socket_addr: SocketAddr,
    pub(crate) last_reg_time: Instant,
    pub(crate) last_heartbeat: Instant,  // New: track last heartbeat separately
    pub(crate) guid: Vec<u8>,
    pub(crate) uuid: Bytes,
    pub(crate) pk: Bytes,
    pub(crate) info: PeerInfo,
    pub(crate) reg_pk: (u32, Instant),
    pub(crate) connection_quality: ConnectionQuality,  // New: track connection quality
}

#[derive(Debug, Clone)]
pub(crate) struct ConnectionQuality {
    pub(crate) last_response_time: Duration,
    pub(crate) missed_heartbeats: u32,
    pub(crate) total_heartbeats: u64,
}

impl Default for ConnectionQuality {
    fn default() -> Self {
        Self {
            last_response_time: Duration::from_millis(0),
            missed_heartbeats: 0,
            total_heartbeats: 0,
        }
    }
}

use std::time::Duration;

impl Default for Peer {
    fn default() -> Self {
        Self {
            socket_addr: "0.0.0.0:0".parse().unwrap(),
            last_reg_time: get_expired_time(),
            last_heartbeat: get_expired_time(),
            guid: Vec::new(),
            uuid: Bytes::new(),
            pk: Bytes::new(),
            info: Default::default(),
            reg_pk: (0, get_expired_time()),
            connection_quality: Default::default(),
        }
    }
}

pub(crate) type LockPeer = Arc<RwLock<Peer>>;

#[derive(Clone)]
pub(crate) struct PeerMap {
    map: Arc<RwLock<HashMap<String, LockPeer>>>,
    pub(crate) db: database::Database,
    last_cleanup: Arc<RwLock<Instant>>,
}

impl PeerMap {
    pub(crate) async fn new() -> ResultType<Self> {
        let db = std::env::var("DB_URL").unwrap_or({
            let mut db = "db_v2.sqlite3".to_owned();
            #[cfg(all(windows, not(debug_assertions)))]
            {
                if let Some(path) = hbb_common::config::Config::icon_path().parent() {
                    db = format!("{}\\{}", path.to_str().unwrap_or("."), db);
                }
            }
            #[cfg(not(windows))]
            {
                db = format!("./{db}");
            }
            db
        });
        
        log::info!("Initializing PeerMap with DB: {}", db);
        let pm = Self {
            map: Default::default(),
            db: database::Database::new(&db).await?,
            last_cleanup: Arc::new(RwLock::new(Instant::now())),
        };
        Ok(pm)
    }

    #[inline]
    pub(crate) async fn update_pk(
        &mut self,
        id: String,
        peer: LockPeer,
        addr: SocketAddr,
        uuid: Bytes,
        pk: Bytes,
        ip: String,
    ) -> register_pk_response::Result {
        log::debug!("update_pk {} {:?}", id, addr);
        
        let (info_str, guid) = {
            let mut w = peer.write().await;
            w.socket_addr = addr;
            w.uuid = uuid.clone();
            w.pk = pk.clone();
            w.last_reg_time = Instant::now();
            w.last_heartbeat = Instant::now();
            w.info.ip = ip;
            w.connection_quality.total_heartbeats += 1;
            w.connection_quality.missed_heartbeats = 0;  // Reset on successful registration
            
            (
                serde_json::to_string(&w.info).unwrap_or_default(),
                w.guid.clone(),
            )
        };
        
        if guid.is_empty() {
            match self.db.insert_peer(&id, &uuid, &pk, &info_str).await {
                Err(err) => {
                    log::error!("db.insert_peer failed: {}", err);
                    return register_pk_response::Result::SERVER_ERROR;
                }
                Ok(guid) => {
                    peer.write().await.guid = guid;
                    log::info!("New peer registered: {}", id);
                }
            }
        } else {
            if let Err(err) = self.db.update_pk(&guid, &id, &pk, &info_str).await {
                log::error!("db.update_pk failed: {}", err);
                return register_pk_response::Result::SERVER_ERROR;
            }
            log::debug!("Peer {} updated", id);
        }
        
        // Set peer status to online (async, non-blocking)
        if let Err(err) = self.db.set_online(&id).await {
            log::error!("db.set_online failed for {}: {}", id, err);
        }
        
        register_pk_response::Result::OK
    }

    #[inline]
    pub(crate) async fn get(&self, id: &str) -> Option<LockPeer> {
        let p = self.map.read().await.get(id).cloned();
        if p.is_some() {
            return p;
        } else if let Ok(Some(v)) = self.db.get_peer(id).await {
            let peer = Peer {
                guid: v.guid,
                uuid: v.uuid.into(),
                pk: v.pk.into(),
                info: serde_json::from_str::<PeerInfo>(&v.info).unwrap_or_default(),
                ..Default::default()
            };
            let peer = Arc::new(RwLock::new(peer));
            self.map.write().await.insert(id.to_owned(), peer.clone());
            log::debug!("Peer {} loaded from database", id);
            return Some(peer);
        }
        None
    }

    #[inline]
    pub(crate) async fn get_or(&self, id: &str) -> LockPeer {
        if let Some(p) = self.get(id).await {
            return p;
        }
        let mut w = self.map.write().await;
        if let Some(p) = w.get(id) {
            return p.clone();
        }
        let tmp = LockPeer::default();
        w.insert(id.to_owned(), tmp.clone());
        tmp
    }

    #[inline]
    pub(crate) async fn get_in_memory(&self, id: &str) -> Option<LockPeer> {
        self.map.read().await.get(id).cloned()
    }

    #[inline]
    pub(crate) async fn is_in_memory(&self, id: &str) -> bool {
        self.map.read().await.contains_key(id)
    }

    #[inline]
    pub(crate) async fn set_offline(&self, id: &str) {
        if let Err(err) = self.db.set_offline(id).await {
            log::error!("db.set_offline failed for {}: {}", id, err);
        }
    }

    /// Enhanced peer checking with configurable timeout and better logging
    pub(crate) async fn check_online_peers(&self) {
        // Get configurable timeout from environment (default 15 seconds)
        let timeout_secs = std::env::var("PEER_TIMEOUT_SECS")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(15);  // Reduced from 20 to 15 seconds
        
        let now = Instant::now();
        let mut offline_peers = Vec::new();
        let mut total_peers = 0;
        let mut degraded_peers = 0;
        
        {
            let map = self.map.read().await;
            total_peers = map.len();
            
            for (id, peer) in map.iter() {
                let p = peer.read().await;
                let last_heartbeat = p.last_heartbeat;
                let elapsed = now.duration_since(last_heartbeat).as_secs();
                
                // Check connection quality
                if p.connection_quality.missed_heartbeats > 2 {
                    degraded_peers += 1;
                    log::warn!("Peer {} has degraded connection (missed {} heartbeats)", 
                              id, p.connection_quality.missed_heartbeats);
                }
                
                if elapsed > timeout_secs {
                    offline_peers.push((id.clone(), elapsed));
                }
            }
        }
        
        if !offline_peers.is_empty() {
            log::info!("Found {} offline peers (total: {}, degraded: {})", 
                      offline_peers.len(), total_peers, degraded_peers);
            
            // Batch offline updates for better performance
            let ids: Vec<String> = offline_peers.iter().map(|(id, _)| id.clone()).collect();
            if let Err(e) = self.db.batch_set_offline(&ids).await {
                log::error!("Batch offline update failed: {}", e);
                // Fallback to individual updates
                for (id, elapsed) in &offline_peers {
                    log::info!("Setting peer {} as offline (last seen {}s ago)", id, elapsed);
                    self.set_offline(id).await;
                }
            }
            
            // Remove from memory
            let mut map = self.map.write().await;
            for (id, _) in offline_peers {
                map.remove(&id);
            }
        } else if total_peers > 0 {
            log::debug!("All {} peers are online", total_peers);
        }
        
        // Periodic cleanup of stale entries
        self.periodic_cleanup().await;
    }
    
    /// Periodic cleanup of old entries to prevent memory leaks
    async fn periodic_cleanup(&self) {
        let mut last = self.last_cleanup.write().await;
        
        // Run cleanup every 5 minutes
        if last.elapsed().as_secs() < 300 {
            return;
        }
        
        log::info!("Running periodic cleanup...");
        *last = Instant::now();
        
        // Cleanup IP blocker
        let mut ip_blocker = IP_BLOCKER.lock().await;
        let before = ip_blocker.len();
        ip_blocker.retain(|_, (a, b)| {
            a.1.elapsed().as_secs() <= IP_BLOCK_DUR
                || b.1.elapsed().as_secs() <= DAY_SECONDS
        });
        let removed = before - ip_blocker.len();
        if removed > 0 {
            log::info!("Cleaned up {} entries from IP blocker", removed);
        }
        drop(ip_blocker);
        
        // Cleanup IP changes
        let mut ip_changes = IP_CHANGES.lock().await;
        let before = ip_changes.len();
        ip_changes.retain(|_, v| v.0.elapsed().as_secs() < IP_CHANGE_DUR_X2 && v.1.len() > 1);
        let removed = before - ip_changes.len();
        if removed > 0 {
            log::info!("Cleaned up {} entries from IP changes tracker", removed);
        }
    }

    /// Update heartbeat for a peer (lightweight operation)
    #[inline]
    pub(crate) async fn update_heartbeat(&self, id: &str) -> bool {
        if let Some(peer) = self.get_in_memory(id).await {
            let mut p = peer.write().await;
            p.last_heartbeat = Instant::now();
            p.connection_quality.total_heartbeats += 1;
            p.connection_quality.missed_heartbeats = 0;
            true
        } else {
            false
        }
    }
    
    /// Record a missed heartbeat
    #[inline]
    pub(crate) async fn record_missed_heartbeat(&self, id: &str) {
        if let Some(peer) = self.get_in_memory(id).await {
            let mut p = peer.write().await;
            p.connection_quality.missed_heartbeats += 1;
            if p.connection_quality.missed_heartbeats > 3 {
                log::warn!("Peer {} has missed {} consecutive heartbeats", 
                          id, p.connection_quality.missed_heartbeats);
            }
        }
    }

    /// Find peer ID by socket address
    #[inline]
    pub(crate) async fn find_by_addr(&self, addr: SocketAddr) -> Option<String> {
        let map = self.map.read().await;
        for (id, peer) in map.iter() {
            let peer_addr = peer.read().await.socket_addr;
            if peer_addr == addr {
                return Some(id.clone());
            }
        }
        None
    }
    
    /// Get statistics about current peers
    pub(crate) async fn get_stats(&self) -> PeerMapStats {
        let map = self.map.read().await;
        let total = map.len();
        let mut healthy = 0;
        let mut degraded = 0;
        let mut critical = 0;
        
        for (_, peer) in map.iter() {
            let p = peer.read().await;
            match p.connection_quality.missed_heartbeats {
                0..=1 => healthy += 1,
                2..=3 => degraded += 1,
                _ => critical += 1,
            }
        }
        
        PeerMapStats {
            total,
            healthy,
            degraded,
            critical,
        }
    }
}

#[derive(Debug)]
pub(crate) struct PeerMapStats {
    pub total: usize,
    pub healthy: usize,
    pub degraded: usize,
    pub critical: usize,
}
