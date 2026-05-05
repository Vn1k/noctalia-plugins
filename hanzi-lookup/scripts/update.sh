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
step "Step 1: Memperbarui Skrip Python"

if [ -f "$SCRIPT_DIR/hanzi-lookup.py" ]; then
    info "Menyalin hanzi-lookup.py ke ~/.local/bin/..."
    cp "$SCRIPT_DIR/hanzi-lookup.py" "$BIN_DIR/hanzi-lookup.py"
    chmod +x "$BIN_DIR/hanzi-lookup.py"
    success "Skrip Python berhasil diperbarui."
else
    info "File hanzi-lookup.py tidak ditemukan di $SCRIPT_DIR, melewati..."
fi

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