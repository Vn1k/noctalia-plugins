# Niri Layout Switcher

A native **Noctalia** plugin to toggle **Niri** window layouts (Center Focused vs Split View) instantly via the bar widget.

## ✨ Features

* **Native Performance:** Toggles layout directly via Noctalia IPC.
* **Smart Auto-Install:** Automatically detects `niri/config.kdl`, creates a partial config (`layout.kdl`), and injects it safely.
* **Safe & Atomic:** Uses an overwrite strategy to prevent configuration corruption. **Automatically backs up** your `config.kdl` before touching it.
* **📱 Responsive Widget:**
    * **Horizontal Bar:** Shows Icon + Text.
    * **Vertical Sidebar:** Shows Icon only with Native Tooltips.

## ⚠️ Requirements

* **Noctalia Shell** (Latest)
* **Niri v25.11 or newer** (Required for the `include` config feature).

## 📦 Installation

1. Clone this repository into your Noctalia plugins directory:
    ```bash
    cd ~/.config/noctalia/plugins
    git clone [https://github.com/Vn1k/noctalia-plugins.git](https://github.com/Vn1k/noctalia-plugins.git)
    git checkout niri-layout-switcher
    ```

2. Reload Noctalia, And go to plugins tab in the settings, and enabled it 
_if the plugin not showed up in the bar, go to bar tab and add manually_

3. Done
    * The plugin will automatically detect your Niri config.
    * It will create `~/.config/niri/layout.kdl`.
    * It will safely inject `include "layout.kdl"` into your main config.

## 🛠️ Configuration

The plugin manages a dedicated file at `~/.config/niri/layout.kdl`.

* **Center Mode:** `center-focused-column "always"`
* **Split Mode:** `center-focused-column "never"`

You can add to your niri keybinds with this command 
`{ spawn "qs" "-c" "noctalia-shell" "ipc" "call" "plugin:niri-layout-mode" "toggle"; }`

_Note: It is recommended NOT to edit `layout.kdl` manually as the plugin overwrites it on state change._