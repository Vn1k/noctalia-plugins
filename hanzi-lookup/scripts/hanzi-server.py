#!/usr/bin/env python3
import socket
import os
import json
import subprocess
import logging
from pathlib import Path
import threading
import sys

from hanzi_lookup import load_cedict, lookup_hanzi, get_ai_translation, process_image_smart

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
    log.info("Memulai Hanzi Server Daemon (Smart Mode)...")
    
    # 1. Load Kamus (Hanya sekali di awal)
    dictionary = load_cedict(CEDICT_PATH)
    
    # 2. Setup Unix Socket
    if os.path.exists(SOCKET_PATH):
        os.remove(SOCKET_PATH)
        
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(SOCKET_PATH)
        server.listen(1)
        log.info(f"Server mendengarkan di {SOCKET_PATH}...")
        
        while True:
            conn, _ = server.accept()
            image_path = None
            try:
                image_path = conn.recv(1024).decode().strip()
                if not image_path or not os.path.exists(image_path):
                    continue
                
                log.info(f"Menerima tangkapan layar baru: {image_path}")
                
                # ─── PANGGIL SMART PIPELINE DARI LOOKUP ───
                final_text, is_text_mode = process_image_smart(image_path)
                
                if final_text:
                    # Jalankan AI Translation panjang HANYA jika mode teks (OCR)
                    # (Karena kalau objek, artinya sudah hanya 1 kata Hanzi singkat)
                    if is_text_mode:
                        threading.Thread(target=get_ai_translation, args=(final_text, IPC_TARGET)).start()
                    
                    # Lookup kamus CC-CEDICT dan kirim ke Noctalia
                    cards, full_pinyin = lookup_hanzi(final_text, dictionary)

                    if cards or full_pinyin:                         
                        payload = json.dumps({
                            "query": final_text, 
                            "results": cards, 
                            "pinyin": full_pinyin, 
                            "mode": "OCR" if is_text_mode else "OBJ"
                        }, ensure_ascii=False)
                        
                        subprocess.run(["qs", "-c", "noctalia-shell", "ipc", "call", IPC_TARGET, "showResult", payload])
                        
            except Exception as e:
                log.error(f"Error memproses koneksi: {e}")
            finally:
                conn.close()
                if image_path and os.path.exists(image_path):
                    os.unlink(image_path)

if __name__ == "__main__":
    main()