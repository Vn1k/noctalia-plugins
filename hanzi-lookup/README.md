# Hanzi Lookup — Noctalia Plugin

Lookup pinyin + arti Hanzi simplified Chinese dari screenshot area layar,
terintegrasi sebagai Noctalia panel.

## Cara Kerja

```
[Super+Z] → pilih area layar → OCR → CC-CEDICT lookup → Panel Noctalia
```

1. Tekan hotkey `Super+Z`
2. Kursor berubah jadi crosshair (via `slurp`) — drag untuk pilih area yang mengandung Hanzi
3. `grim` screenshot area tersebut
4. Tesseract OCR membaca karakter Hanzi (simplified)
5. Python lookup di CC-CEDICT database (~120.000 entri)
6. Hasil dikirim ke Noctalia via IPC → Panel muncul dengan pinyin + arti

## Instalasi

```bash
cd scripts/
chmod +x install.sh
./install.sh
```

## Dependensi

| Komponen | Package | Keterangan |
|---|---|---|
| Screenshot area | `grim` + `slurp` | Wayland screenshot tools |
| OCR | `tesseract` + `tesseract-langpack-chi-sim` | Membaca Hanzi simplified |
| Python | `pytesseract`, `pillow` | Interface ke tesseract |
| Dictionary | CC-CEDICT | ~120k entri, download otomatis saat install |
| Shell | Noctalia + niri | Plugin system + keybind |

## Konfigurasi niri

Tambahkan ke `~/.config/niri/config.kdl`:

```kdl
binds {
    // Hanzi Lookup
    Super+Z { spawn "bash" "-c" "python3 ~/.local/bin/hanzi-lookup.py &"; }
}
```

## Struktur Project

```
hanzi-lookup-project/
├── plugin/
│   ├── manifest.json          # Noctalia plugin metadata
│   ├── Main.qml               # IPC handler (background)
│   ├── Panel.qml              # Display panel
│   └── ControlCenterWidget.qml
├── scripts/
│   ├── hanzi-lookup.py        # Script utama (OCR + lookup + IPC)
│   └── install.sh             # Installer
└── README.md
```

## Usage

```bash
# Normal: screenshot + OCR
python3 ~/.local/bin/hanzi-lookup.py

# Bypass OCR, langsung lookup teks
python3 ~/.local/bin/hanzi-lookup.py --text "你好世界"
python3 ~/.local/bin/hanzi-lookup.py -t "学习汉语"
```

## IPC Manual

Setelah plugin aktif, bisa trigger langsung dari terminal:

```bash
# Lookup tanpa screenshot (untuk testing)
python3 ~/.local/bin/hanzi-lookup.py --text "北京"

# Atau langsung via IPC (kalau sudah ada data)
qs -c noctalia-shell ipc call plugin:hanzi-lookup closePanel
qs -c noctalia-shell ipc call plugin:hanzi-lookup clearResults
```

## Format Data CC-CEDICT

CC-CEDICT menggunakan format:
```
漢字 汉字 [han4 zi4] /Chinese character/CJK character/
```

Script Python meng-konversi angka tone ke Unicode marks:
- `han4` → `hàn`
- `zi4` → `zì`

## Tips

- **Area terlalu kecil**: Zoom in atau scale up dulu sebelum screenshot
- **OCR salah**: Tesseract lebih akurat untuk font yang bersih, hindari screenshot area dengan background ramai
- **Karakter tidak ditemukan**: CC-CEDICT sangat lengkap tapi tidak mencakup nama proper/slang baru
- **Panel tidak muncul**: Cek apakah plugin sudah di-enable di Noctalia Settings

## Log

Log tersimpan di:
```
~/.local/share/hanzi-lookup/hanzi-lookup.log
```
