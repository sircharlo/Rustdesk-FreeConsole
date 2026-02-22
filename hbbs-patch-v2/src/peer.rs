use crate::common::*;
use crate::database;
use hbb_common::{
    bytes::Bytes,
    log,
    rendezvous_proto::*,
    tokio::sync::{Mutex, RwLock},
    tokio,
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
    pub(crate) static ref ID_CHANGE_COOLDOWN: Mutex<HashMap<String, Instant>> = Default::default();
}

pub const IP_CHANGE_DUR: u64 = 180;
pub const IP_CHANGE_DUR_X2: u64 = IP_CHANGE_DUR * 2;
pub const DAY_SECONDS: u64 = 3600 * 24;
pub const IP_BLOCK_DUR: u64 = 60;

// Status tracking constants
const HEARTBEAT_TIMEOUT_SECS: u64 = 15;  // Mark offline after 15s without heartbeat (was 30s)
const CLEANUP_INTERVAL_SECS: u64 = 60;   // Check for stale peers every 60s
const ID_CHANGE_COOLDOWN_SECS: u64 = 300; // 5 minutes between ID changes per device

#[derive(Debug, Default, Serialize, Deserialize, Clone)]
pub(crate) struct PeerInfo {
    #[serde(default)]
    pub(crate) ip: String,
}

pub(crate) struct Peer {
    pub(crate) socket_addr: SocketAddr,
    pub(crate) last_reg_time: Instant,
    pub(crate) guid: Vec<u8>,
    pub(crate) uuid: Bytes,
    pub(crate) pk: Bytes,
    pub(crate) info: PeerInfo,
    pub(crate) reg_pk: (u32, Instant),
    // Track last heartbeat for online status
    pub(crate) last_heartbeat: Instant,
}

impl Default for Peer {
    fn default() -> Self {
        Self {
            socket_addr: "0.0.0.0:0".parse().unwrap(),
            last_reg_time: get_expired_time(),
            guid: Vec::new(),
            uuid: Bytes::new(),
            pk: Bytes::new(),
            info: Default::default(),
            reg_pk: (0, get_expired_time()),
            last_heartbeat: Instant::now(),
        }
    }
}

pub(crate) type LockPeer = Arc<RwLock<Peer>>;

/// Statistics about online peers
pub struct PeerStats {
    pub total: usize,
    pub healthy: usize,
    pub degraded: usize,
    pub critical: usize,
}

#[derive(Clone)]
pub(crate) struct PeerMap {
    map: Arc<RwLock<HashMap<String, LockPeer>>>,
    pub(crate) db: database::Database,
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
        log::info!("DB_URL={}", db);
        
        let database = database::Database::new(&db).await?;
        
        // Reset all devices to offline on startup (clean slate)
        if let Err(e) = database.set_all_offline().await {
            log::warn!("Failed to reset devices to offline: {}", e);
        }
        
        let pm = Self {
            map: Default::default(),
            db: database,
        };
        
        // Start background task to check for stale peers and set them offline
        let pm_clone = pm.clone();
        tokio::spawn(async move {
            pm_clone.status_cleanup_loop().await;
        });
        
