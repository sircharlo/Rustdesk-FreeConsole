# BetterDesk Console - Instrukcje dla Copilota

> Ten plik jest automatycznie dołączany do kontekstu rozmów z GitHub Copilot.
> Zawiera aktualne informacje o stanie projektu i wytyczne do dalszej pracy.

---

## 📊 Stan Projektu (aktualizacja: 2026-02-17)

### Wersja Skryptów ALL-IN-ONE (v2.2.0)

| Plik | Wersja | Platforma | Status |
|------|--------|-----------|--------|
| `betterdesk.sh` | v2.2.0 | Linux | ✅ ALL-IN-ONE + Node.js/Flask choice + Auto mode |
| `betterdesk.ps1` | v2.2.0 | Windows | ✅ ALL-IN-ONE + Node.js/Flask choice + Auto mode |
| `betterdesk-docker.sh` | v2.0.0 | Docker | ✅ Interaktywny ALL-IN-ONE |

### Konsole Webowe

| Typ | Folder | Status | Opis |
|-----|--------|--------|------|
| **Node.js (zalecana)** | `web-nodejs/` | ✅ Aktywna | Express.js, EJS, better-sqlite3 |
| **Flask (legacy)** | `web/` | ✅ Aktywna | Python, Jinja2, sqlite3 |

### Binarki Serwera

| Platforma | Plik | Wersja | Status | Data |
|-----------|------|--------|--------|------|
| Linux x86_64 | `hbbs-patch-v2/hbbs-linux-x86_64` | v2.1.2 | ✅ Przetestowana | 2026-02-13 |
| Linux x86_64 | `hbbs-patch-v2/hbbr-linux-x86_64` | v2.1.2 | ✅ Przetestowana | 2026-02-13 |
| Windows x86_64 | `hbbs-patch-v2/hbbs-windows-x86_64.exe` | v2.1.2 | ✅ Przetestowana | 2026-02-13 |
| Windows x86_64 | `hbbs-patch-v2/hbbr-windows-x86_64.exe` | v2.1.2 | ✅ Przetestowana | 2026-02-13 |

### Sumy Kontrolne SHA256

```
Linux:
  hbbs: 2B6C475A449ECBA3786D0DB46CBF4E038EDB74FC3497F9A45791ADDD5A28834C
  hbbr: 8E7492CB1695B3D812CA13ABAC9A31E4DEA95B50497128D8E128DA39FDAC243D

Windows:
  hbbs: F74F65B909460BED6D363A6DF907BF0D9DB3224F82A1D5B61BD636DC362125AD
  hbbr: 1C3CE3F7900D30A0DD3E48B0998E566F09338C71F0C27422D7E0057049A16F3F
```

---

## 🚀 Skrypty ALL-IN-ONE (v2.2.0)

### Nowe funkcje w v2.2.0

- ✅ **Wybór konsoli Node.js/Flask** - interaktywny wybór podczas instalacji
- ✅ **Flagi --nodejs/--flask (Linux)** - wybór konsoli z linii poleceń
- ✅ **Parametry -NodeJs/-Flask (Windows)** - wybór konsoli w PowerShell
- ✅ **Migracja między konsolami** - automatyczna migracja z Flask do Node.js
- ✅ **Automatyczna instalacja Node.js** - przez apt/dnf/yum/pacman/winget/chocolatey

### Nowe funkcje w v2.1.2

- ✅ **Poprawka systemu banowania** - ban dotyczy tylko konkretnego urządzenia, nie wszystkich z tego samego IP
- ✅ **Poprawka migracji w trybie auto** - migracje bazy danych działają bez interakcji
- ✅ **Weryfikacja SHA256** - automatyczna weryfikacja sum kontrolnych binarek
- ✅ **Tryb automatyczny** - instalacja bez interakcji użytkownika (`--auto` / `-Auto`)
- ✅ **Konfigurowalne porty API** - zmienne środowiskowe `API_PORT`
- ✅ **Ulepszone usługi systemd** - lepsze konfiguracje z dokumentacją

### Funkcje wspólne dla wszystkich skryptów

