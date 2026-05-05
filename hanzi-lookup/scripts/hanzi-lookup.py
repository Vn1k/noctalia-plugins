#!/usr/bin/env python3
"""
hanzi-lookup.py — Hanzi OCR + Pinyin/Meaning Lookup for Noctalia
=================================================================
Alur:
  1. Jalankan slurp → user pilih area layar
  2. grim screenshot area tersebut ke /tmp
  3. Tesseract OCR → dapat string Hanzi
  4. Lookup di CC-CEDICT (sudah di-load ke memory)
  5. Kirim hasil via IPC ke Noctalia plugin

Dependensi:
  - grim, slurp (wayland screenshot tools)
  - tesseract-ocr + tesseract-langpack-chi_sim
  - python3-pillow, python3-pytesseract
  - CC-CEDICT database (lihat install.sh)

Usage:
  python3 hanzi-lookup.py
  python3 hanzi-lookup.py --text "你好世界"   # bypass OCR, langsung lookup
"""

import subprocess
import sys
import os
import json
import re
import tempfile
import argparse
import logging
from pathlib import Path
from typing import Optional
import requests
import threading

# ─── Konfigurasi ────────────────────────────────────────────────────────────

# Path ke file CC-CEDICT
CEDICT_PATH = Path.home() / ".local" / "share" / "hanzi-lookup" / "cedict_ts.u8"

# Noctalia IPC target (harus sama dengan manifest.json)
PLUGIN_ID = "hanzi-lookup"
IPC_TARGET = f"plugin:{PLUGIN_ID}"

# Tesseract config untuk Hanzi simplified
TESSERACT_CONFIG = "--psm 6 -l chi_sim"

# Max karakter untuk di-lookup (cegah terlalu panjang)
MAX_LOOKUP_CHARS = 20

# ─── Logging ────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(Path.home() / ".local" / "share" / "hanzi-lookup" / "hanzi-lookup.log"),
        logging.StreamHandler(sys.stderr),
    ]
)
log = logging.getLogger(__name__)

# ─── CC-CEDICT Parser ────────────────────────────────────────────────────────

def load_cedict(path: Path) -> dict:
    """
    Load CC-CEDICT ke dalam dict untuk lookup cepat.
    Format entry: 漢字 汉字 [han4 zi4] /arti1/arti2/
    Return: { "simplified": [{"traditional": ..., "pinyin": ..., "meanings": [...]}, ...] }
    """
    if not path.exists():
        log.error(f"CC-CEDICT tidak ditemukan di: {path}")
        log.error("Jalankan install.sh untuk download database.")
        return {}

    log.info(f"Loading CC-CEDICT dari {path}...")
    dictionary = {}
    pattern = re.compile(r'^(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+/(.+)/$')

    with open(path, encoding="utf-8") as f:
        for line in f:
            # Skip komentar
            if line.startswith("#"):
                continue
            m = pattern.match(line.strip())
            if not m:
                continue

            traditional, simplified, pinyin_raw, meanings_raw = m.groups()

            # Konversi pinyin ke tone marks (opsional, fallback ke angka)
            pinyin = convert_pinyin_tones(pinyin_raw)
            meanings = [m.strip() for m in meanings_raw.split("/") if m.strip()]

            entry = {
                "traditional": traditional,
                "simplified": simplified,
                "pinyin": pinyin,
                "meanings": meanings
            }

            if simplified not in dictionary:
                dictionary[simplified] = []
            dictionary[simplified].append(entry)

    log.info(f"CC-CEDICT loaded: {len(dictionary):,} entri")
    return dictionary


# Mapping tone numbers ke Unicode combining marks
_VOWEL_TONES = {
    "a": ["ā", "á", "ǎ", "à", "a"],
    "e": ["ē", "é", "ě", "è", "e"],
    "i": ["ī", "í", "ǐ", "ì", "i"],
    "o": ["ō", "ó", "ǒ", "ò", "o"],
    "u": ["ū", "ú", "ǔ", "ù", "u"],
    "ü": ["ǖ", "ǘ", "ǚ", "ǜ", "ü"],
}

