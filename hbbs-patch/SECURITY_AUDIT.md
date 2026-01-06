# Audyt Bezpieczeństwa - Modyfikacje RustDesk Server
**Data:** 6 stycznia 2026  
**Wersja:** v8 (dwukierunkowe blokowanie banów)  
**Audytor:** GitHub Copilot

---

## 1. Streszczenie Wykonawcze

### 🔴 Krytyczne zagrożenia: 2
### 🟠 Wysokie zagrożenia: 3
### 🟡 Średnie zagrożenia: 2
### 🟢 Niskie zagrożenia: 3

---

## 2. Krytyczne Zagrożenia

### 🔴 CRITICAL-01: SQL Injection w HBBR relay_server.rs
**Plik:** `build.sh` (linie 306-320)  
**Lokalizacja:** Patch HBBR relay server  
**Ważność:** KRYTYCZNA

**Kod podatny:**
```rust
let info_pattern = format!("%{}%", client_ip);
match conn.prepare(
    "SELECT id, is_banned FROM peer WHERE info LIKE ? AND is_deleted = 0 LIMIT 10"
) {
    Ok(mut stmt) => {
        if let Ok(mut rows) = stmt.query([&info_pattern]) {
```

**Problem:**
- Adres IP `client_ip` pochodzi z `addr.ip().to_string()` 
- Format IPv6 może zawierać znaki specjalne: `::ffff:192.168.1.1`
- Operator `LIKE` z wildcard `%` może być wykorzystany do pattern injection
- Brak walidacji czy to rzeczywiście poprawny adres IP

**Exploit scenario:**
- Atakujący może spreparować pakiet z fałszywym źródłowym adresem IPv6
- Znaki specjalne w adresie mogą zmienić semantykę zapytania LIKE

**Rekomendacja:**
```rust
// Dodaj walidację adresu IP
let client_ip = addr.ip().to_string();
if !client_ip.chars().all(|c| c.is_ascii_hexdigit() || c == ':' || c == '.') {
    log::warn!("Invalid IP address format: {}", client_ip);
    return true; // Fail closed - block suspicious connections
}

// LUB użyj dokładnego dopasowania JSON:
// SELECT id, is_banned FROM peer WHERE json_extract(info, '$.ip') = ? AND is_deleted = 0
```

---

### 🔴 CRITICAL-02: Fail-Open Policy w błędach bazy danych
**Plik:** `src/rendezvous_server.rs` (linie 717-719, 729-731)  
**Ważność:** KRYTYCZNA

**Kod podatny:**
```rust
Err(e) => {
    log::error!("Failed to check target ban status for {}: {}", id, e);
    // Kontynuuje wykonanie mimo błędu!
}
```

**Problem:**
- Jeśli baza danych jest niedostępna, zbanowane urządzenia MOGĄ się łączyć
- Atakujący może spowodować błędy bazy (DoS na SQLite) aby obejść bany
- Brak mechanizmu fail-safe

**Exploit scenario:**
1. Atakujący zabania swoje urządzenie przez API
2. Atakujący wywołuje wyczerpanie połączeń do bazy (np. 1000 równoległych zapytań)
3. SQLite zwraca błędy "database locked"
4. Zbanowane urządzenie może się teraz połączyć (fail-open)

**Rekomendacja:**
```rust
Err(e) => {
    log::error!("SECURITY: Failed to check ban status for {}: {}", id, e);
    // FAIL CLOSED - blokuj wszystkie połączenia gdy baza jest niedostępna
    let mut msg_out = RendezvousMessage::new();
    msg_out.set_punch_hole_response(PunchHoleResponse {
        failure: punch_hole_response::Failure::SERVER_ERROR.into(),
        ..Default::default()
    });
    return Ok((msg_out, None));
}
```

---

## 3. Wysokie Zagrożenia

### 🟠 HIGH-01: Race Condition w find_by_addr
**Plik:** `src/peer.rs` (linie 217-226)  
**Ważność:** WYSOKA

**Kod podatny:**
```rust
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
```

**Problem:**
- Między wywołaniem `find_by_addr()` a `is_device_banned()` urządzenie może się wyrejestrować i zarejestrować pod tym samym adresem
- TOCTOU (Time-of-Check-Time-of-Use) race condition
- NAT może spowodować że wiele urządzeń ma ten sam adres zewnętrzny

**Exploit scenario:**
1. Urządzenie A (zbanowane) łączy się z 1.2.3.4:12345
2. `find_by_addr` znajduje A
3. A się rozłącza, urządzenie B (niezbanowane) łączy się z tego samego NAT: 1.2.3.4:12345
4. `is_device_banned` sprawdza A (zbanowane) ale blokuje B (niezbanowane)

