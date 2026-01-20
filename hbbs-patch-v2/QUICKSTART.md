# Quick Start Guide - BetterDesk Server v2

## Najważniejsze informacje

### Co to jest BetterDesk Server v2?

Ulepszona, stabilniejsza wersja serwera RustDesk/BetterDesk z kluczowymi optymalizacjami:

- ✅ **50% szybsze wykrywanie offline** (15s zamiast 30s)
- ✅ **5x więcej połączeń do bazy** (pool 5 zamiast 1)
- ✅ **Circuit breaker** - ochrona przed przeciążeniem DB
- ✅ **Retry logic** - automatyczne odzyskiwanie po błędach
- ✅ **Lepsze logowanie** - szczegółowa diagnostyka
- ✅ **100% kompatybilność** z obecnymi urządzeniami

## Szybki Start (Linux)

### 1. Kompilacja

```bash
cd hbbs-patch-v2
cargo build --release
```

### 2. Instalacja

```bash
sudo cp target/release/hbbs /opt/rustdesk/hbbs-v2
sudo chmod +x /opt/rustdesk/hbbs-v2
```

### 3. Uruchomienie

```bash
# Najprostsza wersja
/opt/rustdesk/hbbs-v2 -k YOUR_KEY

# Z pełną konfiguracją
/opt/rustdesk/hbbs-v2 \
  -p 21116 \
  -k YOUR_KEY \
  --max-db-connections=5 \
  --heartbeat-interval=3
```

### 4. Jako serwis (systemd)

```bash
# Skopiuj konfigurację z INSTALLATION.md
sudo systemctl enable betterdesk-v2
sudo systemctl start betterdesk-v2
sudo systemctl status betterdesk-v2
```

## Porównanie z v1

| Feature | v1 | v2 |
|---------|----|----|
| Wykrycie offline | 30s | **15s** ⚡ |
| Połączenia DB | 1 | **5** ⚡ |
| Retry logic | ❌ | **✅** |
| Circuit breaker | ❌ | **✅** |
| Batch operations | ❌ | **✅** |
| Connection quality tracking | ❌ | **✅** |
| Automatic cleanup | ❌ | **✅** |
| Enhanced logging | ⚠️ | **✅** |

## Konfiguracja

### Parametry Wiersza Poleceń

```bash
-p, --port=PORT              # Port główny (domyślnie: 21116)
-k, --key=KEY                # Klucz autoryzacji
-a, --api-port=PORT          # Port HTTP API (domyślnie: 21120)
--max-db-connections=N       # Połączenia DB (domyślnie: 5)
--heartbeat-interval=SECS    # Interwał heartbeat (domyślnie: 3)
```

### Zmienne Środowiskowe

```bash
MAX_DATABASE_CONNECTIONS=5   # Pool połączeń do bazy
HEARTBEAT_INTERVAL_SECS=3    # Częstotliwość sprawdzania peer'ów
PEER_TIMEOUT_SECS=15         # Timeout dla peer'ów
DB_URL=/path/to/db.sqlite3   # Ścieżka do bazy danych
```

## Migracja z v1

### Opcja 1: Bezpośrednia Wymiana

```bash
# 1. Backup
sudo cp /opt/rustdesk/db_v2.sqlite3 /opt/rustdesk/db_v2.sqlite3.backup

# 2. Stop v1
sudo systemctl stop hbbs

# 3. Start v2
sudo systemctl start betterdesk-v2

# 4. Sprawdź
sudo tail -f /var/log/rustdesk/hbbs-v2.log
```

### Opcja 2: Zero Downtime

```bash
# 1. Uruchom v2 na innym porcie
/opt/rustdesk/hbbs-v2 -p 21117 -k YOUR_KEY &

# 2. Przetestuj z kilkoma urządzeniami

# 3. Przełącz wszystkie urządzenia na port 21117

# 4. Zatrzymaj v1
sudo systemctl stop hbbs

# 5. Zmień v2 na standardowy port 21116
```

