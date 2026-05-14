import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null

    // ─── Required for Noctalia panel system ───────────────────────────────────
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    property real contentPreferredWidth:  480 * Style.uiScaleRatio
    property real contentPreferredHeight: 540 * Style.uiScaleRatio

    anchors.fill: parent

    // ─── Data & State ────────────────────────────────────────────────────────
    property var results: []
    property string queryText: ""
    property string currentMode: "OCR"
    property string fullPinyin: ""
    property string activePage: "results"
    
    // New State for My Dictionary (Favorites)
    property bool showSavedOnly: activePage === "dictionary"
    property var savedList: []

    // Translator page state
    readonly property string translatorScript: (Quickshell.env("HOME") || "") + "/.local/bin/hanzi-translate.py"
    property string translatorInput: ""
    property string translatorOutput: ""
    property string translatorPinyin: ""
    property string translatorError: ""
    property bool translatorBusy: false

    function openPage(pageName) {
        root.activePage = pageName
        if (pageName === "dictionary") {
            root.loadSavedVocab()
        } else if (pageName === "results") {
            root.reloadData()
        }
    }

    function reloadData() {
        if (!pluginApi) return
        let raw = pluginApi.pluginSettings.lastResults
        if (!raw || raw === "[]") return
        try {
            let parsed = JSON.parse(raw)
            root.queryText = parsed.query || ""
            root.results   = parsed.results || []
            root.currentMode = pluginApi.pluginSettings.lastMode || "OCR"
            root.fullPinyin  = pluginApi.pluginSettings.lastPinyin || ""
        } catch (e) {
            Logger.e("HanziLookup/Panel", "Parse error:", e.toString())
        }
    }

    // Load saved vocabulary list from plugin settings
    function loadSavedVocab() {
        if (!pluginApi) return
        let raw = pluginApi.pluginSettings.savedVocab || "[]"
        try {
            root.savedList = JSON.parse(raw)
        } catch (e) {
            root.savedList = []
        }
    }

    // Check if a specific Hanzi is already bookmarked
    function isSaved(hanzi) {
        if (!hanzi) return false
        for (let i = 0; i < root.savedList.length; i++) {
            if (root.savedList[i].hanzi === hanzi) return true
        }
        return false
    }

    // Add or Remove word from the saved list
    function toggleSave(resultObj) {
        if (!pluginApi || !resultObj.hanzi) return
        
        loadSavedVocab() // Ensure reading the latest data
        
        let index = -1
        for (let i = 0; i < root.savedList.length; i++) {
            if (root.savedList[i].hanzi === resultObj.hanzi) {
                index = i
                break
            }
        }

        let temp = root.savedList
        if (index > -1) {
            temp.splice(index, 1) // Remove if it already exists (unstar)
        } else {
            temp.push(resultObj)  // Save complete object so card format doesn't break (star)
        }

        root.savedList = temp
        pluginApi.pluginSettings.savedVocab = JSON.stringify(temp)
        pluginApi.saveSettings()
        root.loadSavedVocab() // Refresh UI state
    }

    // Reload every time the panel is shown
    onVisibleChanged: if (visible) { reloadData(); loadSavedVocab(); }
    Component.onCompleted: { reloadData(); loadSavedVocab(); }

    // ─── Process Helper for TTS ─────────────────────────────────────────────
    Process {
        id: ttsProcess
        running: false
    }

    Process {
        id: copyProcess
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0) {
                ToastService.showSuccess("Copied Hanzi")
            } else {
                ToastService.showError("Failed to copy Hanzi")
            }
        }
    }

    Process {
        id: translatorProcess
        running: false

        stdout: StdioCollector {
            id: translatorStdout
        }

        stderr: StdioCollector {
            id: translatorStderr
        }

        onExited: function(exitCode) {
            root.translatorBusy = false
            if (exitCode === 0) {
                let rawOutput = translatorStdout.text.trim()
                try {
                    let parsed = JSON.parse(rawOutput)
                    root.translatorOutput = parsed.translation || ""
                    root.translatorPinyin = parsed.pinyin || ""
                    root.translatorError = ""
                } catch (e) {
                    root.translatorOutput = rawOutput
                    root.translatorPinyin = ""
                    root.translatorError = ""
                }
            } else {
                root.translatorOutput = ""
                root.translatorPinyin = ""
                root.translatorError = translatorStderr.text.trim() || "Translator failed"
            }
        }
    }

    function playTts(text) {
        if (!text) return
        let escapedText = text.replace(/'/g, "'\\''")
        ttsProcess.command = ["bash", "-c", "python3 ~/.local/bin/hanzi-tts.py '" + escapedText + "' &"]
        ttsProcess.running = true
    }

    function translateInput() {
        let text = root.translatorInput.trim()
        if (!text || root.translatorBusy) return

        root.translatorBusy = true
        root.translatorOutput = "Translating..."
        root.translatorPinyin = ""
        root.translatorError = ""
        translatorProcess.command = ["python3", root.translatorScript, "--json", "--text", text]
        translatorProcess.running = true
    }

    function copyTranslatedHanzi() {
        let text = root.translatorOutput.trim()
        if (!text || root.translatorBusy || root.translatorError) return

        copyProcess.command = ["wl-copy", text]
        copyProcess.running = true
    }

    // ─── Main Container ─────────────────────────────────────────────────────
    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            anchors {
                fill: parent
                margins: Style.marginL
            }
            spacing: Style.marginM

            // ── Header ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                NText {
                    // Changes dynamically depending on mode (Search Results vs My Dictionary)
                    text: root.activePage === "translator"
                        ? "AI Translator"
                        : (root.showSavedOnly ? "My Dictionary" : (root.queryText ? "结果: " + root.queryText : "Hanzi Lookup"))
                    pointSize: Style.fontSizeL
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                }

                NIconButton {
                    icon: "search"
                    tooltipText: "Back to Search Results"
                    visible: root.activePage !== "results"
                    onClicked: root.openPage("results")
                }

                // ── Toggle Button for "My Dictionary" (Favorites) ──
                NIconButton {
                    icon: "bookmark"
                    tooltipText: "Open My Dictionary"
                    visible: root.activePage !== "dictionary"
                    onClicked: root.openPage("dictionary")
                }

                NIconButton {
                    icon: "languages"
                    tooltipText: "Open AI Translator"
                    visible: root.activePage !== "translator"
                    onClicked: root.openPage("translator")
                }

                // ── Main Audio Button (Only appears in search mode) ──
                NIconButton {
                    icon: "volume-2"
                    visible: root.activePage === "results" && root.queryText.length > 0
                    onClicked: root.playTts(root.queryText)
                }

                NIconButton {
                    icon: "x"
                    onClicked: pluginApi.closePanel(pluginApi.panelOpenScreen)
                }
            }

            // ── Combined Pinyin (Hidden in Dictionary mode) ─────────────────────
            NText {
                visible: root.activePage === "results" && root.results.length > 0
                
                text: root.fullPinyin
                pointSize: Style.fontSizeL
                color: Color.mPrimary
                font.italic: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: -Style.marginM
                Layout.bottomMargin: Style.marginS
            }

            // ── AI Translation (Hidden in Dictionary mode) ──────────────────────
            NText {
                // Teks ini hanya muncul jika mode-nya OCR dan bukan di mode Kamus
                visible: root.activePage === "results" && root.results.length > 0 && root.currentMode === "OCR"
                text: pluginApi.pluginSettings.aiTranslation || "Loading AI translation..."
                pointSize: Style.fontSizeM
                color: Color.mOnSurfaceVariant  
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: -Style.marginS
                Layout.bottomMargin: Style.marginM
            }

            // Divider Line
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Color.mOutline
                opacity: 0.3
                visible: root.activePage !== "translator" && (root.showSavedOnly ? (root.savedList.length > 0) : (root.results.length > 0))
            }

            // ── Empty State View ────────────────────────────────────────
            NText {
                visible: root.activePage !== "translator" && (root.showSavedOnly ? (root.savedList.length === 0) : (root.results.length === 0))
                text: root.showSavedOnly ? "Your dictionary is empty" : "No results found"
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Style.marginL
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.activePage === "translator"
                spacing: Style.marginM

                NText {
                    text: "Input"
                    font.weight: Font.Bold
                    color: Color.mPrimary
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150 * Style.uiScaleRatio
                    color: Color.mSurface
                    border.color: translatorInputArea.activeFocus ? Color.mSecondary : Color.mOutline
                    border.width: Style.borderS
                    radius: Style.radiusM

                    TextArea {
                        id: translatorInputArea
                        anchors.fill: parent
                        anchors.margins: Style.marginM
                        text: root.translatorInput
                        placeholderText: "Type Indonesian or English text"
                        wrapMode: TextEdit.WordWrap
                        selectByMouse: true
                        color: Color.mOnSurface
                        placeholderTextColor: Qt.alpha(Color.mOnSurfaceVariant, 0.6)
                        background: null
                        font.family: Settings.data.ui.fontDefault
                        font.pointSize: Style.fontSizeM * Style.uiScaleRatio
                        onTextChanged: root.translatorInput = text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    NButton {
                        text: root.translatorBusy ? "Translating" : "Translate"
                        icon: "languages"
                        enabled: root.translatorInput.trim().length > 0 && !root.translatorBusy
                        onClicked: root.translateInput()
                    }

                    NIconButton {
                        icon: "volume-2"
                        tooltipText: "Play Translation"
                        visible: root.translatorOutput.length > 0 && !root.translatorBusy
                        onClicked: root.playTts(root.translatorOutput)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    NText {
                        text: "Output"
                        font.weight: Font.Bold
                        color: Color.mPrimary
                        Layout.fillWidth: true
                    }

                    NIconButton {
                        icon: "copy"
                        tooltipText: "Copy Hanzi"
                        visible: root.translatorOutput.length > 0 && !root.translatorBusy && !root.translatorError
                        onClicked: root.copyTranslatedHanzi()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Color.mSurfaceVariant
                    radius: Style.radiusM

                    NScrollView {
                        anchors.fill: parent
                        anchors.margins: Style.marginM

                        ColumnLayout {
                            width: parent ? parent.width : 0
                            spacing: Style.marginS

                            NText {
                                Layout.fillWidth: true
                                text: root.translatorError ? root.translatorError : (root.translatorOutput || "Translation output will appear here")
                                color: root.translatorError ? Color.mError : (root.translatorOutput ? Color.mOnSurface : Color.mOnSurfaceVariant)
                                pointSize: root.translatorOutput && !root.translatorError ? Style.fontSizeXL : Style.fontSizeM
                                wrapMode: Text.WordWrap
                            }

                            NText {
                                Layout.fillWidth: true
                                visible: root.translatorPinyin.length > 0 && !root.translatorError
                                text: root.translatorPinyin
                                color: Color.mPrimary
                                pointSize: Style.fontSizeM
                                font.italic: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            // ── Selected Results / Dictionary List ──────────────────────────────────
            NScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.activePage !== "translator" && (root.showSavedOnly ? (root.savedList.length > 0) : (root.results.length > 0))

                ListView {
                    id: listView
                    anchors.fill: parent
                    
                    // Change model dynamically based on view state
                    model: root.showSavedOnly ? root.savedList : root.results
                    spacing: Style.marginM
                    clip: true

                    delegate: Rectangle {
                        id: resultContainer
                        width: listView.width
                        property var resultData: modelData  
                        implicitHeight: cardContent.implicitHeight + (Style.marginL * 2)
                        color: Color.mSurfaceVariant
                        radius: Style.radiusL

                        ColumnLayout {
                            id: cardContent
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: Style.marginL
                            }
                            spacing: Style.marginS

                            // ── Hanzi, Pinyin & Control Buttons Row ──
                            RowLayout {
                                Layout.fillWidth: true
                                
                                NText {
                                    text: resultData.hanzi || "?"
                                    pointSize: Style.fontSizeXXL
                                    color: Color.mOnSurface
                                }
                                
                                NText {
                                    text: (resultData.entries?.length > 0) ? resultData.entries[0].pinyin : ""
                                    pointSize: Style.fontSizeL
                                    color: Color.mPrimary
                                    Layout.fillWidth: true
                                }

                                // 1. Audio Button Per-Card
                                NIconButton {
                                    icon: "volume-2"
                                    visible: !!resultData.hanzi
                                    onClicked: root.playTts(resultData.hanzi)
                                }

                                // 2. Bookmark / Star Button (My Dictionary)
                                NIconButton {
                                    // Changes icon shape based on saved state
                                    icon: root.isSaved(resultData.hanzi) ? "star" : "star-off"
                                    visible: !!resultData.hanzi
                                    onClicked: root.toggleSave(resultData)
                                }
                            }

                            // ── Meaning Dictionary ──
                            Repeater {
                                model: resultData.entries || []
                                delegate: ColumnLayout {
                                    id: entryItem
                                    Layout.fillWidth: true
                                    property var entryData: modelData 

                                    Repeater {
                                        model: entryData.meanings || []
                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.marginS

                                            NText {
                                                text: (index + 1) + "."
                                                color: Color.mOnSurfaceVariant
                                                Layout.preferredWidth: 20
                                            }

                                            NText {
                                                text: modelData
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                color: Color.mOnSurface
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: index < (resultData.entries.length - 1)
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Color.mOutline
                                        opacity: 0.2
                                        Layout.topMargin: Style.marginS
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
