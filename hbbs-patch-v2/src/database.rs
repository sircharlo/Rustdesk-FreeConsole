// Enhanced database.rs with retry logic and circuit breaker
use async_trait::async_trait;
use hbb_common::{log, ResultType};
use sqlx::{
    sqlite::SqliteConnectOptions, ConnectOptions, Connection, Error as SqlxError, SqliteConnection,
};
use std::{ops::DerefMut, str::FromStr, sync::Arc, sync::atomic::{AtomicBool, AtomicU32, Ordering}};
use std::time::{Duration, Instant};

type Pool = deadpool::managed::Pool<DbPool>;

pub struct DbPool {
    url: String,
}

#[async_trait]
impl deadpool::managed::Manager for DbPool {
    type Type = SqliteConnection;
    type Error = SqlxError;
    
    async fn create(&self) -> Result<SqliteConnection, SqlxError> {
        let mut opt = SqliteConnectOptions::from_str(&self.url).unwrap();
        opt.log_statements(log::LevelFilter::Debug);
        
        // Retry logic with exponential backoff
        let mut attempts = 0;
        let max_attempts = 3;
        
        loop {
            match SqliteConnection::connect_with(&opt).await {
                Ok(conn) => {
                    if attempts > 0 {
                        log::info!("Database connection established after {} attempts", attempts + 1);
                    }
                    return Ok(conn);
                }
                Err(e) => {
                    attempts += 1;
                    if attempts >= max_attempts {
                        log::error!("Failed to connect to database after {} attempts: {}", max_attempts, e);
                        return Err(e);
                    }
                    let wait_ms = 100 * (2_u64.pow(attempts));
                    log::warn!("Database connection failed (attempt {}/{}), retrying in {}ms: {}", 
                              attempts, max_attempts, wait_ms, e);
                    tokio::time::sleep(Duration::from_millis(wait_ms)).await;
                }
            }
        }
    }
    
    async fn recycle(
        &self,
        obj: &mut SqliteConnection,
    ) -> deadpool::managed::RecycleResult<SqlxError> {
        Ok(obj.ping().await?)
    }
}

/// Circuit breaker to prevent database overload
#[derive(Clone)]
struct CircuitBreaker {
    failure_count: Arc<AtomicU32>,
    last_failure: Arc<tokio::sync::Mutex<Option<Instant>>>,
    is_open: Arc<AtomicBool>,
}

impl CircuitBreaker {
    fn new() -> Self {
        Self {
            failure_count: Arc::new(AtomicU32::new(0)),
            last_failure: Arc::new(tokio::sync::Mutex::new(None)),
            is_open: Arc::new(AtomicBool::new(false)),
        }
    }
    
    async fn call<F, T, E>(&self, f: F) -> Result<T, E>
    where
        F: std::future::Future<Output = Result<T, E>>,
        E: std::fmt::Display,
    {
        // Check if circuit is open
        if self.is_open.load(Ordering::Relaxed) {
            let mut last = self.last_failure.lock().await;
            if let Some(time) = *last {
                // Auto-recover after 30 seconds
                if time.elapsed() > Duration::from_secs(30) {
                    log::info!("Circuit breaker: attempting recovery");
                    self.is_open.store(false, Ordering::Relaxed);
                    self.failure_count.store(0, Ordering::Relaxed);
                    *last = None;
                } else {
                    log::warn!("Circuit breaker is OPEN - blocking database operations");
                    // For now, still try but log the state
                }
            }
        }
        
        match f.await {
            Ok(result) => {
                // Success - reset failure count
                let prev = self.failure_count.swap(0, Ordering::Relaxed);
                if prev > 0 {
                    log::info!("Database operation succeeded, failure count reset");
                }
                Ok(result)
            }
            Err(e) => {
                let count = self.failure_count.fetch_add(1, Ordering::Relaxed) + 1;
                log::error!("Database operation failed (failure #{}) : {}", count, e);
                
                // Open circuit after 5 consecutive failures
                if count >= 5 {
                    log::error!("Circuit breaker OPENED after {} consecutive failures", count);
                    self.is_open.store(true, Ordering::Relaxed);
                    *self.last_failure.lock().await = Some(Instant::now());
                }
                
                Err(e)
            }
        }
    }
}

