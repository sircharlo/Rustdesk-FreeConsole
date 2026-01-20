# 🚀 Getting Started - BetterDesk Server v2

## Najszybszy Start (3 kroki)

### Krok 1: Dokończ Implementację

```bash
cd hbbs-patch-v2
chmod +x complete.sh
./complete.sh
```

Ten skrypt automatycznie:
- ✅ Skopiuje brakujący kod z oryginalnego serwera
- ✅ Zastosuje wszystkie optymalizacje timeoutów
- ✅ Zweryfikuje poprawność zmian

### Krok 2: Zbuduj

```bash
chmod +x build.sh
./build.sh
```

To zajmie 5-15 minut w zależności od twojego komputera.

### Krok 3: Uruchom

```bash
# Prosty test
./target/release/hbbs -k YOUR_KEY

# Lub zainstaluj jako serwis (Linux)
sudo cp target/release/hbbs /opt/rustdesk/hbbs-v2
sudo systemctl start betterdesk-v2
```

## ✅ To wszystko!

Masz teraz działający serwer BetterDesk v2 z:
- ⚡ 50% szybszym wykrywaniem offline
- 💾 5x większym poolem połączeń do bazy
- 🛡️ Circuit breaker dla ochrony
- 📊 Quality tracking połączeń
- 🧹 Automatycznym czyszczeniem pamięci

---

## 📖 Więcej Informacji

- **Szybki Start:** [QUICKSTART.md](QUICKSTART.md) - 5-minutowy przewodnik
- **Instalacja:** [INSTALLATION.md](INSTALLATION.md) - Szczegółowa instalacja
- **Zmiany:** [CHANGES.md](CHANGES.md) - Co nowego w v2
- **Kompilacja:** [BUILD.md](BUILD.md) - Troubleshooting budowania

---

## ⚠️ Jeśli Complete.sh Nie Działa

Możesz ręcznie dokończyć implementację:

```bash
# Skopiuj oryginalny plik
cp ../hbbs-patch/src/rendezvous_server.rs src/rendezvous_server.rs

# Zastosuj zmiany timeoutów
sed -i 's/const REG_TIMEOUT: i32 = 30_000/const REG_TIMEOUT: i32 = 15_000/' src/rendezvous_server.rs
sed -i 's/Duration::from_secs(5))/Duration::from_secs(3))/' src/rendezvous_server.rs
sed -i 's/next_timeout(30_000)/next_timeout(20_000)/' src/rendezvous_server.rs
sed -i 's/timeout(30_000/timeout(20_000/' src/rendezvous_server.rs

# Zbuduj
cargo build --release
```

Zobacz [TODO.md](TODO.md) dla szczegółów.

---

## 🎯 Co Dalej

1. **Przetestuj** - Uruchom na porcie testowym (np. 21117)
2. **Zmigruj** - Gdy działa, przełącz urządzenia
3. **Monitoruj** - Obserwuj logi i metryki
4. **Ciesz się** - Stabilniejszy serwer! 🎉

---

## 📞 Potrzebujesz Pomocy?

- 📖 Zobacz [INSTALLATION.md](INSTALLATION.md#troubleshooting)
- 🐛 Zgłoś problem: GitHub Issues
- 💬 Zadaj pytanie: GitHub Discussions

---

**Powodzenia! 🚀**
