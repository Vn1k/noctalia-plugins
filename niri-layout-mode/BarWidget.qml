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
    property string currentMode: "center" 

    Component.onCompleted: {
        console.log("[BarWidget] Loaded! Asking Main.qml for status...")
        checkStatus.running = true 
    }
    
    Process {
        id: checkStatus
        command: ["qs", "-c", "noctalia-shell", "ipc", "call", "plugin:niri-layout-mode", "getMode"]
        
        stdout: SplitParser {
            onRead: (data) => {
                var cleanData = data.trim()
                if (cleanData === "center" || cleanData === "split") {
                    root.currentMode = cleanData
                    console.log("[BarWidget] Synced Initial Mode: " + cleanData)
                }
            }
        }
    }

    Process {
        id: toggleClick
        command: ["qs", "-c", "noctalia-shell", "ipc", "call", "plugin:niri-layout-mode", "toggle"]
        
        stdout: SplitParser {
            onRead: (data) => {
                var cleanData = data.trim()
                if (cleanData === "center" || cleanData === "split") {
                    root.currentMode = cleanData
                    console.log("[BarWidget] Click Success! New Mode: " + cleanData)
                }
            }
        }
    }

    implicitWidth: isVertical ? Style.capsuleHeight : (layout.implicitWidth + Style.marginM * 2)
    implicitHeight: Style.capsuleHeight
    Layout.alignment: Qt.AlignVCenter
    color: Style.capsuleColor
    radius: Style.radiusL

    readonly property bool isVertical: {
        try { return Settings.data.bar.position === "left" || Settings.data.bar.position === "right" } 
        catch (e) { return false }
    }

    GridLayout {
        id: layout
        anchors.centerIn: parent
        columns: 2
        columnSpacing: Style.marginS

        NIcon {
            Layout.alignment: Qt.AlignCenter
            icon: root.currentMode === "center" ? "focus-2" : "layout-sidebar-right"
            color: root.currentMode === "center" ? Color.mPrimary : Color.mOnSurface
        }

        NText {
            visible: !isVertical 
            Layout.alignment: Qt.AlignCenter
            text: root.currentMode === "center" ? "Center" : "Split"
            color: Color.mOnSurface
            pointSize: Style.fontSizeS
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
            console.log("[BarWidget] Clicked! Sending command...")
            if (!toggleClick.running) toggleClick.running = true
        }
        onEntered: {
            if (root.isVertical) {
                TooltipService.show(root, root.currentMode === "center" ? "Center Mode" : "Split Mode", BarService.getTooltipDirection())
            }
        }
        onExited: TooltipService.hide()
    }
}