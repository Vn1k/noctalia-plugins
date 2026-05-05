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
                Logger.e("HanziLookup", "pluginApi tidak tersedia saat showResult dipanggil")
                return
            }

            Logger.i("HanziLookup", "Menerima data IPC:", jsonData.substring(0, 100) + "...")

            // Validasi JSON
            let parsed
            try {
                parsed = JSON.parse(jsonData)
            } catch (e) {
                Logger.e("HanziLookup", "JSON tidak valid:", e.toString())
                ToastService.showError("Hanzi Lookup: Data tidak valid")
                return
            }

            if (!parsed.results || parsed.results.length === 0) {
                Logger.w("HanziLookup", "Tidak ada hasil untuk:", parsed.query)
                ToastService.showNotice("Tidak ditemukan hasil untuk: " + (parsed.query || ""))
                return
            }

            // Simpan ke settings (Panel.qml akan membacanya)
            pluginApi.pluginSettings.lastQuery   = parsed.query   || ""
            pluginApi.pluginSettings.lastResults = jsonData
            pluginApi.pluginSettings.hasResults  = true
            pluginApi.saveSettings()

            Logger.i("HanziLookup", "Menyimpan", parsed.results.length, "hasil")

            // Buka panel di layar yang aktif
            pluginApi.withCurrentScreen(screen => {
                pluginApi.openPanel(screen)
                Logger.i("HanziLookup", "Panel dibuka di screen:", screen)
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
    }
}
