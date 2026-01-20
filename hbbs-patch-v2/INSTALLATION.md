# Instalacja BetterDesk Server v2

## Wymagania

- Rust 1.70+ (dla kompilacji ze źródeł)
- SQLite 3
- Linux/Windows serwer
- Minimum 512MB RAM
- Minimum 1GB przestrzeni dyskowej

## Szybka instalacja (Linux)

### 1. Kompilacja ze źródeł

```bash
# Zainstaluj zależności
sudo apt-get update
sudo apt-get install -y build-essential libsqlite3-dev pkg-config libssl-dev

# Sklonuj repozytorium
cd hbbs-patch-v2

# Kompiluj (wymaga Rust toolchain)
cargo build --release

# Binaria będą w target/release/
```

### 2. Instalacja

```bash
# Utwórz katalog
sudo mkdir -p /opt/rustdesk

# Skopiuj pliki
sudo cp target/release/hbbs /opt/rustdesk/hbbs-v2
sudo chmod +x /opt/rustdesk/hbbs-v2

# Utwórz bazę danych (jeśli migracja z v1)
# Baza z v1 jest kompatybilna
sudo cp /opt/rustdesk/db_v2.sqlite3 /opt/rustdesk/db_v2.sqlite3.backup
```

### 3. Konfiguracja systemd

Utwórz plik `/etc/systemd/system/betterdesk-v2.service`:

```ini
[Unit]
Description=BetterDesk Server v2 Enhanced Edition
After=network.target

[Service]
Type=simple
User=rustdesk
WorkingDirectory=/opt/rustdesk
ExecStart=/opt/rustdesk/hbbs-v2 -p 21116 -k YOUR_KEY_HERE
Restart=always
RestartSec=5
StandardOutput=append:/var/log/rustdesk/hbbs-v2.log
StandardError=append:/var/log/rustdesk/hbbs-v2-error.log

# Enhanced configuration
Environment="MAX_DATABASE_CONNECTIONS=5"
Environment="HEARTBEAT_INTERVAL_SECS=3"
Environment="PEER_TIMEOUT_SECS=15"

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/rustdesk

[Install]
WantedBy=multi-user.target
```

### 4. Uruchomienie

```bash
# Utwórz użytkownika
sudo useradd -r -s /bin/false rustdesk

# Ustaw uprawnienia
sudo chown -R rustdesk:rustdesk /opt/rustdesk
sudo mkdir -p /var/log/rustdesk
sudo chown rustdesk:rustdesk /var/log/rustdesk

# Uruchom serwis
sudo systemctl daemon-reload
sudo systemctl enable betterdesk-v2
sudo systemctl start betterdesk-v2

# Sprawdź status
sudo systemctl status betterdesk-v2
```

## Migracja z v1 do v2

### Bezpieczna migracja bez przestojów:

```bash
# 1. Backup obecnej bazy
sudo cp /opt/rustdesk/db_v2.sqlite3 /opt/rustdesk/db_v2.sqlite3.v1-backup

# 2. Zatrzymaj stary serwer (opcjonalnie - można uruchomić na innym porcie)
sudo systemctl stop hbbs

# 3. Uruchom nowy serwer na tym samym porcie
sudo systemctl start betterdesk-v2

# 4. Zweryfikuj działanie
sudo systemctl status betterdesk-v2
sudo tail -f /var/log/rustdesk/hbbs-v2.log

# 5. Jeśli wszystko działa, usuń stary serwis
sudo systemctl disable hbbs
```

### Migracja z równoczesnym działaniem (zero downtime):

```bash
# 1. Uruchom v2 na innym porcie (np. 21117)
sudo /opt/rustdesk/hbbs-v2 -p 21117 -k YOUR_KEY &

# 2. Przetestuj połączenia z klientami na nowym porcie

# 3. Gdy wszystko działa, przełącz klientów na nowy port

# 4. Zatrzymaj stary serwer
sudo systemctl stop hbbs

# 5. Zmień port v2 na standardowy (21116) i uruchom jako serwis
```

## Konfiguracja zaawansowana

### Zmienne środowiskowe

```bash
# Maksymalna liczba połączeń do bazy danych
MAX_DATABASE_CONNECTIONS=5

# Interwał sprawdzania heartbeat (sekundy)
HEARTBEAT_INTERVAL_SECS=3

# Timeout dla peer'ów (sekundy)
PEER_TIMEOUT_SECS=15

# Ścieżka do bazy danych
DB_URL=/opt/rustdesk/db_v2.sqlite3
```

### Parametry wiersza poleceń

```bash
/opt/rustdesk/hbbs-v2 \
  -p 21116 \                           # Port główny
  -k YOUR_SECRET_KEY \                 # Klucz autoryzacji
  -a 21120 \                           # Port HTTP API
  --max-db-connections=5 \             # Połączenia DB
  --heartbeat-interval=3 \             # Interwał heartbeat
  -r relay1.example.com,relay2.example.com  # Serwery relay
```

