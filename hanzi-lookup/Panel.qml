import QtQuick
import QtQuick.Layouts
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
                    icon: "x"
                    onClicked: pluginApi.closePanel(pluginApi.panelOpenScreen)
                }
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
                    model: root.results
                    spacing: Style.marginM
                    clip: true

                    delegate: Rectangle {
                        width: listView.width
                        height: cardContent.implicitHeight + Style.marginL * 2
                        color: Color.mSurfaceVariant
                        radius: Style.radiusL

                        ColumnLayout {
                            id: cardContent
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: Style.marginL
                                topMargin: Style.marginM
                            }
                            spacing: Style.marginS

                            // Baris atas: Hanzi besar + pinyin
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginM

                                // Hanzi
                                NText {
                                    text: modelData.hanzi || "?"
                                    pointSize: Style.fontSizeXXL * 1.5
                                    font.weight: Font.Medium
                                    color: Color.mOnSurface
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.marginXS

                                    // Pinyin
                                    NText {
                                        visible: (modelData.entries?.length ?? 0) > 0
                                        text: modelData.entries?.[0]?.pinyin ?? ""
                                        pointSize: Style.fontSizeL
                                        font.weight: Font.Medium
                                        color: Color.mPrimary
                                    }

                                    // Tradisional (hanya jika beda)
                                    NText {
                                        visible: {
                                            let t = modelData.entries?.[0]?.traditional ?? ""
                                            return t && t !== modelData.hanzi
                                        }
                                        text: "繁: " + (modelData.entries?.[0]?.traditional ?? "")
                                        pointSize: Style.fontSizeS
                                        color: Color.mOnSurfaceVariant
                                    }
                                }
                            }

                            // Tidak ditemukan
                            NText {
                                visible: (modelData.entries?.length ?? 0) === 0
                                text: "Tidak ditemukan di kamus"
                                pointSize: Style.fontSizeS
                                color: Color.mOnSurfaceVariant
                                font.italic: true
                            }

                            // Arti-arti
                            Repeater {
                                model: modelData.entries ?? []

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.marginXS

                                    // Pinyin alternatif (entry ke-2 dst)
                                    NText {
                                        visible: index > 0
                                        text: modelData.pinyin ?? ""
                                        pointSize: Style.fontSizeS
                                        color: Color.mPrimary
                                        font.italic: true
                                    }

                                    // Meanings
                                    Repeater {
                                        model: modelData.meanings?.slice(0, 5) ?? []

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.marginS

                                            NText {
                                                text: (index + 1) + "."
                                                pointSize: Style.fontSizeM
                                                color: Color.mOnSurfaceVariant
                                                Layout.preferredWidth: 20
                                            }

                                            NText {
                                                text: modelData
                                                pointSize: Style.fontSizeM
                                                color: Color.mOnSurface
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    // Divider antar entry
                                    Rectangle {
                                        visible: index < (cardContent.parent?.entries?.length ?? 1) - 1
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Color.mOutline
                                        opacity: 0.2
                                        Layout.topMargin: Style.marginXS
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
