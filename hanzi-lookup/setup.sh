#!/usr/bin/env bash
# ============================================================
# setup.sh — Hanzi Lookup full setup helper
# ============================================================
# Fedora-oriented installer for the current Hanzi Lookup layout.
# It keeps large optional components interactive:
#   - Ollama + translation model
#   - MeloTTS container image
#   - NVIDIA Container Toolkit for Podman GPU access
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${CYAN}══ $* ══${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

DATA_DIR="$HOME/.local/share/hanzi-lookup"
BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/noctalia/plugins/hanzi-lookup"

CEDICT_URL="https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz"
CEDICT_GZ="$DATA_DIR/cedict.txt.gz"
CEDICT_FILE="$DATA_DIR/cedict_ts.u8"

OLLAMA_MODEL_DEFAULT="qwen2.5:1.5b-instruct"
MELOTTS_IMAGE="docker.io/sensejworld/melotts:latest"
MELOTTS_CONTAINER="melotts-api"
MELOTTS_PORT="8888"
MELOTTS_SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
MELOTTS_SERVICE_FILE="$MELOTTS_SYSTEMD_USER_DIR/container-$MELOTTS_CONTAINER.service"

ASSUME_YES=0
INSTALL_SYSTEM_PACKAGES=1
INSTALL_PYTHON_PACKAGES=1
INSTALL_OLLAMA="ask"
PULL_OLLAMA_MODEL="ask"
OLLAMA_MODEL="$OLLAMA_MODEL_DEFAULT"
SETUP_MELOTTS="ask"
SETUP_NVIDIA_TOOLKIT="ask"
SETUP_MELOTTS_SYSTEMD="ask"
FORCE_CEDICT=0
NVIDIA_TOOLKIT_HANDLED=0

usage() {
    cat <<EOF
Usage: ./setup.sh [options]

Options:
  -y, --yes                 Use defaults for prompts.
  --no-system-packages      Skip dnf package installation.
  --no-python-packages      Skip pip package installation.
  --with-ollama             Install/start Ollama if missing.
  --no-ollama               Skip Ollama installation.
  --pull-ollama-model       Pull the configured Ollama model.
  --no-ollama-model         Skip Ollama model download.
  --ollama-model MODEL      Ollama model to pull/use. Default: $OLLAMA_MODEL_DEFAULT
  --with-melotts            Pull and run MeloTTS Podman container.
  --no-melotts              Skip MeloTTS container setup.
  --with-melotts-systemd    Generate and enable a user systemd service for MeloTTS.
  --no-melotts-systemd      Skip MeloTTS user systemd service setup.
  --with-nvidia-toolkit     Install/configure nvidia-container-toolkit for Podman.
  --no-nvidia-toolkit       Skip NVIDIA Container Toolkit setup.
  --force-cedict            Re-download CC-CEDICT.
  -h, --help                Show this help.

Recommended Ollama model:
  $OLLAMA_MODEL_DEFAULT

Alternative models can be any model that supports Chinese well.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --no-system-packages) INSTALL_SYSTEM_PACKAGES=0 ;;
        --no-python-packages) INSTALL_PYTHON_PACKAGES=0 ;;
        --with-ollama) INSTALL_OLLAMA="yes" ;;
        --no-ollama) INSTALL_OLLAMA="no" ;;
        --pull-ollama-model) PULL_OLLAMA_MODEL="yes" ;;
        --no-ollama-model) PULL_OLLAMA_MODEL="no" ;;
        --ollama-model)
            [ "${2:-}" ] || error "--ollama-model requires a value"
            OLLAMA_MODEL="$2"
            shift
            ;;
        --with-melotts) SETUP_MELOTTS="yes" ;;
        --no-melotts) SETUP_MELOTTS="no" ;;
        --with-melotts-systemd) SETUP_MELOTTS_SYSTEMD="yes" ;;
        --no-melotts-systemd) SETUP_MELOTTS_SYSTEMD="no" ;;
        --with-nvidia-toolkit) SETUP_NVIDIA_TOOLKIT="yes" ;;
        --no-nvidia-toolkit) SETUP_NVIDIA_TOOLKIT="no" ;;
        --force-cedict) FORCE_CEDICT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) error "Unknown argument: $1" ;;
    esac
    shift
