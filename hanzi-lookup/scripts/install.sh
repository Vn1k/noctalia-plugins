#!/usr/bin/env bash
# ============================================================
# install.sh — Hanzi Lookup Setup Script untuk Fedora
# ============================================================
# Apa yang dilakukan:
#   1. Install dependensi sistem (grim, slurp, tesseract)
#   2. Install dependensi Python (pytesseract, pillow)
#   3. Download CC-CEDICT database
#   4. Copy Python script ke ~/.local/bin/
#   5. Copy Noctalia plugin ke ~/.config/noctalia/plugins/
#   6. Print instruksi konfigurasi niri keybind
# ============================================================

set -e  # Exit on error

# ─── Warna output ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

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
LOG_DIR="$DATA_DIR"

CEDICT_URL="https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
CEDICT_GZ="$DATA_DIR/cedict.txt.gz"
CEDICT_FILE="$DATA_DIR/cedict_ts.u8"

# ─── Step 1: Dependensi sistem ───────────────────────────────────────────────
step "Step 1: Install dependensi sistem"

info "Mengecek paket yang dibutuhkan..."

MISSING_PACKAGES=()
for pkg in grim slurp tesseract tesseract-langpack-chi_sim; do
    if ! rpm -q "$pkg" &>/dev/null 2>&1; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    info "Paket yang perlu diinstall: ${MISSING_PACKAGES[*]}"
    sudo dnf install -y "${MISSING_PACKAGES[@]}"
    success "Dependensi sistem terinstall"
else
    success "Semua dependensi sistem sudah ada"
fi

# Verifikasi tesseract chi_sim tersedia
if ! tesseract --list-langs 2>/dev/null | grep -q "chi_sim"; then
    warn "chi_sim langpack tidak terdeteksi, mencoba install..."
    sudo dnf install -y tesseract-langpack-chi-sim || \
    sudo dnf install -y tesseract-osd || \
    warn "Install manual: sudo dnf install tesseract-langpack-chi-sim"
fi

# ─── Step 2: Dependensi Python ───────────────────────────────────────────────
step "Step 2: Install dependensi Python"

info "Menginstall pytesseract dan Pillow..."
pip3 install pytesseract pillow --break-system-packages --quiet
success "Dependensi Python terinstall"

# ─── Step 3: Direktori data ──────────────────────────────────────────────────
step "Step 3: Menyiapkan direktori"

mkdir -p "$DATA_DIR" "$BIN_DIR" "$PLUGIN_DIR"
success "Direktori dibuat: $DATA_DIR"

# ─── Step 4: Download CC-CEDICT ──────────────────────────────────────────────
step "Step 4: Download CC-CEDICT database"

if [ -f "$CEDICT_FILE" ]; then
    ENTRY_COUNT=$(grep -c "^[^#]" "$CEDICT_FILE" 2>/dev/null || echo "0")
    info "CC-CEDICT sudah ada ($ENTRY_COUNT entri)"

    read -r -p "Download ulang? [y/N] " REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        info "Melewati download"
    else
        DOWNLOAD_CEDICT=1
    fi
else
    DOWNLOAD_CEDICT=1
fi

if [ "${DOWNLOAD_CEDICT:-0}" = "1" ]; then
    info "Downloading CC-CEDICT dari $CEDICT_URL ..."
    info "(Ukuran sekitar 6MB)"

    if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$CEDICT_GZ" "$CEDICT_URL"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "$CEDICT_GZ" "$CEDICT_URL"
    else
        error "curl atau wget tidak ditemukan"
    fi

    info "Mengekstrak..."
    gunzip -f "$CEDICT_GZ"
    # File hasil ekstrak biasanya bernama cedict_1_0_ts_utf-8_mdbg.txt
    EXTRACTED=$(ls "$DATA_DIR"/cedict_*.txt 2>/dev/null | head -1)
    if [ -n "$EXTRACTED" ] && [ "$EXTRACTED" != "$CEDICT_FILE" ]; then
        mv "$EXTRACTED" "$CEDICT_FILE"
    fi

    ENTRY_COUNT=$(grep -c "^[^#]" "$CEDICT_FILE" 2>/dev/null || echo "0")
    success "CC-CEDICT terinstall: $ENTRY_COUNT entri"
