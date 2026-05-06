# Hanzi Lookup — Noctalia Plugin

A Noctalia plugin for looking up Hanzi from a selected screen area. Results are
shown in a panel with Hanzi, pinyin, CC-CEDICT meanings, optional AI translation,
and optional TTS.

## How It Works

```text
Super+Z -> select screen area -> grim/slurp -> Hanzi server -> CnOCR
        -> CC-CEDICT lookup -> Noctalia panel
```

If the screenshot does not contain Hanzi, the current pipeline can fall back to
YOLO object detection, then translate the detected object name into Mandarin via
Ollama.

## Quick Install (Not tested)

The main installer is in the plugin root directory:

```bash
cd hanzi-lookup
chmod +x setup.sh
./setup.sh
```

`setup.sh` installs the base dependencies, Python packages, CC-CEDICT database,
runtime scripts, and Noctalia plugin files. The `hanzi-server.py` daemon is
started through niri `spawn-at-startup`.

Large components are optional:

```bash
# Pull the default Ollama model
./setup.sh --pull-ollama-model

# Pull and run the MeloTTS container
./setup.sh --with-melotts

# Run MeloTTS with NVIDIA Container Toolkit for Podman GPU access
./setup.sh --with-melotts --with-nvidia-toolkit

# Skip large downloads
./setup.sh --no-melotts --no-ollama-model
```

Default Ollama model used by the plugin:

```text
qwen2.5:1.5b-instruct
```

Alternative models can be any model that supports Chinese well.

## Manual Install

Use this section if you do not want to use `setup.sh`.

### 1. System Dependencies

Fedora:

```bash
sudo dnf install -y \
  grim \
  slurp \
  curl \
  gzip \
  python3 \
  python3-pip \
  pipewire-utils
```

Optional for the MeloTTS container:

```bash
sudo dnf install -y podman
```

Optional for Podman + NVIDIA GPU:

```bash
sudo dnf install -y nvidia-container-toolkit
sudo mkdir -p /etc/cdi
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Make sure the NVIDIA host driver is working:

```bash
nvidia-smi
```

### 2. Python Dependencies

```bash
python3 -m pip install --upgrade \
  "cnocr[ort-gpu]" \
  onnxruntime-gpu \
  pillow \
  requests \
  ultralytics \
  --break-system-packages
```

CnOCR will try CUDA first and fall back to CPU if GPU support is unavailable.

### 3. CC-CEDICT Database

```bash
mkdir -p ~/.local/share/hanzi-lookup
curl -L \
  -o ~/.local/share/hanzi-lookup/cedict.txt.gz \
  "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
gunzip -f ~/.local/share/hanzi-lookup/cedict.txt.gz
mv ~/.local/share/hanzi-lookup/cedict*.txt ~/.local/share/hanzi-lookup/cedict_ts.u8
```

### 4. Deploy Scripts and Plugin Files

From the `hanzi-lookup` directory:

```bash
mkdir -p ~/.local/bin
mkdir -p ~/.config/noctalia/plugins/hanzi-lookup

cp scripts/hanzi-server.py ~/.local/bin/
cp scripts/hanzi-client.py ~/.local/bin/
cp scripts/hanzi_lookup.py ~/.local/bin/
cp scripts/hanzi-tts.py ~/.local/bin/

cp *.qml *.json ~/.config/noctalia/plugins/hanzi-lookup/
```

Optional wrapper for a shorter keybind command:

```bash
cat > ~/.local/bin/hanzi-client <<'EOF'
#!/usr/bin/env bash
exec python3 "$HOME/.local/bin/hanzi-client.py" "$@"
EOF
chmod +x ~/.local/bin/hanzi-client
```

### 5. Niri Startup

Add `spawn-at-startup` to `~/.config/niri/config.kdl` so the server starts when
niri starts:

```kdl
spawn-at-startup "python3" "/home/vinik/.local/bin/hanzi-server.py"
```

For other users, replace `/home/vinik` with the correct home path.

Run it manually for the current session if you do not want to log out or reload
niri yet:

```bash
python3 ~/.local/bin/hanzi-server.py &
```

## Ollama

Ollama is used for AI translation. Default endpoint:

```text
http://localhost:11434/api/generate
```

Install Ollama and pull the default model:

```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable --now ollama
ollama pull qwen2.5:1.5b-instruct
```

The model name can be changed from the Noctalia plugin settings.

## MeloTTS

MeloTTS is used by the audio/TTS button in the panel. It is optional because the
image is fairly large.

Pull and run with NVIDIA GPU:

```bash
podman pull docker.io/sensejworld/melotts:latest
podman run -d \
  --name melotts-api \
  --device nvidia.com/gpu=all \
  --security-opt label=disable \
  -p 8888:8080 \
  docker.io/sensejworld/melotts:latest
