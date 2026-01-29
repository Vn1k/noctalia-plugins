import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI     
import qs.Services.System 

Rectangle {
    id: root

    property var pluginApi: null
    // LOG 1: Cek apakah setting berhasil dibaca atau default ke center
    readonly property string mode: {
        var m = pluginApi?.pluginSettings?.mode || "center"
        return m
    }

    // LOGGING SAAT COMPONENT SIAP
    Component.onCompleted: {
        console.log("[BarWidget] Loaded!")
        if (pluginApi) {
            console.log("[BarWidget] Connected to Plugin API. Current mode: " + mode)
        } else {
            console.warn("[BarWidget] WARNING: pluginApi is NULL! (Main.qml might be broken)")
        }
    }

    readonly property bool isVertical: {
        try {
            if (Settings && Settings.data && Settings.data.bar) {
                var pos = Settings.data.bar.position
                return pos === "left" || pos === "right"
            }
        } catch (e) {
            return false
        }
        return false
    }

    implicitWidth: isVertical ? Style.capsuleHeight : (layout.implicitWidth + Style.marginM * 2)
    implicitHeight: Style.capsuleHeight

    Layout.alignment: Qt.AlignVCenter
    color: Style.capsuleColor
    radius: Style.radiusL

    GridLayout {
        id: layout
        anchors.centerIn: parent
        
        columns: 2
        columnSpacing: Style.marginS

        NIcon {
            Layout.alignment: Qt.AlignCenter
            icon: mode === "center" ? "focus-2" : "layout-sidebar-right"
            color: mode === "center" ? Color.mPrimary : Color.mOnSurface
        }

        NText {
            visible: !isVertical 
            Layout.alignment: Qt.AlignCenter
            text: mode === "center" ? "Center" : "Split"
            color: Color.mOnSurface
            pointSize: Style.fontSizeS
        }
    }

    Process {
        id: toggleClick
        // Command untuk memanggil fungsi toggle di Main.qml
        command: ["qs", "-c", "noctalia-shell", "ipc", "call", "plugin:niri-layout-mode", "toggle"]
        
        // LOG 2: IPC DEBUGGING
        // Kalau perintah sukses dijalankan
        stdout: SplitParser {
            onRead: (data) => console.log("[BarWidget] IPC Success: " + data)
        }
        
        // Kalau ada error (PENTING!)
        stderr: SplitParser {
            onRead: (data) => console.error("[BarWidget] IPC Error: " + data)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        
        onClicked: {
            console.log("[BarWidget] Clicked! Sending IPC toggle command...")
            if (!toggleClick.running) {
                toggleClick.running = true
            } else {
                console.log("[BarWidget] Command busy, ignoring click.")
            }
        }

        onEntered: {
            if (root.isVertical) {
                TooltipService.show(
                    root,                                   
                    mode === "center" ? "Center Mode" : "Split Mode", 
                    BarService.getTooltipDirection()     
                )
            }
        }

        onExited: {
            TooltipService.hide()
        }
    }
}