**Rekomendacja:**
- Zwracaj tuple `(id, timestamp)` i weryfikuj czy peer nadal istnieje
- Lub użyj atomic check-and-lock pattern

---

### 🟠 HIGH-02: Brak sprawdzenia banu w RequestRelay
**Plik:** `src/rendezvous_server.rs` (linie 501-513)  
**Ważność:** WYSOKA

**Kod podatny:**
```rust
Some(rendezvous_message::Union::RequestRelay(mut rf)) => {
    if let Some(peer) = self.pm.get_in_memory(&rf.id).await {
        let mut msg_out = RendezvousMessage::new();
        rf.socket_addr = AddrMangle::encode(addr).into();
        msg_out.set_request_relay(rf);
        let peer_addr = peer.read().await.socket_addr;
        self.tx.send(Data::Msg(msg_out.into(), peer_addr)).ok();
    }
    return true;
}
```

**Problem:**
- `RequestRelay` nie sprawdza czy urządzenie jest zbanowane
- To jest alternatywna ścieżka do zestawienia połączenia
- Może być używana do obejścia sprawdzania w `PunchHoleRequest`

**Rekomendacja:**
Dodaj sprawdzenie banu:
```rust
Some(rendezvous_message::Union::RequestRelay(mut rf)) => {
    // BAN CHECK: Block relay for banned devices
    if let Ok(true) = self.pm.db.is_device_banned(&rf.id).await {
        log::warn!("RequestRelay REJECTED - device {} is banned", rf.id);
        return true;
    }
    
    // Check source device
    if let Some(source_id) = self.pm.find_by_addr(addr).await {
        if let Ok(true) = self.pm.db.is_device_banned(&source_id).await {
            log::warn!("RequestRelay REJECTED - source {} is banned", source_id);
            return true;
        }
    }
    
    // Original logic...
```

---

### 🟠 HIGH-03: Potencjalna DoS przez spawn_blocking
**Plik:** `database_patch.rs` + `build.sh` (HBBR patch)  
**Ważność:** WYSOKA

**Problem:**
- Każde sprawdzenie banu wywołuje `tokio::task::spawn_blocking`
- Domyślny pool blocking ma ograniczoną liczbę wątków (512)
- Atakujący może wywołać 1000 równoległych połączeń i wyczerpać pool

**Exploit scenario:**
1. Botnet 1000 clientów wysyła równolegle PunchHoleRequest
2. Każde spawns blocking task (1000 tasków)
3. Blocking pool wyczerpany - wszystkie nowe połączenia czekają
4. Legitymowani użytkownicy nie mogą się połączyć

**Rekomendacja:**
- Dodaj rate limiting per IP
- Użyj dedykowanego connection pool dla ban checks
- Implementuj cache dla wyników ban check (TTL 5-10 sekund)

```rust
lazy_static::lazy_static! {
    static ref BAN_CACHE: RwLock<HashMap<String, (bool, Instant)>> = Default::default();
}

pub async fn is_device_banned_cached(&self, id: &str) -> ResultType<bool> {
    // Check cache first
    {
        let cache = BAN_CACHE.read().await;
        if let Some((banned, timestamp)) = cache.get(id) {
            if timestamp.elapsed().as_secs() < 10 {
                return Ok(*banned);
            }
        }
    }
    
    // Cache miss - query database
    let result = self.is_device_banned(id).await?;
    
    // Update cache
    BAN_CACHE.write().await.insert(id.to_string(), (result, Instant::now()));
    
    Ok(result)
}
```

---

## 4. Średnie Zagrożenia

### 🟡 MEDIUM-01: Brak Rate Limiting na ban checks
**Ważność:** ŚREDNIA

**Problem:**
- Brak limitu ile razy można sprawdzić ban status urządzenia
- Atakujący może wykonać reconnaissance enumerując ID urządzeń

**Rekomendacja:**
- Dodaj rate limiting: max 100 ban checks na IP/minutę
- Loguj nadmierne zapytania jako suspicious activity

---

### 🟡 MEDIUM-02: Wrażliwe dane w logach
**Plik:** Multiple  
**Ważność:** ŚREDNIA

**Problem:**
```rust
log::warn!("Connection REJECTED: Source device {} (from {}) is BANNED", source_id, addr);
```

**Dane wrażliwe w logach:**
- Device IDs (mogą być numerami telefonów)
- Adresy IP użytkowników
- Socket addresses

