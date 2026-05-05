#!/usr/bin/env python3
import socket
import os
import json
import subprocess
import logging
from pathlib import Path
import sys

from hanzi_lookup import load_cedict, lookup_hanzi, get_ai_translation 

SOCKET_PATH = '/tmp/hanzi_lookup.sock'
CEDICT_PATH = Path.home() / ".local" / "share" / "hanzi-lookup" / "cedict_ts.u8"
IPC_TARGET = "plugin:hanzi-lookup"

LOG_FILE = Path.home() / ".local" / "share" / "hanzi-lookup" / "hanzi-lookup.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stderr),
    ]
)
log = logging.getLogger(__name__)

def main():
    log.info("Memulai Hanzi Server Daemon...")
    
    # 1. Load CC-CEDICT (Hanya sekali)
    dictionary = load_cedict(CEDICT_PATH)
    
    # 2. Inisialisasi CnOCR di GPU (Hanya sekali)
    from cnocr import CnOcr
    try:
        ocr = CnOcr(context='cuda', det_model_name=None)
        log.info("CnOCR siap di GPU (CUDA).")
    except Exception as e:
        log.warning(f"Gagal memuat GPU, beralih ke CPU: {e}")
        ocr = CnOcr(context='cpu', det_model_name=None)

    # 3. Setup Unix Socket
    if os.path.exists(SOCKET_PATH):
        os.remove(SOCKET_PATH)
        
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(SOCKET_PATH)
        server.listen(1)
        log.info(f"Server mendengarkan di {SOCKET_PATH}...")
        
        while True:
            conn, _ = server.accept()
            try:
                # Terima path gambar dari Client
                image_path = conn.recv(1024).decode().strip()
                if not image_path or not os.path.exists(image_path):
                    continue
                
                log.info(f"Menerima tugas baru: {image_path}")
                
                # Preprocessing gambar (Resize 2x)
                from PIL import Image
                with Image.open(image_path) as img:
                    img = img.convert('RGB')
                    w, h = img.size
                    img = img.resize((w * 2, h * 2), Image.LANCZOS)
                    img.save(image_path)
                
                # Proses OCR (Sangat Cepat karena model sudah di VRAM)
                ocr_results = ocr.ocr(image_path)
                text = "".join([line['text'] for line in ocr_results if 'text' in line]).strip()
                
                if text:
                    # Jalankan AI Translation di background
                    import threading
                    threading.Thread(target=get_ai_translation, args=(text, IPC_TARGET)).start()
                    
                    # Lookup kamus dan kirim ke Noctalia
                    results = lookup_hanzi(text, dictionary)
                    if results:
                        payload = json.dumps({"query": text, "results": results}, ensure_ascii=False)
                        subprocess.run(["qs", "-c", "noctalia-shell", "ipc", "call", IPC_TARGET, "showResult", payload])
                        
            except Exception as e:
                log.error(f"Error memproses koneksi: {e}")
            finally:
                conn.close()
                if os.path.exists(image_path):
                    os.unlink(image_path) # Hapus file sementara

if __name__ == "__main__":
    main()