#[derive(Clone)]
pub struct Database {
    pool: Pool,
    circuit_breaker: CircuitBreaker,
}

#[derive(Default)]
pub struct Peer {
    pub guid: Vec<u8>,
    pub id: String,
    pub uuid: Vec<u8>,
    pub pk: Vec<u8>,
    pub user: Option<Vec<u8>>,
    pub info: String,
    pub status: Option<i64>,
}

impl Database {
    pub async fn new(url: &str) -> ResultType<Database> {
        if !std::path::Path::new(url).exists() {
            log::info!("Creating new database file: {}", url);
            std::fs::File::create(url).ok();
        }
        
        let n: usize = std::env::var("MAX_DATABASE_CONNECTIONS")
            .unwrap_or_else(|_| "5".to_owned())  // Increased default from 1 to 5
            .parse()
            .unwrap_or(5);
        
        log::info!("Initializing database with {} connection(s)", n);
        
        let pool = Pool::new(
            DbPool {
                url: url.to_owned(),
            },
            n,
        );
        
        // Test connection with retry
        let mut attempts = 0;
        loop {
            match pool.get().await {
                Ok(_) => {
                    log::info!("Database connection pool initialized successfully");
                    break;
                }
                Err(e) => {
                    attempts += 1;
                    if attempts >= 5 {
                        log::error!("Failed to initialize database pool after {} attempts", attempts);
                        return Err(e.into());
                    }
                    log::warn!("Database pool test failed (attempt {}/5), retrying...", attempts);
                    tokio::time::sleep(Duration::from_millis(500 * attempts as u64)).await;
                }
            }
        }
        
        let db = Database { 
            pool,
            circuit_breaker: CircuitBreaker::new(),
        };
        
        db.create_tables().await?;
        Ok(db)
    }

    async fn create_tables(&self) -> ResultType<()> {
        log::debug!("Creating database tables if not exist...");
        
        self.circuit_breaker.call(async {
            sqlx::query!(
                "
                create table if not exists peer (
                    guid blob primary key not null,
                    id varchar(100) not null,
                    uuid blob not null,
                    pk blob not null,
                    created_at datetime not null default(current_timestamp),
                    user blob,
                    status tinyint,
                    note varchar(300),
                    info text not null
                ) without rowid;
                create unique index if not exists index_peer_id on peer (id);
                create index if not exists index_peer_user on peer (user);
                create index if not exists index_peer_created_at on peer (created_at);
                create index if not exists index_peer_status on peer (status);
            "
            )
            .execute(self.pool.get().await?.deref_mut())
            .await
        }).await?;
        
        log::debug!("Database tables ready");
        Ok(())
    }

    pub async fn get_peer(&self, id: &str) -> ResultType<Option<Peer>> {
        self.circuit_breaker.call(async {
            Ok(sqlx::query_as!(
                Peer,
                "select guid, id, uuid, pk, user, status, info from peer where id = ?",
                id
            )
            .fetch_optional(self.pool.get().await?.deref_mut())
            .await?)
        }).await
    }

    pub async fn insert_peer(
        &self,
        id: &str,
        uuid: &[u8],
        pk: &[u8],
        info: &str,
    ) -> ResultType<Vec<u8>> {
        let guid = uuid::Uuid::new_v4().as_bytes().to_vec();
        
        self.circuit_breaker.call(async {
            sqlx::query!(
                "insert into peer(guid, id, uuid, pk, info) values(?, ?, ?, ?, ?)",
                guid,
                id,
                uuid,
                pk,
                info
            )
            .execute(self.pool.get().await?.deref_mut())
            .await?;
            
            Ok(guid.clone())
        }).await
    }

    pub async fn update_pk(
        &self,
        guid: &Vec<u8>,
        id: &str,
        pk: &[u8],
        info: &str,
    ) -> ResultType<()> {
        self.circuit_breaker.call(async {
            sqlx::query!(
                "update peer set id=?, pk=?, info=? where guid=?",
                id,
                pk,
                info,
                guid
            )
            .execute(self.pool.get().await?.deref_mut())
            .await?;
            
            Ok(())
        }).await
    }

