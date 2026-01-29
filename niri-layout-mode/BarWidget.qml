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

    readonly property string configBase: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string configDir: configBase + "/niri"
    readonly property string layoutConfig: configDir + "/layout.kdl"

    onCurrentModeChanged: {
        if (currentMode === "split") {
            statusIcon.icon = "layout-sidebar-right"
            statusIcon.color = Color.mOnSurface
            statusText.text = "Split"
        } else {
            statusIcon.icon = "focus-2"
            statusIcon.color = Color.mPrimary
            statusText.text = "Center"
        }
    }

    Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: {
             Logger.i("NiriDebug", "BarWidget Timer triggered. Requesting status...")
             checkStatus.running = true
        }
    }
    
    Process {
        id: checkStatus
        command: ["bash", "-c", "grep 'center-focused-column' \"" + root.layoutConfig + "\""]        
        stdout: SplitParser {
            onRead: (data) => {
                if (data.includes("never")) {
                    Logger.i("NiriDebug", "File detected: SPLIT mode")
                    root.currentMode = "split"
                } else {
                    Logger.i("NiriDebug", "File detected: CENTER mode")
                    root.currentMode = "center"
                }
            }
        }
    }

    Process {
        id: toggleClick
        command: ["qs", "-c", "noctalia-shell", "ipc", "call", "niri-layout-mode", "toggle"]
        
        stderr: SplitParser {
            onRead: (data) => Logger.e("NiriDebug", "Toggle IPC Error: " + data)
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
            id: statusIcon 
            Layout.alignment: Qt.AlignCenter
            icon: "focus-2"
            color: Color.mPrimary
        }

        NText {
            id: statusText  
            visible: !isVertical 
            Layout.alignment: Qt.AlignCenter
            text: "Center"
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

            if (root.currentMode === "center") {
                root.currentMode = "split"
            } else {
                root.currentMode = "center"
            }

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