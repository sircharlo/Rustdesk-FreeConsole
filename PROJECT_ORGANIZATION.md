# 📁 Organizacja Projektu BetterDesk Console

## 📂 Struktura Katalogów

```
BetterDesk-Console/
│
├── 📄 README.md                      # Główna dokumentacja projektu
├── 📄 LICENSE                        # Licencja MIT
├── 📄 VERSION                        # Wersja projektu (1.2.0-v8)
├── 📄 CHANGELOG.md                   # Historia zmian
├── 📄 CONTRIBUTING.md                # Wytyczne dla kontrybutorów
├── 📄 PROJECT_STRUCTURE.md           # Opis struktury technicznej
│
├── 🔧 install-improved.sh            # ⭐ Instalator Linux (v9 - UŻYWAJ TEGO)
├── 🔧 install-improved.ps1           # ⭐ Instalator Windows (v9 - UŻYWAJ TEGO)
│
├── 📁 hbbs-patch/                    # ⭐ Zmodyfikowane serwery HBBS/HBBR
│   ├── 📁 src/                       # Kod źródłowy modyfikacji
│   │   ├── peer.rs                   # Zarządzanie peer-ami (20s timeout)
│   │   ├── database.rs               # Metody bazodanowe (ban checking)
│   │   ├── http_api.rs               # HTTP API (Axum, port 21114)
│   │   ├── main.rs                   # Punkt wejścia HBBS
│   │   └── rendezvous_server.rs      # Główny serwer sygnałowy
│   │
│   ├── 📁 bin-with-api/              # ⭐ BINARIA Z HTTP API (używane przez instalatory)
│   │   ├── hbbs-v8-api               # Linux binary (10 MB)
│   │   ├── hbbr-v8-api               # Linux binary (4.9 MB)
│   │   ├── hbbs-v8-api.exe           # Windows binary (6.58 MB)
│   │   └── hbbr-v8-api.exe           # Windows binary (2.76 MB)
│   │
│   ├── 📁 bin/                       # Stare binaria (fallback, bez API)
│   ├── 📁 hbbs-ban-check-package/    # Backup kompilacji
│   ├── 🔧 build.sh                   # Skrypt kompilacji Linux
│   ├── 🔧 build-windows-local.ps1    # Skrypt kompilacji Windows
│   └── 📄 README.md                  # Dokumentacja patchy
│
├── 📁 web/                           # ⭐ Konsola webowa Flask
│   ├── app.py                        # Główna aplikacja Flask
│   ├── requirements.txt              # Zależności Pythona
│   ├── betterdesk.service            # Systemd service (Linux)
│   ├── 📁 templates/                 # Szablony HTML
│   │   └── index.html                # Główny interfejs
│   └── 📁 static/                    # Zasoby statyczne
│       ├── style.css                 # CSS (glassmorphism)
│       ├── script.js                 # JavaScript
│       └── MATERIAL_ICONS.md         # Info o ikonach
│
├── 📁 docs/                          # Szczegółowa dokumentacja
│   ├── UPDATE_GUIDE.md               # Instrukcje aktualizacji
│   ├── INSTALLATION_V8.md            # Instalacja v8
│   ├── DEVELOPMENT_ROADMAP.md        # Mapa rozwoju
│   └── RELEASE_NOTES_v1.2.0.md       # Notatki wydania
│
├── 📁 migrations/                    # Migracje bazy danych
│   ├── v1.0.1_soft_delete.py         # Soft delete dla urządzeń
│   └── v1.1.0_device_bans.py         # System banowania
│
├── 📁 dev_modules/                   # Narzędzia deweloperskie
│   ├── check_database.py             # Sprawdzanie DB
│   ├── test_ban_api.sh               # Testowanie API banów
│   └── update.ps1                    # Stary update script
│
├── 📁 screenshots/                   # Zrzuty ekranu do dokumentacji
│
└── 📁 archive/                       # ⭐ ARCHIWUM (stare/nieużywane pliki)
    ├── hbbs-patch-backup-*/          # Stare backupy
    ├── install.sh                    # Stary instalator (v1-v8)
    ├── update.sh                     # Stary update script
    ├── restore_hbbs.sh               # Stary restore script
    └── *.md                          # Stara dokumentacja
```

---

## 🎯 Która Wersja Instalatora?

### ✅ UŻYWAJ (Aktualne, zalecane)

| Plik | System | Wersja | Cechy |
|------|--------|--------|-------|
| **install-improved.sh** | Linux | v9 | Docker support, custom paths, --break-system-packages |
| **install-improved.ps1** | Windows | v9 | Path detection, validation, Windows services |

### ⚠️ ARCHIWUM (Nieaktualne, tylko do referencji)

| Plik | System | Status |
|------|--------|--------|
| archive/install.sh | Linux | Zastąpiony przez install-improved.sh |
| archive/update.sh | Linux | Zastąpiony przez install-improved.sh |
| archive/restore_hbbs.sh | Linux | Przestarzały |

---

## 🔑 Kluczowe Pliki do Edycji

### Modyfikujesz funkcjonalność serwera?
→ Edytuj: `hbbs-patch/src/*.rs`
→ Kompiluj: `bash hbbs-patch/build.sh` (Linux) lub `.\hbbs-patch\build-windows-local.ps1` (Windows)

### Modyfikujesz interfejs webowy?
→ Edytuj: `web/templates/index.html`, `web/static/style.css`, `web/static/script.js`
→ Restart: `sudo systemctl restart betterdesk` (Linux)