1. 🚀 **Nowa instalacja** - pełna instalacja od zera (Node.js lub Flask)
2. ⬆️ **Aktualizacja** - aktualizacja istniejącej instalacji
3. 🔧 **Naprawa** - automatyczna naprawa problemów
4. ✅ **Walidacja** - sprawdzenie poprawności instalacji
5. 💾 **Backup** - tworzenie kopii zapasowych
6. 🔐 **Reset hasła** - reset hasła administratora
7. 🔨 **Budowanie binarek** - kompilacja ze źródeł
8. 📊 **Diagnostyka** - szczegółowa analiza problemów
9. 🗑️ **Odinstalowanie** - pełne usunięcie

### Użycie

```bash
# Linux - tryb interaktywny
sudo ./betterdesk.sh

# Linux - tryb automatyczny z Node.js (zalecane)
sudo ./betterdesk.sh --auto --nodejs

# Linux - tryb automatyczny z Flask (legacy)
sudo ./betterdesk.sh --auto --flask

# Linux - pomiń weryfikację SHA256
sudo ./betterdesk.sh --skip-verify

# Windows (PowerShell jako Administrator) - tryb interaktywny
.\betterdesk.ps1

# Windows - tryb automatyczny z Node.js (zalecane)
.\betterdesk.ps1 -Auto -NodeJs

# Windows - tryb automatyczny z Flask (legacy)
.\betterdesk.ps1 -Auto -Flask

# Windows - pomiń weryfikację SHA256
.\betterdesk.ps1 -SkipVerify

# Docker
./betterdesk-docker.sh
```

---

## 🛠️ Konfiguracja portu API

### Zmienne środowiskowe

```bash
# Linux - niestandardowy port API
API_PORT=21120 sudo ./betterdesk.sh --auto

# Windows
$env:API_PORT = "21114"
.\betterdesk.ps1 -Auto
```

### Domyślne porty

| Port | Usługa | Opis |
|------|--------|------|
| 21120 | HTTP API (Linux) | BetterDesk HTTP API (domyślny Linux) |
| 21114 | HTTP API (Windows) | BetterDesk HTTP API (domyślny Windows) |
| 21115 | TCP | NAT type test |
| 21116 | TCP/UDP | ID Server (rejestracja klientów) |
| 21117 | TCP | Relay Server |
| 5000 | HTTP | Web Console |

### Skrypt diagnostyczny (dev)
```bash
# Szczegółowa diagnostyka offline status
./dev_modules/diagnose_offline_status.sh
```

---

## 🏗️ Architektura

### Struktura Katalogów

```
Rustdesk-FreeConsole/
├── web/                     # Flask web console (Python)
├── hbbs-patch-v2/           # Enhanced server binaries (v2.0.0)
│   ├── hbbs-linux-x86_64    # Signal server Linux
│   ├── hbbr-linux-x86_64    # Relay server Linux  
│   ├── hbbs-windows-x86_64.exe  # Signal server Windows
│   ├── hbbr-windows-x86_64.exe  # Relay server Windows
│   └── src/                 # Source code for modifications
├── docs/                    # Documentation (English)
├── dev_modules/             # Development & testing utilities
├── archive/                 # Archived files (not in git)
├── Dockerfile.*             # Docker images
├── docker-compose.yml       # Docker orchestration
└── migrations/              # Database migrations
```

### Porty

| Port | Usługa | Opis |
|------|--------|------|
| 21114 | HTTP API | BetterDesk Console API (domyślny) |
| 21115 | TCP | NAT type test |
| 21116 | TCP/UDP | ID Server (rejestracja klientów) |
| 21117 | TCP | Relay Server |
| 5000 | HTTP | Web Console |

---

## 🔧 Procedury Kompilacji

### Windows (wymagania)
- Rust 1.70+ (`rustup update`)
- Visual Studio Build Tools z C++ support
- Git

### Kompilacja Windows
```powershell
# 1. Pobierz źródła RustDesk
git clone --branch 1.1.14 https://github.com/rustdesk/rustdesk-server.git
cd rustdesk-server
git submodule update --init --recursive

# 2. Skopiuj modyfikacje BetterDesk
copy ..\hbbs-patch-v2\src\main.rs src\main.rs
copy ..\hbbs-patch-v2\src\http_api.rs src\http_api.rs

# 3. Kompiluj
cargo build --release

# 4. Binarki w: target\release\hbbs.exe, target\release\hbbr.exe
```

