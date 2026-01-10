# 🚨 PILNE OSTRZEŻENIE BEZPIECZEŃSTWA

## ⚠️ KRYTYCZNE ZAGROŻENIE: Niezabezpieczone HTTP API

**Data wykrycia:** 10 stycznia 2026  
**Priorytet:** 🔴 KRYTYCZNY  
**Status:** Wymaga natychmiastowej naprawy przed wdrożeniem produkcyjnym

---

## 🔍 Opis Problemu

HTTP API (port 21114) **NIE MA ŻADNEJ AUTENTYKACJI** i nasłuchuje na `0.0.0.0` (wszystkie interfejsy sieciowe).

### Co to oznacza?

```bash
# KAŻDY w Twojej sieci może wykonać:
curl http://YOUR_SERVER_IP:21114/api/peers

# I otrzyma:
{
  "success": true,
  "data": [
    {"id": "123456789", "note": "CEO Laptop", "online": true},
    {"id": "987654321", "note": "Finance PC", "online": false}
  ]
}
```

**Potencjalne konsekwencje:**
- ✖️ Wyciek informacji o wszystkich urządzeniach w sieci
- ✖️ Tracking online/offline statusu użytkowników
- ✖️ Ekspozycja device IDs do potencjalnych ataków
- ✖️ Naruszenie prywatności (GDPR/RODO)
- ✖️ Reconnaissance dla atakujących

---

## 🛠️ NATYCHMIASTOWE DZIAŁANIA

### Opcja 1: **Firewall (Najszybsze - 2 minuty)**

```bash
# Linux (iptables)
sudo iptables -A INPUT -p tcp --dport 21114 -s 127.0.0.1 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 21114 -j DROP

# Lub (ufw)
sudo ufw deny 21114
sudo ufw allow from 127.0.0.1 to any port 21114

# Windows
New-NetFirewallRule -DisplayName "Block HBBS API" -Direction Inbound -LocalPort 21114 -Protocol TCP -Action Block
New-NetFirewallRule -DisplayName "Allow HBBS API Localhost" -Direction Inbound -LocalAddress 127.0.0.1 -LocalPort 21114 -Protocol TCP -Action Allow
```

**Efekt:** API dostępne tylko lokalnie (localhost), konsola webowa działa, zewnętrzny dostęp zablokowany.

### Opcja 2: **Zmiana nasłuchiwania (5 minut)**

Edytuj `hbbs-patch/src/http_api.rs`:

```rust
// PRZED (niebezpieczne):
let addr = SocketAddr::from(([0, 0, 0, 0], port));

// PO (bezpieczne):
let addr = SocketAddr::from(([127, 0, 0, 1], port));
```

Rekompiluj i wdroż:
```bash
cd hbbs-patch
bash build.sh  # Linux
# LUB
.\build-windows-local.ps1  # Windows

sudo systemctl restart rustdesksignal
```

---

## 🔐 PEŁNE ZABEZPIECZENIE (Zalecane)

### 1. Autentykacja API Key

Edytuj `hbbs-patch/src/http_api.rs`:

```rust
use axum::{
    extract::Extension,
    http::{Request, StatusCode, header::HeaderMap},
    middleware::{self, Next},
    response::Response,
    routing::get,
    Router,
};
use std::env;

// API Key middleware
async fn check_api_key<B>(
    headers: HeaderMap,
    request: Request<B>,
    next: Next<B>,
) -> Result<Response, StatusCode> {
    // Pobierz klucz z zmiennej środowiskowej
    let expected_key = env::var("HBBS_API_KEY").unwrap_or_else(|_| {
        log::warn!("HBBS_API_KEY not set, using default (INSECURE!)");
        "CHANGE_ME_INSECURE_DEFAULT".to_string()
    });

    // Sprawdź nagłówek X-API-Key
    if let Some(api_key) = headers.get("X-API-Key") {
        if api_key.to_str().ok() == Some(&expected_key) {
            return Ok(next.run(request).await);
        }
    }

    log::warn!("Unauthorized API access attempt from {:?}", request.uri());
    Err(StatusCode::UNAUTHORIZED)
}

pub async fn start_api_server(/* ... */) -> Result<(), Box<dyn std::error::Error>> {
    // ... existing code ...

    let app = Router::new()
        .route("/api/health", get(health_check))
        .route("/api/peers", get(get_online_peers))
        .layer(middleware::from_fn(check_api_key))  // ← DODAJ TO
        .layer(axum::Extension(state));

    // Opcjonalnie: bind tylko do localhost
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    
    log::info!("HTTP API server listening on {} (with API Key auth)", addr);
    
    // ... rest of code ...
}
```

**Aktualizacja `app.py`:**

```python
import os

# Na początku pliku
API_KEY = os.environ.get('HBBS_API_KEY', 'CHANGE_ME_INSECURE_DEFAULT')

# W funkcjach wywołujących API:
headers = {'X-API-Key': API_KEY}
response = requests.get(f'{HBBS_API_URL}/peers', timeout=2, headers=headers)
```

**Ustawienie klucza:**

