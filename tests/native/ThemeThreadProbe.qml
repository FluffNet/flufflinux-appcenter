import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
ApplicationWindow {
    id: window
    width: 800; height: 800; visible: true
    property int iteration: 0
    Grid {
        anchors.fill: parent
        columns: 8
        Repeater {
            model: 64
            Column {
                required property int index
                width: 100
                Image {
                    width: 64; height: 64
                    sourceSize: Qt.size(32 + window.iteration % 5 * 8, 32 + window.iteration % 5 * 8)
                    source: "image://icon/font-probe?iteration=" + window.iteration
                    asynchronous: asyncTheme
                    cache: false
                }
                Label {
                    width: 100; height: 35
                    text: ["App", "עברית", "العربية", "日本語", "🙂"][index % 5] + window.iteration
                    font.pixelSize: 14 + window.iteration % 7
                    font.bold: window.iteration % 2 === 0
                }
            }
        }
    }
    Timer {
        interval: 1; running: true; repeat: true
        onTriggered: {
            if (++window.iteration >= probeIterations) {
                console.log("THEME_THREAD_PROBE_COMPLETE", asyncTheme, window.iteration)
                stop()
                Qt.quit()
            }
        }
    }
}