**Rekomendacja:**
- Rozważ hashowanie device IDs w logach
- Lub skróć do ostatnich 4 cyfr: `****1143`
- Dodaj mechanizm redaction dla compliance (GDPR)

---

## 5. Niskie Zagrożenia

### 🟢 LOW-01: Brak timeout w SQLite queries
**Ważność:** NISKA

**Problem:**
- SQLite query może zawiesić się na locked database
- Brak explicit timeout w `Connection::open_with_flags`

**Rekomendacja:**
```rust
let conn = Connection::open_with_flags(db_path, flags)?;
conn.busy_timeout(Duration::from_secs(5))?;
```

---

### 🟢 LOW-02: Brak metryki dla failed ban checks
**Ważność:** NISKA

**Problem:**
- Błędy bazy danych są logowane ale nie ma metryki
- Trudno wykryć systematyczne ataki

**Rekomendacja:**
- Dodaj counter dla failed ban checks
- Alert gdy > 10 błędów/minutę

---

### 🟢 LOW-03: Hardcoded database path
**Ważność:** NISKA

**Problem:**
```rust
let db_path = "./db_v2.sqlite3";
```

**Rekomendacja:**
- Użyj tej samej metody co w oryginalnym kodzie (std::env::var)
- Umożliwi to testowanie i różne ścieżki deployment

---

## 6. Pozytywne Aspekty Bezpieczeństwa ✅

1. **Prepared Statements** - Wszystkie zapytania SQL używają parametryzowanych queries
2. **Defensive Logging** - Dobre logowanie prób obejścia banów
3. **Read-only connections** - Database patch używa READ_ONLY flag (choć HBBR patch nie)
4. **Dwukierunkowe sprawdzanie** - Zarówno source jak i target są weryfikowane
5. **Walidacja is_deleted** - Sprawdzanie czy urządzenie nie jest soft-deleted

---

## 7. Rekomendacje Priorytetowe

### Natychmiastowe (24h):
1. ✅ **Napraw CRITICAL-01**: Dodaj walidację IP przed LIKE query
2. ✅ **Napraw CRITICAL-02**: Zmień fail-open na fail-closed
3. ✅ **Napraw HIGH-02**: Dodaj ban check do RequestRelay

### Krótkoterminowe (1 tydzień):
4. Implementuj cache dla ban checks (HIGH-03)
5. Dodaj rate limiting per IP
6. Fix race condition w find_by_addr (HIGH-01)

### Długoterminowe (1 miesiąc):
7. Dodaj metryki i alerting
8. Implementuj audit log dla wszystkich ban actions
9. Rozważ redaction wrażliwych danych w logach
10. Przeprowadź penetration testing

---

## 8. Test Plan

### Testy bezpieczeństwa do wykonania:
- [ ] Test SQL injection z nietypowymi adresami IP
- [ ] Test fail-closed przy symulowanym błędzie bazy
- [ ] Test race condition (2 urządzenia z tym samym NAT IP)
- [ ] Test DoS przez wyczerpanie blocking thread pool
- [ ] Test obejścia przez RequestRelay
- [ ] Fuzzing message handlers z malformed packets
- [ ] Test memory leak przy długotrwałym działaniu

---

## 9. Zgodność z Best Practices

| Praktyka | Status | Uwagi |
|----------|--------|-------|
| Input validation | ⚠️ | Brak walidacji IP w HBBR patch |
| Output encoding | ✅ | SQL prepared statements |
| Error handling | ❌ | Fail-open zamiast fail-closed |
| Logging | ⚠️ | Wrażliwe dane w logach |
| Authentication | ✅ | Wykorzystuje istniejący system |
| Authorization | ✅ | Sprawdzanie is_banned |
| Rate limiting | ❌ | Brak implementacji |
| Secure defaults | ❌ | Fail-open to niebezpieczny default |

---

## 10. Podsumowanie

Implementacja systemu banowania zawiera **solidne podstawy** ale ma **krytyczne luki bezpieczeństwa** które muszą być naprawione przed produkcyjnym użyciem.

**Główne problemy:**
1. Potencjalna SQL injection w HBBR
2. Fail-open policy umożliwia obejście banów
3. Brak rate limiting i cache prowadzi do możliwości DoS

**Po naprawie krytycznych błędów** system będzie zapewniał akceptowalny poziom bezpieczeństwa dla małych/średnich wdrożeń.

**Dla enterprise deployment** wymagane są dodatkowe warstwy:
- WAF przed serwerem RustDesk
- IDS/IPS monitoring
- Dedykowany audit trail
- Automated security testing w CI/CD

---

**Koniec audytu**