        Ok(pm)
    }
    
    /// Background loop to detect stale peers and mark them offline
    async fn status_cleanup_loop(&self) {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(CLEANUP_INTERVAL_SECS));
        
        loop {
            interval.tick().await;
            
            let now = Instant::now();
            let timeout = std::time::Duration::from_secs(HEARTBEAT_TIMEOUT_SECS);
            let mut stale_peers = Vec::new();
            
            // Find stale peers
            {
                let map = self.map.read().await;
                for (id, peer) in map.iter() {
                    let peer_data = peer.read().await;
                    if now.duration_since(peer_data.last_heartbeat) > timeout {
                        stale_peers.push(id.clone());
                    }
                }
            }
            
            // Set stale peers offline and remove from memory
            if !stale_peers.is_empty() {
                log::info!("Marking {} stale peers as offline", stale_peers.len());
                
                // Batch update database
                if let Err(e) = self.db.batch_set_offline(&stale_peers).await {
                    log::error!("Failed to batch set offline: {}", e);
                }
                
                // Remove from memory map
                {
                    let mut map = self.map.write().await;
                    for id in &stale_peers {
                        map.remove(id);
                        log::debug!("Removed stale peer {} from memory", id);
                    }
                }
            }
            
            // Cleanup IP blocker and IP changes maps
            self.cleanup_ip_maps().await;
        }
    }
    
    /// Cleanup stale entries from IP maps
    async fn cleanup_ip_maps(&self) {
        let now = Instant::now();
        
        // Cleanup IP_BLOCKER
        {
            let mut blocker = IP_BLOCKER.lock().await;
            blocker.retain(|_, ((_, t1), (_, t2))| {
                now.duration_since(*t1).as_secs() < IP_BLOCK_DUR &&
                now.duration_since(*t2).as_secs() < DAY_SECONDS
            });
        }
        
        // Cleanup IP_CHANGES
        {
            let mut changes = IP_CHANGES.lock().await;
            changes.retain(|_, (t, _)| {
                now.duration_since(*t).as_secs() < IP_CHANGE_DUR_X2
            });
        }
    }

    /// Update heartbeat and set device online
    pub(crate) async fn touch_peer(&self, id: &str) {
        if let Some(peer) = self.map.read().await.get(id) {
            peer.write().await.last_heartbeat = Instant::now();
        }
        // Update database status
        self.db.set_online(id).await;
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
        log::info!("update_pk {} {:?} {:?} {:?}", id, addr, uuid, pk);

        // BAN CHECK: Verify device is not banned before registration
        match self.db.is_device_banned(&id).await {
            Ok(true) => {
                log::warn!("Registration REJECTED for device {}: DEVICE IS BANNED", id);
                self.map.write().await.remove(&id);
                return register_pk_response::Result::UUID_MISMATCH;
            }
            Ok(false) => {
                log::debug!("Ban check passed for device {}", id);
            }
            Err(e) => {
                log::error!("Failed to check ban status for device {}: {}. Allowing (fail-open)", id, e);
            }
        }
        
        let (info_str, guid) = {
            let mut w = peer.write().await;
            w.socket_addr = addr;
            w.uuid = uuid.clone();
            w.pk = pk.clone();
            w.last_reg_time = Instant::now();
            w.last_heartbeat = Instant::now();  // Update heartbeat on registration
            w.info.ip = ip;
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
                }
            }
        } else {
            if let Err(err) = self.db.update_pk(&guid, &id, &pk, &info_str).await {
                log::error!("db.update_pk failed: {}", err);
                return register_pk_response::Result::SERVER_ERROR;
            }
            log::info!("pk updated instead of insert");
        }
        
        // Device just registered, mark as online
        self.db.set_online(&id).await;
        
        register_pk_response::Result::OK
    }

    /// Handle ID change request from RegisterPk with old_id
    /// Validates format, rate limit, UUID match, new ID availability
    /// Updates database and in-memory peer map
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
                // TODO: Use register_pk_response::Result::ID_EXISTS when proto supports it
                log::info!("ID {} already exists, cannot change from {}", new_id, old_id);
                return register_pk_response::Result::UUID_MISMATCH;
            }
            Err(e) => {
                log::error!("Failed to check ID availability: {}", e);
                return register_pk_response::Result::SERVER_ERROR;
            }
        }

        // Also check memory map for the new_id
        if self.is_in_memory(&new_id).await {
            // TODO: Use register_pk_response::Result::ID_EXISTS when proto supports it
            log::info!("ID {} exists in memory, cannot change from {}", new_id, old_id);
            return register_pk_response::Result::UUID_MISMATCH;
        }

        // Perform database change
        if let Err(e) = self.db.change_peer_id(&old_id, &new_id).await {
            log::error!("Database ID change failed {} -> {}: {}", old_id, new_id, e);
            return register_pk_response::Result::SERVER_ERROR;
        }

        // Update memory map: remove old_id entry, insert with new_id
        {
            let mut map = self.map.write().await;
            if let Some(peer) = map.remove(&old_id) {
                {
                    let mut w = peer.write().await;
                    w.socket_addr = addr;
                    w.pk = pk;
                    w.last_reg_time = Instant::now();
                    w.last_heartbeat = Instant::now();
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

        // Mark new ID as online
        self.db.set_online(&new_id).await;

        log::info!("ID change successful: {} -> {}", old_id, new_id);
        register_pk_response::Result::OK
    }

    #[inline]
    pub(crate) async fn get(&self, id: &str) -> Option<LockPeer> {
        let p = self.map.read().await.get(id).cloned();
        if p.is_some() {
            return p;
        } else if let Ok(Some(v)) = self.db.get_peer(id).await {
            // BAN CHECK: Do not load banned devices into memory
            if let Ok(true) = self.db.is_device_banned(id).await {
                log::warn!("Blocked loading banned device {} from database", id);
                return None;
            }
            let peer = Peer {
                guid: v.guid,
                uuid: v.uuid.into(),
                pk: v.pk.into(),
                info: serde_json::from_str::<PeerInfo>(&v.info).unwrap_or_default(),
                last_heartbeat: Instant::now(),
                ..Default::default()
            };
            let peer = Arc::new(RwLock::new(peer));
            self.map.write().await.insert(id.to_owned(), peer.clone());
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

    /// Find device ID by socket address (for ban enforcement)
    pub(crate) async fn get_id_by_addr(&self, addr: SocketAddr) -> Option<String> {
        let map = self.map.read().await;
        for (id, peer) in map.iter() {
            let peer_addr = peer.read().await.socket_addr;
            if peer_addr == addr {
                return Some(id.clone());
            }
        }
        None
    }
    
    /// Get statistics about online peers  
    pub(crate) async fn get_stats(&self) -> PeerStats {
        let map = self.map.read().await;
        let total = map.len();
        let now = Instant::now();
        
        let timeout_secs = std::env::var("PEER_TIMEOUT_SECS")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(15);
        let warning_threshold = std::env::var("HEARTBEAT_WARNING_THRESHOLD")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(2);
        let critical_threshold = std::env::var("HEARTBEAT_CRITICAL_THRESHOLD")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(4);
        let heartbeat_interval = std::env::var("HEARTBEAT_INTERVAL_SECS")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(3);
        
        let mut healthy = 0;
        let mut degraded = 0;
        let mut critical = 0;
        
        for (_id, peer) in map.iter() {
            if let Ok(p) = peer.try_read() {
                let elapsed = now.duration_since(p.last_heartbeat).as_secs();
                if elapsed <= timeout_secs {
                    let missed = elapsed / heartbeat_interval;
                    if missed >= critical_threshold {
                        critical += 1;
                    } else if missed >= warning_threshold {
                        degraded += 1;
                    } else {
                        healthy += 1;
                    }
                }
            }
        }
        
        PeerStats { total, healthy, degraded, critical }
    }
    
    /// Check online peers and mark offline ones
    pub(crate) async fn check_online_peers(&self) {
        let timeout_secs = std::env::var("PEER_TIMEOUT_SECS")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(15);
        
        let now = Instant::now();
        let mut offline_peers = Vec::new();
        let mut online_peers = Vec::new();
        
        {
            let map = self.map.read().await;
            for (id, peer) in map.iter() {
                let p = peer.read().await;
                let elapsed = now.duration_since(p.last_heartbeat).as_secs();
                
                if elapsed > timeout_secs {
                    offline_peers.push(id.clone());
                } else {
                    online_peers.push(id.clone());
                }
            }
        }
        
        // Update online devices in database
        for id in &online_peers {
            self.db.set_online(id).await;
        }
        
        // Mark offline devices
        if !offline_peers.is_empty() {
            log::info!("Setting {} peers as offline (timeout {}s)", offline_peers.len(), timeout_secs);
            
            if let Err(e) = self.db.batch_set_offline(&offline_peers).await {
                log::error!("Batch offline update failed: {}", e);
                for id in &offline_peers {
                    self.db.set_offline(id).await;
                }
            }
            
            // Remove from memory
            let mut map = self.map.write().await;
            for id in offline_peers {
                map.remove(&id);
            }
        }
    }
}
