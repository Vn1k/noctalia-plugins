#!/usr/bin/env python3
"""
hanzi-lookup.py — Hanzi OCR + Pinyin/Meaning Lookup for Noctalia
=================================================================
Alur:
  1. Jalankan slurp → user pilih area layar
  2. grim screenshot area tersebut ke /tmp
  3. CnOCR → dapat string Hanzi yang sangat akurat
  4. Lookup di CC-CEDICT (sudah di-load ke memory)
  5. Kirim hasil via IPC ke Noctalia plugin
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

# Noctalia IPC target
PLUGIN_ID = "hanzi-lookup"
IPC_TARGET = f"plugin:{PLUGIN_ID}"

# Max karakter untuk di-lookup
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
    if not path.exists():
        log.error(f"CC-CEDICT tidak ditemukan di: {path}")
        return {}

    log.info(f"Loading CC-CEDICT dari {path}...")
    dictionary = {}
    pattern = re.compile(r'^(\S+)\s+(\S+)\s+\[([^\]]+)\]\s+/(.+)/$')

    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#"):
                continue
            m = pattern.match(line.strip())
            if not m:
                continue

            traditional, simplified, pinyin_raw, meanings_raw = m.groups()
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


_VOWEL_TONES = {
    "a": ["ā", "á", "ǎ", "à", "a"],
    "e": ["ē", "é", "ě", "è", "e"],
    "i": ["ī", "í", "ǐ", "ì", "i"],
    "o": ["ō", "ó", "ǒ", "ò", "o"],
    "u": ["ū", "ú", "ǔ", "ù", "u"],
    "ü": ["ǖ", "ǘ", "ǚ", "ǜ", "ü"],
}

def convert_pinyin_tones(pinyin_raw: str) -> str:
    result = []
    for syllable in pinyin_raw.split():
        if syllable and syllable[-1].isdigit():
            tone = int(syllable[-1])
            syllable_base = syllable[:-1].lower()
        else:
            result.append(syllable)
            continue

        converted = _apply_tone(syllable_base, tone)
        result.append(converted)

    return " ".join(result)


def _apply_tone(syllable: str, tone: int) -> str:
    if tone == 5 or tone == 0:
        return syllable

    for priority in ["a", "e"]:
        if priority in syllable:
            toned = _VOWEL_TONES[priority][tone - 1]
            return syllable.replace(priority, toned, 1)

    if "ou" in syllable:
        toned = _VOWEL_TONES["o"][tone - 1]
        return syllable.replace("o", toned, 1)

    syllable = syllable.replace("u:", "ü").replace("v", "ü")

    for vowel in reversed(syllable):
        if vowel in _VOWEL_TONES:
            toned = _VOWEL_TONES[vowel][tone - 1]
            return syllable[::-1].replace(vowel, toned, 1)[::-1]

    return syllable


# ─── Lookup ─────────────────────────────────────────────────────────────────

def lookup_hanzi(text: str, dictionary: dict) -> list[dict]:
    text = text.strip()
    if not text:
        return []

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
            for j in range(n, i, -1):
                word = chunk[i:j]
                if word in dictionary:
                    if word not in seen:
                        entries = dictionary[word]
                        results.append({
                            "hanzi": word,
                            "entries": entries[:3],
                            "is_phrase": len(word) > 1
                        })
                        seen.add(word)
                    
                    i = j
                    matched = True
                    chars_processed += len(word)
                    break
            
            if not matched:
                char = chunk[i]
                if char not in seen:
                    entries = dictionary.get(char, [])
                    if entries:
                        results.append({
                            "hanzi": char,
                            "entries": entries[:3],
                            "is_phrase": False
                        })
                    seen.add(char)
                i += 1
                chars_processed += 1

    return results


# ─── Screenshot + CnOCR ─────────────────────────────────────────────────────

def capture_area() -> Optional[str]:
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
        log.error("slurp tidak ditemukan.")
        return None

    if result.returncode != 0:
        log.info("User membatalkan pemilihan area")
        return None

    region = result.stdout.strip()
    if not region:
        return None

    tmpfile = tempfile.NamedTemporaryFile(suffix=".png", delete=False, prefix="hanzi-ocr-")
    tmpfile.close()

    log.info(f"Screenshot region {region} → {tmpfile.name}")
    try:
        subprocess.run(
            ["grim", "-g", region, tmpfile.name],
            capture_output=True, text=True, timeout=10
        )
    except FileNotFoundError:
        log.error("grim tidak ditemukan.")
        return None

    return tmpfile.name


_ocr_instance = None

def get_ocr():
    """Lazy-load instance CnOCR dengan dukungan GPU"""
    global _ocr_instance
    if _ocr_instance is None:
        log.info("Memulai inisialisasi CnOCR di GPU...")
        from cnocr import CnOcr
        try:
            # Coba jalankan di GPU (CUDA)
            _ocr_instance = CnOcr(context='cuda', det_model_name=None)
            log.info("CnOCR berhasil dimuat menggunakan GPU (CUDA).")
        except Exception as e:
            log.warn(f"Gagal memuat GPU ({e}), beralih ke CPU.")
            # Fallback otomatis ke CPU jika CUDA gagal
            _ocr_instance = CnOcr(context='cpu', det_model_name=None)
    return _ocr_instance

def run_ocr(image_path: str) -> Optional[str]:
    """
    Jalankan CnOCR untuk ekstraksi karakter Hanzi tingkat tinggi.
    """
    log.info(f"Menjalankan CnOCR pada {image_path}...")
    from PIL import Image

    with Image.open(image_path) as img:
        img = img.convert('RGB')
        w, h = img.size
        img = img.resize((w * 2, h * 2), Image.LANCZOS)
        img.save(image_path)
        
    try:
        # Gunakan instance yang sudah ada
        ocr = get_ocr()
        ocr_results = ocr.ocr(image_path)
        
        text_list = [line['text'] for line in ocr_results if 'text' in line]
        text = "".join(text_list).strip()
        
        log.info(f"CnOCR result: {repr(text)}")
        return text if text else None

    except Exception as e:
        log.error(f"OCR error: {e}")
        return None
    finally:
        try:
            os.unlink(image_path)
        except Exception:
            pass


# ─── AI Translation ─────────────────────────────────────────────────────────

def get_ai_translation(text, ipc_target):
    prompt = f"Translate this Chinese text to English naturally: {text}. Output ONLY the translation."
    try:
        response = requests.post('http://localhost:11434/api/generate', json={
            "model": "qwen2.5:1.5b-instruct",
            "prompt": prompt,
            "stream": False
        })
        ai_text = response.json().get("response", "").strip()
        
        payload = json.dumps({"ai_text": ai_text}, ensure_ascii=False)
        subprocess.run(["qs", "-c", "noctalia-shell", "ipc", "call", ipc_target, "updateAIText", payload])
    except Exception as e:
        log.error(f"AI Translation Error: {e}")


# ─── IPC ────────────────────────────────────────────────────────────────────

def send_to_noctalia(results: list[dict], original_text: str):
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
    except Exception as e:
        log.error(f"IPC call gagal: {e}")


# ─── Main ────────────────────────────────────────────────────────────────────

_dictionary_cache = None

def get_dictionary() -> dict:
    global _dictionary_cache
    if _dictionary_cache is None:
        _dictionary_cache = load_cedict(CEDICT_PATH)
    return _dictionary_cache


def main():
    parser = argparse.ArgumentParser(description="Hanzi Lookup Tool")
    parser.add_argument("--text", "-t", help="Bypass OCR, langsung lookup teks ini")
    args = parser.parse_args()

    dictionary = get_dictionary()
    if not dictionary:
        sys.exit(1)

    if args.text:
        hanzi_text = args.text
        log.info(f"Mode langsung (bypass OCR): {repr(hanzi_text)}")
    else:
        image_path = capture_area()
        if not image_path:
            sys.exit(0)

        hanzi_text = run_ocr(image_path)
        if not hanzi_text:
            sys.exit(1)

    # Menjalankan AI translation di background (tidak memblokir UI panel utama)
    # daemon=False digunakan agar skrip Python tetap hidup sampai Ollama merespons
    ai_thread = threading.Thread(
        target=get_ai_translation, 
        args=(hanzi_text, IPC_TARGET), 
        daemon=False
    )
    ai_thread.start()

    # Hasil pencarian kamus instan (<10ms)
    results = lookup_hanzi(hanzi_text, dictionary)

    if not results:
        log.warning(f"Tidak ada hasil untuk: {repr(hanzi_text)}")
        sys.exit(0)

    send_to_noctalia(results, hanzi_text)


if __name__ == "__main__":
    main()