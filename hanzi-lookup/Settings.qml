import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Widgets
import qs.Commons
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    implicitHeight: mainLayout.implicitHeight
    width: parent ? parent.width : 400

    // ─── Process Helper untuk Restart Daemon ───
    Process {
        id: restartProcess
        command: [
            "bash",
            "-c",
            "pkill -f '[h]anzi-server.py' || true; nohup python3 \"$HOME/.local/bin/hanzi-server.py\" >/tmp/hanzi-server.log 2>&1 &"
        ]
        running: false
    }

    ColumnLayout {
        id: mainLayout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.marginM

        // ─── Header: Server Control ───
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Style.marginS

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                NText {
                    text: "Hanzi Server Control"
                    font.weight: Font.Bold
                    pointSize: Style.fontSizeL
                    color: Color.mOnSurface
                }
                NText {
                    text: "Terapkan perubahan model ke server yang berjalan."
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                }
            }

            NButton {
                text: "Restart Server"
                icon: "refresh-cw"
                onClicked: {
                    restartProcess.running = true
                    ToastService.showSuccess("Hanzi Server berhasil direstart!")
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline; opacity: 0.2; Layout.bottomMargin: Style.marginS }

        // ─── Bagian AI Model (Ollama / Qwen) ───
        NText {
            text: "AI Translation (Ollama)"
            font.weight: Font.Bold
            color: Color.mPrimary
        }

        NTextInput {
            Layout.fillWidth: true
            label: "Ollama Endpoint URL"
            text: pluginApi && pluginApi.pluginSettings.ollamaUrl ? pluginApi.pluginSettings.ollamaUrl : "http://localhost:11434/api/generate"
            onTextChanged: if(pluginApi) pluginApi.pluginSettings.ollamaUrl = text
        }

        NTextInput {
            Layout.fillWidth: true
            label: "Ollama Model Name"
            text: pluginApi && pluginApi.pluginSettings.ollamaModel ? pluginApi.pluginSettings.ollamaModel : "qwen2.5:1.5b-instruct"
            onTextChanged: if(pluginApi) pluginApi.pluginSettings.ollamaModel = text
        }

        // ─── Bagian Object Detection (YOLO) ───
        Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline; opacity: 0.2 }

        NText {
            text: "Object Detection (YOLO)"
            font.weight: Font.Bold
            color: Color.mPrimary
        }

        NTextInput {
            Layout.fillWidth: true
            label: "YOLO Model (e.g. yolo11s.pt, yolov8n.pt)"
            text: pluginApi && pluginApi.pluginSettings.yoloModel ? pluginApi.pluginSettings.yoloModel : "yolo11s.pt"
            onTextChanged: if(pluginApi) pluginApi.pluginSettings.yoloModel = text
        }

        // ─── Bagian TTS (MeloTTS) ───
        Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline; opacity: 0.2 }

        NText {
            text: "Speech Synthesis (MeloTTS)"
            font.weight: Font.Bold
            color: Color.mPrimary
        }

        NTextInput {
            Layout.fillWidth: true
            label: "MeloTTS Endpoint URL"
            text: pluginApi && pluginApi.pluginSettings.meloUrl ? pluginApi.pluginSettings.meloUrl : "http://127.0.0.1:8888/tts/convert/tts"
            onTextChanged: if(pluginApi) pluginApi.pluginSettings.meloUrl = text
        }
    }
}
