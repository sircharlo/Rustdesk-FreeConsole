// Patch dla peer.rs - modyfikuje metodę update_pk
//
// Znajdź metodę `pub(crate) async fn update_pk(` w pliku peer.rs
// i zastąp jej początek (pierwszych ~20 linii) poniższym kodem:

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
        
        // *** NOWE: Sprawdzenie czy urządzenie jest zbanowane ***
        // Zapytanie do bazy danych przed akceptacją rejestracji
        match self.db.is_device_banned(&id).await {
            Ok(true) => {
                // Urządzenie jest zbanowane - odrzuć rejestrację
                log::warn!("Registration REJECTED for device {}: DEVICE IS BANNED", id);
                return register_pk_response::Result::UUID_MISMATCH;
            }
            Ok(false) => {
                // Urządzenie nie jest zbanowane - kontynuuj normalnie
                log::debug!("Ban check passed for device {}", id);
            }
            Err(e) => {
                // Błąd zapytania do bazy - loguj ale przepuść (fail-open policy)
                log::error!("Failed to check ban status for device {}: {}. Allowing registration (fail-open)", id, e);
                // Kontynuuj rejestrację mimo błędu bazy
            }
        }
        // *** KONIEC NOWEGO KODU ***
        
        // Oryginalna logika rejestracji (bez zmian):
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
        
        // ... reszta metody pozostaje bez zmian ...
