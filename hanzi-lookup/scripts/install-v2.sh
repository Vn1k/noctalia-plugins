#!/usr/bin/env bash
# ============================================================
# install.sh — Hanzi Lookup Setup Script (Optimized for Fedora + GPU)
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
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DATA_DIR="$HOME/.local/share/hanzi-lookup"
BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/noctalia/plugins/hanzi-lookup"

CEDICT_URL="https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
CEDICT_GZ="$DATA_DIR/cedict.txt.gz"
CEDICT_FILE="$DATA_DIR/cedict_ts.u8"

# ─── Step 1: Dependensi sistem ───────────────────────────────────────────────
step "Step 1: Install dependensi sistem"

info "Mengecek paket Fedora (grim, slurp)..."
MISSING_PACKAGES=()
for pkg in grim slurp; do
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

# ─── Step 2: Dependensi Python & GPU ─────────────────────────────────────────
step "Step 2: Install dependensi Python (CnOCR + GPU)"

info "Menginstall CnOCR dengan dukungan ONNX Runtime GPU..."
# Menggunakan extra [ort-gpu] untuk dukungan CUDA
pip3 install --upgrade "cnocr[ort-gpu]" onnxruntime-gpu pillow requests --break-system-packages --quiet

if nvidia-smi &>/dev/null; then
    success "NVIDIA GPU terdeteksi, dukungan CUDA siap digunakan."
else
    warn "NVIDIA GPU tidak terdeteksi atau driver belum terpasang. CnOCR akan berjalan di CPU."
fi

# ─── Step 3: Direktori ──────────────────────────────────────────────────────
step "Step 3: Menyiapkan direktori"

mkdir -p "$DATA_DIR" "$BIN_DIR" "$PLUGIN_DIR"
success "Struktur direktori siap"

# ─── Step 4: Database CC-CEDICT ──────────────────────────────────────────────
step "Step 4: Download & Extract Database"

[ -f "$CEDICT_FILE" ] && [ ! -s "$CEDICT_FILE" ] && rm "$CEDICT_FILE"

if [ ! -f "$CEDICT_FILE" ]; then
    info "Downloading CC-CEDICT..."
    curl -L -o "$CEDICT_GZ" "$CEDICT_URL"
    
    info "Mengekstrak database..."
    gunzip -f "$CEDICT_GZ"
    
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

# Prioritas: gunakan file di direktori saat ini atau folder proyek
TARGET_SCRIPT=""
if [ -f "$SCRIPT_DIR/hanzi-lookup.py" ]; then
    TARGET_SCRIPT="$SCRIPT_DIR/hanzi-lookup.py"
elif [ -f "$PROJECT_DIR/hanzi-lookup.py" ]; then
    TARGET_SCRIPT="$PROJECT_DIR/hanzi-lookup.py"
fi

if [ -n "$TARGET_SCRIPT" ]; then
    cp "$TARGET_SCRIPT" "$BIN_DIR/hanzi-lookup.py"
    chmod +x "$BIN_DIR/hanzi-lookup.py"
    success "Script terpasang di $BIN_DIR"
else
    error "hanzi-lookup.py tidak ditemukan!"
fi

# ─── Step 6: Noctalia Plugin ─────────────────────────────────────────────────
step "Step 6: Deploy Noctalia Plugin"

if [ -d "$PROJECT_DIR/plugin" ]; then
    cp -r "$PROJECT_DIR/plugin/"* "$PLUGIN_DIR/"
    success "Plugin disalin ke $PLUGIN_DIR"
else
    warn "Sumber plugin tidak ditemukan di $PROJECT_DIR/plugin"
fi

# ─── Step 7: Verifikasi Final ────────────────────────────────────────────────
step "Step 7: Verifikasi Final"

# Cek Database
ENTRY_COUNT=$(grep -v "^#" "$CEDICT_FILE" | wc -l || echo "0")
if [ "$ENTRY_COUNT" -gt 100000 ]; then
    success "Database Valid: $ENTRY_COUNT entri ditemukan"
else
    error "Database tidak valid atau kosong di $CEDICT_FILE"
fi

# Cek CnOCR
info "Mengetes inisialisasi CnOCR..."
if python3 -c "from cnocr import CnOcr; CnOcr(context='cpu')" &>/dev/null; then
    success "CnOCR Engine siap digunakan"
else
    error "Gagal menginisialisasi CnOCR. Cek instalasi Python."
fi

echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}        SETUP SELESAI!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "CnOCR telah diatur untuk menggunakan GPU secara default."
echo -e "Silakan aktifkan plugin di Noctalia untuk mulai menggunakan."