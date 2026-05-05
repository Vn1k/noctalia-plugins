/**
 * ControlCenterWidget.qml — Hanzi Lookup Control Center Button
 *
 * Tombol di Control Center untuk trigger hanzi lookup secara manual
 * tanpa perlu pakai hotkey.
 */

import QtQuick
import qs.Widgets
import qs.Commons

Item {
    id: root

    property var pluginApi: null

    implicitWidth:  64
    implicitHeight: 64

    NButton {
        anchors.fill: parent

        icon:    "translate"
        text:    "汉字"
        flat:    false
        active:  pluginApi?.pluginSettings?.hasResults ?? false

        onClicked: {
            // Jalankan script Python via shell
            Qt.openUrlExternally("exec:bash -c 'python3 ~/.local/bin/hanzi-lookup.py &'")
        }

        tooltip: "Hanzi Lookup — pilih area layar untuk lookup pinyin & arti"
    }
}