def convert_pinyin_tones(pinyin_raw: str) -> str:
    """
    Konversi pinyin dengan angka ke tone marks.
    Contoh: "han4 zi4" → "hàn zì"
    """
    result = []
    for syllable in pinyin_raw.split():
        # Cari angka tone di akhir (1-5, 5 = neutral)
        if syllable and syllable[-1].isdigit():
            tone = int(syllable[-1])
            syllable_base = syllable[:-1].lower()
        else:
            result.append(syllable)
            continue

        # Tentukan vowel mana yang dapat tone mark
        # Aturan: a/e selalu dapat, ou → o, sisanya vowel terakhir
        converted = _apply_tone(syllable_base, tone)
        result.append(converted)

    return " ".join(result)


def _apply_tone(syllable: str, tone: int) -> str:
    """Apply tone mark ke syllable."""
    if tone == 5 or tone == 0:
        return syllable  # neutral tone

    # Prioritas: a > e > (ou → o) > vowel terakhir
    for priority in ["a", "e"]:
        if priority in syllable:
            toned = _VOWEL_TONES[priority][tone - 1]
            return syllable.replace(priority, toned, 1)

    if "ou" in syllable:
        toned = _VOWEL_TONES["o"][tone - 1]
        return syllable.replace("o", toned, 1)

    # ü handling (u: dalam CEDICT = ü)
    syllable = syllable.replace("u:", "ü").replace("v", "ü")

    # Vowel terakhir
    for vowel in reversed(syllable):
        if vowel in _VOWEL_TONES:
            toned = _VOWEL_TONES[vowel][tone - 1]
            return syllable[::-1].replace(vowel, toned, 1)[::-1]

    return syllable


# ─── Lookup ─────────────────────────────────────────────────────────────────

def lookup_hanzi(text: str, dictionary: dict) -> list[dict]:
    """
    Lookup Hanzi dari teks OCR menggunakan algoritma Forward Maximum Matching (Greedy Search).
    Strategi:
      1. Memecah teks dari blok non-CJK.
      2. Memindai setiap blok dari karakter terpanjang hingga terpendek.
      3. Jika ditemukan di kamus, rekam kata majemuk tersebut dan lompat maju.
      4. Fallback: terjemahkan per karakter jika tidak ada gabungan yang cocok.
    """
    text = text.strip()
    if not text:
        return []

    # Bersihkan: ubah non-CJK menjadi spasi agar bisa di-split menjadi potongan (chunks)
    cjk_only = re.sub(r'[^\u4e00-\u9fff\u3400-\u4dbf\u20000-\u2a6df]', ' ', text)
    chunks = cjk_only.split()

    if not chunks:
        log.warning(f"Tidak ada karakter CJK ditemukan dalam: {repr(text)}")
        return []

    results = []
    seen = set()
    chars_processed = 0

    for chunk in chunks:
        n = len(chunk)
        i = 0
        
        while i < n and chars_processed < MAX_LOOKUP_CHARS:
            matched = False
            
            # Coba substring dari yang terpanjang ke yang terpendek di dalam chunk
            for j in range(n, i, -1):
                word = chunk[i:j]
                
                # Jika kata majemuk/karakter ditemukan di kamus
                if word in dictionary:
                    if word not in seen:
                        entries = dictionary[word]
                        results.append({
                            "hanzi": word,
                            "entries": entries[:3],  # max 3 definisi per kata
                            "is_phrase": len(word) > 1
                        })
                        seen.add(word)
                    
                    # Lompat indeks i sejauh panjang kata yang ditemukan
                    i = j
                    matched = True
                    chars_processed += len(word)
                    break
            
            # Jika tidak ada satu pun kombinasi yang cocok, proses sebagai 1 karakter tunggal
            if not matched:
                char = chunk[i]
                if char not in seen:
                    # Ambil entri jika ada, kosongkan jika tidak
                    entries = dictionary.get(char, [])
                    if entries:
                        results.append({
                            "hanzi": char,
                            "entries": entries[:3],
                            "is_phrase": False
                        })
                    seen.add(char)
                
                # Maju 1 karakter
                i += 1
                chars_processed += 1

    return results


