import QtQuick
import Quickshell
import Quickshell.Io
import qs.Widgets

NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "language"
    tooltipText: "Hanzi Lookup — pilih area layar"

    onClicked: {
        lookupProcess.running = true
    }

    Process {
        id: lookupProcess
        command: ["bash", "-c", "python3 ~/.local/bin/hanzi-lookup.py &"]
        running: false
    }
}
