use async_trait::async_trait;
use hbb_common::{log, ResultType, tokio};
use sqlx::{
    sqlite::SqliteConnectOptions, ConnectOptions, Connection, Error as SqlxError, SqliteConnection,
};
use std::{ops::DerefMut, str::FromStr, sync::Arc};
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
        SqliteConnection::connect_with(&opt).await
    }
    async fn recycle(
        &self,
        obj: &mut SqliteConnection,
    ) -> deadpool::managed::RecycleResult<SqlxError> {
        Ok(obj.ping().await?)
    }
}

#[derive(Clone)]
pub struct Database {
    pool: Pool,
    url: String,
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
            std::fs::File::create(url).ok();
        }
        let n: usize = std::env::var("MAX_DATABASE_CONNECTIONS")
            .unwrap_or_else(|_| "5".to_owned())  // Increased from 1 to 5
            .parse()
            .unwrap_or(5);
        log::info!("MAX_DATABASE_CONNECTIONS={}", n);
        let pool = Pool::new(
            DbPool {
                url: url.to_owned(),
            },
            n,
        );
        let _ = pool.get().await?; // test
        let db = Database { 
            pool, 
            url: url.to_owned(),
        };
        db.create_tables().await?;
        Ok(db)
    }

    async fn create_tables(&self) -> ResultType<()> {
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
        .await?;
        Ok(())
    }

    pub async fn get_peer(&self, id: &str) -> ResultType<Option<Peer>> {
        Ok(sqlx::query_as!(
            Peer,
            "select guid, id, uuid, pk, user, status, info from peer where id = ?",
            id
        )
        .fetch_optional(self.pool.get().await?.deref_mut())
        .await?)
    }

    pub async fn insert_peer(
        &self,
        id: &str,
        uuid: &[u8],
        pk: &[u8],
        info: &str,
    ) -> ResultType<Vec<u8>> {
        let guid = uuid::Uuid::new_v4().as_bytes().to_vec();
        sqlx::query!(
            "insert into peer(guid, id, uuid, pk, info, status, last_online) values(?, ?, ?, ?, ?, 1, datetime('now'))",
            guid,
            id,
            uuid,
            pk,
            info
        )
        .execute(self.pool.get().await?.deref_mut())
        .await?;
        log::info!("New peer {} inserted with status=1 (online)", id);
        Ok(guid)
    }

    pub async fn update_pk(
        &self,
        guid: &Vec<u8>,
        id: &str,
        pk: &[u8],
        info: &str,
    ) -> ResultType<()> {
        sqlx::query!(
            "update peer set id=?, pk=?, info=?, status=1, last_online=datetime('now') where guid=?",
            id,
            pk,
            info,
            guid
        )
        .execute(self.pool.get().await?.deref_mut())
        .await?;
        log::debug!("Peer {} updated pk, set status=1, last_online=now", id);
        Ok(())
    }

    /// Set device status to online and update last_online timestamp
    /// Called when device registers or sends heartbeat
    pub async fn set_online(&self, id: &str) {
        let id_owned = id.to_string();
        let url = self.url.clone();
        
        // Fire and forget - don't block the main flow
        tokio::spawn(async move {
            if let Err(e) = Self::set_online_internal(&url, &id_owned).await {
                log::warn!("Failed to set {} online: {}", id_owned, e);
            }
        });
    }
    
    async fn set_online_internal(url: &str, id: &str) -> ResultType<()> {
        let mut opt = SqliteConnectOptions::from_str(url).unwrap();
        opt.log_statements(log::LevelFilter::Debug);
        let mut conn = SqliteConnection::connect_with(&opt).await?;
        
        sqlx::query!(
            "UPDATE peer SET status = 1, last_online = datetime('now') WHERE id = ?",
            id
        )
        .execute(&mut conn)
        .await?;
        
        log::trace!("Set {} online, last_online updated", id);
        Ok(())
    }
    
    /// Set device status to offline
    /// Called when device times out or disconnects
    pub async fn set_offline(&self, id: &str) {
        let id_owned = id.to_string();
        let url = self.url.clone();
        
        // Fire and forget
        tokio::spawn(async move {
            if let Err(e) = Self::set_offline_internal(&url, &id_owned).await {
                log::warn!("Failed to set {} offline: {}", id_owned, e);
            }
        });
    }
    
    async fn set_offline_internal(url: &str, id: &str) -> ResultType<()> {
        let mut opt = SqliteConnectOptions::from_str(url).unwrap();
        opt.log_statements(log::LevelFilter::Debug);
        let mut conn = SqliteConnection::connect_with(&opt).await?;
        
        sqlx::query!(
            "UPDATE peer SET status = 0 WHERE id = ?",
            id
        )
        .execute(&mut conn)
        .await?;
        
        log::debug!("Set {} offline", id);
        Ok(())
    }
    
    /// Set all devices offline - called on server startup to reset stale status
    pub async fn set_all_offline(&self) -> ResultType<()> {
        sqlx::query!(
            "UPDATE peer SET status = 0 WHERE status = 1"
        )
        .execute(self.pool.get().await?.deref_mut())
        .await?;
        
        log::info!("Reset all devices to offline status on startup");
        Ok(())
    }
    
    /// Set multiple devices offline in a single transaction (batch operation)
    pub async fn batch_set_offline(&self, ids: &[String]) -> ResultType<()> {
        if ids.is_empty() {
            return Ok(());
        }
        
        let mut conn = self.pool.get().await?;
        
        for id in ids {
            sqlx::query!(
                "UPDATE peer SET status = 0 WHERE id = ?",
                id
            )
            .execute(conn.deref_mut())
            .await?;
        }
        
        log::debug!("Batch set {} devices offline", ids.len());
        Ok(())
    }

    /// Check if a device is banned in the database
    /// Returns true if device has is_banned=1, false otherwise
    /// Uses synchronous rusqlite to avoid nested Tokio runtime panic
    pub async fn is_device_banned(&self, id: &str) -> ResultType<bool> {
        let db_path = self.url.clone();
        let id = id.to_string();
        
        // Use spawn_blocking to run synchronous rusqlite code
        let result = tokio::task::spawn_blocking(move || -> ResultType<bool> {
            let conn = rusqlite::Connection::open(&db_path)?;
            let mut stmt = conn.prepare("SELECT is_banned FROM peer WHERE id = ?")?;
            let is_banned: Option<i32> = stmt
                .query_row([&id], |row| row.get(0))
                .unwrap_or(None);
            Ok(is_banned == Some(1))
        }).await?;
        
        result
    }
}