# ─── Screenshot + OCR ───────────────────────────────────────────────────────

def capture_area() -> Optional[str]:
    """
    Jalankan slurp untuk pilih area, lalu grim untuk screenshot.
    Return path ke file gambar, atau None jika dibatalkan.
    """
    # Step 1: slurp — user pilih area
    log.info("Menjalankan slurp untuk pilih area...")
    try:
        result = subprocess.run(
            ["slurp"],
            capture_output=True, text=True, timeout=60
        )
    except subprocess.TimeoutExpired:
        log.warning("slurp timeout")
        return None
    except FileNotFoundError:
        log.error("slurp tidak ditemukan. Install dengan: sudo dnf install slurp")
        notify_error("slurp tidak ditemukan. Jalankan: sudo dnf install slurp")
        return None

    if result.returncode != 0:
        log.info("User membatalkan pemilihan area")
        return None

    region = result.stdout.strip()
    if not region:
        return None

    # Step 2: grim — screenshot area
    tmpfile = tempfile.NamedTemporaryFile(suffix=".png", delete=False, prefix="hanzi-ocr-")
    tmpfile.close()

    log.info(f"Screenshot region {region} → {tmpfile.name}")
    try:
        result = subprocess.run(
            ["grim", "-g", region, tmpfile.name],
            capture_output=True, text=True, timeout=10
        )
    except FileNotFoundError:
        log.error("grim tidak ditemukan. Install dengan: sudo dnf install grim")
        notify_error("grim tidak ditemukan. Jalankan: sudo dnf install grim")
        return None

    if result.returncode != 0:
        log.error(f"grim gagal: {result.stderr}")
        return None

    return tmpfile.name


def run_ocr(image_path: str) -> Optional[str]:
    """
    Jalankan Tesseract OCR pada gambar.
    Return teks hasil OCR, atau None jika gagal.
    """
    log.info(f"Menjalankan OCR pada {image_path}...")
    try:
        import pytesseract
        from PIL import Image, ImageFilter, ImageEnhance

        img = Image.open(image_path)

        # Pre-processing ringan untuk meningkatkan akurasi
        # Scale up jika terlalu kecil
        w, h = img.size
        if w < 200 or h < 50:
            scale = max(200 / w, 50 / h, 2.0)
            img = img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)

        # Sharpen + kontras
        img = img.filter(ImageFilter.SHARPEN)
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(1.5)

        text = pytesseract.image_to_string(img, config=TESSERACT_CONFIG)
        text = text.strip()
        log.info(f"OCR result: {repr(text)}")
        return text if text else None

    except ImportError:
        log.error("pytesseract atau Pillow tidak terinstall")
        log.error("Jalankan: pip install pytesseract pillow --break-system-packages")
        return None
    except Exception as e:
        log.error(f"OCR error: {e}")
        return None
    finally:
        # Bersihkan file temporary
        try:
            os.unlink(image_path)
        except Exception:
            pass

# AI

def get_ai_translation(text, ipc_target):
    # Prompt ringkas agar AI tidak bertele-tele dan cepat merespons
    prompt = f"Translate this Chinese text to English naturally: {text}. Output ONLY the translation."
    
    try:
        # Panggil Ollama API secara lokal
        response = requests.post('http://localhost:11434/api/generate', json={
            "model": "qwen2.5:1.5b-instruct",
            "prompt": prompt,
            "stream": False
        })
        ai_text = response.json().get("response", "").strip()
        
        payload = json.dumps({"ai_text": ai_text}, ensure_ascii=False)
        subprocess.run(["qs", "-c", "noctalia-shell", "ipc", "call", ipc_target, "updateAIText", payload])
    except Exception as e:
        pass