### Linux (wymagania)
```bash
sudo apt-get install -y build-essential libsqlite3-dev pkg-config libssl-dev git
```

---

## 🧪 Środowiska Testowe

### Serwer SSH (Linux tests)
- **Host:** `user@your-server-ip` (skonfiguruj własny serwer testowy)
- **Użycie:** Testowanie binarek Linux, sprawdzanie logów

### Windows (local)
- Testowanie binarek Windows bezpośrednio na maszynie deweloperskiej

---

## 📋 Aktualne Zadania

### ✅ Ukończone (2026-02-04)
1. [x] Usunięto stary folder `hbbs-patch` (v1)
2. [x] Skompilowano binarki Windows v2.0.0
3. [x] Przetestowano binarki na obu platformach
4. [x] Zaktualizowano CHECKSUMS.md
5. [x] Dodano --fix i --diagnose do install-improved.sh (v1.5.5)
6. [x] Dodano -Fix i -Diagnose do install-improved.ps1 (v1.5.1)
7. [x] Dodano obsługę hbbs-patch-v2 binarek Windows w instalatorze PS1
8. [x] Utworzono diagnose_offline_status.sh
9. [x] Zaktualizowano TROUBLESHOOTING_EN.md (Problem 3: Offline Status)

### ✅ Ukończone (2026-02-06)
10. [x] **Naprawiono Docker** - Dockerfile.hbbs/hbbr teraz kopiują binarki BetterDesk z hbbs-patch-v2/
11. [x] **Naprawiono "no such table: peer"** - obrazy Docker używają teraz zmodyfikowanych binarek
12. [x] **Naprawiono "pull access denied"** - dodano `pull_policy: never` w docker-compose.yml
13. [x] **Naprawiono DNS issues** - dodano fallback DNS w Dockerfile.console (AlmaLinux/CentOS)
14. [x] Zaktualizowano DOCKER_TROUBLESHOOTING.md z nowymi rozwiązaniami

### ✅ Ukończone (2026-02-07)
15. [x] **Stworzono build-betterdesk.sh** - interaktywny skrypt do kompilacji (Linux/macOS)
16. [x] **Stworzono build-betterdesk.ps1** - interaktywny skrypt do kompilacji (Windows)
17. [x] **Stworzono GitHub Actions workflow** - automatyczna kompilacja multi-platform (.github/workflows/build.yml)
18. [x] **Stworzono BUILD_GUIDE.md** - dokumentacja budowania ze źródeł
19. [x] **System statusu v3.0** - konfigurowalny timeout, nowe statusy (Online/Degraded/Critical/Offline)
20. [x] **Nowe endpointy API** - /api/config, /api/peers/stats, /api/server/stats
21. [x] **Dokumentacja v3.0** - STATUS_TRACKING_v3.md
22. [x] **Zmiana ID urządzenia** - moduł id_change.rs, endpoint POST /api/peers/:id/change-id
23. [x] **Dokumentacja ID Change** - docs/ID_CHANGE_FEATURE.md

### ✅ Ukończone (2026-02-11)
24. [x] **System i18n** - wielojęzyczność panelu web przez JSON
25. [x] **Moduł Flask i18n** - web/i18n.py z API endpoints
26. [x] **JavaScript i18n** - web/static/js/i18n.js client-side
27. [x] **Tłumaczenia EN/PL** - web/lang/en.json, web/lang/pl.json
28. [x] **Selector języka** - w sidebarze panelu
29. [x] **Dokumentacja i18n** - docs/CONTRIBUTING_TRANSLATIONS.md

### 🔜 Do Zrobienia (priorytety)
1. [ ] Kompilacja binarek v3.0.0 z nowymi plikami źródłowymi
2. [ ] WebSocket real-time push dla statusu
3. [ ] Dodać testy jednostkowe dla HTTP API
4. [ ] Integracja id_change.rs z rendezvous_server_core.rs

---

## 🔄 System Statusu v3.0

### Nowe Pliki Źródłowe

