#!/bin/bash
# Skrypt kompilacji BetterDesk dla Windows

source /root/.cargo/env
cd /root/rustdesk-server-1.1.14

echo "=== Kompilacja dla Windows x86_64 ==="
echo "Target: x86_64-pc-windows-gnu"
echo "Start: $(date)"

# Konfiguracja linkera dla Windows
mkdir -p .cargo
cat > .cargo/config.toml << 'EOF'
[target.x86_64-pc-windows-gnu]
linker = "x86_64-w64-mingw32-gcc"
EOF

# Kompilacja
cargo build --release --target x86_64-pc-windows-gnu

echo ""
echo "=== Koniec kompilacji: $(date) ==="
ls -lh target/x86_64-pc-windows-gnu/release/*.exe 2>/dev/null || echo "Brak plików .exe"
