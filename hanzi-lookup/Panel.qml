import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null

    // ─── Wajib untuk sistem panel Noctalia ───────────────────────────────────
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    property real contentPreferredWidth:  480 * Style.uiScaleRatio
    property real contentPreferredHeight: 540 * Style.uiScaleRatio

    anchors.fill: parent

    // ─── Data ────────────────────────────────────────────────────────────────
    property var results: []
    property string queryText: ""

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

    // Reload setiap kali panel ditampilkan
    onVisibleChanged: if (visible) reloadData()
    Component.onCompleted: reloadData()

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

    // ─── Container utama ─────────────────────────────────────────────────────
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
                    text: root.queryText ? "结果: " + root.queryText : "Hanzi Lookup"
                    pointSize: Style.fontSizeL
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                }

                NIconButton {
                    icon: "volume-2"
                    visible: root.queryText.length > 0
                    onClicked: root.playTts(root.queryText)
                }

                NIconButton {
                    icon: "x"
                    onClicked: pluginApi.closePanel(pluginApi.panelOpenScreen)
                }
            }

            NText {
                visible: root.results.length > 0
                
                // Logika penggabungan Pinyin
                text: {
                    let pinyinArray = []
                    for (let i = 0; i < root.results.length; i++) {
                        let res = root.results[i]
                        // Ambil pinyin dari entri pertama jika ada, jika tidak, tampilkan hanzi-nya
                        if (res.entries && res.entries.length > 0 && res.entries[0].pinyin) {
                            pinyinArray.push(res.entries[0].pinyin)
                        } else {
                            pinyinArray.push(res.hanzi) 
                        }
                    }
                    return pinyinArray.join("  ") // Gabungkan dengan 2 spasi agar lega
                }
                
                pointSize: Style.fontSizeL
                color: Color.mPrimary
                font.italic: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                
                // Margin agar posisinya pas di bawah teks "结果..."
                Layout.topMargin: -Style.marginM 
                Layout.bottomMargin: Style.marginS
            }

            NText {
                visible: root.results.length > 0
                
                text: pluginApi.pluginSettings.aiTranslation || "Load AI translation..."
                
                pointSize: Style.fontSizeM
                color: Color.mOnSurfaceVariant  // Warna redup agar minimalis
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                
                Layout.topMargin: -Style.marginS
                Layout.bottomMargin: Style.marginM
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Color.mOutline
                opacity: 0.3
            }

            // ── Kosong ───────────────────────────────────────────────────────
            NText {
                visible: root.results.length === 0
                text: "Tidak ada hasil"
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Style.marginL
            }

            // ── List hasil ───────────────────────────────────────────────────
            NScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.results.length > 0

                ListView {
                    id: listView
                    anchors.fill: parent
                    
                    model: root.results
                    spacing: Style.marginM
                    clip: true

                    delegate: Rectangle {
                        id: resultContainer
                        width: listView.width
                        property var resultData: modelData 
                        
                        // Gunakan implicitHeight agar tinggi kotak menyesuaikan isi teks
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

                            // ── Baris Hanzi & Pinyin ──
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

                                NIconButton {
                                    icon: "volume-2"
                                    visible: !!resultData.hanzi
                                    onClicked: root.playTts(resultData.hanzi)
                                }
                            }

                            // ── List Entri (Repeater Pertama) ──
                            Repeater {
                                model: resultData.entries || []
                                delegate: ColumnLayout {
                                    id: entryItem
                                    Layout.fillWidth: true
                                    property var entryData: modelData 

                                    // ── List Arti (Repeater Kedua) ──
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

                                    // Divider antar entri
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
