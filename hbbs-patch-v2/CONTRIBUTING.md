# Contributing to BetterDesk Server v2

Dziękujemy za zainteresowanie rozwojem BetterDesk Server v2! 🎉

## 🤝 Jak Pomóc

### Zgłaszanie Problemów (Issues)

Przed zgłoszeniem problemu:
1. Sprawdź czy problem nie został już zgłoszony
2. Upewnij się, że używasz najnowszej wersji
3. Przejrzyj [INSTALLATION.md#troubleshooting](INSTALLATION.md#troubleshooting)

**Dobry zgłoszenie zawiera:**
- System operacyjny i wersja
- Wersja Rust (`rustc --version`)
- Kroki do odtworzenia problemu
- Oczekiwane vs rzeczywiste zachowanie
- Logi błędów (jeśli są)

### Proponowanie Funkcji

Chcesz zaproponować nową funkcję? Świetnie!

1. Otwórz Issue z tagiem `enhancement`
2. Opisz:
   - Jaki problem rozwiązuje
   - Jak ma działać
   - Dlaczego jest potrzebna
3. Dyskutuj z community
4. Implementuj (lub poczekaj aż ktoś zaimplementuje)

### Pull Requests

#### Przed rozpoczęciem:

1. **Dyskusja:** Dla dużych zmian, najpierw otwórz Issue
2. **Fork:** Zrób fork repozytorium
3. **Branch:** Utwórz nowy branch (`git checkout -b feature/amazing-feature`)

#### Podczas implementacji:

```bash
# 1. Zainstaluj dependencies
cargo build

# 2. Implementuj zmiany

# 3. Sprawdź formatowanie
cargo fmt

# 4. Sprawdź linting
cargo clippy

# 5. Przetestuj
cargo test
cargo build --release

# 6. Commit
git commit -m "Add amazing feature"

# 7. Push
git push origin feature/amazing-feature
```

#### Wymagania PR:

- ✅ Kod kompiluje się bez błędów
- ✅ Formatowanie zgodne z `cargo fmt`
- ✅ Brak warningów z `cargo clippy`
- ✅ Testy przechodzą (jeśli są)
- ✅ Dokumentacja zaktualizowana
- ✅ Zmiany opisane w commit message

#### Struktura Commit Message:

```
Type: Short description (max 50 chars)

Longer description if needed. Wrap at 72 characters.
Explain what and why, not how.

Fixes #123
```

**Types:**
- `feat:` - Nowa funkcja
- `fix:` - Naprawa błędu
- `docs:` - Zmiany w dokumentacji
- `style:` - Formatowanie, white-space
- `refactor:` - Refactoring kodu
- `perf:` - Poprawa wydajności
- `test:` - Dodanie testów
- `chore:` - Maintenance (build, deps)

## 📝 Coding Guidelines

### Rust Style

Używamy standardowego stylu Rust:

```rust
// ✅ Dobre
fn handle_connection(stream: TcpStream) -> Result<(), Error> {
    // Implementation
    Ok(())
}

// ❌ Złe
fn handleConnection(stream:TcpStream)->Result<(),Error>{
    //Implementation
    Ok(())
}
```

### Dokumentacja

Każda publiczna funkcja powinna mieć dokumentację:

```rust
/// Handles incoming TCP connection
///
/// # Arguments
/// * `stream` - The TCP stream to handle
///
/// # Returns
/// * `Ok(())` on success
/// * `Err(Error)` on failure
///
/// # Example
/// ```
/// let stream = TcpStream::connect("127.0.0.1:8080")?;
/// handle_connection(stream)?;
/// ```
pub fn handle_connection(stream: TcpStream) -> Result<(), Error> {
    // Implementation
}
```

### Logowanie

Używaj odpowiednich poziomów:

```rust
log::error!("Critical error: {}", e);    // Błędy krytyczne
log::warn!("Warning: {}", msg);          // Ostrzeżenia
log::info!("Server started on {}", port); // Ważne informacje
log::debug!("Processing peer {}", id);   // Debugging
log::trace!("Detailed trace info");      // Bardzo szczegółowe
```

### Obsługa Błędów

```rust
// ✅ Dobre - Propagate errors
fn load_config() -> Result<Config, Error> {
    let content = fs::read_to_string("config.toml")?;
    let config: Config = toml::from_str(&content)?;
    Ok(config)
}

// ❌ Złe - Panic on error
fn load_config() -> Config {
    let content = fs::read_to_string("config.toml").unwrap();
    toml::from_str(&content).unwrap()
}
```

## 🧪 Testowanie

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connection_quality() {
        let quality = ConnectionQuality::default();
        assert_eq!(quality.missed_heartbeats, 0);
    }

    #[tokio::test]
    async fn test_database_connection() {
        let db = Database::new("test.db").await.unwrap();
        // Test implementation
    }
}
```

### Integration Tests

```bash
# Utwórz plik tests/integration_test.rs
cargo test --test integration_test
```

## 📊 Obszary Potrzebujące Pomocy

### Priorytet Wysoki:
- [ ] Testy jednostkowe dla wszystkich modułów
- [ ] Benchmarki wydajnościowe
- [ ] Cross-platform testing (Windows, macOS, Linux)
- [ ] Load testing (100+ concurrent connections)

### Priorytet Średni:
- [ ] Prometheus metrics endpoint
- [ ] WebSocket dla real-time monitoring
- [ ] Admin panel web UI
- [ ] PostgreSQL support
- [ ] Automated CI/CD pipeline

### Priorytet Niski:
- [ ] Docker compose setup
- [ ] Kubernetes manifests
- [ ] Clustering support
- [ ] High availability configuration

## 🎯 Roadmap

### v2.1 (Q2 2024)
- [ ] Complete test coverage (>80%)
- [ ] Prometheus metrics
- [ ] Performance benchmarks
- [ ] Windows service support

### v2.2 (Q3 2024)
- [ ] WebSocket monitoring
- [ ] Admin web UI
- [ ] PostgreSQL support
- [ ] Docker official images

### v3.0 (Q4 2024)
- [ ] Clustering support
- [ ] High availability
- [ ] Load balancing
- [ ] Multi-region support

## 🏆 Contributors

Dziękujemy wszystkim kontrybutom! 

(Lista będzie aktualizowana automatycznie)

## 📜 License

Kontrybuując do tego projektu, zgadzasz się że twój kod będzie licencjonowany 
pod licencją AGPL-3.0, tak jak reszta projektu.

## ❓ Pytania?

Masz pytania? Nie wiesz od czego zacząć?

- 💬 **GitHub Discussions** - Zadaj pytanie
- 📖 **Dokumentacja** - Zobacz [INDEX.md](INDEX.md)
- 🐛 **Issues** - Zgłoś problem

---

**Dziękujemy za pomoc w rozwoju BetterDesk Server v2! 🚀**