| Plik | Opis |
|------|------|
| `peer_v3.rs` | Ulepszony system statusu z konfigurowalnymi timeoutami |
| `database_v3.rs` | Rozszerzona baza danych z server_config |
| `http_api_v3.rs` | Nowe endpointy API dla konfiguracji |

### Konfiguracja przez Zmienne Środowiskowe

```bash
PEER_TIMEOUT_SECS=15        # Timeout dla offline (domyślnie 15s)
HEARTBEAT_INTERVAL_SECS=3   # Interwał sprawdzania (domyślnie 3s)
HEARTBEAT_WARNING_THRESHOLD=2   # Próg dla DEGRADED
HEARTBEAT_CRITICAL_THRESHOLD=4  # Próg dla CRITICAL
```

### Nowe Statusy Urządzeń

```
ONLINE   → Wszystko OK
DEGRADED → 2-3 pominięte heartbeaty
CRITICAL → 4+ pominięte, wkrótce offline
OFFLINE  → Przekroczony timeout
```

### Dokumentacja

Pełna dokumentacja: [STATUS_TRACKING_v3.md](../docs/STATUS_TRACKING_v3.md)

---

## � Zmiana ID Urządzenia

### Endpoint API

```
POST /api/peers/:old_id/change-id
Content-Type: application/json
X-API-Key: <api-key>

{ "new_id": "NEWID123" }
```

### Pliki Źródłowe

| Plik | Opis |
|------|------|
| `id_change.rs` | Moduł obsługi zmiany ID przez protokół klienta |
| `database_v3.rs` | Funkcje `change_peer_id()`, `get_peer_id_history()` |
| `http_api_v3.rs` | Endpoint POST `/api/peers/:id/change-id` |

### Walidacja

- **Długość ID**: 6-16 znaków
- **Dozwolone znaki**: A-Z, 0-9, `-`, `_`
- **Unikatowość**: Nowe ID nie może być zajęte
- **Rate limiting** (klient): 5 min cooldown

### Dokumentacja

Pełna dokumentacja: [ID_CHANGE_FEATURE.md](../docs/ID_CHANGE_FEATURE.md)

---

## 🌍 System i18n (Wielojęzyczność)

### Pliki Systemu

| Plik | Opis |
|------|------|
| `web/i18n.py` | Moduł Flask z API endpoints |
| `web/static/js/i18n.js` | Klient JavaScript |
| `web/static/css/i18n.css` | Style dla selektora języka |
| `web/lang/*.json` | Pliki tłumaczeń |

### API Endpoints

| Endpoint | Metoda | Opis |
|----------|--------|------|
| `/api/i18n/languages` | GET | Lista dostępnych języków |
| `/api/i18n/translations/{code}` | GET | Pobierz tłumaczenia |
| `/api/i18n/set/{code}` | POST | Ustaw preferencję języka |

### Dodawanie nowego języka

1. Skopiuj `web/lang/en.json` do `web/lang/{kod}.json`
2. Przetłumacz wszystkie wartości
3. Zaktualizuj sekcję `meta` z informacjami o języku

### Dokumentacja

Pełna dokumentacja: [CONTRIBUTING_TRANSLATIONS.md](../docs/CONTRIBUTING_TRANSLATIONS.md)

---

## 🔨 Skrypty Budowania

### Interaktywne skrypty kompilacji

| Skrypt | Platforma | Opis |
|--------|-----------|------|
| `build-betterdesk.sh` | Linux/macOS | Interaktywny build z wyborem wersji/platformy |
| `build-betterdesk.ps1` | Windows | Interaktywny build PowerShell |

### Użycie

```bash
# Linux - tryb interaktywny
./build-betterdesk.sh

# Linux - tryb automatyczny
./build-betterdesk.sh --auto

# Windows - tryb interaktywny
.\build-betterdesk.ps1

# Windows - tryb automatyczny
.\build-betterdesk.ps1 -Auto
```

### GitHub Actions CI/CD

Workflow `.github/workflows/build.yml` automatycznie:
- Buduje binarki dla Linux x64, Linux ARM64, Windows x64
- Uruchamia się przy zmianach w `hbbs-patch-v2/src/**`
- Pozwala na ręczne uruchomienie z wyborem wersji
- Opcjonalnie tworzy GitHub Release

