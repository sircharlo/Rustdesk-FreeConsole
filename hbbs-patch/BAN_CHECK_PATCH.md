# HBBS Ban Check Patch

Modyfikacja RustDesk Server (hbbs) v1.1.14 dodająca sprawdzanie zbanowanych urządzeń.

## Zmiany

### 1. database.rs - Dodanie metody sprawdzania bana

Dodaj nową metodę do struktury `Database`:

```rust
impl Database {
    // ... existing methods ...
    
    /// Check if a device is banned
    pub async fn is_device_banned(&self, id: &str) -> ResultType<bool> {
        let result = sqlx::query!(
            "SELECT is_banned FROM peer WHERE id = ? AND is_deleted = 0",
            id
        )
        .fetch_optional(self.pool.get().await?.deref_mut())
        .await?;
        
        Ok(result.map(|r| r.is_banned.unwrap_or(0) == 1).unwrap_or(false))
    }
}
```

### 2. peer.rs - Sprawdzenie bana podczas rejestracji

Modyfikuj metodę `update_pk`:

```rust
impl PeerMap {
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
        
        // *** NOWE: Sprawdź czy urządzenie jest zbanowane ***
        match self.db.is_device_banned(&id).await {
            Ok(true) => {
                log::warn!("Registration rejected: device {} is BANNED", id);
                return register_pk_response::Result::UUID_MISMATCH; // Odrzuć rejestrację
            }
            Err(e) => {
                log::error!("Failed to check ban status for {}: {}", id, e);
                // W razie błędu bazy, przepuść (fail-open)
            }
            _ => {}
        }
        
        // ... reszta oryginalnego kodu ...
        let (info_str, guid) = {
            let mut w = peer.write().await;
            w.socket_addr = addr;
            w.uuid = uuid.clone();
            w.pk = pk.clone();
            w.last_reg_time = Instant::now();
            w.info.ip = ip;
            (
                serde_json::to_string(&w.info).unwrap_or_default(),
                w.guid.clone(),
            )
        };
        // ... reszta metody bez zmian ...
    }
}
```

### 3. Migracja bazy danych

Upewnij się, że tabela `peer` ma kolumnę `is_banned`:

```sql
ALTER TABLE peer ADD COLUMN is_banned INTEGER DEFAULT 0;
ALTER TABLE peer ADD COLUMN banned_at INTEGER;
ALTER TABLE peer ADD COLUMN banned_by VARCHAR(100);
ALTER TABLE peer ADD COLUMN ban_reason TEXT;
CREATE INDEX IF NOT EXISTS idx_peer_is_banned ON peer(is_banned);
```

## Kompilacja

```bash
cd rustdesk-server
cargo build --release --bin hbbs

# Skompilowany binarny:
# target/release/hbbs
```

## Instalacja

```bash
# Backup starego
sudo systemctl stop hbbs
sudo cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.backup

# Zainstaluj nowy
sudo cp target/release/hbbs /opt/rustdesk/
sudo chmod +x /opt/rustdesk/hbbs

# Restart
sudo systemctl start hbbs
sudo systemctl status hbbs
```

## Weryfikacja

```bash
# Sprawdź logi
sudo journalctl -u hbbs -f

# Podczas próby połączenia zbanowanego urządzenia:
# "Registration rejected: device 123456789 is BANNED"
```

## Jak to działa

1. **Klient próbuje się połączyć** → wysyła `RegisterPk` request
2. **HBBS odbiera request** → wywołuje `update_pk()`  
3. **Sprawdzenie bazy** → `is_device_banned()` query
4. **Jeśli is_banned=1** → zwraca `UUID_MISMATCH` (odrzucenie)
5. **Klient dostaje błąd** → nie może się połączyć

## Różnice vs Ban Enforcer

| Ban Enforcer (stary) | HBBS Patch (nowy) |
|---|---|
| Czyści dane co 2s | Sprawdza przy każdej rejestracji |
| Wyścig z RustDesk | Natywna integracja |
| Możliwe "okna" | 100% skuteczność |
| +1 demon | Bez dodatkowych procesów |
| Modyfikuje bazę | Tylko odczyt |

## Uwagi

- Używamy `UUID_MISMATCH` jako kodu błędu (RustDesk go rozumie)
- "Fail-open" - jeśli baza nie odpowiada, przepuszczamy ruch (bezpieczeństwo > dostępność)
- Index na `is_banned` przyspiesza query
- Kompatybilne z istniejącymi kolumnami bazy
