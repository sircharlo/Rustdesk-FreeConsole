# RustDesk Desktop Client – System logowania i zmiany ID

## Dokument techniczny opisujący mechanizmy autentykacji i identyfikacji klienta desktop

---

## 1. Architektura ogólna

RustDesk desktop client składa się z kilku kluczowych warstw:

```
┌─────────────────────────────────────────────────┐
│                    Flutter UI                    │
│         (flutter/lib/desktop/)                   │
├─────────────────────────────────────────────────┤
│            Flutter FFI / Sciter UI               │
│    (src/flutter_ffi.rs / src/ui.rs)              │
├─────────────────────────────────────────────────┤
│              UI Interface Layer                  │
│          (src/ui_interface.rs)                   │
├─────────────────────────────────────────────────┤
│        Client Logic / LoginConfigHandler         │
│             (src/client.rs)                      │
├─────────────────────────────────────────────────┤
│          Rendezvous Mediator                     │
│       (src/rendezvous_mediator.rs)               │
├─────────────────────────────────────────────────┤
│       Server-side Connection Handler             │
│       (src/server/connection.rs)                 │
├─────────────────────────────────────────────────┤
│           Config / hbb_common                    │
│     (libs/hbb_common/src/config.rs)              │
└───────────────────────────────────────────���─────┘
```

---

## 2. System identyfikacji klienta (ID)

### 2.1 Czym jest ID w RustDesk?

Każdy klient RustDesk posiada unikalny identyfikator numeryczny (ID), który służy do:
- rejestracji na serwerze rendezvous (pośredniczącym)
- identyfikacji klienta w sieci
- nawiązywania połączeń zdalnych z innymi klientami

### 2.2 Skąd pochodzi ID?

ID jest przechowywane w konfiguracji lokalnej (`Config`). Pobieranie ID odbywa się wielopoziomowo:

**W module IPC** (`src/ipc.rs`):
```rust
pub fn get_id() -> String {
    if let Ok(Some(v)) = get_config("id") {
        if let Ok(Some(v2)) = get_config("salt") {
            Config::set_salt(&v2);
        }
        if v != Config::get_id() {
            Config::set_key_confirmed(false);
            Config::set_id(&v);
        }
        v
    } else {
        Config::get_id()
    }
}
```

**W warstwie UI** (`src/ui_interface.rs`):
```rust
pub fn get_id() -> String {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    return Config::get_id();
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    return ipc::get_id();
}
```

Na desktopie ID jest pobierane przez IPC (Inter-Process Communication) z serwisowego procesu działającego w tle. Na urządzeniach mobilnych bezpośrednio z `Config`.

### 2.3 Rejestracja ID na serwerze rendezvous

Klient cyklicznie rejestruje się na serwerze rendezvous, aby być „widocznym" w sieci. Dzieje się to w `src/rendezvous_mediator.rs`:

**`register_peer()`** – rejestracja peera (cykliczna):
```rust
async fn register_peer(&mut self, socket: Sink<'_>) -> ResultType<()> {
    // Sprawdzenie czy klucz publiczny jest potwierdzony
    if !Config::get_key_confirmed() || !Config::get_host_key_confirmed(&self.host_prefix) {
        // Jeśli nie – najpierw zarejestruj klucz publiczny
        return self.register_pk(socket).await;
    }
    let id = Config::get_id();
    let serial = Config::get_serial();
    msg_out.set_register_peer(RegisterPeer { id, serial, .. });
    socket.send(&msg_out).await?;
    Ok(())
}
```

**`register_pk()`** – rejestracja klucza publicznego:
```rust
async fn register_pk(&mut self, socket: Sink<'_>) -> ResultType<()> {
    let pk = Config::get_key_pair().1;    // klucz publiczny
    let uuid = hbb_common::get_uuid();     // UUID maszyny
    let id = Config::get_id();
    msg_out.set_register_pk(RegisterPk {
        id,
        uuid: uuid.into(),
        pk: pk.into(),
        no_register_device: Config::no_register_device(),
        ..Default::default()
    });
    socket.send(&msg_out).await?;
    Ok(())
}
```

