# BetterDesk Console - Instrukcje dla Copilota

> Ten plik jest automatycznie dołączany do kontekstu rozmów z GitHub Copilot.
> Zawiera aktualne informacje o stanie projektu i wytyczne do dalszej pracy.

---

## 📊 Stan Projektu (aktualizacja: 2026-02-08)

### Wersja Skryptów ALL-IN-ONE (v2.0.0)

| Plik | Wersja | Platforma | Status |
|------|--------|-----------|--------|
| `betterdesk.sh` | v2.0.0 | Linux | ✅ Nowy - interaktywny ALL-IN-ONE |
| `betterdesk.ps1` | v2.0.0 | Windows | ✅ Nowy - interaktywny ALL-IN-ONE |
| `betterdesk-docker.sh` | v2.0.0 | Docker | ✅ Nowy - interaktywny ALL-IN-ONE |

### Skrypty Legacy (dla zaawansowanych)

| Plik | Wersja | Status |
|------|--------|--------|
| `install-improved.sh` | v1.5.5 | ⚠️ Legacy - bez menu interaktywnego |
| `install-improved.ps1` | v1.5.2 | ⚠️ Legacy - bez menu interaktywnego |

### Binarki Serwera

| Platforma | Plik | Wersja | Status | Data |
|-----------|------|--------|--------|------|
| Linux x86_64 | `hbbs-patch-v2/hbbs-linux-x86_64` | v2.0.0 | ✅ Przetestowana | 2026-02-02 |
| Linux x86_64 | `hbbs-patch-v2/hbbr-linux-x86_64` | v2.0.0 | ✅ Przetestowana | 2026-02-02 |
| Windows x86_64 | `hbbs-patch-v2/hbbs-windows-x86_64.exe` | v2.0.0 | ✅ Przetestowana | 2026-02-04 |
| Windows x86_64 | `hbbs-patch-v2/hbbr-windows-x86_64.exe` | v2.0.0 | ✅ Przetestowana | 2026-02-04 |

### Sumy Kontrolne SHA256

```
Linux:
  hbbs: 2D99FE55378AC6CDED8A4D5BDA717367BBCF17B83B6AADA0D080C02C3BF1B2C1
  hbbr: C7197CF9FCBFB47BB4C9F6D4663DF29B27D2A9AB008FF7AE32A13C6150024528

Windows:
  hbbs: 50BA3BCE44AC607917C2B6870B2859D2F5DB59769E79F6BFB3E757244A53A7F7
  hbbr: 78E7B0F61B7DF8FD780550B8AB9F81F802C3C63CD8171BD93194EC23CA51EB94
```

---

## 🚀 Skrypty ALL-IN-ONE (v2.0.0)

### Funkcje wspólne dla wszystkich skryptów

1. 🚀 **Nowa instalacja** - pełna instalacja od zera
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
# Linux
sudo ./betterdesk.sh

# Windows (PowerShell jako Administrator)
.\betterdesk.ps1

# Docker
./betterdesk-docker.sh
```

---

## 🛠️ Narzędzia Diagnostyczne

### Linux
```bash
# Diagnoza problemów (offline status, zła binarka, porty)
sudo ./install-improved.sh --diagnose

# Szybka naprawa - wymiana binarek na BetterDesk
sudo ./install-improved.sh --fix

# Pełna instalacja/aktualizacja
sudo ./install-improved.sh
```

### Windows (PowerShell)
```powershell
# Diagnoza problemów
.\install-improved.ps1 -Diagnose

# Szybka naprawa binarek
.\install-improved.ps1 -Fix

# Pełna instalacja
.\install-improved.ps1
```

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

## �🔨 Skrypty Budowania

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
