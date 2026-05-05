/**
 * Panel.qml — Hanzi Lookup Display Panel
 *
 * Panel overlay yang menampilkan hasil lookup Hanzi:
 *   - Karakter Hanzi besar
 *   - Pinyin dengan tone marks
 *   - Arti dalam bahasa Inggris/Indonesia
 *   - Karakter tradisional (opsional)
 *
 * Panel membaca data dari pluginApi.pluginSettings.lastResults
 * yang sudah diset oleh Main.qml ketika menerima IPC call.
 */

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null

    // Minimal ukuran panel
    implicitWidth:  pluginApi?.pluginSettings?.panelWidth ?? 480
    implicitHeight: Math.min(600, contentColumn.implicitHeight + 48)

    // ─── Data Binding ─────────────────────────────────────────────────────────

    // Parse hasil dari JSON string saat settings berubah
    property var parsedData: ({query: "", results: []})

    Connections {
        target: pluginApi?.pluginSettings ?? null
        function onLastResultsChanged() {
            root.reloadData()
        }
    }

    Component.onCompleted: {
        reloadData()
    }

    function reloadData() {
        if (!pluginApi?.pluginSettings?.lastResults) return
        try {
            let raw = pluginApi.pluginSettings.lastResults
            let data = JSON.parse(raw)
            root.parsedData = data
        } catch (e) {
            Logger.e("HanziLookup/Panel", "Gagal parse data:", e.toString())
        }
    }

    // ─── UI ──────────────────────────────────────────────────────────────────

    ColumnLayout {
        id: contentColumn
        anchors {
            top:    parent.top
            left:   parent.left
            right:  parent.right
            margins: 20
        }
        spacing: 4

        // Header: query + tombol tutup
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Label query
            NText {
                text: {
                    let q = root.parsedData?.query ?? ""
                    return q ? "Hasil untuk: " + q : "Hanzi Lookup"
                }
                font.pixelSize: Style.fontSize.sm
                color: Style.color.onSurface2
                Layout.fillWidth: true
            }

            // Tombol tutup
            NButton {
                text: "✕"
                flat: true
                onClicked: {
                    if (pluginApi) {
                        pluginApi.withCurrentScreen(screen => {
                            pluginApi.closePanel(screen)
                        })
                    }
                }
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Style.color.border
            opacity: 0.3
        }

        // Pesan jika kosong
        NText {
            visible: !root.parsedData?.results?.length
            text: "Tidak ada hasil"
            color: Style.color.onSurface2
            Layout.alignment: Qt.AlignHCenter
            topPadding: 16
            bottomPadding: 16
        }

        // ─── List hasil per karakter/kata ────────────────────────────────────
        Repeater {
            model: root.parsedData?.results ?? []

            delegate: CharacterCard {
                Layout.fillWidth: true
                Layout.topMargin: 8

                hanziData:      modelData
                showTraditional: pluginApi?.pluginSettings?.showTraditional ?? true
                showPinyin:      pluginApi?.pluginSettings?.showPinyin ?? true
            }
        }

        // Spacer bawah
        Item {
            Layout.preferredHeight: 8
        }
    }

    // ─── Component: CharacterCard ─────────────────────────────────────────────

    component CharacterCard: Item {
        id: card

        property var hanziData: ({})
        property bool showTraditional: true
        property bool showPinyin: true

        // Tinggi disesuaikan dengan isi
        implicitHeight: cardLayout.implicitHeight + 24
        implicitWidth: parent.width

        // Background card
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Style.color.surface2
            opacity: 0.7
        }

        ColumnLayout {
            id: cardLayout
            anchors {
                top:    parent.top
                left:   parent.left
                right:  parent.right
                margins: 14
                topMargin: 14
            }
            spacing: 6

            // Baris atas: Hanzi besar + Pinyin
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // Hanzi karakter (besar)
                NText {
                    text: card.hanziData?.hanzi ?? "?"
                    font.pixelSize: 52
                    font.weight: Font.Medium
                    color: Style.color.onSurface

                    // Badge jika phrase
                    Rectangle {
                        visible: card.hanziData?.is_phrase ?? false
                        anchors {
                            top: parent.top
                            right: parent.right
                            topMargin: 4
                            rightMargin: -4
                        }
                        width: 36; height: 16
                        radius: 8
                        color: Style.color.primary
                        opacity: 0.85

                        NText {
                            anchors.centerIn: parent
                            text: "词"
                            font.pixelSize: 9
                            color: Style.color.onPrimary
                        }
                    }
                }

                // Pinyin + Traditional
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    // Pinyin (ambil dari entry pertama)
                    NText {
                        visible: card.showPinyin && (card.hanziData?.entries?.length ?? 0) > 0
                        text: card.hanziData?.entries?.[0]?.pinyin ?? ""
                        font.pixelSize: Style.fontSize.xl
                        color: Style.color.primary
                        font.weight: Font.Medium
                    }

                    // Karakter tradisional
                    NText {
                        visible: {
                            if (!card.showTraditional) return false
                            let trad = card.hanziData?.entries?.[0]?.traditional ?? ""
                            let simp = card.hanziData?.hanzi ?? ""
                            return trad !== simp  // tampilkan hanya jika beda
                        }
                        text: {
                            let trad = card.hanziData?.entries?.[0]?.traditional ?? ""
                            return trad ? "繁: " + trad : ""
                        }
                        font.pixelSize: Style.fontSize.sm
                        color: Style.color.onSurface2
                    }
                }
            }

            // Tidak ditemukan di dictionary
            NText {
                visible: (card.hanziData?.entries?.length ?? 0) === 0
                text: "Tidak ditemukan di kamus"
                color: Style.color.onSurface2
                font.pixelSize: Style.fontSize.sm
                font.italic: true
                Layout.fillWidth: true
            }

            // Definisi (tiap entry dari dictionary)
            Repeater {
                model: card.hanziData?.entries ?? []

                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    // Pinyin alternatif (jika ada lebih dari 1 entry, tampilkan lagi)
                    NText {
                        visible: index > 0 && card.showPinyin
                        text: modelData?.pinyin ?? ""
                        font.pixelSize: Style.fontSize.sm
                        color: Style.color.primary
                        font.italic: true
                    }

                    // Meanings: tampilkan sebagai numbered list
                    Repeater {
                        model: modelData?.meanings?.slice(0, 5) ?? []

                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            NText {
                                text: (index + 1) + "."
                                font.pixelSize: Style.fontSize.sm
                                color: Style.color.onSurface2
                                Layout.preferredWidth: 18
                            }

                            NText {
                                text: modelData
                                font.pixelSize: Style.fontSize.sm
                                color: Style.color.onSurface
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Divider antar entry
                    Rectangle {
                        visible: index < (card.hanziData?.entries?.length ?? 1) - 1
                        Layout.fillWidth: true
                        height: 1
                        color: Style.color.border
                        opacity: 0.2
                        Layout.topMargin: 4
                    }
                }
            }
        }
    }
}