### 2.4 Odpowiedzi serwera rendezvous

Po rejestracji klucza, serwer odpowiada (`RegisterPkResponse`):

```rust
Some(rendezvous_message::Union::RegisterPkResponse(rpr)) => {
    match rpr.result.enum_value() {
        Ok(register_pk_response::Result::OK) => {
            Config::set_key_confirmed(true);
            Config::set_host_key_confirmed(&self.host_prefix, true);
        }
        Ok(register_pk_response::Result::UUID_MISMATCH) => {
            self.handle_uuid_mismatch(sink).await?;
        }
        _ => { log::error!("unknown RegisterPkResponse"); }
    }
}
```

W przypadku `UUID_MISMATCH` (np. po reinstalacji), klient:
1. Ustawia `key_confirmed = false`
2. Generuje nowe ID (`Config::update_id()`)
3. Ponownie rejestruje klucz publiczny

---

## 3. System zmiany ID

### 3.1 Inicjacja z UI

Użytkownik może zmienić ID klienta z poziomu interfejsu graficznego.

**Flutter FFI** (`src/flutter_ffi.rs`):
```rust
pub fn main_change_id(new_id: String) {
    change_id(new_id)
}
```

**Sciter UI** (`src/ui.rs`):
```rust
fn change_id(&self, id: String) {
    reset_async_job_status();
    let old_id = self.get_id();
    change_id_shared(id, old_id);
}
```

### 3.2 Walidacja i rejestracja nowego ID

Cała logika zmiany ID znajduje się w `src/ui_interface.rs`:

```rust
pub async fn change_id_shared_(id: String, old_id: String) -> &'static str {
    // 1. Walidacja formatu ID
    if !hbb_common::is_valid_custom_id(&id) {
        return INVALID_FORMAT;
    }

    // 2. Pobranie UUID maszyny (unikatowy identyfikator sprzętowy)
    let uuid = Bytes::from(
        hbb_common::machine_uid::get()
            .unwrap_or("".to_owned())
            .as_bytes().to_vec(),
    );

    if uuid.is_empty() {
        return UNKNOWN_ERROR;
    }

    // 3. Pobranie listy serwerów rendezvous
    let rendezvous_servers = crate::ipc::get_rendezvous_servers(1_000).await;

    // 4. Weryfikacja na KAŻDYM serwerze rendezvous równolegle
    let mut futs = Vec::new();
    for rendezvous_server in rendezvous_servers {
        futs.push(tokio::spawn(async move {
            let tmp = check_id(rendezvous_server, old_id, id, uuid).await;
            if !tmp.is_empty() {
                *err.lock().unwrap() = tmp;
            }
        }));
    }
    join_all(futs).await;

    // 5. Jeśli sukces – zapisz nowe ID
    if err.is_empty() {
        crate::ipc::set_config_async("id", id.to_owned()).await.ok();
    }
    err
}
```

### 3.3 Weryfikacja ID na serwerze (`check_id`)

```rust
async fn check_id(
    rendezvous_server: String,
    old_id: String,
    id: String,
    uuid: Bytes,
) -> &'static str {
    // Połączenie TCP z serwerem rendezvous
    let mut socket = connect_tcp(...).await;

    // Wysłanie wiadomości RegisterPk z nowym ID
    msg_out.set_register_pk(RegisterPk {
        old_id,
        id,
        uuid,
        ..Default::default()
    });
    socket.send(&msg_out).await;

    // Odczytanie odpowiedzi
    match rpr.result.enum_value() {
        Ok(register_pk_response::Result::OK) => { ok = true; }
        Ok(register_pk_response::Result::ID_EXISTS) => {
            return "Not available";      // ID już zajęte!
        }
        Ok(register_pk_response::Result::TOO_FREQUENT) => {
            return "Too frequent";       // Za częste zmiany
        }
        Ok(register_pk_response::Result::NOT_SUPPORT) => {
            return "server_not_support"; // Serwer nie wspiera
        }
        Ok(register_pk_response::Result::SERVER_ERROR) => {
            return "Server error";
        }
        Ok(register_pk_response::Result::INVALID_ID_FORMAT) => {
            return INVALID_FORMAT;       // Nieprawidłowy format
        }
    }
}
```

