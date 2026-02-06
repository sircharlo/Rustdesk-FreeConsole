# BetterDesk Console - Instrukcje dla Copilota

> Ten plik jest automatycznie dołączany do kontekstu rozmów z GitHub Copilot.
> Zawiera aktualne informacje o stanie projektu i wytyczne do dalszej pracy.

---

## 📊 Stan Projektu (aktualizacja: 2026-02-06)

### Wersja Instalatorów

| Plik | Wersja | Status |
|------|--------|--------|
| `install-improved.sh` | v1.5.5 | ✅ z --fix, --diagnose, pełna migracja DB |
| `install-improved.ps1` | v1.5.2 | ✅ z -Fix, -Diagnose, pełna migracja DB |

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

### 🔜 Do Zrobienia (priorytety)
1. [ ] **Auto-update workflow** - GitHub Actions do automatycznego pobierania nowej wersji RustDesk i aplikowania patchy
2. [ ] Dodać ARM64 binarki dla Linux (Raspberry Pi)
3. [ ] Dodać automatyczne CI/CD builds (GitHub Actions)
4. [ ] Ulepszyć dokumentację instalacji Windows
5. [ ] Dodać testy jednostkowe dla HTTP API

### 🔄 Planowany Auto-Update Workflow

**Cel:** Automatyczne aktualizowanie bazy RustDesk Server z zachowaniem patchy BetterDesk

**Proces:**
1. GitHub Actions sprawdza nowe tagi w `rustdesk/rustdesk-server`
2. Klonuje nową wersję i aplikuje patche z `hbbs-patch-v2/src/`
3. Próbuje skompilować (`cargo build --release`)
4. Uruchamia testy funkcjonalne API
5. Jeśli sukces → tworzy PR z nową wersją
6. Jeśli błąd → tworzy Issue z logiem błędów

**Pliki do aplikowania:**
- `src/main.rs` - dodaje `--api-port` i uruchamia HTTP API
- `src/http_api.rs` - cały moduł HTTP API (nowy plik)

**Ryzyko:** Zmiany w API axum/sqlx między wersjami RustDesk

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

*Ostatnia aktualizacja: 2026-02-04 przez GitHub Copilot*