## Testowanie

### Test podstawowy

```bash
# Sprawdź czy serwer odpowiada
telnet localhost 21116

# Sprawdź logi
sudo tail -f /var/log/rustdesk/hbbs-v2.log

# Sprawdź API
curl -H "X-API-Key: $(cat /opt/rustdesk/.api_key)" \
  http://localhost:21120/api/health
```

### Test wydajnościowy

```bash
# Sprawdź statystyki połączeń
sudo systemctl status betterdesk-v2

# Monitor w czasie rzeczywistym
watch -n 1 'curl -s -H "X-API-Key: $(cat /opt/rustdesk/.api_key)" \
  http://localhost:21120/api/peers | jq ".data | length"'
```

## Troubleshooting

### Problem: Serwer się nie uruchamia

```bash
# Sprawdź logi
sudo journalctl -u betterdesk-v2 -n 50

# Sprawdź uprawnienia
ls -la /opt/rustdesk/

# Sprawdź port
sudo netstat -tulpn | grep 21116
```

### Problem: Baza danych zablokowana

```bash
# Sprawdź procesy używające bazy
sudo lsof /opt/rustdesk/db_v2.sqlite3

# Jeśli potrzeba, zatrzymaj stare procesy
sudo systemctl stop hbbs
```

### Problem: Wysokie zużycie pamięci

```bash
# Zmniejsz liczbę połączeń DB
sudo systemctl edit betterdesk-v2

# Dodaj:
[Service]
Environment="MAX_DATABASE_CONNECTIONS=3"

# Restart
sudo systemctl restart betterdesk-v2
```

## Monitoring

### Podstawowy monitoring

```bash
# Status serwera
sudo systemctl status betterdesk-v2

# Użycie zasobów
top -p $(pgrep hbbs-v2)

# Statystyki peer'ów (co minutę w logach)
sudo tail -f /var/log/rustdesk/hbbs-v2.log | grep "Peer Statistics"
```

### Integracja z Prometheus (opcjonalnie)

```bash
# Endpoint metryki można dodać w przyszłej wersji
# Na razie można parsować logi
```

## Bezpieczeństwo

### Zabezpieczenie API

```bash
# API key jest generowany automatycznie przy pierwszym uruchomieniu
sudo cat /opt/rustdesk/.api_key

# Zmiana API key
echo "NEW_SECURE_KEY_HERE" | sudo tee /opt/rustdesk/.api_key
sudo chmod 600 /opt/rustdesk/.api_key
sudo chown rustdesk:rustdesk /opt/rustdesk/.api_key
sudo systemctl restart betterdesk-v2
```

### Firewall

```bash
# Otwórz tylko potrzebne porty
sudo ufw allow 21116/tcp  # Główny port
sudo ufw allow 21115/tcp  # NAT test port
sudo ufw allow 21118/tcp  # WebSocket port
sudo ufw allow 21117/udp  # Relay port (jeśli używany)

# API powinno być dostępne tylko z LAN
sudo ufw allow from 192.168.0.0/16 to any port 21120 proto tcp
```

## Wydajność

### Zalecane ustawienia dla różnych obciążeń

**Małe wdrożenie (do 50 urządzeń):**
```bash
MAX_DATABASE_CONNECTIONS=3
HEARTBEAT_INTERVAL_SECS=5
PEER_TIMEOUT_SECS=20
```

**Średnie wdrożenie (50-200 urządzeń):**
```bash
MAX_DATABASE_CONNECTIONS=5
HEARTBEAT_INTERVAL_SECS=3
PEER_TIMEOUT_SECS=15
```

**Duże wdrożenie (200+ urządzeń):**
```bash
MAX_DATABASE_CONNECTIONS=10
HEARTBEAT_INTERVAL_SECS=3
PEER_TIMEOUT_SECS=15
# Rozważ dedykowany serwer z SSD
```

## Backup

```bash
# Automatyczny backup codziennie
sudo cat > /etc/cron.daily/betterdesk-backup << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
cp /opt/rustdesk/db_v2.sqlite3 /opt/rustdesk/backups/db_v2_$DATE.sqlite3
# Zachowaj tylko ostatnie 7 dni
find /opt/rustdesk/backups/ -name "db_v2_*.sqlite3" -mtime +7 -delete
EOF

sudo chmod +x /etc/cron.daily/betterdesk-backup
sudo mkdir -p /opt/rustdesk/backups
```

## Wsparcie

W razie problemów:
1. Sprawdź logi: `/var/log/rustdesk/hbbs-v2.log`
2. Zobacz dokumentację: [docs/](../docs/)
3. Zgłoś issue na GitHub
