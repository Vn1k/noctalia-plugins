#!/usr/bin/env python3
import argparse
import json
import re
import socket
import subprocess
import sys
from pathlib import Path

import requests

SOCKET_PATH = "/tmp/hanzi_lookup.sock"
PLUGIN_ID = "hanzi-lookup"
CEDICT_PATH = Path.home() / ".local" / "share" / "hanzi-lookup" / "cedict_ts.u8"


SYSTEM_PROMPT = """You are a professional native Mandarin Chinese translator.
Translate Indonesian or English into natural, idiomatic Simplified Chinese Hanzi.

Your goal is to preserve the original meaning, tone, and all specific details — 
including names, numbers, and URLs — exactly as they appear. Never infer, expand, 
omit, or substitute any part of the input.

Use the phrasing a native Mandarin speaker would naturally choose. For example,
a casual self-introduction sounds more natural as "我叫 X" than "我的名字是 X",
just as in English "I'm X" feels more natural than "My name is X" in conversation.

Output ONLY the Chinese translation in Simplified Hanzi. No pinyin, no explanations, 
no quotes, no markdown, no alternatives."""

_dictionary_cache = None


def get_noctalia_settings() -> dict:
    try:
        result = subprocess.run(
            ["qs", "-c", "noctalia-shell", "plugin", "settings", PLUGIN_ID],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
    except Exception:
        pass
    return {}


def translate_to_hanzi(text: str) -> str:
    text = (text or "").strip()
    if not text:
        return ""

    settings = get_noctalia_settings()
    url = settings.get("ollamaUrl", "http://localhost:11434/api/generate")
    model = settings.get("ollamaModel", "qwen2.5:1.5b-instruct")

    response = requests.post(
        url,
        json={
            "model": model,
            "system": SYSTEM_PROMPT,
            "prompt": text,
            "stream": False,
        },
        timeout=120,
    )
    response.raise_for_status()
    return response.json().get("response", "").strip()


def get_dictionary():
    global _dictionary_cache
    if _dictionary_cache is None:
        from hanzi_lookup import load_cedict

        _dictionary_cache = load_cedict(CEDICT_PATH)
    return _dictionary_cache


def get_pinyin_for_hanzi(hanzi: str, dictionary: dict | None = None) -> str:
    hanzi = (hanzi or "").strip()
    if not hanzi:
        return ""

    try:
        from hanzi_lookup import lookup_hanzi

        active_dictionary = dictionary if dictionary is not None else get_dictionary()
        _, full_pinyin = lookup_hanzi(hanzi, active_dictionary)
        return clean_pinyin_for_display(full_pinyin or "")
    except Exception:
        return ""


def clean_pinyin_for_display(pinyin: str) -> str:
    # If an English name is returned as "K e v i n", keep it readable as "Kevin".
    return re.sub(
        r"(?<!\S)(?:[A-Za-z]\s+){1,}[A-Za-z](?=$|\s|[。.,!?，！？、;；:])",
        lambda match: match.group(0).replace(" ", ""),
        pinyin,
    )


def build_translation_payload(text: str, dictionary: dict | None = None) -> dict:
    translation = translate_to_hanzi(text)
    return {
        "translation": translation,
        "pinyin": get_pinyin_for_hanzi(translation, dictionary),
    }


def handle_translate_request(conn, request: dict, dictionary: dict | None = None):
    text = (request.get("text") or "").strip()
    payload = build_translation_payload(text, dictionary) if text else {"translation": "", "pinyin": ""}
    conn.sendall(json.dumps(payload, ensure_ascii=False).encode("utf-8"))


def request_server_translation_payload(text: str) -> dict:
    payload = json.dumps({"type": "translate", "text": text}, ensure_ascii=False)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(130)
        client.connect(SOCKET_PATH)
        client.sendall(payload.encode("utf-8"))
        client.shutdown(socket.SHUT_WR)

        chunks = []
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)

    raw = b"".join(chunks).decode("utf-8").strip()
    if not raw:
        return {"translation": "", "pinyin": ""}

    data = json.loads(raw)
    if "error" in data:
        raise RuntimeError(data["error"])
    return {
        "translation": data.get("translation", "").strip(),
        "pinyin": data.get("pinyin", "").strip(),
    }


def request_server_translation(text: str) -> str:
    return request_server_translation_payload(text).get("translation", "")


def main() -> int:
    parser = argparse.ArgumentParser(description="Translate Indonesian or English text to natural Simplified Chinese Hanzi.")
    parser.add_argument("--text", help="Text to translate. If omitted, stdin is used.")
    parser.add_argument("--direct", action="store_true", help="Call Ollama directly instead of the hanzi server daemon.")
    parser.add_argument("--json", action="store_true", help="Output translation and pinyin as JSON.")
    args = parser.parse_args()

    text = args.text if args.text is not None else sys.stdin.read()
    text = text.strip()
    if not text:
        return 0

    try:
        payload = build_translation_payload(text) if args.direct else request_server_translation_payload(text)
    except Exception as server_error:
        if args.direct:
            print(f"ERROR: {server_error}", file=sys.stderr)
            return 1
        try:
            payload = build_translation_payload(text)
        except Exception as direct_error:
            print(f"ERROR: {direct_error}", file=sys.stderr)
            return 1

    if args.json:
        print(json.dumps(payload, ensure_ascii=False))
    else:
        print(payload.get("translation", ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
