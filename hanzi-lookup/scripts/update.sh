#!/usr/bin/env bash
# ============================================================
# update.sh — Hanzi Lookup Quick Update Script
# ============================================================

set -e

# ─── Warna output ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
step()    { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ─── Direktori ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/noctalia/plugins/hanzi-lookup"

# ─── Step 1: Update Python Script ────────────────────────────────────────────
# ─── Step 1: Update Python Script ────────────────────────────────────────────
step "Step 1: Memperbarui Skrip Python"

# Array berisi nama-nama file arsitektur Daemon yang baru
PYTHON_SCRIPTS=("hanzi-server.py" "hanzi-client.py" "hanzi_lookup.py" "hanzi-tts.py" "hanzi-translate.py")

for script in "${PYTHON_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        info "Menyalin $script ke ~/.local/bin/..."
        cp "$SCRIPT_DIR/$script" "$BIN_DIR/$script"
        chmod +x "$BIN_DIR/$script"
    else
        # Fallback jika file ada di root project (PROJECT_DIR)
        if [ -f "$PROJECT_DIR/$script" ]; then
            info "Menyalin $script ke ~/.local/bin/..."
            cp "$PROJECT_DIR/$script" "$BIN_DIR/$script"
            chmod +x "$BIN_DIR/$script"
        else
            info "File $script tidak ditemukan, melewati..."
        fi
    fi
done

success "Skrip Python arsitektur Daemon berhasil diperbarui."

# ─── Step 2: Update UI Noctalia ──────────────────────────────────────────────
step "Step 2: Memperbarui Plugin Noctalia"

mkdir -p "$PLUGIN_DIR"

info "Menyalin file QML dan manifest ke direktori plugin..."
# Menyalin semua file QML dan JSON dari root project
cp "$PROJECT_DIR"/*.qml "$PLUGIN_DIR/" 2>/dev/null || true
cp "$PROJECT_DIR"/*.json "$PLUGIN_DIR/" 2>/dev/null || true

success "File antarmuka plugin berhasil diperbarui."

# ─── Selesai ─────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}        UPDATE SELESAI!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "Perubahan pada UI telah diterapkan. Silakan muat ulang (reload)"
echo -e "Noctalia Anda agar QML yang baru dieksekusi."