# ─── IPC + Notifikasi ────────────────────────────────────────────────────────

def send_to_noctalia(results: list[dict], original_text: str):
    """
    Kirim hasil lookup ke Noctalia plugin via IPC.
    Data dikirim sebagai JSON string.
    """
    payload = {
        "query": original_text,
        "results": results
    }

    payload_json = json.dumps(payload, ensure_ascii=False)

    log.info(f"Mengirim {len(results)} hasil ke Noctalia IPC...")
    try:
        subprocess.run(
            ["qs", "-c", "noctalia-shell", "ipc", "call",
             IPC_TARGET, "showResult", payload_json],
            timeout=5,
            check=True
        )
        log.info("IPC call berhasil")
    except subprocess.TimeoutExpired:
        log.error("IPC call timeout")
    except subprocess.CalledProcessError as e:
        log.error(f"IPC call gagal (exit {e.returncode})")
    except FileNotFoundError:
        log.error("qs tidak ditemukan. Pastikan noctalia-shell berjalan.")


def notify_error(message: str):
    """Tampilkan notifikasi error via notify-send sebagai fallback."""
    try:
        subprocess.run(
            ["notify-send", "-a", "Hanzi Lookup", "-i", "dialog-error",
             "Hanzi Lookup Error", message],
            timeout=5
        )
    except Exception:
        pass


# ─── Main ────────────────────────────────────────────────────────────────────

_dictionary_cache = None

def get_dictionary() -> dict:
    """Lazy-load dictionary (singleton)."""
    global _dictionary_cache
    if _dictionary_cache is None:
        _dictionary_cache = load_cedict(CEDICT_PATH)
    return _dictionary_cache


def main():
    parser = argparse.ArgumentParser(description="Hanzi Lookup Tool")
    parser.add_argument(
        "--text", "-t",
        help="Bypass OCR, langsung lookup teks ini"
    )
    parser.add_argument(
        "--no-preload",
        action="store_true",
        help="Jangan pre-load dictionary (lebih lambat, hemat RAM)"
    )
    args = parser.parse_args()

    # Load dictionary
    log.info("Memuat CC-CEDICT dictionary...")
    dictionary = get_dictionary()

    if not dictionary:
        notify_error("CC-CEDICT tidak ditemukan. Jalankan install.sh terlebih dahulu.")
        sys.exit(1)

    # Tentukan teks yang akan di-lookup
    if args.text:
        # Mode bypass OCR
        hanzi_text = args.text
        log.info(f"Mode langsung (bypass OCR): {repr(hanzi_text)}")
    else:
        # Mode normal: screenshot + OCR
        image_path = capture_area()
        if not image_path:
            log.info("Dibatalkan atau tidak ada area yang dipilih")
            sys.exit(0)

        hanzi_text = run_ocr(image_path)
        if not hanzi_text:
            notify_error("OCR gagal membaca teks. Coba pilih area yang lebih besar.")
            log.warning("OCR tidak menghasilkan teks")
            sys.exit(1)

    # Lookup di dictionary
    ai_thread = threading.Thread(
        target=get_ai_translation, 
        args=(hanzi_text, IPC_TARGET), 
        daemon=False 
    )
    ai_thread.start()
    results = lookup_hanzi(hanzi_text, dictionary)

    if not results:
        notify_error(f"Tidak ditemukan: {hanzi_text[:20]}")
        log.warning(f"Tidak ada hasil untuk: {repr(hanzi_text)}")
        sys.exit(0)

    # Kirim ke Noctalia
    send_to_noctalia(results, hanzi_text)
    log.info(f"Selesai. {len(results)} karakter/kata ditemukan.")
    log.info("Hasil awal dikirim, menunggu AI di background...")

if __name__ == "__main__":
    main()
