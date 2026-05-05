import QtQuick
import QtQuick.Layouts
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
    
    // New State for My Dictionary (Favorites)
    property bool showSavedOnly: false
    property var savedList: []

    function reloadData() {
        if (!pluginApi) return
        let raw = pluginApi.pluginSettings.lastResults
        if (!raw || raw === "[]") return
        try {
            let parsed = JSON.parse(raw)
            root.queryText = parsed.query || ""
            root.results   = parsed.results || []
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

    function playTts(text) {
        if (!text) return
        let escapedText = text.replace(/'/g, "'\\''")
        ttsProcess.command = ["bash", "-c", "python3 ~/.local/bin/hanzi-tts.py '" + escapedText + "' &"]
        ttsProcess.running = true
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
                    text: root.showSavedOnly ? "My Dictionary" : (root.queryText ? "结果: " + root.queryText : "Hanzi Lookup")
                    pointSize: Style.fontSizeL
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                }

                // ── Toggle Button for "My Dictionary" (Favorites) ──
                NIconButton {
                    icon: root.showSavedOnly ? "search" : "bookmark"
                    tooltipText: root.showSavedOnly ? "Back to Search" : "Open My Dictionary"
                    onClicked: {
                        root.showSavedOnly = !root.showSavedOnly
                        if (root.showSavedOnly) {
                            root.loadSavedVocab()
                        } else {
                            root.reloadData()
                        }
                    }
                }

                // ── Main Audio Button (Only appears in search mode) ──
                NIconButton {
                    icon: "volume-2"
                    visible: !root.showSavedOnly && root.queryText.length > 0
                    onClicked: root.playTts(root.queryText)
                }

                NIconButton {
                    icon: "x"
                    onClicked: pluginApi.closePanel(pluginApi.panelOpenScreen)
                }
            }

            // ── Combined Pinyin (Hidden in Dictionary mode) ─────────────────────
            NText {
                visible: !root.showSavedOnly && root.results.length > 0
                
                text: {
                    let pinyinArray = []
                    for (let i = 0; i < root.results.length; i++) {
                        let res = root.results[i]
                        if (res.entries && res.entries.length > 0 && res.entries[0].pinyin) {
                            pinyinArray.push(res.entries[0].pinyin)
                        } else {
                            pinyinArray.push(res.hanzi) 
                        }
                    }
                    return pinyinArray.join("  ") 
                }
                
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
                visible: !root.showSavedOnly && root.results.length > 0
                text: pluginApi.pluginSettings.aiTranslation || "Load AI translation..."
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
                visible: root.showSavedOnly ? (root.savedList.length > 0) : (root.results.length > 0)
            }

            // ── Empty State View ────────────────────────────────────────
            NText {
                visible: root.showSavedOnly ? (root.savedList.length === 0) : (root.results.length === 0)
                text: root.showSavedOnly ? "Your dictionary is empty" : "No results found"
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Style.marginL
            }

            // ── Selected Results / Dictionary List ──────────────────────────────────
            NScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.showSavedOnly ? (root.savedList.length > 0) : (root.results.length > 0)

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