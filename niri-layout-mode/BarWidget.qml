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

    readonly property string mode: pluginApi?.pluginSettings?.mode || "center"

    Process {
        id: toggleClick
        command: ["qs", "-c", "noctalia-shell", "ipc", "call", "niri-layout-mode", "toggle"]
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
            icon: root.mode === "center" ? "focus-2" : "layout-sidebar-right"
            color: root.mode === "center" ? Color.mPrimary : Color.mOnSurface
        }

        NText {
            visible: !isVertical 
            Layout.alignment: Qt.AlignCenter
            text: root.mode === "center" ? "Center" : "Split"
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
            if (!toggleClick.running) toggleClick.running = true
        }
        onEntered: {
            if (root.isVertical) {
                TooltipService.show(root, root.mode === "center" ? "Center Mode" : "Split Mode", BarService.getTooltipDirection())
            }
        }
        onExited: TooltipService.hide()
    }
}