### 3.4 Schemat procesu zmiany ID

```
Użytkownik wpisuje nowe ID
        │
        ▼
Walidacja formatu (is_valid_custom_id)
        │
        ▼
Pobranie UUID maszyny (machine_uid)
        │
        ▼
Pobranie listy serwerów rendezvous
        │
        ▼
┌───────────────────────────────────────────┐
│ Dla KAŻDEGO serwera rendezvous (równolegle):│
│                                            │
│  1. Połączenie TCP                         │
│  2. Wysłanie RegisterPk{old_id, id, uuid}  │
│  3. Odebranie RegisterPkResponse           │
│     ├─ OK → kontynuuj                      │
│     ├─ ID_EXISTS → "Not available"         │
│     ├─ TOO_FREQUENT → "Too frequent"       │
│     └─ INVALID_ID_FORMAT → błąd            │
└───────────────────────────────────────────┘
        │
        ▼ (wszystkie serwery zwróciły OK)
        │
Zapis nowego ID przez IPC → Config::set_id()
Config::set_key_confirmed(false)
        │
        ▼
Ponowna rejestracja klucza publicznego
na serwerach rendezvous z nowym ID
```

### 3.5 Warunki wstępne zmiany ID

Zmiana ID jest możliwa tylko gdy `machine_uid::get()` zwróci poprawną wartość:
```rust
fn is_ok_change_id(&self) -> bool {
    hbb_common::machine_uid::get().is_ok()
}
```

---

## 4. System logowania (autentykacja połączeń zdalnych)

### 4.1 Przegląd

System logowania w RustDesk obejmuje autentykację przy nawiązywaniu połączenia zdalnego między dwoma klientami. Centralnym elementem jest `LoginConfigHandler` w `src/client.rs`.

### 4.2 LoginConfigHandler – struktura

```rust
pub struct LoginConfigHandler {
    id: String,                     // ID peera
    pub conn_type: ConnType,        // typ połączenia (remote desktop, file transfer, etc.)
    hash: Hash,                     // hash challenge od serwera
    password: Vec<u8>,              // zapamiętane hasło (do reconnect)
    pub remember: bool,             // czy zapamiętać hasło
    config: PeerConfig,             // konfiguracja peera (zapisane hasło, ustawienia)
    pub session_id: u64,            // ID sesji
    pub force_relay: bool,          // wymuszenie relay
    switch_uuid: Option<String>,    // UUID przy przełączaniu stron
    password_source: PasswordSource, // źródło hasła
    shared_password: Option<String>, // hasło współdzielone (z address book)
    pub enable_trusted_devices: bool,
    // ... inne pola
}
```

### 4.3 Proces logowania – krok po kroku

#### Krok 1: Nawiązanie połączenia

Klient inicjuje połączenie przez `Client::start()` z ID peera, kluczem i tokenem.

#### Krok 2: Hash Challenge (handle_hash)

Serwer (zdalny klient) wysyła `Hash` zawierający `salt` i `challenge`. Klient odpowiada w `handle_hash()`:

```rust
pub async fn handle_hash(
    lc: Arc<RwLock<LoginConfigHandler>>,
    password_preset: &str,
    hash: Hash,
    interface: &impl Interface,
    peer: &mut Stream,
) {
    lc.write().unwrap().hash = hash.clone();

    // Priorytet źródeł hasła:

    // 1. Switch UUID (przełączanie stron)
    let uuid = lc.write().unwrap().switch_uuid.take();
    if let Some(uuid) = uuid { ... return; }

    // 2. Ostatnio użyte hasło (z pamięci)
    let mut password = lc.read().unwrap().password.clone();

    // 3. Hasło preset (przekazane z linii poleceń)
    if password.is_empty() && !password_preset.is_empty() {
        let mut hasher = Sha256::new();
        hasher.update(password_preset);
        hasher.update(&hash.salt);
        password = hasher.finalize()[..].into();
    }

    // 4. Hasło współdzielone (z address book)
    let shared_password = lc.write().unwrap().shared_password.take();
    if let Some(shared_password) = shared_password { ... }

    // 5. Hasło zapisane w PeerConfig
    if password.is_empty() {
        password = lc.read().unwrap().config.password.clone();
    }

    // 6. Hasło z osobistej książki adresowej
    if password.is_empty() {
        try_get_password_from_personal_ab(lc.clone(), &mut password);
    }

    // 7. Domyślne hasło połączenia
    if password.is_empty() {
        let p = get_builtin_option("default-connect-password");
        if !p.is_empty() { ... }
    }

    // Jeśli nadal brak hasła → pokaż dialog "input-password"
    if password.is_empty() {
        interface.msgbox("input-password", "Password Required", "", "");
    } else {
        // Hashowanie: SHA256(password + challenge)
        let mut hasher = Sha256::new();
        hasher.update(&password);
        hasher.update(&hash.challenge);
        password = hasher.finalize()[..].into();
    }

    // Wysłanie loginu
    send_login(lc, os_username, os_password, password, peer).await;
}
```

#### Krok 3: Hashowanie hasła (schemat kryptograficzny)

```
Hasło użytkownika
        │
        ▼
    SHA256(hasło + salt)          ← "password hash"
        │
        ▼
    SHA256(password_hash + challenge)  ← "login hash"
        │
        ▼
    Wysłane do zdalnego peera
```

To jest schemat challenge-response:
- **salt** – zapobiega atakom rainbow table
- **challenge** – jest jednorazowy, zapobiega atakom replay

#### Krok 4: Tworzenie wiadomości LoginRequest

```rust
fn create_login_msg(&self, os_username: String, os_password: String, password: Vec<u8>) -> Message {
    let my_id = Config::get_id();

    let lr = LoginRequest {
        username: pure_id,            // ID klienta kontrolującego
        password: password.into(),     // zhashowane hasło
        my_id,                         // moje pełne ID
        my_name: display_name,        // nazwa wyświetlana
        my_platform,                   // platforma (Windows/Linux/macOS)
        option: self.get_option_message(true).into(),
        session_id: self.session_id,
        version: crate::VERSION.to_string(),
        os_login: Some(OSLogin {       // logowanie do sesji OS
            username: os_username,
            password: os_password,
        }),
        hwid,                          // ID sprzętowy (trusted devices)
        ..Default::default()
    };

    // Dodatkowe opcje w zależności od typu połączenia:
    match self.conn_type {
        ConnType::FILE_TRANSFER => lr.set_file_transfer(...),
        ConnType::VIEW_CAMERA => lr.set_view_camera(...),
        ConnType::PORT_FORWARD => lr.set_port_forward(...),
        ConnType::TERMINAL => lr.set_terminal(...),
        _ => {}
    }

    msg_out.set_login_request(lr);
    msg_out
}
```

#### Krok 5: Obsługa logowania z UI (handle_login_from_ui)

Gdy użytkownik wpisuje hasło ręcznie:

```rust
pub async fn handle_login_from_ui(
    lc: Arc<RwLock<LoginConfigHandler>>,
    os_username: String,
    os_password: String,
    password: String,
    remember: bool,
    peer: &mut Stream,
) {
    let hash_password = if password.is_empty() {
        // Użyj zapamiętanego hasła
        lc.read().unwrap().password.clone()
    } else {
        // Hashuj nowe hasło:
        // SHA256(password + salt)
        let mut hasher = Sha256::new();
        hasher.update(password);
        hasher.update(&lc.read().unwrap().hash.salt);
        hasher.finalize()[..].into()
    };

    // Finalne hashowanie z challenge:
    // SHA256(hash_password + challenge)
    let mut hasher2 = Sha256::new();
    hasher2.update(&hash_password[..]);
    hasher2.update(&lc.read().unwrap().hash.challenge);
    let final_hash = hasher2.finalize()[..].to_vec();

    send_login(lc, os_username, os_password, final_hash, peer).await;
}
```

### 4.4 Strona serwera (odbierająca połączenie)