```bash
# Linux (dodaj do /etc/environment lub .bashrc)
export HBBS_API_KEY="$(openssl rand -hex 32)"

# Systemd service
sudo nano /etc/systemd/system/rustdesksignal.service
# Dodaj linię:
Environment="HBBS_API_KEY=your-secure-random-key-here"

# Flask service
sudo nano /etc/systemd/system/betterdesk.service
# Dodaj linię:
Environment="HBBS_API_KEY=your-secure-random-key-here"

sudo systemctl daemon-reload
sudo systemctl restart rustdesksignal betterdesk
```

```powershell
# Windows (jako Administrator)
[System.Environment]::SetEnvironmentVariable("HBBS_API_KEY", "your-secure-random-key", "Machine")

# Restart serwisów
Restart-Service RustDesk*
```

### 2. Rate Limiting

```bash
pip install Flask-Limiter
```

```python
# app.py
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://"
)

@app.route('/api/devices')
@limiter.limit("30 per minute")
def get_devices():
    # ... existing code ...
```

### 3. CORS Protection

```bash
cargo add tower-http --features cors
```

```rust
// http_api.rs
use tower_http::cors::{CorsLayer, Any};
use http::Method;

let cors = CorsLayer::new()
    .allow_origin("http://localhost:5000".parse::<HeaderValue>().unwrap())
    .allow_methods([Method::GET])
    .allow_headers([HeaderName::from_static("x-api-key")]);

let app = Router::new()
    .route("/api/peers", get(get_online_peers))
    .layer(cors)
    .layer(middleware::from_fn(check_api_key))
    .layer(axum::Extension(state));
```

---

## ✅ WERYFIKACJA ZABEZPIECZEŃ

### Test 1: Firewall działa

```bash
# Z innego komputera w sieci:
curl http://YOUR_SERVER_IP:21114/api/health
# Powinno: Connection refused lub timeout

# Z serwera lokalnie:
curl http://localhost:21114/api/health
# Powinno: {"success":true,"data":"RustDesk API is running"}
```

### Test 2: API Key działa

```bash
# Bez klucza:
curl http://localhost:21114/api/peers
# Powinno: 401 Unauthorized

# Z kluczem:
curl -H "X-API-Key: YOUR_KEY" http://localhost:21114/api/peers
# Powinno: {"success":true,"data":[...]}
```

### Test 3: Rate Limiting działa

```bash
# Wyślij 50 requestów szybko:
for i in {1..50}; do curl http://localhost:5000/api/devices; done
# Po ~30 requestach powinno: 429 Too Many Requests
```

---

## 📋 CHECKLIST WDROŻENIA

### Minimalne zabezpieczenie (przed produkcją):
- [ ] Firewall blokuje port 21114 z zewnątrz
- [ ] HBBS API nasłuchuje tylko na 127.0.0.1
- [ ] Logi monitorowane pod kątem podejrzanej aktywności

### Pełne zabezpieczenie (zalecane):
- [ ] API Key authentication zaimplementowane
- [ ] Rate limiting w Flask
- [ ] CORS skonfigurowany
- [ ] Klucze w zmiennych środowiskowych
- [ ] HTTPS/TLS dla produkcji (certyfikat SSL)
- [ ] Monitoring i alerty

---

## 🚦 BIEŻĄCY STATUS ZABEZPIECZEŃ

| Warstwa | Status | Uwagi |
|---------|--------|-------|
| SQL Injection | ✅ ZABEZPIECZONE | Parametryzowane zapytania |
| XSS | ⚠️ CZĘŚCIOWE | Podstawowa sanityzacja |
| Buffer Overflow | ✅ ZABEZPIECZONE | Rust type safety |
| Race Conditions | ✅ ZABEZPIECZONE | Arc/RwLock |
| **Authentication** | 🔴 **BRAK** | **WYMAGA NAPRAWY** |
| Authorization | 🔴 BRAK | Wymaga naprawy |
| Rate Limiting | 🔴 BRAK | Wymaga naprawy |
| CORS | 🔴 BRAK | Wymaga naprawy |
| HTTPS/TLS | ⚠️ OPCJONALNE | Zalecane dla WAN |

---

## 📞 DALSZE KROKI

1. **Natychmiast:** Zastosuj firewall (Opcja 1)
2. **Dziś:** Zmień bind na 127.0.0.1 (Opcja 2)
3. **W tym tygodniu:** Implementuj API Key authentication
4. **Przy okazji:** Rate limiting + CORS

---

## ⚖️ ODPOWIEDZIALNOŚĆ

**Obecny stan:**  
System działa poprawnie funkcjonalnie, ale ma krytyczną lukę w zabezpieczeniach.  
**NIE WDRAŻAJ DO PRODUKCJI** bez zastosowania minimum Opcji 1 lub 2.

**Po zastosowaniu poprawek:**  
System bezpieczny dla użytku wewnętrznego w sieci lokalnej. Dla ekspozycji na internet dodatkowy HTTPS + hardening.

---

**Autor analizy:** GitHub Copilot  
**Data:** 10 stycznia 2026  
**Wersja dokumentu:** 1.0