done

prompt_yes_no() {
    local question="$1"
    local default_answer="${2:-n}"
    local answer prompt

    if [ "$ASSUME_YES" = "1" ]; then
        case "$default_answer" in
            y|Y) return 0 ;;
            *) return 1 ;;
        esac
    fi

    if [[ "$default_answer" =~ ^[Yy]$ ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -r -p "$question $prompt " answer
    answer="${answer:-$default_answer}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

resolve_ask() {
    local value="$1"
    local question="$2"
    local default_answer="$3"

    case "$value" in
        yes) return 0 ;;
        no) return 1 ;;
        ask) prompt_yes_no "$question" "$default_answer" ;;
        *) return 1 ;;
    esac
}

have_rpm_pkg() {
    rpm -q "$1" &>/dev/null
}

install_dnf_packages() {
    local missing=()
    local pkg

    for pkg in "$@"; do
        if ! have_rpm_pkg "$pkg"; then
            missing+=("$pkg")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        success "System packages are already installed"
        return 0
    fi

    info "Installing packages: ${missing[*]}"
    sudo dnf install -y "${missing[@]}"
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$output" "$url"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "$output" "$url"
    else
        error "curl or wget was not found"
    fi
}

ensure_directories() {
    step "Step 1: Prepare directories"
    mkdir -p "$DATA_DIR" "$BIN_DIR" "$PLUGIN_DIR"
    success "Directories are ready"
}

install_system_dependencies() {
    step "Step 2: System dependencies"

    if [ "$INSTALL_SYSTEM_PACKAGES" != "1" ]; then
        warn "Skipping system package installation"
        return 0
    fi

    if ! command -v dnf &>/dev/null; then
        warn "dnf was not found. Install these packages manually:"
        warn "grim slurp curl gzip python3 python3-pip pipewire-utils"
        warn "podman and nvidia-container-toolkit are optional"
        return 0
    fi

    install_dnf_packages \
        grim \
        slurp \
        curl \
        gzip \
        python3 \
        python3-pip \
        pipewire-utils

    if command -v grim &>/dev/null && command -v slurp &>/dev/null; then
        success "Screenshot tools are ready"
    fi
}

install_python_dependencies() {
    step "Step 3: Python dependencies"

    if [ "$INSTALL_PYTHON_PACKAGES" != "1" ]; then
        warn "Skipping Python package installation"
        return 0
    fi

    info "Installing CnOCR, ONNX Runtime GPU, Pillow, Requests, and Ultralytics"
    python3 -m pip install --upgrade \
        "cnocr[ort-gpu]" \
        onnxruntime-gpu \
        pillow \
        requests \
        ultralytics \
        --break-system-packages

    if nvidia-smi &>/dev/null; then
        success "NVIDIA GPU detected. CnOCR will try CUDA and fall back to CPU if needed."
    else
        warn "nvidia-smi is not available. CnOCR can still run on CPU."
    fi
}

