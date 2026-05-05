#!/usr/bin/env bash
# ============================================================
# install.sh — Hanzi Lookup Setup Script (Optimized for Fedora)
# ============================================================

set -e

# ─── Warna output ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ─── Direktori ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Jika script di dalam folder 'scripts/', maka project dir adalah satu level di atasnya
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DATA_DIR="$HOME/.local/share/hanzi-lookup"
BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/noctalia/plugins/hanzi-lookup"

CEDICT_URL="https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
CEDICT_GZ="$DATA_DIR/cedict.txt.gz"
CEDICT_FILE="$DATA_DIR/cedict_ts.u8"

# ─── Step 1: Dependensi sistem ───────────────────────────────────────────────
step "Step 1: Install dependensi sistem"

info "Mengecek paket Fedora..."
# Fedora menggunakan chi_sim (underscore) bukan chi-sim (hyphen)
MISSING_PACKAGES=()
for pkg in grim slurp tesseract tesseract-langpack-chi_sim; do
    if ! rpm -q "$pkg" &>/dev/null 2>&1; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    info "Menginstall: ${MISSING_PACKAGES[*]}"
    sudo dnf install -y "${MISSING_PACKAGES[@]}"
else
    success "Dependensi sistem sudah terpenuhi"
fi

# ─── Step 2: Dependensi Python ───────────────────────────────────────────────
step "Step 2: Install dependensi Python"

info "Mengupdate pytesseract dan Pillow..."
# Menggunakan --upgrade untuk memastikan versi terbaru di Python 3.14
pip3 install --upgrade pytesseract pillow --break-system-packages --quiet
success "Dependensi Python OK"

# ─── Step 3: Direktori ──────────────────────────────────────────────────────
step "Step 3: Menyiapkan direktori"

mkdir -p "$DATA_DIR" "$BIN_DIR" "$PLUGIN_DIR"
success "Struktur direktori siap"

# ─── Step 4: Database CC-CEDICT ──────────────────────────────────────────────
step "Step 4: Download & Extract Database"

# Hapus file lama jika korup (0 bytes)
[ -f "$CEDICT_FILE" ] && [ ! -s "$CEDICT_FILE" ] && rm "$CEDICT_FILE"

if [ ! -f "$CEDICT_FILE" ]; then
    info "Downloading CC-CEDICT..."
    curl -L -o "$CEDICT_GZ" "$CEDICT_URL"
    
    info "Mengekstrak database..."
    # gunzip akan menghasilkan file bernama cedict.txt jika inputnya cedict.txt.gz
    gunzip -f "$CEDICT_GZ"
    
    # Cari file hasil ekstrak (biasanya cedict.txt atau nama asli dari MDBG)
    EXTRACTED_FILE=$(ls "$DATA_DIR"/cedict* | grep -v ".log" | head -n 1)
    
    if [ -f "$EXTRACTED_FILE" ]; then
        mv "$EXTRACTED_FILE" "$CEDICT_FILE"
        success "Database berhasil diinstal ke $CEDICT_FILE"
    else
        error "Gagal menemukan file hasil ekstrak"
    fi
else
    success "Database CC-CEDICT sudah ada"
fi

# ─── Step 5: Install Script ──────────────────────────────────────────────────
step "Step 5: Deploy Python Script"

if [ -f "$SCRIPT_DIR/hanzi-lookup.py" ]; then
    cp "$SCRIPT_DIR/hanzi-lookup.py" "$BIN_DIR/hanzi-lookup.py"
    chmod +x "$BIN_DIR/hanzi-lookup.py"
    success "Script terpasang di $BIN_DIR"
else
    # Jika dijalankan dari root project, bukan dari folder scripts
    if [ -f "$PROJECT_DIR/hanzi-lookup.py" ]; then
        cp "$PROJECT_DIR/hanzi-lookup.py" "$BIN_DIR/hanzi-lookup.py"
        chmod +x "$BIN_DIR/hanzi-lookup.py"
    else
        warn "hanzi-lookup.py tidak ditemukan di $SCRIPT_DIR"
    fi
fi

# ─── Step 6: Noctalia Plugin ─────────────────────────────────────────────────
step "Step 6: Deploy Noctalia Plugin"

# Mencoba mencari folder 'plugin' di root project
if [ -d "$PROJECT_DIR/plugin" ]; then
    cp -r "$PROJECT_DIR/plugin/"* "$PLUGIN_DIR/"
    success "Plugin disalin ke $PLUGIN_DIR"
else
    warn "Sumber plugin tidak ditemukan di $PROJECT_DIR/plugin"
fi

# ─── Step 7: Verifikasi Akhir ────────────────────────────────────────────────
step "Step 7: Verifikasi Final"

ENTRY_COUNT=$(grep -v "^#" "$CEDICT_FILE" | wc -l || echo "0")
if [ "$ENTRY_COUNT" -gt 100000 ]; then
    success "Database Valid: $ENTRY_COUNT entri ditemukan"
else
    error "Database tidak valid atau kosong. Silakan cek $CEDICT_FILE"
fi

if tesseract --list-langs | grep -q "chi_sim"; then
    success "OCR Mandarin (chi_sim) tersedia"
else
    error "OCR Mandarin tidak ditemukan di Tesseract"
fi

echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}        SETUP SELESAI!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "Silakan aktifkan plugin di Noctalia dan tambahkan keybind di Niri."