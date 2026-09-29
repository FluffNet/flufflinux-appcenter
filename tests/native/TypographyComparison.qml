import QtQuick
import QtQuick.Controls
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    visible: true; width: 1000; height: 760
    palette.window: "#202326"; palette.windowText: "#ffffff"; palette.placeholderText: "#a5a9ad"
    Rectangle {
        anchors.fill: parent; color: main.backgroundColor; z: 999
        Column {
            x: 40; y: 30; spacing: 24
            Repeater {
                model: ["3297 applications", "flathub (System)", "0123456789 ABCDEFG abcdefg"]
                Column {
                    required property string modelData
                    spacing: 8
                    Label { text: "Typed input / default label / Qt / Native / Curve"; font.pixelSize: 18 }
                    TextField {
                        objectName: "compareInput"
                        width: 850; height: 26; padding: 0; background: null
                        text: modelData; color: main.textColor
                    }
                    Label { objectName: "compareLabel"; text: modelData; color: main.textColor }
                    Label { objectName: "compareQt"; text: modelData; color: main.textColor; renderType: Text.QtRendering }
                    Label { objectName: "compareNative"; text: modelData; color: main.textColor; renderType: Text.NativeRendering }
                    Label { objectName: "compareCurve"; text: modelData; color: main.textColor; renderType: Text.CurveRendering }
                }
            }
        }
    }
}