Po stronie zdalnego klienta (`src/server/connection.rs`), po weryfikacji hasła:

```rust
fn try_start_cm(&mut self, peer_id: String, name: String, authorized: bool) {
    self.send_to_cm(ipc::Data::Login {
        id: self.inner.id(),
        is_file_transfer: self.file_transfer.is_some(),
        peer_id,
        name,
        authorized,       // czy hasło jest poprawne
        keyboard: self.keyboard,
        clipboard: self.clipboard,
        audio: self.audio,
        file: self.file,
        // ... inne uprawnienia
    });
}
```

Jeśli hasło jest błędne:
```rust
async fn send_login_error<T: std::string::ToString>(&mut self, err: T) {
    let mut res = LoginResponse::new();
    res.set_error(err.to_string());
    if err.to_string() == crate::client::REQUIRE_2FA {
        res.enable_trusted_devices = Self::enable_trusted_devices();
    }
    msg_out.set_login_response(res);
    self.send(msg_out).await;
}
```

### 4.5 Kody błędów logowania

Zdefiniowane w `src/client.rs`:

| Stała | Znaczenie |
|-------|-----------|
| `LOGIN_MSG_PASSWORD_EMPTY` | Puste hasło |
| `LOGIN_MSG_PASSWORD_WRONG` | Złe hasło |
| `LOGIN_MSG_2FA_WRONG` | Błędny kod 2FA |
| `REQUIRE_2FA` | Wymagana autentykacja dwuskładnikowa |
| `LOGIN_MSG_NO_PASSWORD_ACCESS` | Brak dostępu hasłem |
| `LOGIN_MSG_OFFLINE` | Peer offline |
| `LOGIN_MSG_DESKTOP_SESSION_NOT_READY` | Sesja desktopowa niegotowa |
| `LOGIN_MSG_DESKTOP_SESSION_ANOTHER_USER` | Zalogowany inny użytkownik |

### 4.6 Typy haseł i ich priorytet

```
1. Switch UUID          (przełączanie stron sesji)
2. Ostatnie hasło       (z pamięci RAM – do reconnect)
3. Hasło preset         (z argumentów wiersza poleceń)
4. Hasło współdzielone  (z shared address book)
5. Hasło PeerConfig     (zapisane lokalnie)
6. Hasło z personal AB  (z osobistej książki adresowej)
7. Hasło domyślne       (default-connect-password)
8. Brak hasła           → dialog "input-password" / logowanie bez hasła (akceptacja zdalna)
```

### 4.7 Trusted Devices (Zaufane urządzenia)

Jeśli włączono 2FA i zaufane urządzenia:
```rust
if self.require_2fa.is_some() && !lr.hwid.is_empty() && Self::enable_trusted_devices() {
    let devices = Config::get_trusted_devices();
    if let Some(device) = devices.iter().find(|d| d.hwid == lr.hwid) {
        if !device.outdate()
            && device.id == lr.my_id
            && device.name == lr.my_name
            && device.platform == lr.my_platform
        {
            log::info!("2FA bypassed by trusted devices");
            self.require_2fa = None;  // Pomiń 2FA!
        }
    }
}
```

---

## 5. Logowanie do konta (Account Login – OIDC)

### 5.1 Przegląd

Poza logowaniem do zdalnych peerów, RustDesk wspiera również logowanie do konta użytkownika na serwerze API (OIDC – OpenID Connect).

Kod znajduje się w `src/hbbs_http/account.rs`.

### 5.2 Struktura sesji OIDC

```rust
pub struct OidcSession {
    client: Option<Client>,           // klient HTTP
    state_msg: &'static str,          // stan: "Requesting"/"Waiting"/"Login"
    failed_msg: String,               // komunikat błędu
    code_url: Option<OidcAuthUrl>,    // URL do autoryzacji
    auth_body: Option<AuthBody>,      // dane po zalogowaniu
    keep_querying: bool,              // czy ciągle sprawdzać status
    running: bool,
    query_timeout: Duration,          // timeout (3 minuty)
}
```

### 5.3 Proces OIDC

