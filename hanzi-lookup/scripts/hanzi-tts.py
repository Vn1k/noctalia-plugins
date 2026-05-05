#!/usr/bin/env python3
import sys
import requests
import subprocess
import re

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    text = sys.argv[1].strip()
    if not text:
        sys.exit(0)

    # Deteksi bahasa secara otomatis
    if re.search(r'[\u4e00-\u9fff]', text):
        language = "ZH"
        speaker_id = "ZH"

    payload = {
        "text": text,
        "speed": 1.0,
        "language": language,
        "speaker_id": speaker_id,
        "sdp_ratio": 0.2,
        "noise_scale": 0.6,
        "noise_scale_w": 0.8
    }

    try:
        # Kirim request ke container MeloTTS local Anda (Port 8888)
        r = requests.post("http://127.0.0.1:8888/tts/convert/tts", json=payload, stream=True)
        r.raise_for_status()

        # Gunakan pw-play (bawaan Fedora/Pipewire) untuk memutar stream WAV langsung
        try:
            player = subprocess.Popen(["pw-play", "-"], stdin=subprocess.PIPE)
        except FileNotFoundError:
            player = subprocess.Popen(["aplay"], stdin=subprocess.PIPE)

        for chunk in r.iter_content(chunk_size=4096):
            if chunk:
                player.stdin.write(chunk)
        
        player.stdin.close()
        player.wait()

    except Exception as e:
        print(f"Error playing TTS: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()