```

If you are not using GPU:

```bash
podman run -d \
  --name melotts-api \
  --security-opt label=disable \
  -p 8888:8080 \
  docker.io/sensejworld/melotts:latest
```

Optional: create a systemd service from the container so MeloTTS can auto-start:

```bash
mkdir -p ~/.config/systemd/user
podman generate systemd --new --name melotts-api --files
systemctl --user daemon-reload
systemctl --user enable --now container-melotts-api.service
```

If you want the user service to auto-start after boot before login:

```bash
loginctl enable-linger "$USER"
```

Default MeloTTS endpoint:

```text
http://127.0.0.1:8888/tts/convert/tts
```

The endpoint can be changed from the Noctalia plugin settings.

## Niri Configuration

Add the startup daemon and keybinds to `~/.config/niri/config.kdl`:

```kdl
spawn-at-startup "python3" "/home/vinik/.local/bin/hanzi-server.py"

binds {
    Super+Z { spawn "bash" "-c" "hanzi-client &"; }
    Mod+Shift+Z { spawn-sh "qs -c noctalia-shell ipc call plugin:hanzi-lookup togglePanelDirect"; }
}
```

For other users, replace `/home/vinik` with the correct home path.

If you do not create the `hanzi-client` wrapper, use:

```kdl
binds {
    Super+Z { spawn "bash" "-c" "python3 ~/.local/bin/hanzi-client.py &"; }
    Mod+Shift+Z { spawn-sh "qs -c noctalia-shell ipc call plugin:hanzi-lookup togglePanelDirect"; }
}
```

## Update

`scripts/update.sh` only copies the Python scripts and QML/JSON files back to
their runtime locations. It is intended for users who already have all
dependencies installed.

```bash
cd hanzi-lookup/scripts
./update.sh
pkill -f '[h]anzi-server.py' || true
python3 ~/.local/bin/hanzi-server.py &
```

If dependencies, models, database files, or containers are missing, use
`setup.sh` or follow the manual installation steps above.

## Project Structure

```text
hanzi-lookup/
├── ControlCenterWidget.qml
├── Main.qml
├── Panel.qml
├── Settings.qml
├── manifest.json
├── setup.sh
└── scripts/
    ├── hanzi-client.py
    ├── hanzi-server.py
    ├── hanzi-tts.py
    ├── hanzi_lookup.py
    ├── install-v2.sh
    └── update.sh
```

## Useful Commands

```bash
# Daemon status
pgrep -af hanzi-server.py

# Application log
tail -f ~/.local/share/hanzi-lookup/hanzi-lookup.log

# Restart after changing the model in Settings
pkill -f '[h]anzi-server.py' || true
python3 ~/.local/bin/hanzi-server.py &

# Check the MeloTTS container
podman ps --filter name=melotts-api
podman logs -f melotts-api
```

## CC-CEDICT Data Format

CC-CEDICT uses this format:

```text
漢字 汉字 [han4 zi4] /Chinese character/CJK character/
```

The Python script converts numbered pinyin tones to tone marks:

```text
han4 zi4 -> hàn zì
```

## Tips

- OCR area too small: zoom in or select a cleaner screen area.
- OCR is slow on first run: CnOCR/YOLO may download models the first time they are used.
- Panel does not appear: check that the plugin is enabled in Noctalia and `hanzi-server.py` is running.
- AI translation is empty: check that Ollama is running and the model has been pulled.
- TTS has no audio: check that the MeloTTS container is running on port `8888`.