### Modyfikujesz logikę Flask?
→ Edytuj: `web/app.py`
→ Restart: `sudo systemctl restart betterdesk` (Linux)

### Modyfikujesz instalator?
→ Edytuj: `install-improved.sh` (Linux) lub `install-improved.ps1` (Windows)
→ Test: Uruchom w środowisku testowym przed wdrożeniem

---

## ⚡ Binaria - Ważne!

### Struktura `hbbs-patch/bin-with-api/`

```
bin-with-api/
├── hbbs-v8-api         ← Linux (ELF 64-bit LSB executable, x86-64)
├── hbbr-v8-api         ← Linux (ELF 64-bit LSB executable, x86-64)
├── hbbs-v8-api.exe     ← Windows (PE32+ executable, x86-64)
└── hbbr-v8-api.exe     ← Windows (PE32+ executable, x86-64)
```

### ⛔ NIGDY nie mieszaj binariów między platformami!

- **Linux installer** (`install-improved.sh`) używa plików **BEZ rozszerzenia .exe**
- **Windows installer** (`install-improved.ps1`) używa plików **Z rozszerzeniem .exe**

### Skąd się biorą binaria?

```bash
# Linux (kompilacja na serwerze SSH lub natywnym Linux)
cd hbbs-patch
bash build.sh

# Windows (kompilacja lokalna z Rust toolchain)
cd hbbs-patch
.\build-windows-local.ps1
```

Po kompilacji binaria trafiają automatycznie do `bin-with-api/`.

---

## 🔄 Workflow Rozwoju

### 1. Zmiana kodu źródłowego

```bash
# Edytuj pliki w hbbs-patch/src/
nano hbbs-patch/src/peer.rs

# Kompiluj
cd hbbs-patch
bash build.sh  # Linux
# LUB
.\build-windows-local.ps1  # Windows
```

### 2. Testowanie lokalne

```bash
# Zatrzymaj istniejące serwisy
sudo systemctl stop rustdesksignal rustdeskrelay

# Uruchom nowe binaria ręcznie
cd hbbs-patch/bin-with-api
./hbbs-v8-api -h  # Test

# Jeśli działa, zainstaluj
cd ../..
sudo ./install-improved.sh
```

### 3. Wdrożenie produkcyjne

```bash
# Utwórz backup (automatyczny w instalatorze)
# Uruchom instalator
sudo ./install-improved.sh

# Sprawdź logi
sudo journalctl -u rustdesksignal -f
```

---

## 📊 Zależności między Komponentami

```
┌─────────────────────────────────────────────┐
│         Klient RustDesk                     │
│     (Desktop/Mobile/Web)                    │
└──────────────┬──────────────────────────────┘
               │ heartbeat (~20-30s)
               ▼
┌─────────────────────────────────────────────┐
│    HBBS Server (hbbs-v8-api)                │
│    - peer.rs: zarządzanie połączeniami      │
│    - database.rs: ban checking              │
│    - http_api.rs: REST API (21114)          │
└─────────────┬───────────────────────────────┘
              │
    ┌─────────┴──────────┐
    ▼                    ▼
┌─────────┐      ┌──────────────┐
│ SQLite  │      │ Arc<PeerMap> │
│ (bany,  │◄────►│ (status w    │
│ devices)│      │  pamięci)    │
└─────────┘      └──────┬───────┘
                        │ HTTP GET /api/peers
                        ▼
              ┌──────────────────┐
              │  Flask Web App   │
              │  (port 5000)     │
              │  - app.py        │
              │  - templates/    │
              │  - static/       │
              └──────────────────┘
```

---

## 🔧 Utrzymanie i Troubleshooting

### Sprawdź status serwisów

```bash
# Linux
sudo systemctl status rustdesksignal
sudo systemctl status rustdeskrelay
sudo systemctl status betterdesk

# Windows
Get-Service RustDesk*
```

### Logi

```bash
# Linux
sudo journalctl -u rustdesksignal -f
sudo journalctl -u betterdesk -f

# Windows
Get-EventLog -LogName Application -Source RustDesk*
```

### Restart po zmianach

```bash
# Linux
sudo systemctl restart rustdesksignal rustdeskrelay betterdesk

# Windows
Restart-Service RustDesk*
```

---

## 📦 Co Należy do Repozytorium?

### ✅ Commituj:
- Kod źródłowy (`hbbs-patch/src/`)
- Skrypty (`*.sh`, `*.ps1`)
- Dokumentację (`*.md`)
- Szablony i static files (`web/`)
- Binaria w `hbbs-patch/bin-with-api/` (precompiled releases)

### ⛔ NIE commituj:
- Katalogi kompilacji (`hbbs-patch/rustdesk-server-*/`, `target/`)
- Pliki ZIP (`*.zip`, `*.tar.gz`)
- Backupy (`*backup*`, `*.old`)
- Logi (`*.log`)
- Bazy danych (`*.sqlite3`, `*.db`)
- Klucze prywatne (`id_*`)

---

## 🆘 Pytania?

Jeśli coś jest niejasne:
1. Sprawdź `README.md` - główna dokumentacja
2. Zobacz `docs/` - szczegółowe instrukcje
3. Przejrzyj `hbbs-patch/README.md` - technikalia
4. Zajrzyj do `archive/` - historia projektu

**Podstawowe zasady:**
- Wszystkie nowe funkcje dokumentuj w CHANGELOG.md
- Testy przed wdrożeniem produkcyjnym
- Backupy przed każdą większą zmianą
- Binaria specyficzne dla platformy NIE są zamienne