```
1. Klient wysyła POST /api/oidc/auth {op, id, uuid, deviceInfo}
2. Serwer zwraca {code, url}
3. Klient otwiera URL w przeglądarce (użytkownik loguje się)
4. Klient odpytuje POST /api/oidc/auth-query {code, id, uuid}
5. Po zalogowaniu → serwer zwraca AuthBody {access_token, user}
```

### 5.4 AuthBody – dane po zalogowaniu

```rust
pub struct AuthBody {
    pub access_token: String,
    pub r#type: String,
    pub tfa_type: String,    // typ 2FA
    pub secret: String,       // sekret 2FA
    pub user: UserPayload,    // dane użytkownika
}

pub struct UserPayload {
    pub name: String,
    pub email: Option<String>,
    pub status: UserStatus,
    pub info: UserInfo,
    pub is_admin: bool,
    pub third_auth_type: Option<String>,
}
```

---

## 6. Schemat nawiązywania połączenia (Connection Flow)

```
Klient A (kontrolujący)              Serwer Rendezvous              Klient B (kontrolowany)
        │                                    │                              │
        │  ── RegisterPeer(id_A) ──────────►│                              │
        │                                    │◄──── RegisterPeer(id_B) ────│
        │                                    │                              │
        │  ── PunchHoleRequest(id_B) ──────►│                              │
        │                                    │──── PunchHole(id_A) ───────►│
        │                                    │◄──── PunchHoleSent ─────────│
        │◄── PunchHoleSent ─────────────────│                              │
        │                                    │                              │
        │  ══════ Połączenie P2P / Relay ══════════════════════════════════│
        │                                                                   │
        │  ◄──── Hash{salt, challenge} ────────────────────────────────────│
        │                                                                   │
        │  ── LoginRequest{id, password_hash, my_name, ...} ─────────────►│
        │                                                                   │
        │  ◄──── LoginResponse{OK / Error} ────────────────────────────────│
        │                                                                   │
        │  ◄════ Sesja zdalna (video/audio/input/clipboard) ══════════════│
```

---

## 7. Podsumowanie

| Mechanizm | Pliki źródłowe | Opis |
|-----------|---------------|------|
| **Generowanie/odczyt ID** | `libs/hbb_common/src/config.rs`, `src/ipc.rs` | ID przechowywane w konfiguracji, pobierane przez IPC |
| **Rejestracja na rendezvous** | `src/rendezvous_mediator.rs` | Cykliczna rejestracja ID + klucza publicznego |
| **Zmiana ID** | `src/ui_interface.rs` (`change_id_shared_`, `check_id`) | Walidacja → weryfikacja na serwerach → zapis |
| **Logowanie hasłem** | `src/client.rs` (`handle_hash`, `handle_login_from_ui`, `send_login`) | Challenge-response z SHA256 |
| **LoginConfigHandler** | `src/client.rs` | Centralna struktura zarządzająca sesją logowania |
| **Obsługa po stronie serwera** | `src/server/connection.rs` | Weryfikacja hasła, 2FA, trusted devices |
| **Logowanie OIDC** | `src/hbbs_http/account.rs` | Logowanie do konta przez OpenID Connect |
| **Interface trait** | `src/client.rs` | Wspólny interfejs implementowany przez CLI, Sciter, Flutter |

### Kluczowe obserwacje:

1. **Hasła nigdy nie są przesyłane w postaci jawnej** – zawsze stosowany jest schemat challenge-response z SHA256.
2. **Zmiana ID wymaga potwierdzenia ze WSZYSTKICH serwerów rendezvous** – jeśli choć jeden odrzuci, zmiana nie zostanie zastosowana.
3. **UUID maszyny jest kluczowy** – wiąże ID z fizycznym urządzeniem, zapobiega kradzieży ID.
4. **System haseł ma 8 poziomów priorytetów** – od switch UUID po logowanie bez hasła.
5. **2FA może być pominięte** przez mechanizm zaufanych urządzeń (HWID).
6. **Proces jest asynchroniczny** – całość działa na tokio runtime z wzorcem async/await.