fi

# ─── Step 5: Copy Python script ──────────────────────────────────────────────
step "Step 5: Install Python script"

cp "$SCRIPT_DIR/hanzi-lookup.py" "$BIN_DIR/hanzi-lookup.py"
chmod +x "$BIN_DIR/hanzi-lookup.py"

# Buat wrapper shell script yang lebih mudah dipanggil
cat > "$BIN_DIR/hanzi-lookup" << 'EOF'
#!/usr/bin/env bash
# Wrapper untuk hanzi-lookup.py
exec python3 "$HOME/.local/bin/hanzi-lookup.py" "$@"
EOF
chmod +x "$BIN_DIR/hanzi-lookup"

success "Script diinstall di $BIN_DIR/hanzi-lookup"

# Pastikan ~/.local/bin ada di PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    warn "$BIN_DIR tidak ada di PATH"
    warn "Tambahkan ke ~/.bashrc atau ~/.zshrc:"
    warn '  export PATH="$HOME/.local/bin:$PATH"'
fi

# ─── Step 6: Install Noctalia plugin ─────────────────────────────────────────
step "Step 6: Install Noctalia plugin"

if [ -d "$PROJECT_DIR/plugin" ]; then
    cp -r "$PROJECT_DIR/plugin/"* "$PLUGIN_DIR/"
    success "Plugin diinstall di $PLUGIN_DIR"
else
    warn "Direktori plugin tidak ditemukan di $PROJECT_DIR/plugin"
    warn "Copy manual file QML ke $PLUGIN_DIR"
fi

# ─── Step 7: Test dasar ──────────────────────────────────────────────────────
step "Step 7: Verifikasi instalasi"

# Test Python import
if python3 -c "import pytesseract, PIL; print('OK')" &>/dev/null; then
    success "Python dependencies OK"
else
    warn "Python dependencies bermasalah, cek log di atas"
fi

# Test tesseract
if tesseract --version &>/dev/null; then
    TESS_VER=$(tesseract --version 2>&1 | head -1)
    success "Tesseract OK: $TESS_VER"
else
    error "Tesseract tidak ditemukan"
fi

# Test grim
if command -v grim &>/dev/null; then
    success "grim OK"
else
    warn "grim tidak ditemukan"
fi

# Test slurp
if command -v slurp &>/dev/null; then
    success "slurp OK"
else
    warn "slurp tidak ditemukan"
fi

# Test lookup sederhana (tanpa screenshot)
info "Test lookup 你好..."
if python3 "$BIN_DIR/hanzi-lookup.py" --text "你好" 2>&1 | grep -q "Mengirim"; then
    success "Lookup test OK"
else
    warn "Lookup test gagal (mungkin karena Noctalia belum berjalan - itu normal)"
fi

# ─── Selesai: Instruksi ──────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Instalasi selesai!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "Langkah selanjutnya:"
echo ""
echo -e "${CYAN}1. Enable plugin di Noctalia Settings${NC}"
echo -e "   Buka Settings → Plugins → Cari 'Hanzi Lookup' → Enable"
echo ""
echo -e "${CYAN}2. Tambahkan keybind di niri config${NC}"
echo -e "   Edit ~/.config/niri/config.kdl, tambahkan:"
echo -e ""
echo -e "   ${YELLOW}binds {"
echo -e "     // Hanzi Lookup: tekan untuk pilih area layar"
echo -e "     Super+Z { spawn \"bash\" \"-c\" \"python3 ~/.local/bin/hanzi-lookup.py &\"; }"
echo -e "   }${NC}"
echo ""
echo -e "${CYAN}3. Test manual${NC}"
echo -e "   python3 ~/.local/bin/hanzi-lookup.py --text '你好世界'"
echo ""
echo -e "${CYAN}4. Reload niri config${NC}"
echo -e "   niri msg action reload-config"
echo ""
echo -e "Log ada di: ${DATA_DIR}/hanzi-lookup.log"
