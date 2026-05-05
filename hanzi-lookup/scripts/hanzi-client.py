#!/usr/bin/env python3
import socket
import subprocess
import tempfile
import sys

def capture_area():
    """Jalankan slurp dan grim untuk mengambil screenshot"""
    try:
        result = subprocess.run(["slurp"], capture_output=True, text=True, timeout=60)
        if result.returncode != 0: return None
        
        region = result.stdout.strip()
        tmpfile = tempfile.NamedTemporaryFile(suffix=".png", delete=False, prefix="hanzi-ocr-")
        tmpfile.close()
        
        subprocess.run(["grim", "-g", region, tmpfile.name], capture_output=True)
        return tmpfile.name
    except Exception:
        return None

def main():
    image_path = capture_area()
    if not image_path:
        sys.exit(0)
        
    # Kirim lokasi gambar ke Server Daemon
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect('/tmp/hanzi_lookup.sock')
            s.sendall(image_path.encode())
    except ConnectionRefusedError:
        print("Error: Hanzi Server Daemon tidak berjalan!")

if __name__ == "__main__":
    main()