## Monitoring

### Podstawowy

```bash
# Status
sudo systemctl status betterdesk-v2

# Logi
sudo tail -f /var/log/rustdesk/hbbs-v2.log

# Logi tylko błędy
sudo tail -f /var/log/rustdesk/hbbs-v2.log | grep ERROR

# Statystyki co minutę
sudo tail -f /var/log/rustdesk/hbbs-v2.log | grep "Peer Statistics"
```

### HTTP API

```bash
# Health check
curl -H "X-API-Key: $(cat /opt/rustdesk/.api_key)" \
  http://localhost:21120/api/health

# Lista peer'ów
curl -H "X-API-Key: $(cat /opt/rustdesk/.api_key)" \
  http://localhost:21120/api/peers | jq

# Szczegóły peer'a
curl -H "X-API-Key: $(cat /opt/rustdesk/.api_key)" \
  http://localhost:21120/api/peers/PEER_ID | jq
```

## Troubleshooting

### Serwer się nie uruchamia

```bash
# Sprawdź logi
sudo journalctl -u betterdesk-v2 -n 50

# Sprawdź port
sudo netstat -tulpn | grep 21116

# Sprawdź uprawnienia
ls -la /opt/rustdesk/
```

### Wysokie zużycie pamięci

```bash
# Zmniejsz połączenia DB
export MAX_DATABASE_CONNECTIONS=3

# Zwiększ interwał heartbeat
export HEARTBEAT_INTERVAL_SECS=5
```

### Baza danych zablokowana

```bash
# Sprawdź procesy
sudo lsof /opt/rustdesk/db_v2.sqlite3

# Zatrzymaj stare procesy
sudo systemctl stop hbbs
```

## Zalecane Ustawienia

### Małe Wdrożenie (<50 urządzeń)

```bash
MAX_DATABASE_CONNECTIONS=3
HEARTBEAT_INTERVAL_SECS=5
PEER_TIMEOUT_SECS=20
```

### Średnie Wdrożenie (50-200 urządzeń)

```bash
MAX_DATABASE_CONNECTIONS=5
HEARTBEAT_INTERVAL_SECS=3
PEER_TIMEOUT_SECS=15
```

### Duże Wdrożenie (200+ urządzeń)

```bash
MAX_DATABASE_CONNECTIONS=10
HEARTBEAT_INTERVAL_SECS=3
PEER_TIMEOUT_SECS=15
# + dedykowany serwer z SSD
```

## FAQ

**Q: Czy muszę zmienić coś w klientach RustDesk?**
A: Nie, v2 jest w pełni kompatybilny z obecnymi klientami.

**Q: Czy mogę użyć tej samej bazy danych co v1?**
A: Tak, baza danych jest w pełni kompatybilna.

**Q: Co jeśli chcę wrócić do v1?**
A: Po prostu zatrzymaj v2 i uruchom v1. Baza danych jest kompatybilna w obie strony.

**Q: Czy v2 zużywa więcej zasobów?**
A: Nieznacznie więcej RAM (~20%) przez connection pooling, ale jest znacznie wydajniejszy.

**Q: Jak długo trwa migracja?**
A: Dla małych wdrożeń: ~5 minut. Dla dużych: można stopniowo migrować przez kilka dni.

**Q: Co się stanie z obecnymi połączeniami podczas migracji?**
A: Przy direct replacement będzie krótka przerwa (~30s). Przy zero downtime - żadnej przerwy.

## Wsparcie i Dokumentacja

- **Pełna instalacja:** [INSTALLATION.md](INSTALLATION.md)
- **Porównanie zmian:** [CHANGES.md](CHANGES.md)
- **Readme główne:** [README.md](README.md)
- **Issues:** GitHub Issues

## Licencja

AGPL-3.0 (zgodnie z RustDesk)