install_cedict() {
    step "Step 4: Database CC-CEDICT"

    if [ "$FORCE_CEDICT" != "1" ] && [ -s "$CEDICT_FILE" ]; then
        local entry_count
        entry_count="$(grep -c "^[^#]" "$CEDICT_FILE" 2>/dev/null || echo "0")"
        success "CC-CEDICT already exists: $entry_count entries"
        return 0
    fi

    info "Downloading CC-CEDICT from MDBG"
    download_file "$CEDICT_URL" "$CEDICT_GZ"

    info "Extracting database"
    gunzip -f "$CEDICT_GZ"

    local extracted
    extracted="$(find "$DATA_DIR" -maxdepth 1 -type f -name 'cedict*.txt' | head -n 1 || true)"
    if [ -n "$extracted" ]; then
        mv "$extracted" "$CEDICT_FILE"
    fi

    if [ ! -s "$CEDICT_FILE" ]; then
        error "Failed to create CC-CEDICT at $CEDICT_FILE"
    fi

    local entry_count
    entry_count="$(grep -c "^[^#]" "$CEDICT_FILE" 2>/dev/null || echo "0")"
    success "CC-CEDICT installed: $entry_count entries"
}

deploy_hanzi_lookup() {
    step "Step 5: Deploy Hanzi Lookup"

    local scripts=(
        "hanzi-server.py"
        "hanzi-client.py"
        "hanzi_lookup.py"
        "hanzi-tts.py"
    )
    local script

    for script in "${scripts[@]}"; do
        if [ -f "$PROJECT_DIR/scripts/$script" ]; then
            cp "$PROJECT_DIR/scripts/$script" "$BIN_DIR/$script"
            chmod +x "$BIN_DIR/$script"
            info "Installed $script"
        else
            warn "Could not find $PROJECT_DIR/scripts/$script"
        fi
    done

    cat > "$BIN_DIR/hanzi-client" <<'EOF'
#!/usr/bin/env bash
exec python3 "$HOME/.local/bin/hanzi-client.py" "$@"
EOF
    chmod +x "$BIN_DIR/hanzi-client"

    cat > "$BIN_DIR/hanzi-tts" <<'EOF'
#!/usr/bin/env bash
exec python3 "$HOME/.local/bin/hanzi-tts.py" "$@"
EOF
    chmod +x "$BIN_DIR/hanzi-tts"

    cp "$PROJECT_DIR"/*.qml "$PLUGIN_DIR/" 2>/dev/null || true
    cp "$PROJECT_DIR"/*.json "$PLUGIN_DIR/" 2>/dev/null || true

    success "Runtime scripts and Noctalia plugin files are installed"
}

print_niri_startup_hint() {
    step "Step 6: Startup Hanzi Server"

    cat <<EOF
Hanzi Lookup uses the hanzi-server.py daemon. Add this line to
~/.config/niri/config.kdl so the server starts when niri starts:

  spawn-at-startup "python3" "$HOME/.local/bin/hanzi-server.py"
EOF

    warn "setup.sh does not edit niri config automatically"
}

setup_ollama() {
    step "Step 7: Ollama and AI model"

    cat <<EOF
Default Ollama model used by Hanzi Lookup:
  $OLLAMA_MODEL_DEFAULT

Alternative models can be any model that supports Chinese well.
EOF

    if ! command -v ollama &>/dev/null; then
        if resolve_ask "$INSTALL_OLLAMA" "Ollama is not installed. Install Ollama now?" "n"; then
            if ! command -v curl &>/dev/null; then
                error "curl is required to install Ollama"
            fi
            info "Running the official Ollama installer"
            curl -fsSL https://ollama.com/install.sh | sh
        else
            warn "Skipping Ollama installation"
        fi
    else
        success "Ollama is already installed"
    fi

    if command -v ollama &>/dev/null; then
        if systemctl list-unit-files ollama.service &>/dev/null; then
            sudo systemctl enable --now ollama.service || warn "Failed to enable Ollama service. Start it manually if needed."
        fi

        if resolve_ask "$PULL_OLLAMA_MODEL" "Pull Ollama model '$OLLAMA_MODEL' now?" "y"; then
            ollama pull "$OLLAMA_MODEL"
            success "Ollama model is ready: $OLLAMA_MODEL"
        else
            warn "Skipping Ollama model download"
            warn "Run manually: ollama pull $OLLAMA_MODEL"
        fi
    fi
}

setup_nvidia_toolkit_for_podman() {
    if [ "$NVIDIA_TOOLKIT_HANDLED" = "1" ]; then
        return 0
    fi
    NVIDIA_TOOLKIT_HANDLED=1

    if ! resolve_ask "$SETUP_NVIDIA_TOOLKIT" "Install/configure nvidia-container-toolkit for Podman GPU?" "n"; then
        warn "Skipping NVIDIA Container Toolkit"
        return 0
    fi

    if ! command -v dnf &>/dev/null; then
        warn "dnf was not found. Install manually: sudo dnf install -y nvidia-container-toolkit"
        return 0
    fi

    install_dnf_packages nvidia-container-toolkit

    if command -v nvidia-ctk &>/dev/null; then
        info "Generating NVIDIA CDI spec for Podman"
        sudo mkdir -p /etc/cdi
        sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml || warn "Failed to generate /etc/cdi/nvidia.yaml"
    else
        warn "nvidia-ctk was not found after installing nvidia-container-toolkit"
    fi

    if nvidia-smi &>/dev/null; then
        success "nvidia-smi is available on the host"
    else
        warn "nvidia-smi is not available. Make sure the NVIDIA host driver is installed."
    fi
}

podman_gpu_ready() {
    nvidia-smi &>/dev/null &&
        { [ -f /etc/cdi/nvidia.yaml ] || [ -f /var/run/cdi/nvidia.yaml ]; }
}

setup_melotts() {
    step "Step 8: MeloTTS container"

    if ! resolve_ask "$SETUP_MELOTTS" "Pull and run the MeloTTS container? The image is large." "n"; then
        warn "Skipping MeloTTS"
        warn "Manual commands:"
        warn "  podman pull $MELOTTS_IMAGE"
        warn "  podman run -d --name $MELOTTS_CONTAINER --device nvidia.com/gpu=all --security-opt label=disable -p $MELOTTS_PORT:8080 $MELOTTS_IMAGE"
        return 0
    fi

    if ! command -v podman &>/dev/null; then
        if [ "$INSTALL_SYSTEM_PACKAGES" = "1" ] && command -v dnf &>/dev/null; then
            install_dnf_packages podman
        else
            error "podman was not found"
        fi
    fi

    setup_nvidia_toolkit_for_podman

    info "Pull image MeloTTS: $MELOTTS_IMAGE"
    podman pull "$MELOTTS_IMAGE"

    if podman container exists "$MELOTTS_CONTAINER"; then
        info "Container $MELOTTS_CONTAINER already exists. Restarting it."
        podman stop "$MELOTTS_CONTAINER" &>/dev/null || true
        podman start "$MELOTTS_CONTAINER"
    else
        info "Running MeloTTS at http://127.0.0.1:$MELOTTS_PORT"
        if podman_gpu_ready; then
            podman run -d \
                --name "$MELOTTS_CONTAINER" \
                --device nvidia.com/gpu=all \
                --security-opt label=disable \
                -p "$MELOTTS_PORT:8080" \
                "$MELOTTS_IMAGE"
        else
            warn "NVIDIA CDI for Podman is not ready. Running the container without --device nvidia.com/gpu=all."
            podman run -d \
                --name "$MELOTTS_CONTAINER" \
                --security-opt label=disable \
                -p "$MELOTTS_PORT:8080" \
                "$MELOTTS_IMAGE"
        fi
    fi

    success "MeloTTS container is ready"
    setup_melotts_systemd
}

setup_melotts_systemd() {
    if ! resolve_ask "$SETUP_MELOTTS_SYSTEMD" "Generate and enable a user systemd service for MeloTTS auto-start?" "n"; then
        warn "Skipping MeloTTS systemd user service"
        warn "Manual command: podman generate systemd --new --name $MELOTTS_CONTAINER --files"
        return 0
    fi

    mkdir -p "$MELOTTS_SYSTEMD_USER_DIR"

    info "Generating $MELOTTS_SERVICE_FILE"
    (
        cd "$MELOTTS_SYSTEMD_USER_DIR"
        podman generate systemd --new --name "$MELOTTS_CONTAINER" --files
    )

    systemctl --user daemon-reload
    systemctl --user enable --now "container-$MELOTTS_CONTAINER.service"
    success "MeloTTS user service is enabled: container-$MELOTTS_CONTAINER.service"

    warn "Optional for auto-start before login: loginctl enable-linger \"$USER\""
}

verify_setup() {
    step "Step 9: Verify"

    local ok=1

    for cmd in grim slurp python3; do
        if command -v "$cmd" &>/dev/null; then
            success "$cmd OK"
        else
            warn "$cmd is not available"
            ok=0
        fi
    done

    if [ -s "$CEDICT_FILE" ]; then
        success "CC-CEDICT OK"
    else
        warn "CC-CEDICT is not available"
        ok=0
    fi

    if python3 -c "import requests, PIL, cnocr, ultralytics" &>/dev/null; then
        success "Python imports OK"
    else
        warn "Some Python packages could not be imported"
        ok=0
    fi

    if pgrep -f "$HOME/.local/bin/hanzi-server.py" &>/dev/null ||
        pgrep -f "hanzi-server.py" &>/dev/null; then
        success "hanzi-server.py is running"
    else
        warn "hanzi-server.py is not running. This is normal before reloading niri or logging in again."
    fi

    if command -v ollama &>/dev/null; then
        if ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$OLLAMA_MODEL"; then
            success "Ollama model is available: $OLLAMA_MODEL"
        else
            warn "Ollama model was not found: $OLLAMA_MODEL"
        fi
    fi

    if command -v podman &>/dev/null && podman container exists "$MELOTTS_CONTAINER"; then
        success "MeloTTS container exists: $MELOTTS_CONTAINER"
    else
        warn "MeloTTS container was not found. This is normal if MeloTTS was skipped."
    fi

    [ "$ok" = "1" ]
}

print_next_steps() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}        HANZI LOOKUP SETUP COMPLETE${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "Important locations:"
    echo "  Data       : $DATA_DIR"
    echo "  Scripts    : $BIN_DIR"
    echo "  Plugin     : $PLUGIN_DIR"
    echo "  Startup    : niri spawn-at-startup"
    echo ""
    echo "Default endpoints:"
    echo "  Ollama     : http://localhost:11434/api/generate"
    echo "  MeloTTS    : http://127.0.0.1:$MELOTTS_PORT/tts/convert/tts"
    echo "  Default Ollama model: $OLLAMA_MODEL_DEFAULT"
    echo ""
    echo "Add this to ~/.config/niri/config.kdl:"
    echo "  spawn-at-startup \"python3\" \"$HOME/.local/bin/hanzi-server.py\""
    echo ""
    echo "Recommended niri keybinds:"
    echo '  Super+Z { spawn "bash" "-c" "hanzi-client &"; }'
    echo '  Mod+Shift+Z { spawn-sh "qs -c noctalia-shell ipc call plugin:hanzi-lookup togglePanelDirect"; }'
    echo ""
    echo "Useful commands:"
    echo "  pgrep -af hanzi-server.py"
    echo "  tail -f $DATA_DIR/hanzi-lookup.log"
    echo "  ollama pull $OLLAMA_MODEL_DEFAULT"
    echo "  podman logs -f $MELOTTS_CONTAINER"
    echo "  mkdir -p ~/.config/systemd/user"
    echo "  podman generate systemd --new --name $MELOTTS_CONTAINER --files"
    echo "  systemctl --user daemon-reload"
    echo "  systemctl --user enable --now container-$MELOTTS_CONTAINER.service"
}

ensure_directories
install_system_dependencies
install_python_dependencies
install_cedict
deploy_hanzi_lookup
print_niri_startup_hint
setup_ollama
if [ "$SETUP_NVIDIA_TOOLKIT" = "yes" ]; then
    setup_nvidia_toolkit_for_podman
fi
setup_melotts
verify_setup || true
print_next_steps
