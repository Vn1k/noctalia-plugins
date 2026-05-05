import QtQuick
import Quickshell
import Quickshell.Io
import qs.Widgets

NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "language"
    tooltipText: "Open My Dictionary"

    onClicked: {
        if (pluginApi) {
            pluginApi.openPanel(screen)
        }
    }
}