### Dokumentacja

Pełna dokumentacja budowania: [BUILD_GUIDE.md](../docs/BUILD_GUIDE.md)

---

## ⚠️ Znane Problemy

1. ~~**Docker pull error**~~ ✅ ROZWIĄZANE - Obrazy budowane lokalnie z `pull_policy: never`
2. **Axum 0.5 vs 0.6** - Projekt używa axum 0.5, nie 0.6 (różnica w API State vs Extension)
3. **Windows API key path** - Na Windows `.api_key` jest w katalogu roboczym, nie w `/opt/rustdesk/`
4. ~~**Urządzenia offline**~~ ✅ ROZWIĄZANE - Docker obrazy używają teraz binarek BetterDesk
5. ~~**"no such table: peer"**~~ ✅ ROZWIĄZANE - Dockerfile.hbbs kopiuje zmodyfikowane binarki

---

## 📝 Wytyczne dla Copilota

### Przy kompilacji:
1. Zawsze używaj `git submodule update --init --recursive` po sklonowaniu rustdesk-server
2. Sprawdź wersję axum w Cargo.toml przed modyfikacją http_api.rs
3. Po kompilacji zaktualizuj CHECKSUMS.md

### Przy modyfikacjach kodu:
1. Kod API jest w `hbbs-patch-v2/src/http_api.rs`
2. Kod main jest w `hbbs-patch-v2/src/main.rs`
3. Używaj `hbb_common::log::info!()` zamiast `println!()`
4. Testuj na SSH (Linux) i lokalnie (Windows)
5. W plikach projektu używaj angielskiego, dokumentacja także ma być po angielsku, upewnij się za każdym razem że twoje zmiany są zgodne z aktualnym stylem i konwencjami projektu, nie wprowadzaj nowych konwencji bez uzasadnienia oraz są napisane w sposób spójny z resztą kodu, unikaj mieszania stylów kodowania, jeśli masz wątpliwości co do stylu, sprawdź istniejący kod i dostosuj się do niego, pamiętaj że spójność jest kluczowa dla utrzymania czytelności i jakości kodu. Wykorzystuj tylko język angielski w komunikacji, dokumentacji i komentarzach, nawet jeśli pracujesz nad polskojęzyczną funkcją, zachowaj angielski dla wszystkich aspektów kodu i dokumentacji, to ułatwi współpracę z innymi deweloperami i utrzyma spójność projektu.
6. Tworząc nowe moduły i zakładki pamiętaj o zachowaniu spójności z istniejącym stylem kodowania, strukturą projektu i konwencjami nazewnictwa, sprawdź istniejące moduły i zakładki, aby upewnić się że twoje zmiany są zgodne z aktualnym stylem, unikaj wprowadzania nowych konwencji bez uzasadnienia, jeśli masz wątpliwości co do stylu, dostosuj się do istniejącego kodu, pamiętaj że spójność jest kluczowa dla utrzymania czytelności i jakości kodu.
7. Przy dodawaniu nowych elementów do panelu web czy innych części projektu upewnij się że są one zgodne z systemem i18n, dodaj odpowiednie klucze do plików tłumaczeń i przetestuj działanie w obu językach, pamiętaj że wszystkie teksty powinny być tłumaczalne i nie powinno się używać hardcoded stringów w kodzie, to ułatwi utrzymanie wielojęzyczności projektu i zapewni spójność w komunikacji z użytkownikami (nie stosuj tych praktyk w przypadku elementów które nie będą bezpośrednio dostępne w interfejsie i które są zwyczajnymi funkcjami w kodzie).

### Przy problemach Docker:
1. Sprawdź czy obrazy są budowane lokalne (`docker compose build`)
2. Nie używaj `docker compose pull` dla obrazów betterdesk-*
3. Sprawdź DOCKER_TROUBLESHOOTING.md

---

## 📞 Kontakt

- **Repozytorium:** https://github.com/UNITRONIX/Rustdesk-FreeConsole
- **Issues:** GitHub Issues

---

*Ostatnia aktualizacja: 2026-02-07 przez GitHub Copilot*
