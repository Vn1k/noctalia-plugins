/**
 * Main.qml — Hanzi Lookup Plugin (Background + IPC)
 *
 * Komponen ini berjalan di background dan menerima IPC call dari
 * hanzi-lookup.py, lalu menyimpan data ke pluginSettings agar
 * Panel.qml bisa menampilkannya.
 *
 * IPC command:
 *   qs -c noctalia-shell ipc call plugin:hanzi-lookup showResult '{"query":"...","results":[...]}'
 */

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    property var pluginApi: null

    // ─── IPC Handler ─────────────────────────────────────────────────────────

    IpcHandler {
        target: "plugin:hanzi-lookup"

        /**
         * showResult(jsonData: string)
         *
         * Dipanggil dari hanzi-lookup.py setelah OCR + dictionary lookup selesai.
         * jsonData adalah JSON string dengan format:
         * {
         *   "query": "你好",
         *   "results": [
         *     {
         *       "hanzi": "你",
         *       "is_phrase": false,
         *       "entries": [
         *         {
         *           "traditional": "你",
         *           "simplified": "你",
         *           "pinyin": "nǐ",
         *           "meanings": ["you (informal)", "you"]
         *         }
         *       ]
         *     }
         *   ]
         * }
         */

        function updateAIText(jsonData: string) {
            if (!pluginApi) return
            try {
                let parsed = JSON.parse(jsonData)
                // Simpan ke settings agar QML otomatis merefresh UI
                pluginApi.pluginSettings.aiTranslation = parsed.ai_text
                pluginApi.saveSettings()
            } catch (e) {
                Logger.e("HanziLookup", "Gagal parse teks AI:", e.toString())
            }
        }

        function showResult(jsonData: string) {
            if (!pluginApi) {
                Logger.e("HanziLookup", "pluginApi is not available when showResult is called")
                return
            }

            Logger.i("HanziLookup", "Received IPC data:", jsonData.substring(0, 100) + "...")

            let parsed
            try {
                parsed = JSON.parse(jsonData)
            } catch (e) {
                Logger.e("HanziLookup", "Invalid JSON:", e.toString())
                ToastService.showError("Hanzi Lookup: Invalid data")
                return
            }

            if (!parsed.results || parsed.results.length === 0) {
                Logger.w("HanziLookup", "No results for:", parsed.query)
                ToastService.showNotice("No results found for: " + (parsed.query || ""))
                return
            }

            // Save to settings
            pluginApi.pluginSettings.lastMode    = parsed.mode || "OCR"
            
            // If it's an object, hide the AI loading text. If OCR, show loading.
            pluginApi.pluginSettings.aiTranslation = (parsed.mode === "OBJ") ? "" : "Loading AI translation..."
            
            pluginApi.pluginSettings.lastQuery   = parsed.query   || ""
            pluginApi.pluginSettings.lastResults = jsonData
            pluginApi.pluginSettings.hasResults  = true
            pluginApi.saveSettings()

            Logger.i("HanziLookup", "Saved", parsed.results.length, "results")

            pluginApi.withCurrentScreen(screen => {
                pluginApi.openPanel(screen)
            })
        }

        /**
         * closePanel()
         *
         * Tutup panel jika sedang terbuka.
         * Bisa dipanggil via IPC atau keybind.
         */
        function closePanel() {
            if (!pluginApi) return
            pluginApi.withCurrentScreen(screen => {
                pluginApi.closePanel(screen)
            })
        }

        /**
         * clearResults()
         *
         * Bersihkan hasil terakhir.
         */
        function clearResults() {
            if (!pluginApi) return
            pluginApi.pluginSettings.lastQuery   = ""
            pluginApi.pluginSettings.lastResults = "[]"
            pluginApi.pluginSettings.hasResults  = false
            pluginApi.saveSettings()
            Logger.i("HanziLookup", "Hasil dibersihkan")
        }

        /**
         * togglePanelDirect()
         *
         * Opens or closes the panel directly without triggering OCR.
         * Perfect for binding to a keyboard shortcut.
         */
        function togglePanelDirect() {
            if (!pluginApi) return
            pluginApi.withCurrentScreen(screen => {
                // If Noctalia API supports togglePanel
                if (typeof pluginApi.togglePanel === "function") {
                    pluginApi.togglePanel(screen)
                } else {
                    // Fallback if togglePanel doesn't exist, just open it
                    pluginApi.openPanel(screen)
                }
                Logger.i("HanziLookup", "Panel triggered directly via IPC")
            })
        }
    }
}