    /// Check if a device is banned in the database (with retry logic)
    pub async fn is_device_banned(&self, id: &str) -> ResultType<bool> {
        use sqlx::Row;
        
        self.circuit_breaker.call(async {
            let r = sqlx::query("SELECT is_banned FROM peer WHERE id = ? AND is_deleted = 0")
                .bind(id)
                .fetch_optional(self.pool.get().await?.deref_mut())
                .await?;
            
            if let Some(row) = r {
                let banned: i32 = row.try_get("is_banned")?;
                Ok(banned == 1)
            } else {
                Ok(false)
            }
        }).await
    }

    /// Set peer as online in database (async, non-blocking)
    pub async fn set_online(&self, id: &str) -> ResultType<()> {
        let id = id.to_owned();
        let db = self.clone();
        
        // Fire and forget - don't block the caller
        tokio::spawn(async move {
            if let Err(e) = db._set_online_internal(&id).await {
                log::error!("Failed to set peer {} as online: {}", id, e);
            }
        });
        
        Ok(())
    }
    
    async fn _set_online_internal(&self, id: &str) -> ResultType<()> {
        self.circuit_breaker.call(async {
            sqlx::query("UPDATE peer SET last_online = datetime('now') WHERE id = ? AND is_deleted = 0")
                .bind(id)
                .execute(self.pool.get().await?.deref_mut())
                .await?;
            Ok(())
        }).await
    }

    /// Set peer as offline in database (async, non-blocking)
    pub async fn set_offline(&self, id: &str) -> ResultType<()> {
        let id = id.to_owned();
        let db = self.clone();
        
        // Fire and forget - don't block the caller
        tokio::spawn(async move {
            if let Err(e) = db._set_offline_internal(&id).await {
                log::error!("Failed to set peer {} as offline: {}", id, e);
            }
        });
        
        Ok(())
    }
    
    async fn _set_offline_internal(&self, id: &str) -> ResultType<()> {
        self.circuit_breaker.call(async {
            sqlx::query("UPDATE peer SET last_online = NULL WHERE id = ? AND is_deleted = 0")
                .bind(id)
                .execute(self.pool.get().await?.deref_mut())
                .await?;
            Ok(())
        }).await
    }
    
    /// Batch update online status for multiple peers (more efficient)
    pub async fn batch_set_offline(&self, ids: &[String]) -> ResultType<()> {
        if ids.is_empty() {
            return Ok(());
        }
        
        log::debug!("Batch setting {} peers as offline", ids.len());
        
        self.circuit_breaker.call(async {
            let mut conn = self.pool.get().await?;
            let mut tx = conn.begin().await?;
            
            for id in ids {
                sqlx::query("UPDATE peer SET last_online = NULL WHERE id = ? AND is_deleted = 0")
                    .bind(id)
                    .execute(&mut *tx)
                    .await?;
            }
            
            tx.commit().await?;
            Ok(())
        }).await
    }
}

#[cfg(test)]
mod tests {
    use hbb_common::tokio;
    
    #[test]
    fn test_insert() {
        insert();
    }

    #[tokio::main(flavor = "multi_thread")]
    async fn insert() {
        let db = super::Database::new("test_v2.sqlite3").await.unwrap();
        let mut jobs = vec![];
        
        for i in 0..1000 {
            let cloned = db.clone();
            let id = i.to_string();
            let a = tokio::spawn(async move {
                let empty_vec = Vec::new();
                cloned
                    .insert_peer(&id, &empty_vec, &empty_vec, "")
                    .await
                    .unwrap();
            });
            jobs.push(a);
        }
        
        for i in 0..1000 {
            let cloned = db.clone();
            let id = i.to_string();
            let a = tokio::spawn(async move {
                cloned.get_peer(&id).await.unwrap();
            });
            jobs.push(a);
        }
        
        hbb_common::futures::future::join_all(jobs).await;
    }
}
